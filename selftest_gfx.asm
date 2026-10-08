; ============================================================================
; selftest_gfx.asm - built-in checks of the bloom post-process and of the
;                    scene table of the timeline
;                    (part of SiliconDreams.exe /selftest).
; ----------------------------------------------------------------------------
; The checks draw a white 16 x 16 patch into an otherwise black frame, run
; Bloom_Apply and read single pixels back:
;   * a picture below the threshold is left alone,
;   * the patch stays bright and gets a halo that is mirror-symmetric (a
;     shifted blur tap or a wrong buffer offset breaks the symmetry),
;   * the halo fades with the distance and never reaches the far field,
;   * the halo is proportional to the gain and matches a measured profile
;     (near / mid values catch a missing level or a wrong scale),
;   * the glow neither wraps around the left/right nor the top/bottom edges.
; Measured profile (patch excess 63, gain 2.0), green channel, by distance
; from the patch edge:  0 px: 78   3 px: 50   9 px: 16   17 px: 4   29 px: 1.
;
; The scene table (sceneTab in timeline.asm), for every scene:
;   * the row lists the renderer and the initialiser of that scene (stFns and
;     stInits give the expected order) and a caption numbered like the scene
;     (the title has none),
;   * Tl_RenderScene draws exactly what the renderer of the row draws at the
;     same local time (so the dispatch and the time offset of the scene are
;     right).
; ============================================================================
INCLUDE common.inc

PATCH_SIZE  EQU 16
PATCH_THR   EQU 192                       ; excess 63: gains 2.0 and 4.0 stay below saturation
PATCH_X     EQU 312                       ; multiples of 4 so that the patch fills whole blocks
PATCH_Y     EQU 172
PATCH_R     EQU PATCH_X + PATCH_SIZE      ; first column right of the patch
PATCH_B     EQU PATCH_Y + PATCH_SIZE      ; first row below the patch
ROW_Y       EQU 179                       ; a row through the patch
COL_X       EQU 319                       ; a column through the patch
NEAR_LO     EQU 40                        ; halo 3 pixels beside the patch (measured 50)
NEAR_HI     EQU 62
MID_LO      EQU 12                        ; halo 9 pixels beside the patch (measured 16)
MID_HI      EQU 22
DOT_GAIN    EQU 4000                      ; 15.6 x: one lit pixel per block still glows
COMPOSE_MS  EQU 6000                      ; the title scene: sun, neon grid and text
COMPOSE_MIN EQU 200000                    ; bytes that must come out brighter than the plain scene (measured 483732)
TABLE_LT    EQU 9000                      ; local time of the table check: every caption is gone by then

.const
szBlThr     BYTE "bloom: a picture below the threshold is untouched", 0
szBlCore    BYTE "bloom: a bright patch stays bright", 0
szBlHalo    BYTE "bloom: halo around the patch, mirror-symmetric", 0
szBlDecay   BYTE "bloom: the halo fades with distance, the far field stays dark", 0
szBlLevel   BYTE "bloom: halo level matches the measured profile", 0
szBlGain    BYTE "bloom: the halo is proportional to the gain", 0
szBlBlocks  BYTE "bloom: every pixel of a 4x4 block counts the same", 0
szBlEdge    BYTE "bloom: the glow does not wrap around the frame edges", 0
szPrScene   BYTE "bloom parameters: scene values and cross-fade between scenes", 0
szPrPump    BYTE "bloom parameters: the kick pumps the gain, capped", 0
szCompose   BYTE "timeline: the composed frame is the scene plus glow", 0
szTabRow    BYTE "scene table: renderer, initialiser and numbered caption of the row", 0
szTabDraw   BYTE "scene table: Tl_RenderScene draws what the renderer of the row draws", 0

; The scenes in the order of the timeline (a new scene is appended here as well).
ALIGN 8
stFns       QWORD Fx_Title_Render, Fx_Plasma_Render, Fx_Tunnel_Render, Fx_Stars_Render, Fx_Blobs_Render
            QWORD Fx_Roto_Render, Fx_Fire_Render, Fx_Prism_Render, Fx_Voxel_Render
