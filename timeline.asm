; ============================================================================
; timeline.asm - scene schedule, beat clock, transitions, captions and the
;                top-level frame composition (Demo_Init / Demo_Render).
; ----------------------------------------------------------------------------
; Every scene is a pure function of its local time, so any frame can be
; rendered at any moment (seeking, screenshots and tests need no state).
; Scene i owns [i*SCENE_MS, (i+1)*SCENE_MS); during the last TRANS_MS the next
; scene is rendered too and the two are blended. Scenes 1.. start TRANS_MS
; early so they already animate while fading in.
;
; The beat reaches the picture as one smooth swell (gBeatEnv: peak on the
; beat, zero half a beat later, no corner).  Every scene is drawn with that
; swell scaled by its own depth (scenePulse), published to the scene code as
; gKick, so the scenes do not know about the depths and a scene can be made
; steadier or livelier by one number.  The bloom pump follows the same depth.
; ============================================================================
INCLUDE common.inc

CAP_FADE_IN_AT EQU 800
CAP_HOLD_UNTIL EQU 5400

.const
szCap0 BYTE 0
szCap1 BYTE "01   AURORA  /  PLASMA", 0
szCap2 BYTE "02   WORMHOLE  /  TUNNEL", 0
szCap3 BYTE "03   WARP  /  STARFIELD", 0
szCap4 BYTE "04   MERCURY  /  METABALLS", 0
szCap5 BYTE "05   MANDALA  /  FRACTAL ROTOZOOM", 0
szCap6 BYTE "06   INFERNO  /  FIRE", 0
szCap7 BYTE "07   PRISM  /  SOFTWARE 3D", 0
szCap8 BYTE "08   TERRA  /  VOXEL LANDSCAPE", 0

.data
ALIGN 16
sceneTab SCENE <Fx_Title_Render,  Fx_Title_Init,  szCap0, 0, BLOOMPACK(140, 640)>
         SCENE <Fx_Plasma_Render, Fx_Plasma_Init, szCap1, 1, BLOOMPACK(205, 420)>
         SCENE <Fx_Tunnel_Render, Fx_Tunnel_Init, szCap2, 2, BLOOMPACK(165, 520)>
         SCENE <Fx_Stars_Render,  Fx_Stars_Init,  szCap3, 0, BLOOMPACK(190, 900)>
         SCENE <Fx_Blobs_Render,  Fx_Blobs_Init,  szCap4, 2, BLOOMPACK(150, 576)>
         SCENE <Fx_Roto_Render,   Fx_Roto_Init,   szCap5, 1, BLOOMPACK(220, 300)>
         SCENE <Fx_Fire_Render,   Fx_Fire_Init,   szCap6, 0, BLOOMPACK(190, 448)>
         SCENE <Fx_Prism_Render,  Fx_Prism_Init,  szCap7, 2, BLOOMPACK(190, 320)>
         SCENE <Fx_Voxel_Render,  Fx_Voxel_Init,  szCap8, 0, BLOOMPACK(215, 420)>

; How much of the beat swell the picture of each scene shows, 0..256: 256 is
; the full punch the scenes were written for (the old hard kick), 0 a steady
; picture.  With these values one beat changes the mean brightness of a scene
; by about 3 %, never by more than 5 %; the landscape does not pulse at all.
scenePulse DWORD 48, 56, 32, 96, 40, 40, 40, 72, 0
.ERRNZ ($ - scenePulse) - NUM_SCENES * 4        ; one depth per scene

.data?
ALIGN 16
capMask BYTE NUM_SCENES * 16 DUP (?)       ; TXMASK[NUM_SCENES]
capReq  BYTE 48 DUP (?)                    ; FONTREQ

.code

; Tl_Progress(ecx = percent) - records progress and pings the optional callback.
FN_BEGIN Tl_Progress, 0
    mov  gProgress, ecx
    mov  rax, gProgressCb
    test rax, rax
    jz   tp_done
    call rax
tp_done:
    FN_RET
FN_END Tl_Progress

; ---------------------------------------------------------------------------
; Demo_Init -> eax = 0. Tables, buffers, every scene, caption masks.
; ---------------------------------------------------------------------------
FN_BEGIN Demo_Init, 0
    call Mth_Init
    call Gfx_Init
    call Gfx_FxInit
    call Bloom_Init
    mov  ecx, SCR_BYTES
    call Mem_Alloc
    mov  gFbA, rax
    mov  ecx, SCR_BYTES
    call Mem_Alloc
    mov  gFbB, rax
    mov  ecx, SCR_BYTES
    call Mem_Alloc
    mov  gFbC, rax
    mov  ecx, OUT_BYTES
    call Mem_Alloc
    mov  gFbOut, rax
    xor  ebx, ebx
