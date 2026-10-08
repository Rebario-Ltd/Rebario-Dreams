; ============================================================================
; fx_blobs.asm - scene 4 "MERCURY": liquid chrome metaballs.
; ----------------------------------------------------------------------------
; The scalar field is accumulated by splatting a precomputed compact kernel
; ((1 - d^2/R^2)^2) for every ball into a 16-bit buffer with a margin (so no
; clipping is needed).  Pixels above the threshold are shaded as a sphere:
; the outward direction comes from the field gradient, the tilt from a LUT of
; the field value (flat in the middle, grazing at the silhouette), and the
; colour from a procedural chrome environment map (matcap).  Pixels below the
; threshold get a neon halo proportional to the field on top of a gradient
; with drifting bokeh discs.  Everything is a pure function of time.
; ============================================================================
INCLUDE common.inc

BLB_M    EQU 80                           ; field margin around the screen
BLB_FW   EQU SCR_W + 2 * BLB_M            ; 800
BLB_FH   EQU SCR_H + 2 * BLB_M            ; 520
BLB_R1   EQU 72                           ; big kernel radius
BLB_S1   EQU 152                          ; big kernel row stride (words, multiple of 8)
BLB_R2   EQU 52
BLB_S2   EQU 112
THRESH   EQU 2048                         ; field value of the surface
BLB_TILT EQU 350                         ; gradient -> matcap offset, 1/1024 units
BLB_EDGE EQU 1260                        ; edge anti-aliasing slope, 1/1024 units
BLB_TMAX EQU 120                         ; longest matcap offset (the matcap radius is 127)
NBALLS   EQU 9
NBOKEH   EQU 20

; ball parameter block (DWORDs)
BALL STRUCT
    rngX DWORD ?                          ; horizontal amplitude, pixels
    rngY DWORD ?                          ; vertical amplitude
    fx   DWORD ?                          ; frequencies (sine steps per 1024 ms)
    fy   DWORD ?
    phx  DWORD ?                          ; phases (sine steps)
    phy  DWORD ?
    kern DWORD ?                          ; 0 big kernel, 1 small kernel
    amp  DWORD ?                          ; relative amplitude, 256 = 1.0
BALL ENDS

V_FB     EQU LOC + 0
V_T      EQU LOC + 8

.const
ALIGN 16
kMHalf   REAL4 0.5
kMOne    REAL4 1.0
kMBias   REAL4 0.40                       ; where the environment horizon sits
kMC      REAL4 127.5
kMInv    REAL4 0.0078431373               ; 1 / 127.5
k255m    REAL4 255.0
k256m    REAL4 256.0
kMHx     REAL4 -0.2486
kMHy     REAL4 0.3425
kMHz     REAL4 0.9059

ballTab  BALL <230, 100, 520, 710,    0,  700, 0, 256>
         BALL <200, 120, 690, 450, 1500,  100, 0, 240>
         BALL <150,  90, 810, 880,  900, 2200, 0, 230>
         BALL <260,  60, 380, 940, 3000, 1400, 0, 250>
         BALL <120, 130, 970, 620, 2500, 3300, 1, 190>
         BALL <240, 110, 440, 530,  700, 2900, 1, 184>
         BALL <170,  80, 760, 1040, 3600, 500, 1, 180>
         BALL < 90,  50, 1100, 830, 1900, 3900, 1, 176>
         BALL <280, 125, 330, 600,  400, 1800, 0, 256>

bokSize  DWORD 56, 88, 136
bokColor DWORD 00FF2E88h, 0038C6F4h, 007A5CFFh, 00FFB347h

; chrome environment: dark floor, violet, pink, warm horizon line, cyan sky, deep blue zenith
envKeys  DWORD 8
         DWORD 0,     000A0A28h
         DWORD 19661, 003A1C8Ah
         DWORD 28836, 00C83C9Eh
         DWORD 32440, 00FFB0C0h
         DWORD 33096, 00FFF4E0h
         DWORD 34079, 007CD8FFh
         DWORD 45875, 002E6AE0h
         DWORD 65536, 000A1050h