stInits     QWORD Fx_Title_Init, Fx_Plasma_Init, Fx_Tunnel_Init, Fx_Stars_Init, Fx_Blobs_Init
            QWORD Fx_Roto_Init, Fx_Fire_Init, Fx_Prism_Init, Fx_Voxel_Init
.ERRNZ ($ - stFns) - NUM_SCENES * 16       ; one renderer and one initialiser per scene

.code

; Sg_Px(rcx = framebuffer, edx = x, r8d = y) -> eax = green channel.
LEAF_BEGIN Sg_Px
    imul   r8d, r8d, SCR_W
    add    r8d, edx
    movzx  eax, BYTE PTR [rcx+r8*4+1]
    ret
LEAF_END Sg_Px

; Sg_White(rcx = framebuffer, edx = x, r8d = y, r9d = size) - white square.
LEAF_BEGIN Sg_White
    imul   r8d, r8d, SCR_W
    add    r8d, edx
    lea    rcx, [rcx+r8*4]
    mov    r10d, r9d
sw_row:
    xor    eax, eax
sw_px:
    mov    DWORD PTR [rcx+rax*4], 00FFFFFFh
    inc    eax
    cmp    eax, r9d
    jb     sw_px
    add    rcx, SCR_W * 4
    dec    r10d
    jnz    sw_row
    ret
LEAF_END Sg_White

; Sg_Dots(rcx = framebuffer, edx = x, r8d = y, r9d = k) - a 16 x 16 area in which only
; the pixel at position k (0..15 = column + 4 * row) of every 4 x 4 block is white.
LEAF_BEGIN Sg_Dots
    imul   r8d, r8d, SCR_W
    add    r8d, edx
    lea    rcx, [rcx+r8*4]
    xor    r10d, r10d
sd_row:
    xor    eax, eax
sd_px:
    mov    edx, r10d
    and    edx, 3
    shl    edx, 2
    mov    r11d, eax
    and    r11d, 3
    or     edx, r11d                           ; position inside the block
    cmp    edx, r9d
    jne    sd_skip
    mov    DWORD PTR [rcx+rax*4], 00FFFFFFh
sd_skip:
    inc    eax
    cmp    eax, PATCH_SIZE
    jb     sd_px
    add    rcx, SCR_W * 4
    inc    r10d
    cmp    r10d, PATCH_SIZE
    jb     sd_row
    ret
LEAF_END Sg_Dots

; Sg_AllEqual(rcx = framebuffer, edx = value) -> eax = 1 when every pixel equals value.
LEAF_BEGIN Sg_AllEqual
    mov    r8d, SCR_PIX
ae_lp:
    cmp    DWORD PTR [rcx], edx
    jne    ae_no
    add    rcx, 4
    dec    r8d
    jnz    ae_lp
    mov    eax, 1
    ret
ae_no:
    xor    eax, eax
    ret
LEAF_END Sg_AllEqual

; Sg_Near(eax = a, edx = b, ecx = tolerance) -> eax = 1 when |a - b| <= tolerance.
LEAF_BEGIN Sg_Near
    sub    eax, edx
    cdq
    xor    eax, edx
    sub    eax, edx
    cmp    eax, ecx
    setbe  al
    movzx  eax, al
    ret
LEAF_END Sg_Near

; Sg_Range(eax = value, ecx = low, edx = high) -> eax = 1 when low <= value <= high.
LEAF_BEGIN Sg_Range
    sub    eax, ecx
    sub    edx, ecx
    cmp    eax, edx
    setbe  al
    movzx  eax, al
    ret
LEAF_END Sg_Range

; Sg_Patch(edx = x, r8d = y, r9d = gain) - black frame in gFbA, a white patch at
; (x, y), then the bloom with the test threshold.
FN_BEGIN Sg_Patch, 0
    mov    ebx, edx
    mov    esi, r8d
    mov    edi, r9d
    mov    rcx, QWORD PTR gFbA
    xor    edx, edx
    call   Gfx_Fill
    mov    rcx, QWORD PTR gFbA
    mov    edx, ebx
    mov    r8d, esi
    mov    r9d, PATCH_SIZE
    call   Sg_White
    mov    rcx, QWORD PTR gFbA
    mov    edx, PATCH_THR
    mov    r8d, edi
    call   Bloom_Apply
    FN_RET
