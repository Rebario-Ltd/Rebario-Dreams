; ============================================================================
; fx_voxel.asm - scene 8 "TERRA": a flight over a procedural voxel landscape
;                at golden hour, ending with the credits.
; ----------------------------------------------------------------------------
; The camera path is a table built once (PATH_N entries, one per 100 ms): the
; heading turns smoothly from facing the sun to being side-lit, the height
; follows a smoothed maximum of the terrain ahead plus a safety margin.  At
; render time the table is interpolated, so the frame is a pure function of
; the scene time.  The heavy lifting is in vox_terrain.asm (generation) and
; vox_render.asm (ray casting); this module adds the camera and the credits.
; ============================================================================
INCLUDE common.inc
INCLUDE vox.inc

PATH_N     EQU 166                       ; 16.5 s at 100 ms
PATH_X0    EQU 430                       ; start position (cells)
PATH_Y0    EQU 290
PATH_STEP  EQU 176947                    ; 2.7 cells per 100 ms (27 cells / s), 16.16
A_START    EQU 32043                     ; 176 degrees in 1/16 table units: facing the sun
A_END      EQU 17476                     ; 96 degrees: sun on the right
T_TOTAL    EQU 16500
HOR_BASE   EQU 170
CLEAR_H    EQU 7680                      ; safety margin above the terrain: 30 cells
CLEAR_N    EQU 11                        ; number of probe points around the camera
CR_TITLE_AT EQU 10200                    ; credits timing (scene ms)
CR_SUB_AT   EQU 11400
CR_LINE_AT  EQU 12300

VDM MACRO txm:REQ, px:REQ, py:REQ, col:REQ, alp:REQ, md:REQ
    lea  rax, vxDm
    mov  QWORD PTR [rax+DMASK.dst], r12
    lea  rcx, txm
    mov  QWORD PTR [rax+DMASK.tx], rcx
    mov  ecx, DWORD PTR px
    mov  DWORD PTR [rax+DMASK.x], ecx
    mov  ecx, DWORD PTR py
    mov  DWORD PTR [rax+DMASK.y], ecx
    mov  DWORD PTR [rax+DMASK.color], col
    mov  DWORD PTR [rax+DMASK.alpha], alp
    mov  DWORD PTR [rax+DMASK.mode], md
    mov  QWORD PTR [rax+DMASK.rowPal], 0
    mov  QWORD PTR [rax+DMASK.rowOff], 0
ENDM

; Renders a string into a mask (rsi = FONTREQ *).
VFONT MACRO dstSym:REQ, textSym:REQ, hgt:REQ, wgt:REQ, fce:REQ, itl:REQ, trk:REQ
    lea  rax, dstSym
    mov  QWORD PTR [rsi+FONTREQ.dst], rax
    lea  rax, textSym
    mov  QWORD PTR [rsi+FONTREQ.text], rax
    mov  DWORD PTR [rsi+FONTREQ.height], hgt
    mov  DWORD PTR [rsi+FONTREQ.weight], wgt
    mov  DWORD PTR [rsi+FONTREQ.face], fce
    mov  DWORD PTR [rsi+FONTREQ.italic], itl
    mov  DWORD PTR [rsi+FONTREQ.track], trk
    mov  rcx, rsi
    call Font_Render
ENDM

.const
ALIGN 16
; (ahead, side) offsets in cells, relative to the camera, where the terrain is probed
vxOffsets   DWORD -10, 0,  0, 0,  12, 0,  26, 0,  44, 0
            DWORD 10, -16,  10, 16,  26, -24,  26, 24,  0, -12,  0, 12
vxGoldKeys  DWORD 4
            DWORD 0,     00FFF6D8h
            DWORD 26000, 00FFD27Ah
            DWORD 48000, 00FF9A6Ah
            DWORD 65536, 00E0607Ah
szCrTitle   BYTE "REBARIO DREAMS", 0
szCrSub     BYTE "A 64-BIT ASSEMBLY DEMO", 0

.data?
ALIGN 16
vxPathX     DWORD PATH_N DUP (?)
vxPathY     DWORD PATH_N DUP (?)
vxPathA     DWORD PATH_N DUP (?)
vxPathH     DWORD PATH_N DUP (?)
vxPathM     DWORD PATH_N DUP (?)         ; terrain clearance signal (before smoothing)
vxMTitle    BYTE 16 DUP (?)              ; TXMASK
vxMSub      BYTE 16 DUP (?)
vxHTitle    BYTE 16 DUP (?)              ; blurred masks
vxHSub      BYTE 16 DUP (?)
vxHLine     BYTE 16 DUP (?)              ; ... of the text of the credit line (sigText)
vxHHeart    BYTE 16 DUP (?)              ; ... and of its heart (sigHeart)
vxTxtPos    DWORD 6 DUP (?)              ; x, y of title / sub / credit line
vxGoldPal   DWORD 256 DUP (?)            ; row colours of the title
vxReq       BYTE 48 DUP (?)
vxDm        BYTE 64 DUP (?)