di_scene:
    lea  rax, sceneTab
    mov  ecx, ebx
    shl  ecx, 5
    call QWORD PTR [rax+rcx+SCENE.initFn]
    lea  eax, [rbx+1]
    imul eax, eax, 70
    shr  eax, 3
    add  eax, 5
    mov  ecx, eax
    call Tl_Progress
    inc  ebx
    cmp  ebx, NUM_SCENES
    jb   di_scene
    xor  ebx, ebx
di_cap:
    lea  rax, sceneTab
    mov  ecx, ebx
    shl  ecx, 5
    mov  rdx, QWORD PTR [rax+rcx+SCENE.caption]
    cmp  BYTE PTR [rdx], 0
    je   di_cap_next
    lea  rsi, capReq
    lea  rax, capMask
    mov  ecx, ebx
    shl  ecx, 4
    add  rax, rcx
    mov  QWORD PTR [rsi+FONTREQ.dst], rax
    mov  QWORD PTR [rsi+FONTREQ.text], rdx
    mov  DWORD PTR [rsi+FONTREQ.height], 24
    mov  DWORD PTR [rsi+FONTREQ.weight], 500
    mov  DWORD PTR [rsi+FONTREQ.face], 1
    mov  DWORD PTR [rsi+FONTREQ.italic], 0
    mov  DWORD PTR [rsi+FONTREQ.track], 3
    mov  rcx, rsi
    call Font_Render
di_cap_next:
    inc  ebx
    cmp  ebx, NUM_SCENES
    jb   di_cap
    xor  eax, eax
    FN_RET
FN_END Demo_Init

; ---------------------------------------------------------------------------
; Tl_BeatEnv(ecx = phase inside the beat 0..65535) -> eax = swell 0..256.
; ((1 + cos 2 pi phase) / 2) ^ 2 * 256: a smooth bump with its peak on the
; beat, 64 a quarter of a beat before and after it and 0 half a beat away.  It
; has no corner and changes by at most 1045 per beat; the hard kick envelope
; it replaces jumped by the full 256 from one frame to the next.
; ---------------------------------------------------------------------------
LEAF_BEGIN Tl_BeatEnv
    shr  ecx, 4                            ; 4096 steps per beat
    add  ecx, 1024                         ; a quarter turn on, the sine table is the cosine
    and  ecx, 4095
    lea  rax, gSinTab
    movsx eax, WORD PTR [rax+rcx*2]        ; cos * 32767
    add  eax, 32768 + 128                  ; (1 + cos) / 2 in 1/65536; the 128 rounds the peak to a full 256
    shr  eax, 8                            ; 0..256
    imul eax, eax
    shr  eax, 8                            ; squared: 0..256
    ret
LEAF_END Tl_BeatEnv

; ---------------------------------------------------------------------------
; Tl_ScenePulse(ecx = scene, edx = blend 0..256 towards the next scene)
;   -> eax = gBeatEnv * depth / 256 (0..256); touches only eax, r10, r11.
; The depths of the two scenes are cross-faded like the bloom parameters (the
; last scene has no successor), so a transition never makes the pulse jump.
; ---------------------------------------------------------------------------
LEAF_BEGIN Tl_ScenePulse
    lea  r10, scenePulse
    mov  eax, DWORD PTR [r10+rcx*4]        ; depth of this scene
    mov  r11d, eax
    cmp  ecx, NUM_SCENES - 1
    jae  sp_have
    mov  r11d, DWORD PTR [r10+rcx*4+4]     ; depth of the next scene
sp_have:
    sub  r11d, eax
    imul r11d, edx
    sar  r11d, 8
    add  eax, r11d                         ; cross-faded depth
    imul eax, DWORD PTR gBeatEnv
    shr  eax, 8
    ret
LEAF_END Tl_ScenePulse

; ---------------------------------------------------------------------------
; Tl_Update(ecx = tMs) - publishes time, beat phase and the beat swell.
; beats = t * BPM / 60000, kept as 16.16.  gKick starts as the plain swell (a
; scene drawn directly sees that); Tl_RenderScene and Tl_Bloom scale it.
; ---------------------------------------------------------------------------
FN_BEGIN Tl_Update, 0
    mov  gTimeMs, ecx
    mov  eax, ecx
    imul rax, rax, BPM * 65536
    xor  edx, edx
    mov  ecx, 60000
    div  rcx
    mov  edx, eax
    shr  edx, 16
    mov  gBeatNo, edx
    movzx ecx, ax
    mov  gBeat16, ecx
    call Tl_BeatEnv
    mov  gBeatEnv, eax
    mov  gKick, eax
    FN_RET
FN_END Tl_Update