FN_END Sg_Patch

; Reads the green channel of gFbA at (x, y) into eax.
PXGET MACRO x:REQ, y:REQ
    mov    rcx, QWORD PTR gFbA
    mov    edx, x
    mov    r8d, y
    call   Sg_Px
ENDM

; ---------------------------------------------------------------------------
; St_BloomSym - the mirror positions of the halo: left/right and up/down.
; ---------------------------------------------------------------------------
FN_BEGIN St_BloomSym, 0
    PXGET  PATCH_R + 9, ROW_Y                  ; right of the patch
    mov    r12d, eax
    PXGET  PATCH_X - 10, ROW_Y                 ; the mirror position on the left
    mov    r13d, eax
    PXGET  COL_X, PATCH_Y - 11                 ; above
    mov    r14d, eax
    PXGET  COL_X, PATCH_B + 10                 ; the mirror position below
    mov    r15d, eax
    mov    eax, r12d
    mov    edx, r13d
    mov    ecx, 2
    call   Sg_Near
    mov    ebx, eax
    mov    eax, r14d
    mov    edx, r15d
    mov    ecx, 2
    call   Sg_Near
    and    ebx, eax
    test   r12d, r12d
    setnz  al
    movzx  eax, al
    and    ebx, eax
    test   r14d, r14d
    setnz  al
    movzx  eax, al
    and    ebx, eax
    mov    edx, ebx
    lea    rcx, szBlHalo
    call   St_Report
    FN_RET
FN_END St_BloomSym

; ---------------------------------------------------------------------------
; St_BloomProfile - fall-off and calibration along a row through the patch.
; ---------------------------------------------------------------------------
FN_BEGIN St_BloomProfile, 0
    PXGET  PATCH_R + 3, ROW_Y                  ; near
    mov    r12d, eax
    PXGET  PATCH_R + 9, ROW_Y                  ; mid
    mov    r13d, eax
    PXGET  PATCH_R + 29, ROW_Y                 ; far
    mov    r14d, eax
    PXGET  40, ROW_Y                           ; far field, left
    mov    r15d, eax
    PXGET  COL_X, 5                            ; far field, top
    xor    edx, edx
    cmp    r12d, r13d
    seta   dl                                  ; near > mid
    cmp    r13d, r14d
    seta   cl
    and    dl, cl                              ; mid > far
    test   r15d, r15d
    setz   cl
    and    dl, cl
    test   eax, eax
    setz   cl
    and    dl, cl
    lea    rcx, szBlDecay
    call   St_Report
    mov    eax, r12d
    mov    ecx, NEAR_LO
    mov    edx, NEAR_HI
    call   Sg_Range
    mov    ebx, eax
    mov    eax, r13d
    mov    ecx, MID_LO
    mov    edx, MID_HI
    call   Sg_Range
    and    eax, ebx
    mov    edx, eax
    lea    rcx, szBlLevel
    call   St_Report
    mov    eax, r13d
    FN_RET
FN_END St_BloomProfile

; ---------------------------------------------------------------------------
; St_BloomBlocks - only one pixel of every 4 x 4 block is lit, at each of the 16
; positions in turn, with a large gain: the halo must be the same for all of
; them (every pixel of a block counts equally, none is skipped or doubled).
; ---------------------------------------------------------------------------
FN_BEGIN St_BloomBlocks, 0
    xor    ebx, ebx                            ; position
    mov    r12d, 255                           ; smallest halo
    xor    r13d, r13d                          ; largest halo