haloKeys DWORD 4
         DWORD 0,     00000000h
         DWORD 22937, 001A0A3Ah
         DWORD 45875, 006A1A8Ah
         DWORD 65536, 00FF4CA8h
bgKeys   DWORD 3
         DWORD 0,     000A0418h
         DWORD 40000, 0014082Eh
         DWORD 65536, 00280C48h

.data?
ALIGN 16
blbField  WORD BLB_FW * BLB_FH DUP (?)
blbKern1  WORD BLB_S1 * (2 * BLB_R1 + 1) DUP (?)
blbKern2  WORD BLB_S2 * (2 * BLB_R2 + 1) DUP (?)
blbMatcap DWORD 65536 DUP (?)
blbEnv    DWORD 256 DUP (?)
blbHalo   DWORD 1024 DUP (?)
blbBg     DWORD SCR_H DUP (?)
blbBok    BYTE 48 DUP (?)                 ; 3 x TXMASK

.code

; ---------------------------------------------------------------------------
; Blb_BuildKernel(rcx = dst, edx = R, r8d = row stride in words)
; k = 8192 * (1 - d^2/R^2)^2 inside the radius, zero outside / in the padding.
; ---------------------------------------------------------------------------
FN_BEGIN Blb_BuildKernel, 0
    mov  rdi, rcx
    mov  r12d, edx                         ; R
    mov  r13d, r8d                         ; stride
    mov  r14d, edx
    imul r14d, edx                         ; R^2
    lea  r15d, [r12*2+1]                   ; rows
    xor  esi, esi                          ; y
bk_row:
    xor  ebx, ebx                          ; x
bk_px:
    xor  eax, eax
    mov  ecx, ebx
    sub  ecx, r12d
    imul ecx, ecx                          ; dx^2
    mov  edx, esi
    sub  edx, r12d
    imul edx, edx
    add  ecx, edx                          ; d^2
    cmp  ebx, r15d
    jae  bk_store
    cmp  ecx, r14d
    jae  bk_store
    mov  eax, r14d
    sub  eax, ecx                          ; R^2 - d^2
    shl  eax, 14
    xor  edx, edx
    div  r14d                              ; q = 16384 * (1 - d^2/R^2), k = q^2 / 32768
    imul eax, eax
    shr  eax, 15                           ; peak 8192: headroom for overlapping balls
bk_store:
    mov  WORD PTR [rdi], ax
    add  rdi, 2
    inc  ebx
    cmp  ebx, r13d
    jb   bk_px
    inc  esi
    cmp  esi, r15d
    jb   bk_row
    FN_RET
FN_END Blb_BuildKernel

; ---------------------------------------------------------------------------
; Blb_BuildMatcap - 256 x 256 chrome sphere: environment reflection (planar
; horizon), a tight specular highlight and a soft rim light.
; ---------------------------------------------------------------------------
FN_BEGIN Blb_BuildMatcap, 16
    lea  rdi, blbMatcap
    xor  r12d, r12d                        ; v
bm_row:
    xor  r13d, r13d                        ; u
bm_px:
    cvtsi2ss xmm0, r13d
    subss xmm0, DWORD PTR kMC
    mulss xmm0, DWORD PTR kMInv            ; nx
    cvtsi2ss xmm1, r12d
    movss xmm2, DWORD PTR kMC
    subss xmm2, xmm1
    mulss xmm2, DWORD PTR kMInv            ; ny (up)
    movaps xmm3, xmm0
    mulss xmm3, xmm3
    movaps xmm4, xmm2
    mulss xmm4, xmm4
    addss xmm3, xmm4                       ; r^2
    movss xmm4, DWORD PTR kMOne
    comiss xmm3, xmm4
    jbe  bm_in
    sqrtss xmm5, xmm3
    divss xmm0, xmm5
    divss xmm2, xmm5
    movaps xmm3, xmm4                      ; clamp onto the rim
