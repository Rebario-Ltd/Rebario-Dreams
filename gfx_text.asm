; ============================================================================
; gfx_text.asm - drawing 8-bit coverage masks (text) into a framebuffer and
;                box-blurring masks for glow.
; ============================================================================
INCLUDE common.inc

.const
ALIGN 16
kMrHalf    REAL4 0.5
kMrOne     REAL4 1.0
kMrMax     REAL4 255.0
kMrFour    REAL4 4.0

.data?
ALIGN 16
mskTmp     BYTE 524288 DUP (?)

.code

; ---------------------------------------------------------------------------
; Msk_Radial(rcx = TXMASK * out, edx = size, r8d = power 1, 2 or 3)
; Allocates a size x size mask holding a soft round glow: 255 in the centre,
; falling to 0 at the border as (1 - r/R) or (1 - r/R)^2; power 3 gives a
; flat disc (255) whose outer quarter fades out (bokeh).
; ---------------------------------------------------------------------------
FN_BEGIN Msk_Radial, 0
    mov  rbx, rcx
    mov  r12d, edx
    mov  r13d, r8d
    mov  eax, edx
    imul eax, edx
    mov  ecx, eax
    call Mem_Alloc
    mov  QWORD PTR [rbx+TXMASK.pix], rax
    mov  DWORD PTR [rbx+TXMASK.w], r12d
    mov  DWORD PTR [rbx+TXMASK.h], r12d
    mov  rdi, rax
    cvtsi2ss xmm5, r12d
    mulss xmm5, DWORD PTR kMrHalf          ; R = size / 2
    xor  esi, esi                          ; y
mr_row:
    cvtsi2ss xmm1, esi
    addss xmm1, DWORD PTR kMrHalf
    subss xmm1, xmm5
    mulss xmm1, xmm1                       ; dy^2
    xor  ebx, ebx                          ; x
mr_px:
    cvtsi2ss xmm0, ebx
    addss xmm0, DWORD PTR kMrHalf
    subss xmm0, xmm5
    mulss xmm0, xmm0
    addss xmm0, xmm1
    sqrtss xmm0, xmm0
    divss xmm0, xmm5                       ; r / R
    movss xmm2, DWORD PTR kMrOne
    subss xmm2, xmm0
    xorps xmm3, xmm3
    maxss xmm2, xmm3
    cmp  r13d, 3
    jne  mr_pow
    mulss xmm2, DWORD PTR kMrFour          ; power 3: flat disc with a soft rim
    minss xmm2, DWORD PTR kMrOne
    jmp  mr_lin
mr_pow:
    cmp  r13d, 2
    jb   mr_lin
    mulss xmm2, xmm2
mr_lin:
    mulss xmm2, DWORD PTR kMrMax
    cvttss2si eax, xmm2
    mov  BYTE PTR [rdi], al
    inc  rdi
    inc  ebx
    cmp  ebx, r12d
    jb   mr_px
    inc  esi
    cmp  esi, r12d
    jb   mr_row
    FN_RET
FN_END Msk_Radial

; ---------------------------------------------------------------------------
; Gfx_DrawMask(rcx = DMASK *) - blends or adds a colour through a text mask.
; Clipped against the framebuffer. Per-row colour (rowPal) and per-row x
; offset (rowOff) are optional.
; ---------------------------------------------------------------------------
FN_BEGIN Gfx_DrawMask, 0
    mov  r15, rcx
    mov  r14, QWORD PTR [r15+DMASK.tx]
    mov  r12d, DWORD PTR [r14+TXMASK.w]
    mov  r13d, DWORD PTR [r14+TXMASK.h]
    mov  rbp, QWORD PTR [r14+TXMASK.pix]
    xor  esi, esi                          ; mask row
dm_row:
    mov  eax, DWORD PTR [r15+DMASK.y]
    add  eax, esi
    cmp  eax, SCR_H
    jae  dm_next_row                       ; unsigned: also rejects negatives
    mov  r8d, eax                          ; screen row
    mov  ecx, DWORD PTR [r15+DMASK.x]
    mov  rdx, QWORD PTR [r15+DMASK.rowOff]
    test rdx, rdx
    jz   dm_nooff
    add  ecx, DWORD PTR [rdx+rsi*4]
dm_nooff:
    mov  r9d, DWORD PTR [r15+DMASK.color]
    mov  rdx, QWORD PTR [r15+DMASK.rowPal]
    test rdx, rdx
    jz   dm_nopal
    mov  r9d, DWORD PTR [rdx+rsi*4]
dm_nopal:
    xor  r10d, r10d                        ; first column = max(0, -x)
    mov  eax, ecx
    neg  eax
    cmp  eax, 0
    jle  dm_c0
    mov  r10d, eax
dm_c0:
    mov  r11d, SCR_W                       ; last column (excl.) = min(w, SCR_W - x)
    sub  r11d, ecx
    cmp  r11d, r12d
    jle  dm_c1
    mov  r11d, r12d
dm_c1:
    cmp  r10d, r11d
    jge  dm_next_row
    mov  eax, r8d
    imul eax, SCR_W
    add  eax, ecx
    movsxd rax, eax                        ; may be negative when x < 0
    mov  rdi, QWORD PTR [r15+DMASK.dst]
    lea  rdi, [rdi+rax*4]
    mov  eax, esi
    imul eax, r12d
    lea  rbx, [rbp+rax]                    ; mask row
    mov  r8d, DWORD PTR [r15+DMASK.mode]
