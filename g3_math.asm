; ============================================================================
; g3_math.asm - angles in turns, rotation matrices and easing curves of the
;               software 3D renderer (see g3.inc).
; ----------------------------------------------------------------------------
; Angles are measured in turns (1.0 = 360 degrees) because that is what the
; 4096-entry sine table gSinTabF is indexed by.  A rotation is built as
; R = Rz * Ry * Rx; matrices are stored as three columns so that a matrix
; times a vector is c0 * x + c1 * y + c2 * z (three packed multiplies).
; ============================================================================
INCLUDE common.inc
INCLUDE g3.inc

.const
ALIGN 16
kG3SignV  DWORD 80000000h, 80000000h, 80000000h, 80000000h
kG3AbsV   DWORD 7FFFFFFFh, 7FFFFFFFh, 7FFFFFFFh, 7FFFFFFFh
kG3Zero   REAL4 0.0
kG3Half   REAL4 0.5
kG3One    REAL4 1.0
kG3Two    REAL4 2.0
kG3Three  REAL4 3.0
kG3Tab    REAL4 4096.0
kBackC1   REAL4 1.70158               ; ease-out-back overshoot constants
kBackC3   REAL4 2.70158

.code

; ---------------------------------------------------------------------------
; G3_SinCos(xmm0 = angle in turns) -> xmm0 = sin, xmm1 = cos.
; Linear interpolation between two entries of the sine table (error < 1e-6);
; any angle works, negative ones and ones beyond a turn included.
; ---------------------------------------------------------------------------
LEAF_BEGIN G3_SinCos
    mulss     xmm0, DWORD PTR kG3Tab        ; position in table units
    cvttss2si eax, xmm0
    cvtsi2ss  xmm2, eax
    comiss    xmm2, xmm0
    jbe       sc_floor                      ; truncated value is not above x
    dec       eax                           ; negative input: truncation rounded up
    subss     xmm2, DWORD PTR kG3One
sc_floor:
    subss     xmm0, xmm2                    ; fraction 0 .. 1
    and       eax, 4095
    lea       rdx, gSinTabF
    movss     xmm1, DWORD PTR [rdx+rax*4]
    movss     xmm2, DWORD PTR [rdx+rax*4+4]
    subss     xmm2, xmm1
    mulss     xmm2, xmm0
    addss     xmm1, xmm2                    ; sin
    lea       ecx, [rax+1024]               ; cos = sin shifted by a quarter turn
    and       ecx, 4095
    movss     xmm3, DWORD PTR [rdx+rcx*4]
    movss     xmm2, DWORD PTR [rdx+rcx*4+4]
    subss     xmm2, xmm3
    mulss     xmm2, xmm0
    addss     xmm3, xmm2                    ; cos
    movaps    xmm0, xmm1
    movaps    xmm1, xmm3
    ret
LEAF_END G3_SinCos

; ---------------------------------------------------------------------------
; G3_RotMat(rcx = dst MAT3, xmm0 = x turns, xmm1 = y turns, xmm2 = z turns)
; R = Rz * Ry * Rx, stored by columns:
;   col0 = (cc cb,                  sc cb,                  -sb )
;   col1 = (cc sb sa - sc ca,       sc sb sa + cc ca,       cb sa)
;   col2 = (cc sb ca + sc sa,       sc sb ca - cc sa,       cb ca)
; (a = x angle, b = y angle, c = z angle).
; ---------------------------------------------------------------------------
FNX_BEGIN G3_RotMat, 0
    mov       rsi, rcx
    movaps    xmm14, xmm1                   ; y angle
    movaps    xmm15, xmm2                   ; z angle
    call      G3_SinCos
    movaps    xmm6, xmm0                    ; sa
    movaps    xmm7, xmm1                    ; ca
    movaps    xmm0, xmm14
    call      G3_SinCos
    movaps    xmm8, xmm0                    ; sb
    movaps    xmm9, xmm1                    ; cb
    movaps    xmm0, xmm15
    call      G3_SinCos
    movaps    xmm10, xmm0                   ; sc
    movaps    xmm11, xmm1                   ; cc
    movaps    xmm12, xmm8
    mulss     xmm12, xmm6                   ; t1 = sb sa
    movaps    xmm13, xmm8
    mulss     xmm13, xmm7                   ; t2 = sb ca
    movaps    xmm0, xmm11
    mulss     xmm0, xmm9
    movss     DWORD PTR [rsi], xmm0         ; r00 = cc cb
    movaps    xmm0, xmm10
    mulss     xmm0, xmm9
    movss     DWORD PTR [rsi+4], xmm0       ; r10 = sc cb
    xorps     xmm0, xmm0
    subss     xmm0, xmm8
    movss     DWORD PTR [rsi+8], xmm0       ; r20 = -sb
    mov       DWORD PTR [rsi+12], 0
    movaps    xmm0, xmm11
    mulss     xmm0, xmm12
    movaps    xmm1, xmm10
    mulss     xmm1, xmm7
    subss     xmm0, xmm1
    movss     DWORD PTR [rsi+16], xmm0      ; r01 = cc t1 - sc ca
    movaps    xmm0, xmm10
    mulss     xmm0, xmm12
    movaps    xmm1, xmm11
    mulss     xmm1, xmm7
    addss     xmm0, xmm1
    movss     DWORD PTR [rsi+20], xmm0      ; r11 = sc t1 + cc ca
    movaps    xmm0, xmm9
    mulss     xmm0, xmm6
    movss     DWORD PTR [rsi+24], xmm0      ; r21 = cb sa
    mov       DWORD PTR [rsi+28], 0
    movaps    xmm0, xmm11
    mulss     xmm0, xmm13
    movaps    xmm1, xmm10
    mulss     xmm1, xmm6
    addss     xmm0, xmm1
    movss     DWORD PTR [rsi+32], xmm0      ; r02 = cc t2 + sc sa
    movaps    xmm0, xmm10
    mulss     xmm0, xmm13
    movaps    xmm1, xmm11
    mulss     xmm1, xmm6
    subss     xmm0, xmm1
    movss     DWORD PTR [rsi+36], xmm0      ; r12 = sc t2 - cc sa
    movaps    xmm0, xmm9
    mulss     xmm0, xmm7
    movss     DWORD PTR [rsi+40], xmm0      ; r22 = cb ca
    mov       DWORD PTR [rsi+44], 0
    FNX_RET