bm_in:
    subss xmm4, xmm3
    xorps xmm5, xmm5
    maxss xmm4, xmm5
    sqrtss xmm5, xmm4                      ; nz
    movss DWORD PTR [rsp+LOC], xmm0
    movss DWORD PTR [rsp+LOC+4], xmm2
    movss DWORD PTR [rsp+LOC+8], xmm5
    movaps xmm1, xmm5
    mulss xmm1, xmm2                       ; ry / 2
    addss xmm1, DWORD PTR kMBias
    mulss xmm1, DWORD PTR k255m
    cvttss2si eax, xmm1                    ; environment index
    xor  ecx, ecx
    test eax, eax
    cmovs eax, ecx
    mov  ecx, 255
    cmp  eax, 255
    cmova eax, ecx
    lea  rdx, blbEnv
    mov  eax, DWORD PTR [rdx+rax*4]
    movss xmm0, DWORD PTR [rsp+LOC]        ; specular: (N.H)^32
    mulss xmm0, DWORD PTR kMHx
    movss xmm1, DWORD PTR [rsp+LOC+4]
    mulss xmm1, DWORD PTR kMHy
    addss xmm0, xmm1
    movss xmm1, DWORD PTR [rsp+LOC+8]
    mulss xmm1, DWORD PTR kMHz
    addss xmm0, xmm1
    xorps xmm1, xmm1
    maxss xmm0, xmm1
    mulss xmm0, xmm0
    mulss xmm0, xmm0
    mulss xmm0, xmm0
    mulss xmm0, xmm0
    mulss xmm0, xmm0
    mulss xmm0, DWORD PTR k255m
    cvttss2si ecx, xmm0
    imul ecx, ecx, 00010101h
    PIXADD eax, ecx, xmm0, xmm1
    movss xmm1, DWORD PTR kMOne            ; rim: (1 - nz)^3
    subss xmm1, DWORD PTR [rsp+LOC+8]
    movaps xmm2, xmm1
    mulss xmm1, xmm1
    mulss xmm1, xmm2
    mulss xmm1, DWORD PTR k256m
    cvttss2si edx, xmm1
    mov  ecx, 00FF4CA8h
    PIXSCALE ecx, edx, r8d
    PIXADD eax, ecx, xmm0, xmm1
    mov  DWORD PTR [rdi], eax
    add  rdi, 4
    inc  r13d
    cmp  r13d, 256
    jb   bm_px
    inc  r12d
    cmp  r12d, 256
    jb   bm_row
    FN_RET
FN_END Blb_BuildMatcap

FN_BEGIN Fx_Blobs_Init, 0
    lea  rcx, blbKern1
    mov  edx, BLB_R1
    mov  r8d, BLB_S1
    call Blb_BuildKernel
    lea  rcx, blbKern2
    mov  edx, BLB_R2
    mov  r8d, BLB_S2
    call Blb_BuildKernel
    lea  rcx, blbEnv
    mov  edx, 256
    lea  r8, envKeys
    call Pal_FromKeys
    lea  rcx, blbHalo
    mov  edx, 1024
    lea  r8, haloKeys
    call Pal_FromKeys
    lea  rcx, blbBg
    mov  edx, SCR_H
    lea  r8, bgKeys
    call Pal_FromKeys
    call Blb_BuildMatcap
    xor  ebx, ebx
bi_bok:
    lea  rax, bokSize
    mov  edx, DWORD PTR [rax+rbx*4]
    mov  ecx, ebx
    shl  ecx, 4
    lea  rax, blbBok
    add  rcx, rax
    mov  r8d, 3
    call Msk_Radial
    inc  ebx
    cmp  ebx, 3
    jb   bi_bok
    xor  eax, eax
    FN_RET
FN_END Fx_Blobs_Init