bb_lp:
    mov    rcx, QWORD PTR gFbA
    xor    edx, edx
    call   Gfx_Fill
    mov    rcx, QWORD PTR gFbA
    mov    edx, PATCH_X
    mov    r8d, PATCH_Y
    mov    r9d, ebx
    call   Sg_Dots
    mov    rcx, QWORD PTR gFbA
    mov    edx, PATCH_THR
    mov    r8d, DOT_GAIN
    call   Bloom_Apply
    PXGET  PATCH_R + 9, ROW_Y
    cmp    eax, r12d
    cmovb  r12d, eax
    cmp    eax, r13d
    cmova  r13d, eax
    inc    ebx
    cmp    ebx, 16
    jb     bb_lp
    xor    edx, edx
    cmp    r12d, 4                             ; every position produced a halo
    setae  dl
    sub    r13d, r12d
    cmp    r13d, 1                             ; and they differ by at most one level
    setbe  cl
    and    dl, cl
    lea    rcx, szBlBlocks
    call   St_Report
    FN_RET
FN_END St_BloomBlocks

; ---------------------------------------------------------------------------
; St_BloomEdges - patches touching the right and the bottom edge.
; ---------------------------------------------------------------------------
FN_BEGIN St_BloomEdges, 0
    mov    edx, SCR_W - PATCH_SIZE
    mov    r8d, PATCH_Y
    mov    r9d, 512
    call   Sg_Patch
    PXGET  0, ROW_Y                            ; opposite edge: must stay black
    mov    ebx, eax
    PXGET  SCR_W - 1, ROW_Y
    mov    r12d, eax
    PXGET  SCR_W - PATCH_SIZE - 12, ROW_Y
    mov    r13d, eax
    mov    edx, PATCH_X
    mov    r8d, SCR_H - PATCH_SIZE
    mov    r9d, 512
    call   Sg_Patch
    PXGET  COL_X, 0
    mov    r14d, eax
    PXGET  COL_X, SCR_H - 1
    mov    r15d, eax
    PXGET  COL_X, SCR_H - PATCH_SIZE - 12
    mov    esi, eax
    xor    edx, edx
    or     ebx, r14d
    setz   dl                                  ; both opposite edges are black
    cmp    r12d, 250
    setae  cl
    and    dl, cl
    cmp    r15d, 250
    setae  cl
    and    dl, cl
    test   r13d, r13d
    setnz  cl
    and    dl, cl
    test   esi, esi
    setnz  cl
    and    dl, cl
    lea    rcx, szBlEdge
    call   St_Report
    FN_RET
FN_END St_BloomEdges

; ---------------------------------------------------------------------------
; St_BloomGain - a second patch with double the gain: the halo doubles.
; In: ecx = halo value 9 pixels beside the patch at gain 2.0.
; ---------------------------------------------------------------------------
FN_BEGIN St_BloomGain, 0
    mov    ebx, ecx
    mov    edx, PATCH_X
    mov    r8d, PATCH_Y
    mov    r9d, 1024
    call   Sg_Patch
    PXGET  PATCH_R + 9, ROW_Y
    xor    edx, edx
    lea    ecx, [rbx+rbx*2]
    shr    ecx, 1                              ; 1.5 x
    cmp    eax, ecx
    setae  dl
    lea    ecx, [rbx*2+4]                      ; 2 x (+ rounding)
    cmp    eax, ecx
    setbe  cl
    and    dl, cl
    lea    rcx, szBlGain
    call   St_Report
    FN_RET
FN_END St_BloomGain

; Sg_Compare(rcx = a, rdx = b) -> eax = bytes where a > b, edx = bytes where a < b
; (whole 640 x 360 BGRA frames).
LEAF_BEGIN Sg_Compare
    xor    r8d, r8d
    xor    r9d, r9d
    mov    r10d, SCR_BYTES
cm_lp:
    movzx  eax, BYTE PTR [rcx]
    movzx  r11d, BYTE PTR [rdx]
    cmp    eax, r11d
    jbe    cm_le
    inc    r8d
    jmp    cm_next
cm_le:
    jae    cm_next
    inc    r9d
cm_next:
    inc    rcx
    inc    rdx
    dec    r10d
    jnz    cm_lp
    mov    eax, r8d
    mov    edx, r9d
    ret
LEAF_END Sg_Compare