dm_px:
    movzx eax, BYTE PTR [rbx+r10]
    test eax, eax
    jz   dm_px_next
    imul eax, DWORD PTR [r15+DMASK.alpha]
    shr  eax, 8
    jz   dm_px_next
    mov  edx, eax
    shr  edx, 7
    add  eax, edx                          ; a = 0..256
    test r8d, r8d
    jnz  dm_add
    mov  ecx, 256
    sub  ecx, eax                          ; 256 - a
    mov  edx, DWORD PTR [rdi+r10*4]
    mov  r14d, edx
    and  r14d, 00FF00FFh
    imul r14d, ecx
    mov  edx, r9d
    and  edx, 00FF00FFh
    imul edx, eax
    add  r14d, edx
    shr  r14d, 8
    and  r14d, 00FF00FFh                   ; R,B channels
    mov  edx, DWORD PTR [rdi+r10*4]
    and  edx, 0000FF00h
    imul edx, ecx
    mov  ecx, r9d
    and  ecx, 0000FF00h
    imul ecx, eax
    add  edx, ecx
    shr  edx, 8
    and  edx, 0000FF00h                    ; G channel
    or   edx, r14d
    mov  DWORD PTR [rdi+r10*4], edx
    jmp  dm_px_next
dm_add:
    mov  edx, r9d
    and  edx, 00FF00FFh
    imul edx, eax
    shr  edx, 8
    and  edx, 00FF00FFh
    mov  ecx, r9d
    and  ecx, 0000FF00h
    imul ecx, eax
    shr  ecx, 8
    and  ecx, 0000FF00h
    or   edx, ecx
    movd xmm0, edx
    movd xmm1, DWORD PTR [rdi+r10*4]
    paddusb xmm0, xmm1
    movd DWORD PTR [rdi+r10*4], xmm0
dm_px_next:
    inc  r10d
    cmp  r10d, r11d
    jl   dm_px
dm_next_row:
    inc  esi
    cmp  esi, r13d
    jb   dm_row
    FN_RET
FN_END Gfx_DrawMask

; ---------------------------------------------------------------------------
; Msk_BoxBlur(rcx = pixels, edx = w, r8d = h, r9d = radius) - in place,
; one horizontal and one vertical box pass (w*h <= 524288).
; ---------------------------------------------------------------------------
FN_BEGIN Msk_BoxBlur, 16
    mov  r12, rcx
    mov  r13d, edx
    mov  r14d, r8d
    mov  r15d, r9d
    lea  ecx, [r15*2+1]                    ; n = 2r + 1
    lea  eax, [rcx+65535]
    xor  edx, edx
    div  ecx                               ; recip = ceil(65536 / n)
    mov  DWORD PTR [rsp+LOC], eax
    xor  esi, esi                          ; --- horizontal pass: pix -> mskTmp
bh_row:
    mov  eax, esi
    imul eax, r13d
    lea  rdi, [r12+rax]
    lea  rbx, mskTmp
    add  rbx, rax
    xor  ebp, ebp
    xor  ecx, ecx
bh_init:
    cmp  ecx, r15d
    ja   bh_init_end
    cmp  ecx, r13d
    jae  bh_init_end
    movzx eax, BYTE PTR [rdi+rcx]
    add  ebp, eax
    inc  ecx
    jmp  bh_init
bh_init_end:
    xor  ecx, ecx
bh_px:
    mov  eax, ebp
    imul eax, DWORD PTR [rsp+LOC]
    shr  eax, 16
    mov  BYTE PTR [rbx+rcx], al
    lea  edx, [rcx+r15+1]
    cmp  edx, r13d
    jae  bh_noadd
    movzx eax, BYTE PTR [rdi+rdx]
    add  ebp, eax
bh_noadd:
    mov  edx, ecx
    sub  edx, r15d
    js   bh_nosub
    movzx eax, BYTE PTR [rdi+rdx]
    sub  ebp, eax
bh_nosub:
    inc  ecx
    cmp  ecx, r13d
    jb   bh_px
    inc  esi
    cmp  esi, r14d
    jb   bh_row
    xor  esi, esi                          ; --- vertical pass: mskTmp -> pix
bv_col:
    lea  rdi, mskTmp
    add  rdi, rsi
    lea  rbx, [r12+rsi]
    xor  ebp, ebp
    xor  ecx, ecx
bv_init:
    cmp  ecx, r15d
    ja   bv_init_end
    cmp  ecx, r14d
    jae  bv_init_end
    mov  eax, ecx
    imul eax, r13d
    movzx eax, BYTE PTR [rdi+rax]
    add  ebp, eax
    inc  ecx
    jmp  bv_init
bv_init_end:
    xor  ecx, ecx
bv_px:
    mov  eax, ebp
    imul eax, DWORD PTR [rsp+LOC]
    shr  eax, 16
    mov  edx, ecx
    imul edx, r13d
    mov  BYTE PTR [rbx+rdx], al
    lea  edx, [rcx+r15+1]
    cmp  edx, r14d
    jae  bv_noadd
    imul edx, r13d
    movzx eax, BYTE PTR [rdi+rdx]
    add  ebp, eax
bv_noadd:
    mov  edx, ecx
    sub  edx, r15d
    js   bv_nosub
    imul edx, r13d
    movzx eax, BYTE PTR [rdi+rdx]
    sub  ebp, eax
bv_nosub:
    inc  ecx
    cmp  ecx, r14d
    jb   bv_px
    inc  esi
    cmp  esi, r13d
    jb   bv_col
    FN_RET
FN_END Msk_BoxBlur

END