.code

; ---------------------------------------------------------------------------
; Vox_Sin16(ecx = angle, 1/16 table units) -> eax = sine, +-32767, interpolated.
; Clobbers rcx, rdx, r8.
; ---------------------------------------------------------------------------
LEAF_BEGIN Vox_Sin16
    mov  eax, ecx
    shr  eax, 4
    and  eax, 4095
    and  ecx, 15
    lea  rdx, gSinTab
    movsx r8d, WORD PTR [rdx+rax*2]
    inc  eax
    and  eax, 4095
    movsx eax, WORD PTR [rdx+rax*2]
    sub  eax, r8d
    imul eax, ecx
    sar  eax, 4
    add  eax, r8d
    ret
LEAF_END Vox_Sin16

; ---------------------------------------------------------------------------
; Vox_Lerp(rcx = DWORD array, edx = index, r8d = fraction 0..255) -> eax.
; Clobbers r9.
; ---------------------------------------------------------------------------
LEAF_BEGIN Vox_Lerp
    mov  eax, DWORD PTR [rcx+rdx*4]
    mov  r9d, DWORD PTR [rcx+rdx*4+4]
    sub  r9d, eax
    imul r9d, r8d
    sar  r9d, 8
    add  eax, r9d
    ret
LEAF_END Vox_Lerp

; ---------------------------------------------------------------------------
; Vox_Ramp(ecx = time, edx = start, r8d = duration) -> eax = 0..256.
; ---------------------------------------------------------------------------
LEAF_BEGIN Vox_Ramp
    sub  ecx, edx
    jg   vrp_go
    xor  eax, eax
    ret
vrp_go:
    shl  ecx, 8
    mov  eax, ecx
    xor  edx, edx
    div  r8d
    mov  ecx, 256
    cmp  eax, ecx
    cmova eax, ecx
    ret
LEAF_END Vox_Ramp

; ---------------------------------------------------------------------------
; Vox_PathHeading(ebx = table index) -> eax = heading (1/16 table units)
; smooth turn from A_START to A_END plus a gentle sway.
; ---------------------------------------------------------------------------
FN_BEGIN Vox_PathHeading, 0
    imul r14d, ebx, 100                    ; t (ms)
    mov  eax, r14d
    shl  eax, 16
    xor  edx, edx
    mov  ecx, T_TOTAL
    div  ecx                               ; u, 16.16
    mov  r8, rax
    imul rax, r8
    shr  rax, 16                           ; u^2
    mov  rdx, 3 * 65536
    sub  rdx, r8
    sub  rdx, r8                           ; 3 - 2u
    imul rax, rdx
    shr  rax, 16                           ; smoothstep(u)
    mov  rdx, A_END - A_START
    imul rdx, rax
    sar  rdx, 16
    add  edx, A_START
    mov  r15d, edx
    mov  eax, r14d                         ; sway: +-3 degrees, 0.7 rad / s
    imul eax, 467
    shr  eax, 10
    and  eax, 4095
    lea  rdx, gSinTab
    movsx eax, WORD PTR [rdx+rax*2]
    imul eax, 546
    sar  eax, 15
    add  eax, r15d
    FN_RET
FN_END Vox_PathHeading

; ---------------------------------------------------------------------------
; Vox_BuildPath - positions and headings by integration of the flight speed.
; ---------------------------------------------------------------------------
FN_BEGIN Vox_BuildPath, 0
    mov  r12d, PATH_X0 SHL 16
    mov  r13d, PATH_Y0 SHL 16
    xor  ebx, ebx
bp_lp:
    call Vox_PathHeading
    mov  r15d, eax
    lea  rax, vxPathX
    mov  DWORD PTR [rax+rbx*4], r12d
    lea  rax, vxPathY
    mov  DWORD PTR [rax+rbx*4], r13d
    lea  rax, vxPathA
    mov  DWORD PTR [rax+rbx*4], r15d
    lea  ecx, [r15+16384]
    call Vox_Sin16                         ; cos
    movsxd rax, eax
    imul rax, PATH_STEP
    sar  rax, 15
    add  r12d, eax
    mov  ecx, r15d
    call Vox_Sin16                         ; sin
    movsxd rax, eax
    imul rax, PATH_STEP
    sar  rax, 15
    add  r13d, eax
    inc  ebx
    cmp  ebx, PATH_N
    jb   bp_lp
    FN_RET
