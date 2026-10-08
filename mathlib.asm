; ============================================================================
; mathlib.asm - sine tables, x87 float helpers, PRNG and integer hash
; ============================================================================
INCLUDE common.inc

.const
ALIGN 16
kTwoPiOver4096 REAL8 0.0015339807878856412
k32767         REAL4 32767.0

.code

; ---------------------------------------------------------------------------
; Mth_Init - fills gSinTab (int16, +-32767) and gSinTabF (float, 4097 entries).
; ---------------------------------------------------------------------------
FN_BEGIN Mth_Init, 16
    lea  rsi, gSinTabF
    lea  rdi, gSinTab
    xor  ebx, ebx
init_lp:
    mov  DWORD PTR [rsp+LOC], ebx
    fild DWORD PTR [rsp+LOC]
    fmul QWORD PTR kTwoPiOver4096
    fsin
    fst  DWORD PTR [rsi+rbx*4]
    cmp  ebx, 4096
    jae  init_pop
    fmul DWORD PTR k32767
    fistp WORD PTR [rsp+LOC+8]
    mov  ax, WORD PTR [rsp+LOC+8]
    mov  WORD PTR [rdi+rbx*2], ax
    jmp  init_nx
init_pop:
    fstp st(0)
init_nx:
    inc  ebx
    cmp  ebx, 4096
    jbe  init_lp
    FN_RET
FN_END Mth_Init

; ---------------------------------------------------------------------------
; x87-backed float helpers: argument and result in xmm0 (xmm1 for 2nd arg).
; ---------------------------------------------------------------------------
FN_BEGIN Mth_Sinf, 16
    movss DWORD PTR [rsp+LOC], xmm0
    fld   DWORD PTR [rsp+LOC]
    fsin
    fstp  DWORD PTR [rsp+LOC]
    movss xmm0, DWORD PTR [rsp+LOC]
    FN_RET
FN_END Mth_Sinf

FN_BEGIN Mth_Cosf, 16
    movss DWORD PTR [rsp+LOC], xmm0
    fld   DWORD PTR [rsp+LOC]
    fcos
    fstp  DWORD PTR [rsp+LOC]
    movss xmm0, DWORD PTR [rsp+LOC]
    FN_RET
FN_END Mth_Cosf

; atan2(y = xmm0, x = xmm1)
FN_BEGIN Mth_Atan2f, 16
    movss DWORD PTR [rsp+LOC], xmm0
    movss DWORD PTR [rsp+LOC+4], xmm1
    fld   DWORD PTR [rsp+LOC]
    fld   DWORD PTR [rsp+LOC+4]
    fpatan
    fstp  DWORD PTR [rsp+LOC]
    movss xmm0, DWORD PTR [rsp+LOC]
    FN_RET
FN_END Mth_Atan2f

; 2^x
FN_BEGIN Mth_Exp2f, 16
    movss DWORD PTR [rsp+LOC], xmm0
    fld   DWORD PTR [rsp+LOC]
    fld   st(0)
    frndint
    fsub  st(1), st(0)
    fxch
    f2xm1
    fld1
    faddp st(1), st(0)
    fscale
    fstp  st(1)
    fstp  DWORD PTR [rsp+LOC]
    movss xmm0, DWORD PTR [rsp+LOC]
    FN_RET
FN_END Mth_Exp2f

; log2(x)
FN_BEGIN Mth_Log2f, 16
    movss DWORD PTR [rsp+LOC], xmm0
    fld1
    fld   DWORD PTR [rsp+LOC]
    fyl2x
    fstp  DWORD PTR [rsp+LOC]
    movss xmm0, DWORD PTR [rsp+LOC]
    FN_RET
FN_END Mth_Log2f

; ---------------------------------------------------------------------------
; PRNG (xorshift32) and integer hash. Leaf functions.
; ---------------------------------------------------------------------------
LEAF_BEGIN Mth_Seed                     ; ecx = seed (0 is remapped)
    mov  eax, 9E3779B9h
    test ecx, ecx
    cmovz ecx, eax
    mov  gRng, ecx
    ret
LEAF_END Mth_Seed

LEAF_BEGIN Mth_Rand                     ; -> eax
    mov  eax, gRng
    mov  edx, eax
    shl  edx, 13
    xor  eax, edx
    mov  edx, eax
    shr  edx, 17
    xor  eax, edx
    mov  edx, eax
    shl  edx, 5
    xor  eax, edx
    mov  gRng, eax
    ret
LEAF_END Mth_Rand

LEAF_BEGIN Mth_Hash2                    ; ecx = x, edx = y, r8d = seed -> eax
    imul ecx, ecx, 374761393
    imul edx, edx, 668265263
    add  ecx, edx
    imul r8d, r8d, 1274126177
    add  ecx, r8d
    mov  eax, ecx
    shr  eax, 13
    xor  ecx, eax
    imul ecx, ecx, 1274126177
    mov  eax, ecx
    shr  eax, 16
    xor  eax, ecx
    ret
LEAF_END Mth_Hash2

END