; ---------------------------------------------------------------------------
; Blb_Splat - adds a kernel into the field (custom register convention).
;   rcx = field cell of the kernel's top-left corner, rdx = kernel,
;   r8d = rows, r9d = 8-word vectors per row, r10d = amplitude 0..65535
; ---------------------------------------------------------------------------
LEAF_BEGIN Blb_Splat
    BCAST16 xmm2, r10d
    mov  r10d, r9d
    shl  r10d, 4                           ; kernel row stride in bytes
sp_row:
    xor  eax, eax
    mov  r11d, r9d
sp_vec:
    movdqu xmm0, XMMWORD PTR [rdx+rax]
    pmulhuw xmm0, xmm2
    movdqu xmm1, XMMWORD PTR [rcx+rax]
    paddusw xmm1, xmm0
    movdqu XMMWORD PTR [rcx+rax], xmm1
    add  eax, 16
    dec  r11d
    jnz  sp_vec
    add  rcx, BLB_FW * 2
    add  rdx, r10
    dec  r8d
    jnz  sp_row
    ret
LEAF_END Blb_Splat

; ---------------------------------------------------------------------------
; Blb_PlaceBall(ecx = ball index, edx = ms) - evaluates its Lissajous
; position and splats it.  Beat: the amplitude swells with gKick.
; ---------------------------------------------------------------------------
FN_BEGIN Blb_PlaceBall, 0
    mov  r13d, edx
    imul ecx, ecx, SIZEOF BALL
    lea  rsi, ballTab
    add  rsi, rcx
    lea  rdi, gSinTab
    mov  eax, r13d
    imul eax, DWORD PTR [rsi+BALL.fx]
    shr  eax, 10
    add  eax, DWORD PTR [rsi+BALL.phx]
    and  eax, 4095
    movsx eax, WORD PTR [rdi+rax*2]
    imul eax, DWORD PTR [rsi+BALL.rngX]
    sar  eax, 15
    add  eax, SCR_W / 2
    mov  r12d, eax                         ; x
    mov  eax, r13d
    imul eax, DWORD PTR [rsi+BALL.fy]
    shr  eax, 10
    add  eax, DWORD PTR [rsi+BALL.phy]
    and  eax, 4095
    movsx eax, WORD PTR [rdi+rax*2]
    imul eax, DWORD PTR [rsi+BALL.rngY]
    sar  eax, 15
    add  eax, SCR_H / 2
    mov  r14d, eax                         ; y
    mov  eax, gKick
    shr  eax, 1
    add  eax, 256
    imul eax, DWORD PTR [rsi+BALL.amp]
    cmp  eax, 65535
    jbe  pb_amp
    mov  eax, 65535
pb_amp:
    mov  r10d, eax
    cmp  DWORD PTR [rsi+BALL.kern], 0
    jne  pb_small
    mov  ecx, BLB_R1                       ; big kernel
    lea  rdx, blbKern1
    mov  r8d, 2 * BLB_R1 + 1
    mov  r9d, BLB_S1 / 8
    jmp  pb_go
pb_small:
    mov  ecx, BLB_R2
    lea  rdx, blbKern2
    mov  r8d, 2 * BLB_R2 + 1
    mov  r9d, BLB_S2 / 8
pb_go:
    mov  eax, r14d                         ; field cell of the kernel's corner
    sub  eax, ecx
    add  eax, BLB_M
    imul eax, BLB_FW
    add  eax, r12d
    sub  eax, ecx
    add  eax, BLB_M
    cdqe
    lea  rcx, blbField
    lea  rcx, [rcx+rax*2]
    call Blb_Splat
    FN_RET
FN_END Blb_PlaceBall

; ---------------------------------------------------------------------------
; Blb_Bokeh(rcx = fb, edx = ms) - NBOKEH soft discs rising slowly; positions,
; sizes, colours and speeds come from a hash of the disc index.
; ---------------------------------------------------------------------------
FN_BEGIN Blb_Bokeh, 64
    lea  rdi, [rsp+LOC]                    ; DMASK
    mov  QWORD PTR [rdi+DMASK.dst], rcx
    mov  DWORD PTR [rdi+DMASK.mode], 1
    mov  QWORD PTR [rdi+DMASK.rowPal], 0
    mov  QWORD PTR [rdi+DMASK.rowOff], 0
    mov  r12d, edx                         ; t
    xor  ebx, ebx