FN_END Vox_BuildPath

; ---------------------------------------------------------------------------
; Vox_Clearance(ebx = table index) -> eax = highest terrain around the path
; point (positions ahead of and behind the camera), water-clamped.
; ---------------------------------------------------------------------------
FN_BEGIN Vox_Clearance, 0
    lea  rax, vxPathX
    mov  r12d, DWORD PTR [rax+rbx*4]
    lea  rax, vxPathY
    mov  r13d, DWORD PTR [rax+rbx*4]
    lea  rax, vxPathA
    mov  esi, DWORD PTR [rax+rbx*4]
    lea  ecx, [rsi+16384]
    call Vox_Sin16
    mov  r14d, eax                         ; cos
    mov  ecx, esi
    call Vox_Sin16
    mov  r15d, eax                         ; sin
    lea  r8, vxOffsets
    xor  edi, edi
    xor  ebp, ebp
cl_o:
    mov  eax, DWORD PTR [r8+rbp*8]         ; ahead
    mov  edx, DWORD PTR [r8+rbp*8+4]       ; side (right is positive)
    mov  ecx, eax
    imul ecx, r14d                         ; ahead * cos
    mov  r9d, edx
    imul r9d, r15d                         ; side * sin
    sub  ecx, r9d
    lea  ecx, [r12+rcx*2]                  ; x = px + (ahead * cos - side * sin), 16.16
    imul eax, r15d
    imul edx, r14d
    add  eax, edx
    lea  edx, [r13+rax*2]                  ; y = py + (ahead * sin + side * cos)
    call Vox_HeightAt
    cmp  eax, edi
    cmova edi, eax
    inc  ebp
    cmp  ebp, CLEAR_N
    jb   cl_o
    mov  eax, edi
    FN_RET
FN_END Vox_Clearance

; ---------------------------------------------------------------------------
; Vox_BuildHeights - camera height = smoothed clearance + margin.
; ---------------------------------------------------------------------------
FN_BEGIN Vox_BuildHeights, 0
    xor  ebx, ebx
bh_m:
    call Vox_Clearance
    lea  rdx, vxPathM
    mov  DWORD PTR [rdx+rbx*4], eax
    inc  ebx
    cmp  ebx, PATH_N
    jb   bh_m
    xor  ebx, ebx
bh_i:
    xor  esi, esi                          ; sum
    mov  ebp, -14
bh_k:
    lea  eax, [rbx+rbp]
    xor  ecx, ecx
    test eax, eax
    cmovs eax, ecx
    mov  ecx, PATH_N - 1
    cmp  eax, ecx
    cmova eax, ecx
    lea  rdx, vxPathM
    add  esi, DWORD PTR [rdx+rax*4]
    inc  ebp
    cmp  ebp, 14
    jle  bh_k
    mov  eax, esi
    xor  edx, edx
    mov  ecx, 29
    div  ecx
    mov  ecx, VX_WATER
    cmp  eax, ecx
    cmovb eax, ecx
    add  eax, CLEAR_H
    lea  rdx, vxPathH
    mov  DWORD PTR [rdx+rbx*4], eax
    inc  ebx
    cmp  ebx, PATH_N
    jb   bh_i
    FN_RET
FN_END Vox_BuildHeights

; ---------------------------------------------------------------------------
; Vox_Camera(ecx = scene ms) - fills vxp from the interpolated path.
; ---------------------------------------------------------------------------
FN_BEGIN Vox_Camera, 0
    mov  r12d, ecx
    lea  rsi, vxp
    mov  eax, ecx
    xor  edx, edx
    mov  ecx, 100
    div  ecx
    cmp  eax, PATH_N - 2
    jbe  cm_idx
    mov  eax, PATH_N - 2
    mov  edx, 99