; Checks the bloom parameters of (scene, blend) against (threshold, gain); the
; difference is or-ed into ebx (0 = everything matched so far).
PARAMCHK MACRO sc:REQ, blend:REQ, thr:REQ, gain:REQ
    mov    ecx, sc
    mov    edx, blend
    call   Tl_BloomParams
    xor    eax, thr
    xor    edx, gain
    or     eax, edx
    or     ebx, eax
ENDM

; ---------------------------------------------------------------------------
; St_Params - per-scene bloom parameters, cross-fade and beat pump.
; The expected numbers follow from the scene table in timeline.asm.
; ---------------------------------------------------------------------------
FN_BEGIN St_Params, 0
    mov    DWORD PTR gKick, 0
    xor    ebx, ebx
    PARAMCHK 0, 0, 140, 640                    ; the scene's own values
    PARAMCHK 0, 256, 205, 420                  ; blend 1.0 = the next scene
    PARAMCHK 1, 128, 185, 470                  ; halfway, threshold falling
    PARAMCHK 1, 100, 189, 459                  ; rounds towards minus infinity
    PARAMCHK 2, 64, 171, 615                   ; gain rising
    PARAMCHK 3, 192, 160, 657                  ; gain falling
    PARAMCHK 7, 128, 202, 370                  ; PRISM into the voxel landscape
    PARAMCHK 8, 128, 215, 420                  ; the last scene has no successor
    xor    edx, edx
    test   ebx, ebx
    setz   dl
    lea    rcx, szPrScene
    call   St_Report
    xor    ebx, ebx
    mov    DWORD PTR gKick, 256
    PARAMCHK 0, 0, 140, 800                    ; + 25 % at the peak of the kick
    PARAMCHK 3, 0, 190, 1000                   ; capped
    mov    DWORD PTR gKick, 128
    PARAMCHK 0, 0, 140, 720
    mov    DWORD PTR gKick, 0
    PARAMCHK 0, 0, 140, 640
    xor    edx, edx
    test   ebx, ebx
    setz   dl
    lea    rcx, szPrPump
    call   St_Report
    FN_RET
FN_END St_Params

; ---------------------------------------------------------------------------
; St_Compose - the frame of the timeline is the plain scene plus glow: never
; darker, clearly brighter in places (the bloom is really wired in).
; ---------------------------------------------------------------------------
FN_BEGIN St_Compose, 0
    mov    ecx, COMPOSE_MS
    call   Tl_Update
    mov    ecx, COMPOSE_MS
    call   Tl_Compose                          ; gFbC = scene + glow
    xor    ecx, ecx
    mov    rdx, QWORD PTR gFbA
    mov    r8d, COMPOSE_MS
    call   Tl_RenderScene                      ; gFbA = the scene alone
    mov    rcx, QWORD PTR gFbC
    mov    rdx, QWORD PTR gFbA
    call   Sg_Compare
    mov    ebx, eax
    mov    esi, edx
    xor    ecx, ecx
    test   esi, esi
    setz   cl                                  ; never darker
    cmp    ebx, COMPOSE_MIN
    setae  al
    and    cl, al
    movzx  edx, cl
    lea    rcx, szCompose
    call   St_Report
    FN_RET
FN_END St_Compose

; ---------------------------------------------------------------------------
; St_TableRow(ecx = scene) -> eax = 1 when row `scene` of sceneTab lists the
; renderer and the initialiser of that scene and a caption numbered like it
; (scene 7 is captioned "07   PRISM ...": the characters '0' and the digit of
; the index; the title, scene 0, has no caption).
; ---------------------------------------------------------------------------
FN_BEGIN St_TableRow, 0
    mov    ebx, ecx
    mov    eax, ecx
    shl    eax, 5                              ; SIZEOF SCENE
    lea    rsi, sceneTab
    add    rsi, rax                            ; the row
    lea    rax, stFns
    mov    rdx, QWORD PTR [rax+rbx*8]
    cmp    QWORD PTR [rsi+SCENE.renderFn], rdx
    sete   r12b
    lea    rax, stInits
    mov    rdx, QWORD PTR [rax+rbx*8]
    cmp    QWORD PTR [rsi+SCENE.initFn], rdx
    sete   al
    and    r12b, al
    mov    rdx, QWORD PTR [rsi+SCENE.caption]
    test   ebx, ebx
    jnz    tr_num
    cmp    BYTE PTR [rdx], 0                   ; the title has no caption
    sete   al
    jmp    tr_cap
