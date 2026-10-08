; ============================================================================
; palette.asm - colour ramps: piecewise-linear key gradients and cosine palettes
; ============================================================================
INCLUDE common.inc

.const
ALIGN 16
kTwoPiF   REAL4 6.28318530718
k255f     REAL4 255.0
kHalfF    REAL4 0.5
kZeroF    REAL4 0.0
kOneF     REAL4 1.0

.code

; ---------------------------------------------------------------------------
; Pal_FromKeys - builds a ramp by linear interpolation between key colours.
;   rcx = dst (uint32[count]), edx = count (>= 2),
;   r8  = keys: DWORD n, then n * { DWORD pos (0..65536), DWORD 0x00RRGGBB }
;   Keys must be sorted by pos; the ramp is clamped outside the first/last key.
; ---------------------------------------------------------------------------
FN_BEGIN Pal_FromKeys, 0
    mov  rdi, rcx
    mov  r15d, edx                        ; count
    mov  r10d, DWORD PTR [r8]             ; number of keys
    lea  r11, [r8+4]                      ; keys[0]
    xor  ebx, ebx                         ; i
    xor  esi, esi                         ; s = left key of the current segment
pk_next:
    mov  eax, ebx
    shl  eax, 16
    xor  edx, edx
    lea  ecx, [r15-1]
    div  ecx
    mov  r12d, eax                        ; p = i * 65536 / (count - 1)
pk_adv:
    lea  eax, [rsi+2]
    cmp  eax, r10d
    ja   pk_seg                           ; last segment reached
    mov  eax, DWORD PTR [r11+rsi*8+8]
    cmp  r12d, eax
    jbe  pk_seg
    inc  esi
    jmp  pk_adv
pk_seg:
    mov  eax, DWORD PTR [r11+rsi*8]       ; posL
    mov  ecx, DWORD PTR [r11+rsi*8+8]     ; posR
    sub  ecx, eax                         ; span
    mov  r13d, r12d
    sub  r13d, eax                        ; p - posL (may be negative)
    xor  r14d, r14d                       ; t = 0 when the span is empty
    test ecx, ecx
    jle  pk_blend
    movsxd rax, r13d
    shl  rax, 8
    cqo
    movsxd rcx, ecx
    idiv rcx                              ; t = (p - posL) * 256 / span
    mov  r14d, eax
    test r14d, r14d
    jns  pk_hi
    xor  r14d, r14d
pk_hi:
    cmp  r14d, 256
    jbe  pk_blend
    mov  r14d, 256
pk_blend:
    mov  r13d, 256
    sub  r13d, r14d                       ; 256 - t
    mov  r8d, DWORD PTR [r11+rsi*8+4]     ; colour L
    mov  r9d, DWORD PTR [r11+rsi*8+12]    ; colour R
    mov  eax, r8d
    and  eax, 00FF00FFh
    imul eax, r13d
    mov  edx, r9d
    and  edx, 00FF00FFh
    imul edx, r14d
    add  eax, edx
    shr  eax, 8
    and  eax, 00FF00FFh
    mov  ebp, eax
    mov  eax, r8d
    and  eax, 0000FF00h
    imul eax, r13d
    mov  edx, r9d
    and  edx, 0000FF00h
    imul edx, r14d
    add  eax, edx
    shr  eax, 8
    and  eax, 0000FF00h
    or   eax, ebp
    mov  DWORD PTR [rdi+rbx*4], eax
    inc  ebx
    cmp  ebx, r15d
    jb   pk_next
    FN_RET
FN_END Pal_FromKeys

; ---------------------------------------------------------------------------
; Pal_Cosine - Inigo Quilez style palette: c(t) = a + b * cos(2*pi*(c*t + d)).
;   rcx = dst (uint32[count]), edx = count,
;   r8  = float params[12]: a.rgb, b.rgb, c.rgb, d.rgb   (t = i / count)
; ---------------------------------------------------------------------------
FN_BEGIN Pal_Cosine, 32
    mov  rdi, rcx
    mov  r13d, edx                        ; count
    mov  r12, r8                          ; params
    xor  ebx, ebx
pc_px:
    cvtsi2ss xmm0, ebx
    cvtsi2ss xmm1, r13d
    divss xmm0, xmm1
    movss DWORD PTR [rsp+LOC+16], xmm0    ; t
    xor  esi, esi                         ; channel 0..2 (R, G, B)
pc_ch:
    movss xmm0, DWORD PTR [r12+rsi*4+24]  ; c
    mulss xmm0, DWORD PTR [rsp+LOC+16]
    addss xmm0, DWORD PTR [r12+rsi*4+36]  ; + d
    mulss xmm0, DWORD PTR kTwoPiF
    call Mth_Cosf
    mulss xmm0, DWORD PTR [r12+rsi*4+12]  ; * b
    addss xmm0, DWORD PTR [r12+rsi*4]     ; + a
    maxss xmm0, DWORD PTR kZeroF
    minss xmm0, DWORD PTR kOneF
    mulss xmm0, DWORD PTR k255f
    addss xmm0, DWORD PTR kHalfF
    cvttss2si eax, xmm0
    mov  BYTE PTR [rsp+LOC+rsi], al
    inc  esi
    cmp  esi, 3
    jb   pc_ch
    movzx eax, BYTE PTR [rsp+LOC]         ; R
    shl  eax, 16
    movzx edx, BYTE PTR [rsp+LOC+1]       ; G
    shl  edx, 8
    or   eax, edx
    movzx edx, BYTE PTR [rsp+LOC+2]       ; B
    or   eax, edx
    mov  DWORD PTR [rdi+rbx*4], eax
    inc  ebx
    cmp  ebx, r13d
    jb   pc_px
    FN_RET
FN_END Pal_Cosine

END