cm_idx:
    imul edx, 41
    shr  edx, 4                            ; fraction 0..255
    mov  r13d, eax
    mov  r14d, edx
    lea  rcx, vxPathX
    mov  edx, r13d
    mov  r8d, r14d
    call Vox_Lerp
    mov  DWORD PTR [rsi+VXP.camX], eax
    lea  rcx, vxPathY
    mov  edx, r13d
    mov  r8d, r14d
    call Vox_Lerp
    mov  DWORD PTR [rsi+VXP.camY], eax
    lea  rcx, vxPathH
    mov  edx, r13d
    mov  r8d, r14d
    call Vox_Lerp
    mov  DWORD PTR [rsi+VXP.camH], eax
    lea  rcx, vxPathA
    mov  edx, r13d
    mov  r8d, r14d
    call Vox_Lerp
    mov  r15d, eax                         ; heading
    lea  ecx, [r15+16384]
    call Vox_Sin16
    mov  DWORD PTR [rsi+VXP.fwdX], eax
    mov  ecx, r15d
    call Vox_Sin16
    mov  DWORD PTR [rsi+VXP.fwdY], eax
    mov  eax, r12d                         ; horizon sways slightly
    imul eax, 3
    and  eax, 4095
    lea  rdx, gSinTab
    movsx eax, WORD PTR [rdx+rax*2]
    imul eax, 4
    sar  eax, 15
    add  eax, HOR_BASE
    mov  DWORD PTR [rsi+VXP.hor], eax
    mov  eax, r12d                         ; glitter time bucket
    shr  eax, 7
    imul eax, 83492791
    mov  DWORD PTR [rsi+VXP.tb], eax
    mov  ecx, VX_SUN_AZ                    ; sun position on the screen
    sub  ecx, r15d
    mov  r13d, ecx
    call Vox_Sin16
    mov  r14d, eax                         ; sin(delta)
    lea  ecx, [r13+16384]
    call Vox_Sin16                         ; cos(delta)
    mov  DWORD PTR [rsi+VXP.sunX], 100000
    cmp  eax, 4000
    jle  cm_done
    mov  ecx, eax
    imul eax, r14d, VX_F
    cdq
    idiv ecx
    add  eax, 320
    mov  DWORD PTR [rsi+VXP.sunX], eax
    mov  eax, VX_SUN_UP * 32767
    cdq
    idiv ecx
    neg  eax
    add  eax, DWORD PTR [rsi+VXP.hor]
    mov  DWORD PTR [rsi+VXP.sunY], eax
cm_done:
    FN_RET
FN_END Vox_Camera

; ---------------------------------------------------------------------------
; Vox_BuildTexts - credit masks, blurred shadows, positions, title colours.
; ---------------------------------------------------------------------------
FN_BEGIN Vox_BuildTexts, 0
    lea  rsi, vxReq
    VFONT vxMTitle, szCrTitle, 56, 900, 0, 1, 4
    lea  rsi, vxReq
    VFONT vxMSub, szCrSub, 22, 500, 1, 0, 9
    call Sig_Init                          ; "created with <heart> by Paul Deecalov (c) 2026"
    lea  rcx, vxMTitle
    lea  rdx, vxHTitle
    mov  r8d, 8
    call Font_Glow
    lea  rcx, vxMSub
    lea  rdx, vxHSub
    mov  r8d, 6
    call Font_Glow
    lea  rcx, sigText
    lea  rdx, vxHLine
    mov  r8d, 5
    call Font_Glow
    lea  rcx, sigHeart
    lea  rdx, vxHHeart
    mov  r8d, 5
    call Font_Glow
    lea  rcx, vxMTitle
    lea  rdx, vxGoldPal
    lea  r8, vxGoldKeys
    call Font_RowPal
    lea  rsi, vxTxtPos
    lea  rdi, vxMTitle
    mov  r8d, 142
    call Vox_Place
    lea  rdi, vxMSub
    mov  r8d, 200
    call Vox_Place
    lea  rdi, sigText                      ; sigHeart has the same size, so it shares the place
    mov  r8d, 232
    call Vox_Place
    FN_RET
FN_END Vox_BuildTexts

; ---------------------------------------------------------------------------
; Vox_Place(rsi = {x, y} slot, rdi = TXMASK *, r8d = centre row) -> centres the
; mask horizontally, advances rsi to the next slot.
; ---------------------------------------------------------------------------
LEAF_BEGIN Vox_Place
    mov  eax, SCR_W
    sub  eax, DWORD PTR [rdi+TXMASK.w]
    shr  eax, 1
    mov  DWORD PTR [rsi], eax
    mov  eax, DWORD PTR [rdi+TXMASK.h]
    shr  eax, 1
    mov  edx, r8d
    sub  edx, eax
    mov  DWORD PTR [rsi+4], edx
    add  rsi, 8
    ret
LEAF_END Vox_Place

