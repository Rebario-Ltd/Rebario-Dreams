; ============================================================================
; gfx.asm - framebuffer primitives (SSE2): fill/copy/mix/add/fade, vignette
;           post pass and the smooth 2x upscaler used for presentation.
; All framebuffers are 32-bit BGRA, 16-byte aligned.
; ============================================================================
INCLUDE common.inc

.const
ALIGN 16
kVigHalfW  REAL4 319.5
kVigHalfH  REAL4 179.5
kVigInvW   REAL4 0.003125          ; 1 / 320
kVigInvH   REAL4 0.0055555556      ; 1 / 180
kVigA      REAL4 38.0
kVigB      REAL4 14.0
k255       REAL4 255.0

.data?
ALIGN 16
gVig       BYTE SCR_PIX DUP (?)    ; vignette multiplier per pixel (255 = none)
upTmp      BYTE 5632 DUP (?)       ; two padded rows for the upscaler

.code

; Gfx_Fill(rcx = fb, edx = BGRA colour)
FN_BEGIN Gfx_Fill, 0
    mov  rdi, rcx
    mov  eax, edx
    mov  ecx, SCR_PIX
    rep  stosd
    FN_RET
FN_END Gfx_Fill

; Gfx_Copy(rcx = dst, rdx = src)
FN_BEGIN Gfx_Copy, 0
    mov  rdi, rcx
    mov  rsi, rdx
    mov  ecx, SCR_BYTES / 8
    rep  movsq
    FN_RET
FN_END Gfx_Copy

; Gfx_Mix(rcx = dst, rdx = a, r8 = b, r9d = alpha 0..256): dst = a + (b - a) * alpha / 256
FNX_BEGIN Gfx_Mix, 0
    mov  eax, 256
    sub  eax, r9d
    BCAST16 xmm6, eax
    BCAST16 xmm7, r9d
    pxor xmm5, xmm5
    xor  eax, eax
    mov  r10d, SCR_BYTES / 16
mix_lp:
    movdqa xmm0, XMMWORD PTR [rdx+rax]
    movdqa xmm1, XMMWORD PTR [r8+rax]
    movdqa xmm2, xmm0
    movdqa xmm3, xmm1
    punpcklbw xmm0, xmm5
    punpckhbw xmm2, xmm5
    punpcklbw xmm1, xmm5
    punpckhbw xmm3, xmm5
    pmullw xmm0, xmm6
    pmullw xmm2, xmm6
    pmullw xmm1, xmm7
    pmullw xmm3, xmm7
    paddw  xmm0, xmm1
    paddw  xmm2, xmm3
    psrlw  xmm0, 8
    psrlw  xmm2, 8
    packuswb xmm0, xmm2
    movdqa XMMWORD PTR [rcx+rax], xmm0
    add  rax, 16
    dec  r10d
    jnz  mix_lp
    FNX_RET
FN_END Gfx_Mix

; Gfx_AddSat(rcx = dst, rdx = src): dst = saturate(dst + src), per channel.
LEAF_BEGIN Gfx_AddSat
    xor  eax, eax
    mov  r8d, SCR_BYTES / 16
as_lp:
    movdqa xmm0, XMMWORD PTR [rcx+rax]
    movdqa xmm1, XMMWORD PTR [rdx+rax]
    paddusb xmm0, xmm1
    movdqa XMMWORD PTR [rcx+rax], xmm0
    add  rax, 16
    dec  r8d
    jnz  as_lp
    ret
LEAF_END Gfx_AddSat

; Gfx_Scale(rcx = fb, edx = multiplier 0..256): in-place brightness scale.
FNX_BEGIN Gfx_Scale, 0
    BCAST16 xmm6, edx
    pxor xmm5, xmm5
    xor  eax, eax
    mov  r10d, SCR_BYTES / 16
sc_lp:
    movdqa xmm0, XMMWORD PTR [rcx+rax]
    movdqa xmm2, xmm0
    punpcklbw xmm0, xmm5
    punpckhbw xmm2, xmm5
    pmullw xmm0, xmm6
    pmullw xmm2, xmm6
    psrlw  xmm0, 8
    psrlw  xmm2, 8
    packuswb xmm0, xmm2
    movdqa XMMWORD PTR [rcx+rax], xmm0
    add  rax, 16
    dec  r10d
    jnz  sc_lp
    FNX_RET