bk2_lp:
    mov  ecx, ebx
    mov  edx, 7
    mov  r8d, 99
    call Mth_Hash2
    mov  r14d, eax                         ; h1: position / phase
    mov  ecx, ebx
    mov  edx, 11
    mov  r8d, 5
    call Mth_Hash2
    mov  r15d, eax                         ; h2: size / colour / speed / alpha
    mov  eax, r15d
    shr  eax, 8
    and  eax, 255
    imul eax, 3
    shr  eax, 8                            ; size class 0..2
    mov  esi, eax
    lea  rdx, bokSize
    mov  ecx, DWORD PTR [rdx+rsi*4]
    shr  ecx, 1                            ; half size
    mov  r13d, ecx
    shl  esi, 4
    lea  rdx, blbBok
    add  rsi, rdx                          ; TXMASK *
    mov  QWORD PTR [rdi+DMASK.tx], rsi
    mov  eax, r14d
    and  eax, 1023
    imul eax, 760
    shr  eax, 10
    sub  eax, 60                           ; x0
    mov  r8d, eax
    mov  eax, r15d
    shr  eax, 20
    and  eax, 15
    add  eax, 14                           ; speed, pixels per ~1 s
    imul eax, r12d
    shr  eax, 10                           ; distance risen
    mov  r9d, eax
    mov  eax, r14d
    shr  eax, 12
    and  eax, 1023
    imul eax, 480
    shr  eax, 10                           ; y0
    add  eax, 480 * 128
    sub  eax, r9d
    xor  edx, edx
    mov  ecx, 480
    div  ecx
    sub  edx, 60                           ; y
    mov  r9d, edx
    mov  eax, r14d
    shr  eax, 22
    and  eax, 63
    shl  eax, 3
    add  eax, 200
    imul eax, r12d
    shr  eax, 10
    mov  edx, r14d
    and  edx, 4095
    add  eax, edx
    and  eax, 4095
    lea  rdx, gSinTab
    movsx eax, WORD PTR [rdx+rax*2]
    imul eax, 14
    sar  eax, 15
    add  r8d, eax                          ; x + sway
    sub  r8d, r13d
    mov  DWORD PTR [rdi+DMASK.x], r8d
    sub  r9d, r13d
    mov  DWORD PTR [rdi+DMASK.y], r9d
    mov  eax, r15d
    shr  eax, 14
    and  eax, 3
    lea  rdx, bokColor
    mov  eax, DWORD PTR [rdx+rax*4]
    mov  DWORD PTR [rdi+DMASK.color], eax
    mov  eax, r15d
    shr  eax, 24
    and  eax, 31
    add  eax, eax
    add  eax, 36
    mov  edx, gKick
    shr  edx, 3
    add  eax, edx
    mov  DWORD PTR [rdi+DMASK.alpha], eax
    mov  rcx, rdi
    call Gfx_DrawMask
    inc  ebx
    cmp  ebx, NBOKEH
    jb   bk2_lp
    FN_RET
FN_END Blb_Bokeh

; ---------------------------------------------------------------------------
; Fx_Blobs_Render(rcx = fb, edx = local ms)
; ---------------------------------------------------------------------------
FN_BEGIN Fx_Blobs_Render, 32
    mov  QWORD PTR [rsp+V_FB], rcx
    mov  DWORD PTR [rsp+V_T], edx
    mov  rdi, rcx                          ; gradient backdrop, row by row
    lea  rsi, blbBg
    xor  ebx, ebx