; ---------------------------------------------------------------------------
; Tl_RenderScene(ecx = scene, rdx = fb, r8d = demo time): scene + caption.
; The scene is drawn with the beat swell at its own depth (gKick).
; Locals: DMASK at +0 (56 bytes).
; ---------------------------------------------------------------------------
FN_BEGIN Tl_RenderScene, 64
    mov  ebx, ecx
    mov  r12, rdx
    xor  edx, edx                          ; no blend: the depth of the scene itself
    call Tl_ScenePulse
    mov  gKick, eax
    mov  eax, ebx
    imul eax, eax, SCENE_MS
    mov  r13d, r8d
    sub  r13d, eax
    test ebx, ebx
    jz   rs_time
    add  r13d, TRANS_MS
rs_time:
    lea  rax, sceneTab
    mov  ecx, ebx
    shl  ecx, 5
    mov  rax, QWORD PTR [rax+rcx+SCENE.renderFn]
    mov  rcx, r12
    mov  edx, r13d
    call rax
    lea  rax, capMask
    mov  ecx, ebx
    shl  ecx, 4
    add  rax, rcx
    cmp  QWORD PTR [rax+TXMASK.pix], 0
    je   rs_done
    mov  r14, rax
    mov  eax, r13d                         ; fade in: (lt - FADE_IN_AT) * 256 / 600
    sub  eax, CAP_FADE_IN_AT
    shl  eax, 8
    cdq
    mov  ecx, 600
    idiv ecx
    mov  esi, eax
    mov  eax, CAP_HOLD_UNTIL               ; fade out: (HOLD - lt) * 256 / 800
    sub  eax, r13d
    shl  eax, 8
    cdq
    mov  ecx, 800
    idiv ecx
    cmp  eax, esi
    cmovl esi, eax
    cmp  esi, 256
    jle  rs_lo
    mov  esi, 256
rs_lo:
    test esi, esi
    jle  rs_done
    lea  rdi, [rsp+LOC]
    mov  QWORD PTR [rdi+DMASK.dst], r12
    mov  QWORD PTR [rdi+DMASK.tx], r14
    mov  DWORD PTR [rdi+DMASK.x], 28 - FONT_PAD
    mov  eax, SCR_H - 12
    sub  eax, DWORD PTR [r14+TXMASK.h]
    mov  DWORD PTR [rdi+DMASK.y], eax
    mov  DWORD PTR [rdi+DMASK.color], 00E6F4FFh
    mov  DWORD PTR [rdi+DMASK.alpha], esi
    mov  DWORD PTR [rdi+DMASK.mode], 0
    mov  QWORD PTR [rdi+DMASK.rowPal], 0
    mov  QWORD PTR [rdi+DMASK.rowOff], 0
    mov  rcx, rdi
    call Gfx_DrawMask
rs_done:
    FN_RET
FN_END Tl_RenderScene

; ---------------------------------------------------------------------------
; Tl_BloomParams(ecx = scene, edx = blend 0..256 towards the next scene)
;   -> eax = bright-pass threshold, edx = gain (8.8).
; The values of the two scenes are cross-faded (a + (b - a) * blend / 256, the
; last scene has no successor) and the gain is pumped by gKick (up to +25 % at
; a pulse of 256, capped at 1000 = x3.9).
; ---------------------------------------------------------------------------
LEAF_BEGIN Tl_BloomParams
    lea  rax, sceneTab
    shl  ecx, 5
    mov  r8d, DWORD PTR [rax+rcx+SCENE.bloom]
    mov  r9d, r8d
    cmp  ecx, (NUM_SCENES - 1) SHL 5
    jae  bp_have
    mov  r9d, DWORD PTR [rax+rcx+32+SCENE.bloom]
bp_have:
    movzx r10d, r8b                        ; threshold
    movzx r11d, r9b
    sub  r11d, r10d
    imul r11d, edx
    sar  r11d, 8
    add  r10d, r11d
    shr  r8d, 8                            ; gain, same interpolation
    shr  r9d, 8
    sub  r9d, r8d
    imul r9d, edx
    sar  r9d, 8
    add  r8d, r9d
    mov  eax, gKick
    imul eax, r8d
    shr  eax, 10
    add  r8d, eax                          ; beat pump
    cmp  r8d, 1000
    jbe  bp_cap
    mov  r8d, 1000
bp_cap:
    mov  eax, r10d
    mov  edx, r8d
    ret
LEAF_END Tl_BloomParams

; Tl_Bloom(ecx = scene, edx = blend) - glows the composite in gFbC.  The pump
; follows the (cross-faded) pulse depth of the scenes on the screen.
FN_BEGIN Tl_Bloom, 0
    call Tl_ScenePulse
    mov  gKick, eax
    call Tl_BloomParams
    mov  r8d, edx
    mov  edx, eax
    mov  rcx, gFbC
    call Bloom_Apply
    FN_RET