FN_END Gfx_Scale

; ---------------------------------------------------------------------------
; Gfx_Init - builds the vignette table (float math, once).
; ---------------------------------------------------------------------------
FN_BEGIN Gfx_Init, 0
    lea  rdi, gVig
    xor  r12d, r12d                       ; y
vg_row:
    cvtsi2ss xmm1, r12d
    subss xmm1, DWORD PTR kVigHalfH
    mulss xmm1, DWORD PTR kVigInvH
    mulss xmm1, xmm1                      ; fy^2
    xor  r13d, r13d                       ; x
vg_px:
    cvtsi2ss xmm0, r13d
    subss xmm0, DWORD PTR kVigHalfW
    mulss xmm0, DWORD PTR kVigInvW
    mulss xmm0, xmm0
    addss xmm0, xmm1                      ; r2
    movaps xmm2, xmm0
    mulss xmm2, xmm0
    mulss xmm2, DWORD PTR kVigB
    mulss xmm0, DWORD PTR kVigA
    addss xmm0, xmm2
    movss xmm3, DWORD PTR k255
    subss xmm3, xmm0
    xorps xmm4, xmm4
    maxss xmm3, xmm4
    cvttss2si eax, xmm3
    mov  BYTE PTR [rdi], al
    inc  rdi
    inc  r13d
    cmp  r13d, SCR_W
    jb   vg_px
    inc  r12d
    cmp  r12d, SCR_H
    jb   vg_row
    FN_RET
FN_END Gfx_Init

; ---------------------------------------------------------------------------
; Gfx_Post(rcx = fb): in-place  pixel = pixel * vignette * gFade + gFlash.
; ---------------------------------------------------------------------------
FNX_BEGIN Gfx_Post, 0
    mov  edx, gFade
    BCAST16 xmm6, edx
    mov  edx, gFlash
    movd xmm7, edx
    punpcklbw xmm7, xmm7
    punpcklwd xmm7, xmm7
    pshufd xmm7, xmm7, 0                  ; flash in every byte
    pxor xmm5, xmm5
    lea  rsi, gVig
    xor  eax, eax                         ; byte offset in fb
    xor  ebx, ebx                         ; pixel index in gVig
    mov  r10d, SCR_BYTES / 16
post_lp:
    movdqa xmm0, XMMWORD PTR [rcx+rax]
    movd   xmm1, DWORD PTR [rsi+rbx]
    punpcklbw xmm1, xmm1
    punpcklwd xmm1, xmm1
    movdqa xmm2, xmm0
    punpcklbw xmm0, xmm5
    punpckhbw xmm2, xmm5
    movdqa xmm3, xmm1
    punpcklbw xmm1, xmm5
    punpckhbw xmm3, xmm5
    pmullw xmm1, xmm6
    pmullw xmm3, xmm6
    psrlw  xmm1, 8
    psrlw  xmm3, 8
    pmullw xmm0, xmm1
    pmullw xmm2, xmm3
    psrlw  xmm0, 8
    psrlw  xmm2, 8
    packuswb xmm0, xmm2
    paddusb xmm0, xmm7
    movdqa XMMWORD PTR [rcx+rax], xmm0
    add  rax, 16
    add  ebx, 4
    dec  r10d
    jnz  post_lp
    FNX_RET
FN_END Gfx_Post

; ---------------------------------------------------------------------------
; Gfx_Up2(rcx = dst (2w x 2h), rdx = src (w x h), r8d = w, r9d = h)
; Bilinear 2x enlargement for any width that is a multiple of 4 (up to 640):
; a vertical blend (0.75 / 0.25) into two temporary rows, then horizontal
; expansion.  Buffers must be 16-byte aligned.
; Locals: +0 source row bytes, +4 source height, +8 destination bytes per
; source row (two output rows).
; ---------------------------------------------------------------------------
HEXPAND MACRO srcr:REQ, dstr:REQ, lbl:REQ
    xor  eax, eax
    mov  r10, dstr