; ---------------------------------------------------------------------------
; Vox_CreditLine(rcx = fb, edx = scene ms, r8d = start, r9d = slot) - one line.
; Slots: 0 title (chrome + glow), 1 subtitle, 2 credit line (text, then heart).
; ---------------------------------------------------------------------------
FN_BEGIN Vox_CreditLine, 0
    mov  r12, rcx
    mov  ecx, edx
    mov  edx, r8d
    mov  r8d, 1000
    mov  r14d, r9d
    call Vox_Ramp
    test eax, eax
    jz   cl_done
    mov  r13d, eax                         ; opacity
    lea  rsi, vxTxtPos
    lea  eax, [r14*8]
    add  rsi, rax
    mov  eax, DWORD PTR [rsi]
    mov  DWORD PTR vxTxtX, eax
    mov  eax, DWORD PTR [rsi+4]
    mov  DWORD PTR vxTxtY, eax
    imul ebx, r13d, 150                    ; dark halo keeps the text legible
    shr  ebx, 8
    cmp  r14d, 1
    ja   cl_h2
    je   cl_h1
    VDM  vxHTitle, vxTxtX, vxTxtY, 00180A20h, ebx, 0
    jmp  cl_halo
cl_h1:
    VDM  vxHSub, vxTxtX, vxTxtY, 00180A20h, ebx, 0
    jmp  cl_halo
cl_h2:
    VDM  vxHLine, vxTxtX, vxTxtY, 00180A20h, ebx, 0
cl_halo:
    mov  rcx, rax
    call Gfx_DrawMask
    cmp  r14d, 1
    ja   cl_t2
    je   cl_t1
    VDM  vxMTitle, vxTxtX, vxTxtY, 00FFFFFFh, r13d, 0
    lea  rcx, vxGoldPal
    mov  QWORD PTR [rax+DMASK.rowPal], rcx
    jmp  cl_draw
cl_t1:
    VDM  vxMSub, vxTxtX, vxTxtY, 00FFE3B0h, r13d, 0
    jmp  cl_draw
cl_t2:
    VDM  sigText, vxTxtX, vxTxtY, 00FFC8A0h, r13d, 0
cl_draw:
    mov  rcx, rax
    call Gfx_DrawMask
    cmp  r14d, 2
    jne  cl_done
    VDM  vxHHeart, vxTxtX, vxTxtY, 00300008h, ebx, 0      ; dark red halo of the heart
    mov  rcx, rax
    call Gfx_DrawMask
    VDM  sigHeart, vxTxtX, vxTxtY, SIG_RED, r13d, 0
    mov  rcx, rax
    call Gfx_DrawMask
cl_done:
    FN_RET
FN_END Vox_CreditLine

.data?
vxTxtX      DWORD ?
vxTxtY      DWORD ?

.code

; ---------------------------------------------------------------------------
; Vox_Credits(rcx = fb, edx = scene ms)
; ---------------------------------------------------------------------------
FN_BEGIN Vox_Credits, 0
    mov  r12, rcx
    mov  r13d, edx
    mov  rcx, r12
    mov  edx, r13d
    mov  r8d, CR_TITLE_AT
    xor  r9d, r9d
    call Vox_CreditLine
    mov  rcx, r12
    mov  edx, r13d
    mov  r8d, CR_SUB_AT
    mov  r9d, 1
    call Vox_CreditLine
    mov  rcx, r12
    mov  edx, r13d
    mov  r8d, CR_LINE_AT
    mov  r9d, 2
    call Vox_CreditLine
    FN_RET
FN_END Vox_Credits

FN_BEGIN Fx_Voxel_Init, 0
    call Vox_BuildTerrain
    call Vox_InitTables
    call Vox_BuildPath
    call Vox_BuildHeights
    call Vox_BuildTexts
    xor  eax, eax
    FN_RET
FN_END Fx_Voxel_Init

; ---------------------------------------------------------------------------
; Fx_Voxel_Render(rcx = fb, edx = scene ms)
; ---------------------------------------------------------------------------
FN_BEGIN Fx_Voxel_Render, 16
    mov  QWORD PTR [rsp+LOC], rcx
    mov  DWORD PTR [rsp+LOC+8], edx
    mov  ecx, edx
    call Vox_Camera
    mov  rcx, QWORD PTR [rsp+LOC]
    call Vox_Frame
    mov  rcx, QWORD PTR [rsp+LOC]
    mov  edx, DWORD PTR [rsp+LOC+8]
    call Vox_Credits
    FN_RET
FN_END Fx_Voxel_Render

END