bs_bg:
    mov  eax, DWORD PTR [rsi+rbx*4]
    mov  ecx, SCR_W
    rep  stosd
    inc  ebx
    cmp  ebx, SCR_H
    jb   bs_bg
    mov  rcx, QWORD PTR [rsp+V_FB]
    mov  edx, DWORD PTR [rsp+V_T]
    call Blb_Bokeh
    lea  rdi, blbField                     ; clear the field
    xor  eax, eax
    mov  ecx, BLB_FW * BLB_FH / 2
    rep  stosd
    xor  ebx, ebx
bl_balls:
    mov  ecx, ebx
    mov  edx, DWORD PTR [rsp+V_T]
    call Blb_PlaceBall
    inc  ebx
    cmp  ebx, NBALLS
    jb   bl_balls
    lea  rsi, blbField
    add  rsi, (BLB_M * BLB_FW + BLB_M) * 2
    mov  rdi, QWORD PTR [rsp+V_FB]
    lea  r8, blbMatcap
    lea  r9, blbHalo
    mov  r15d, DWORD PTR [r9+1023*4]       ; halo colour at the surface
    xor  r12d, r12d                        ; y
bs_row:
    xor  ecx, ecx
bs_px:
    movzx eax, WORD PTR [rsi+rcx*2]
    cmp  eax, THRESH
    jb   bs_out
    mov  ebx, eax                          ; f
    movzx ebp, WORD PTR [rsi+rcx*2+2]
    movzx eax, WORD PTR [rsi+rcx*2-2]
    sub  ebp, eax                          ; gx
    imul ebp, BLB_TILT
    sar  ebp, 10
    neg  ebp                               ; dx: outward normal = -gradient
    movzx r10d, WORD PTR [rsi+rcx*2+BLB_FW*2]
    movzx eax, WORD PTR [rsi+rcx*2-BLB_FW*2]
    sub  r10d, eax                         ; gy
    imul r10d, BLB_TILT
    sar  r10d, 10
    neg  r10d                              ; dy
    mov  eax, ebp
    cdq
    xor  eax, edx
    sub  eax, edx                          ; |dx|
    mov  r11d, r10d
    mov  edx, r10d
    sar  edx, 31
    xor  r11d, edx
    sub  r11d, edx                         ; |dy|
    cmp  eax, r11d
    jae  bs_ord
    xchg eax, r11d
bs_ord:
    shr  r11d, 1
    add  eax, r11d                         ; length estimate max + min/2
    cmp  eax, BLB_TMAX
    jbe  bs_nolim
    mov  r11d, eax                         ; merged blobs: shorten, keep the direction
    mov  eax, BLB_TMAX * 65536
    xor  edx, edx
    div  r11d
    imul ebp, eax
    sar  ebp, 16
    imul r10d, eax
    sar  r10d, 16
bs_nolim:
    add  ebp, 128
    add  r10d, 128
    shl  r10d, 8
    or   r10d, ebp                         ; matcap index (v << 8) | u
    mov  eax, DWORD PTR [r8+r10*4]         ; chrome colour
    sub  ebx, THRESH
    imul ebx, BLB_EDGE
    shr  ebx, 10                           ; edge coverage 0..256
    cmp  ebx, 256
    jae  bs_store
    mov  edx, DWORD PTR [rdi]
    PIXADD edx, r15d, xmm0, xmm1           ; backdrop + halo at the silhouette
    PIXMIX edx, eax, ebx, r10d, r11d       ; soften the edge
    mov  eax, edx
bs_store:
    mov  DWORD PTR [rdi], eax
    jmp  bs_next
bs_out:
    shr  eax, 2
    mov  eax, DWORD PTR [r9+rax*4]         ; neon halo over the backdrop
    mov  edx, DWORD PTR [rdi]
    PIXADD eax, edx, xmm0, xmm1
    mov  DWORD PTR [rdi], eax
bs_next:
    add  rdi, 4
    inc  ecx
    cmp  ecx, SCR_W
    jb   bs_px
    add  rsi, BLB_FW * 2
    inc  r12d
    cmp  r12d, SCR_H
    jb   bs_row
    FN_RET
FN_END Fx_Blobs_Render

END