lbl:
    movdqa xmm0, XMMWORD PTR [srcr+rax]
    movdqu xmm1, XMMWORD PTR [srcr+rax-4]
    movdqu xmm2, XMMWORD PTR [srcr+rax+4]
    pavgb  xmm1, xmm0
    pavgb  xmm2, xmm0
    pavgb  xmm1, xmm0
    pavgb  xmm2, xmm0
    movdqa xmm3, xmm1
    punpckldq xmm1, xmm2
    punpckhdq xmm3, xmm2
    movdqa XMMWORD PTR [r10], xmm1
    movdqa XMMWORD PTR [r10+16], xmm3
    add  r10, 32
    add  eax, 16
    cmp  eax, DWORD PTR [rsp+LOC]
    jb   lbl
ENDM

FN_BEGIN Gfx_Up2, 16
    mov  r12, rcx                         ; dst
    mov  r13, rdx                         ; src
    lea  eax, [r8*4]
    mov  DWORD PTR [rsp+LOC], eax         ; source row bytes
    shl  eax, 2
    mov  DWORD PTR [rsp+LOC+8], eax       ; output bytes per source row
    mov  DWORD PTR [rsp+LOC+4], r9d       ; source height
    lea  r14, upTmp
    add  r14, 16                          ; T row (top blend)
    lea  r15, upTmp
    add  r15, 2816 + 16                   ; B row (bottom blend)
    xor  esi, esi                         ; source row j
up_row:
    mov  eax, esi
    imul eax, DWORD PTR [rsp+LOC]
    lea  rbx, [r13+rax]                   ; row A
    mov  ecx, esi
    test ecx, ecx
    jz   up_u
    dec  ecx
up_u:
    imul ecx, DWORD PTR [rsp+LOC]
    lea  rdi, [r13+rcx]                   ; row U
    mov  ecx, esi
    mov  eax, DWORD PTR [rsp+LOC+4]
    dec  eax
    cmp  ecx, eax
    jae  up_d
    inc  ecx
up_d:
    imul ecx, DWORD PTR [rsp+LOC]
    lea  rbp, [r13+rcx]                   ; row D
    xor  eax, eax
up_vb:
    movdqa xmm0, XMMWORD PTR [rbx+rax]
    movdqa xmm1, XMMWORD PTR [rdi+rax]
    movdqa xmm2, XMMWORD PTR [rbp+rax]
    pavgb  xmm1, xmm0
    pavgb  xmm2, xmm0
    pavgb  xmm1, xmm0
    pavgb  xmm2, xmm0
    movdqa XMMWORD PTR [r14+rax], xmm1
    movdqa XMMWORD PTR [r15+rax], xmm2
    add  eax, 16
    cmp  eax, DWORD PTR [rsp+LOC]
    jb   up_vb
    mov  ecx, DWORD PTR [rsp+LOC]
    mov  eax, DWORD PTR [r14]             ; replicate edge pixels into the pads
    mov  DWORD PTR [r14-4], eax
    mov  eax, DWORD PTR [r14+rcx-4]
    mov  DWORD PTR [r14+rcx], eax
    mov  eax, DWORD PTR [r15]
    mov  DWORD PTR [r15-4], eax
    mov  eax, DWORD PTR [r15+rcx-4]
    mov  DWORD PTR [r15+rcx], eax
    mov  eax, esi
    imul eax, DWORD PTR [rsp+LOC+8]
    lea  r8, [r12+rax]                    ; first output row
    lea  r9, [r8+rcx*2]                   ; second output row (2 * source row bytes)
    HEXPAND r14, r8, up_hx1
    HEXPAND r15, r9, up_hx2
    inc  esi
    cmp  esi, DWORD PTR [rsp+LOC+4]
    jb   up_row
    FN_RET
FN_END Gfx_Up2

; Gfx_Upscale2x(rcx = dst 1280x720, rdx = src 640x360) - presentation upscale.
LEAF_BEGIN Gfx_Upscale2x
    mov  r8d, SCR_W
    mov  r9d, SCR_H
    jmp  Gfx_Up2
LEAF_END Gfx_Upscale2x

END