FN_END G3_RotMat

; ---------------------------------------------------------------------------
; G3_MatMul(rcx = dst, rdx = A, r8 = B): dst = A * B.  Column j of the result
; is A applied to column j of B; dst must not overlap A or B.
; ---------------------------------------------------------------------------
LEAF_BEGIN G3_MatMul
    movaps    xmm3, XMMWORD PTR [rdx]
    movaps    xmm4, XMMWORD PTR [rdx+16]
    movaps    xmm5, XMMWORD PTR [rdx+32]
    mov       r9d, 3
mm_col:
    movaps    xmm0, XMMWORD PTR [r8]
    movaps    xmm1, xmm0
    shufps    xmm1, xmm1, 055h
    movaps    xmm2, xmm0
    shufps    xmm2, xmm2, 0AAh
    shufps    xmm0, xmm0, 000h
    mulps     xmm0, xmm3
    mulps     xmm1, xmm4
    mulps     xmm2, xmm5
    addps     xmm0, xmm1
    addps     xmm0, xmm2
    movaps    XMMWORD PTR [rcx], xmm0
    add       r8, 16
    add       rcx, 16
    dec       r9d
    jnz       mm_col
    ret
LEAF_END G3_MatMul

; G3_MatVec(rcx = MAT3, xmm0 = (x, y, z, 0)) -> xmm0 = M * v.
LEAF_BEGIN G3_MatVec
    movaps    xmm1, xmm0
    shufps    xmm1, xmm1, 000h
    mulps     xmm1, XMMWORD PTR [rcx]
    movaps    xmm2, xmm0
    shufps    xmm2, xmm2, 055h
    mulps     xmm2, XMMWORD PTR [rcx+16]
    shufps    xmm0, xmm0, 0AAh
    mulps     xmm0, XMMWORD PTR [rcx+32]
    addps     xmm0, xmm1
    addps     xmm0, xmm2
    ret
LEAF_END G3_MatVec

; G3_Smooth(xmm0 = x) -> xmm0 = s * s * (3 - 2 s) with s = clamp(x, 0, 1).
LEAF_BEGIN G3_Smooth
    maxss     xmm0, DWORD PTR kG3Zero
    minss     xmm0, DWORD PTR kG3One
    movaps    xmm1, xmm0
    mulss     xmm1, DWORD PTR kG3Two
    movss     xmm2, DWORD PTR kG3Three
    subss     xmm2, xmm1
    mulss     xmm0, xmm0
    mulss     xmm0, xmm2
    ret
LEAF_END G3_Smooth

; ---------------------------------------------------------------------------
; G3_EaseBack(xmm0 = x) -> xmm0 = 1 + c3 (s - 1)^3 + c1 (s - 1)^2 with
; s = clamp(x, 0, 1): 0 at 0, 1 at 1, with a 10 % overshoot on the way.
; ---------------------------------------------------------------------------
LEAF_BEGIN G3_EaseBack
    maxss     xmm0, DWORD PTR kG3Zero
    minss     xmm0, DWORD PTR kG3One
    subss     xmm0, DWORD PTR kG3One        ; y = s - 1
    movaps    xmm1, xmm0
    mulss     xmm1, xmm1                    ; y^2
    mulss     xmm0, DWORD PTR kBackC3
    addss     xmm0, DWORD PTR kBackC1
    mulss     xmm0, xmm1
    addss     xmm0, DWORD PTR kG3One
    ret
LEAF_END G3_EaseBack

END