FN_END Tl_Bloom

; ---------------------------------------------------------------------------
; Tl_Compose(ecx = tMs) - renders the (possibly blended) scene into gFbC and
; adds the bloom.
; ---------------------------------------------------------------------------
FN_BEGIN Tl_Compose, 0
    mov  ebx, ecx
    mov  gFlash, 0
    xor  r12d, r12d                        ; blend factor (0 outside transitions)
    mov  eax, ebx
    xor  edx, edx
    mov  ecx, SCENE_MS
    div  ecx
    cmp  eax, NUM_SCENES - 1
    jbe  tc_idx
    mov  eax, NUM_SCENES - 1
    mov  edx, SCENE_MS - 1
tc_idx:
    mov  esi, eax                          ; scene
    mov  edi, edx                          ; time inside the scene
    cmp  esi, NUM_SCENES - 1
    jae  tc_single
    cmp  edi, SCENE_MS - TRANS_MS
    jae  tc_trans
tc_single:
    mov  ecx, esi
    mov  rdx, gFbC
    mov  r8d, ebx
    call Tl_RenderScene
    jmp  tc_done
tc_trans:
    mov  ecx, esi
    mov  rdx, gFbA
    mov  r8d, ebx
    call Tl_RenderScene
    lea  ecx, [rsi+1]
    mov  rdx, gFbB
    mov  r8d, ebx
    call Tl_RenderScene
    mov  eax, edi
    sub  eax, SCENE_MS - TRANS_MS
    shl  eax, 8
    xor  edx, edx
    mov  ecx, TRANS_MS
    div  ecx
    mov  r12d, eax                         ; blend factor 0..256
    lea  rax, sceneTab
    mov  ecx, esi
    shl  ecx, 5
    mov  r13d, DWORD PTR [rax+rcx+SCENE.trans]
    cmp  r13d, 1
    je   tc_flash
    cmp  r13d, 2
    je   tc_iris
    mov  rcx, gFbC                         ; style 0: cross-fade
    mov  rdx, gFbA
    mov  r8, gFbB
    mov  r9d, r12d
    call Gfx_Mix
    jmp  tc_done
tc_flash:                                  ; style 1: through white
    mov  rcx, gFbC
    mov  rdx, gFbA
    cmp  r12d, 128
    jb   tc_f_src
    mov  rdx, gFbB
tc_f_src:
    call Gfx_Copy
    mov  eax, r12d
    sub  eax, 128
    cdq
    xor  eax, edx
    sub  eax, edx                          ; |alpha - 128|
    shl  eax, 1
    mov  ecx, 255
    sub  ecx, eax
    jns  tc_f_set
    xor  ecx, ecx
tc_f_set:
    mov  gFlash, ecx
    jmp  tc_done
tc_iris:                                   ; style 2: circular wipe
    mov  rcx, gFbC
    mov  rdx, gFbA
    mov  r8, gFbB
    imul r9d, r12d, 450
    shr  r9d, 8
    sub  r9d, 40
    call Gfx_Iris
tc_done:
    mov  ecx, esi
    mov  edx, r12d
    call Tl_Bloom
    FN_RET
FN_END Tl_Compose

; ---------------------------------------------------------------------------
; Demo_Frame(ecx = tMs) - the picture of the beat state that Tl_Update has
; published: composition, global fade, post-processing and the 2x upscale
; into gFbOut.  (Split from Demo_Render so a test can pin the beat swell.)
; ---------------------------------------------------------------------------
FN_BEGIN Demo_Frame, 0
    mov  ebx, ecx
    call Tl_Compose
    mov  eax, 256                          ; global fade in / out
    cmp  ebx, 1000
    jae  dr_tail
    imul eax, ebx, 256
    mov  ecx, 1000
    xor  edx, edx
    div  ecx
    jmp  dr_fade
dr_tail:
    mov  ecx, TOTAL_MS
    sub  ecx, ebx
    cmp  ecx, 2000
    jge  dr_fade
    test ecx, ecx
    jns  dr_t2
    xor  ecx, ecx
dr_t2:
    imul eax, ecx, 256
    xor  edx, edx
    mov  ecx, 2000
    div  ecx
dr_fade:
    mov  gFade, eax
    mov  rcx, gFbC
    call Gfx_Post
    mov  rcx, gFbOut
    mov  rdx, gFbC
    call Gfx_Upscale2x
    FN_RET
FN_END Demo_Frame

; ---------------------------------------------------------------------------
; Demo_Render(ecx = tMs) - one complete presentation frame into gFbOut.
; ---------------------------------------------------------------------------
FN_BEGIN Demo_Render, 0
    mov  ebx, ecx
    call Tl_Update
    mov  ecx, ebx
    call Demo_Frame
    FN_RET
FN_END Demo_Render

END