tr_num:
    cmp    BYTE PTR [rdx], '0'
    sete   al
    lea    ecx, [rbx+'0']
    cmp    BYTE PTR [rdx+1], cl
    sete   cl
    and    al, cl
tr_cap:
    and    r12b, al
    movzx  eax, r12b
    FN_RET
FN_END St_TableRow

; ---------------------------------------------------------------------------
; St_TableDraw(ecx = scene) -> eax = 1 when Tl_RenderScene draws the scene at
; demo time (scene * SCENE_MS + TABLE_LT, minus TRANS_MS for every scene after
; the first, which starts early) exactly as the renderer of its row does at
; the local time TABLE_LT.
; ---------------------------------------------------------------------------
FN_BEGIN St_TableDraw, 0
    mov    ebx, ecx
    imul   r12d, ebx, SCENE_MS
    add    r12d, TABLE_LT
    test   ebx, ebx
    jz     td_run
    sub    r12d, TRANS_MS
td_run:
    mov    ecx, ebx
    mov    rdx, QWORD PTR gFbA
    mov    r8d, r12d
    call   Tl_RenderScene                      ; through the table, with the time offset
    mov    eax, ebx
    shl    eax, 5
    lea    rsi, sceneTab
    mov    rax, QWORD PTR [rsi+rax+SCENE.renderFn]
    mov    rcx, QWORD PTR gFbB
    mov    edx, TABLE_LT
    call   rax                                 ; the renderer itself
    mov    rcx, QWORD PTR gFbA
    mov    rdx, QWORD PTR gFbB
    call   Sg_Compare
    or     eax, edx
    setz   al
    movzx  eax, al
    FN_RET
FN_END St_TableDraw

; ---------------------------------------------------------------------------
; St_Table - both checks for every scene, reported as "scene N: ...".
; ---------------------------------------------------------------------------
FN_BEGIN St_Table, 0
    xor    ebx, ebx
tb_lp:
    mov    ecx, ebx
    call   St_TableRow
    mov    esi, eax
    mov    ecx, ebx
    lea    rdx, szTabRow
    call   St_NameScene
    mov    rcx, rax
    mov    edx, esi
    call   St_Report
    mov    ecx, ebx
    call   St_TableDraw
    mov    esi, eax
    mov    ecx, ebx
    lea    rdx, szTabDraw
    call   St_NameScene
    mov    rcx, rax
    mov    edx, esi
    call   St_Report
    inc    ebx
    cmp    ebx, NUM_SCENES
    jb     tb_lp
    FN_RET
FN_END St_Table

; ---------------------------------------------------------------------------
; St_Gfx - all graphics checks.
; ---------------------------------------------------------------------------
FN_BEGIN St_Gfx, 0
    mov    rcx, QWORD PTR gFbA
    mov    edx, 00646464h
    call   Gfx_Fill
    mov    rcx, QWORD PTR gFbA
    mov    edx, 150                            ; threshold above every pixel
    mov    r8d, 512
    call   Bloom_Apply
    mov    rcx, QWORD PTR gFbA
    mov    edx, 00646464h
    call   Sg_AllEqual
    mov    edx, eax
    lea    rcx, szBlThr
    call   St_Report
    mov    edx, PATCH_X
    mov    r8d, PATCH_Y
    mov    r9d, 512
    call   Sg_Patch
    PXGET  COL_X, ROW_Y
    xor    edx, edx
    cmp    eax, 250
    setae  dl
    lea    rcx, szBlCore
    call   St_Report
    call   St_BloomSym
    call   St_BloomProfile
    mov    ecx, eax
    call   St_BloomGain
    call   St_BloomBlocks
    call   St_BloomEdges
    call   St_Params
    call   St_Compose
    call   St_Table
    FN_RET
FN_END St_Gfx

END
