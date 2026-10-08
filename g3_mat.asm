; ============================================================================
; g3_mat.asm - procedural matcaps (materials) of the 3D renderer (see g3.inc).
; ----------------------------------------------------------------------------
; A matcap is a 256 x 256 picture of a sphere seen from the camera: the
; rasteriser looks a pixel up by its view-space normal, so the picture holds
; everything a material does with light.  Texel (x, y) stands for the normal
;     n = ((x + 0.5) / 128 - 1, 1 - (y + 0.5) / 128, sqrt(1 - nx^2 - ny^2))
; (outside the disc the normal is the nearest point of the rim, nz = 0),
; the reflection vector r = (2 nz nx, 2 nz ny, 2 nz^2 - 1) (the viewer looks
; along +z) and the Schlick term fres = (1 - nz)^5.  The light is a studio:
; four soft boxes, light^e of the cosine between r and the box direction, and
; a vertical gradient (horizon at the middle) from a 4096-entry palette.
;
;   oil    iridescent film (0.5 + 0.5 cos(2 pi (t + (0, .33, .67))) with
;          t = 1.1 (1 - nz) + 0.4 h + 0.1 nx) modulated by the luminance of the
;          environment, plus the key light; h = (ry + 1) / 2
;   gold   environment x (f0 + (1 - f0) fres) with f0 = (1, 0.8, 0.3)
;   teal   glossy ceramic: Lambert body, key light, cyan rim
;   glass  additive: cyan on the left, magenta on the right, bright rim
; The formulas were tuned on a Python prototype; selftest_g3m.asm compares
; sample texels with its output.
; ============================================================================
INCLUDE common.inc
INCLUDE g3.inc

ENV_N     EQU 4096                       ; entries of an environment palette
LT_COL    EQU 16                         ; light: direction (16 bytes), colour (16), exponent (+ padding)
LT_EXP    EQU 32

.const
ALIGN 16
kZero4    REAL4 0.0, 0.0, 0.0, 0.0
kOne4     REAL4 1.0, 1.0, 1.0, 1.0
kHalf4    REAL4 0.5, 0.5, 0.5, 0.5
k255v     REAL4 255.0, 255.0, 255.0, 255.0
kInv255   REAL4 0.003921569, 0.003921569, 0.003921569, 0.003921569
kLumW     REAL4 0.3, 0.5, 0.2, 0.0
kF0       REAL4 1.0, 0.80, 0.30, 0.0     ; gold: normal-incidence reflectance
kGoldTint REAL4 1.0, 0.97, 0.88, 0.0
kTealL    REAL4 -0.39801488, 0.59702231, 0.69652603, 0.0
kTealBody REAL4 0.02, 0.55, 0.62, 0.0
kTealRim  REAL4 0.3, 0.9, 1.0, 0.0
kCyanTint REAL4 0.15, 0.55, 1.0, 0.0     ; glass, left side
kMagTint  REAL4 1.0, 0.25, 0.75, 0.0     ; glass, right side
kKey35    REAL4 0.35, 0.35, 0.35, 0.0
kKey90    REAL4 0.9, 0.9, 0.9, 0.0
kHalfF    REAL4 0.5
kOneF     REAL4 1.0
kZeroF    REAL4 0.0
kTwoF     REAL4 2.0
kInv128   REAL4 0.0078125
kEnvMax   REAL4 4095.0
kLumMax   REAL4 1.4
kGain0    REAL4 0.10
kGain1    REAL4 0.95
kFilm1    REAL4 1.1
kFilm2    REAL4 0.40
kFilm3    REAL4 0.10
kPhase1   REAL4 0.33
kPhase2   REAL4 0.67
kBody0    REAL4 0.14
kBody1    REAL4 0.86
kRim3     REAL4 3.0
kEdgeP    REAL4 2.2
kEdge0    REAL4 0.10
kEdge1    REAL4 1.1
kTiny     REAL4 0.000001

; soft boxes: direction, colour, exponent (read with aligned vector loads)
ALIGN 16
ltKey     REAL4 -0.45341345, 0.65493054, 0.60455127, 0.0
          REAL4 2.2, 2.0, 1.7, 0.0
          DWORD 26, 0, 0, 0
ltFill    REAL4 0.78140380, 0.11162911, 0.61396013, 0.0
          REAL4 0.2, 1.0, 1.5, 0.0
          DWORD 14, 0, 0, 0
ltRed     REAL4 -0.80709324, 0.20177331, -0.55487660, 0.0
          REAL4 1.8, 0.3, 1.1, 0.0
          DWORD 10, 0, 0, 0
ltCyan    REAL4 0.70982818, 0.35491409, -0.60842415, 0.0
          REAL4 0.3, 1.3, 1.6, 0.0
          DWORD 10, 0, 0, 0
ltGoldKey REAL4 -0.45341345, 0.65493054, 0.60455127, 0.0
          REAL4 2.4, 2.2, 1.9, 0.0
          DWORD 26, 0, 0, 0
ltGoldFil REAL4 0.78140380, 0.11162911, 0.61396013, 0.0
          REAL4 0.9, 0.7, 0.5, 0.0
          DWORD 14, 0, 0, 0

; environment gradients (reflection height 0 .. 1): count, then (position * 65536, 0x00RRGGBB)
keysCool  DWORD 8
          DWORD     0, 00D051Ah
          DWORD 19661, 0240F42h
          DWORD 30147, 08C408Ch
          DWORD 32440, 0FFCCD9h
          DWORD 33096, 0FFF2E6h
          DWORD 35389, 073CCFFh
          DWORD 49152, 03373F2h
          DWORD 65536, 00D1A73h
keysWarm  DWORD 8
          DWORD     0, 01A140Fh
          DWORD 19661, 04C3D2Eh
          DWORD 30147, 0D9BF99h
          DWORD 32440, 0FFF5D9h
          DWORD 33096, 0FFFFF2h
          DWORD 35389, 0FFF2D9h
          DWORD 49152, 0D9D1CCh
          DWORD 65536, 073738Ch

matTab    QWORD Mb_Oil, Mb_Gold, Mb_Teal, Mb_Glass

.data?
ALIGN 16
envCool   DWORD ENV_N DUP (?)
envWarm   DWORD ENV_N DUP (?)
envReady  DWORD ?

.code

; ---------------------------------------------------------------------------
; Mb_Pow(xmm0 = x, ecx = exponent >= 1) -> xmm0 = x ^ exponent (binary powering).
; ---------------------------------------------------------------------------
LEAF_BEGIN Mb_Pow
    movss     xmm1, DWORD PTR kOneF
pw_lp:
    test      ecx, 1
    jz        pw_sq
    mulss     xmm1, xmm0
pw_sq:
    mulss     xmm0, xmm0
    shr       ecx, 1
    jnz       pw_lp
    movaps    xmm0, xmm1
    ret
LEAF_END Mb_Pow

; ---------------------------------------------------------------------------
; Mb_Env(rcx = palette, xmm0 = t 0 .. 1) -> xmm0 = (r, g, b, 0) in 0 .. 1.
; ---------------------------------------------------------------------------
LEAF_BEGIN Mb_Env
    mulss     xmm0, DWORD PTR kEnvMax
    maxss     xmm0, DWORD PTR kZeroF
    minss     xmm0, DWORD PTR kEnvMax
    cvttss2si eax, xmm0
    movd      xmm0, DWORD PTR [rcx+rax*4]
    pxor      xmm1, xmm1
    punpcklbw xmm0, xmm1
    punpcklwd xmm0, xmm1
    cvtdq2ps  xmm0, xmm0                     ; (b, g, r, 0) in 0 .. 255
    mulps     xmm0, XMMWORD PTR kInv255
    shufps    xmm0, xmm0, 0C6h               ; (r, g, b, 0)
    ret
LEAF_END Mb_Env

; ---------------------------------------------------------------------------
; Mb_Box(rcx = light, xmm0 = reflection vector) -> xmm0 = colour * cos^e, with
; cos = clamp(r . direction, 0, 1).  Touches xmm0 .. xmm3 only.
; ---------------------------------------------------------------------------
FN_BEGIN Mb_Box, 0
    mov       rsi, rcx
    mulps     xmm0, XMMWORD PTR [rsi]
    HSUM3     xmm0, xmm0, xmm1, xmm2
    maxss     xmm0, DWORD PTR kZeroF
    minss     xmm0, DWORD PTR kOneF
    mov       ecx, DWORD PTR [rsi+LT_EXP]
    call      Mb_Pow
    shufps    xmm0, xmm0, 000h
    mulps     xmm0, XMMWORD PTR [rsi+LT_COL]
    FN_RET
FN_END Mb_Box

; Mb_Pack(xmm0 = (r, g, b, .) in 0 .. 1, clamped) -> eax = 0x00RRGGBB.
LEAF_BEGIN Mb_Pack
    maxps     xmm0, XMMWORD PTR kZero4
    minps     xmm0, XMMWORD PTR kOne4
    mulps     xmm0, XMMWORD PTR k255v
    addps     xmm0, XMMWORD PTR kHalf4
    cvttps2dq xmm0, xmm0
    shufps    xmm0, xmm0, 0C6h               ; (b, g, r, .)
    packssdw  xmm0, xmm0
    packuswb  xmm0, xmm0
    movd      eax, xmm0
    and       eax, 00FFFFFFh
    ret
LEAF_END Mb_Pack

; ---------------------------------------------------------------------------
; The materials.  In: xmm6 = n, xmm7 = r, xmm8 = fres in every lane.
; Out: xmm0 = (r, g, b, 0), not clamped.  (FNX frames keep the caller's xmm6..15.)
; ---------------------------------------------------------------------------
; Mb_Height -> xmm9 = h = (ry + 1) / 2 in every lane.
Mb_Height MACRO
    movaps    xmm9, xmm7
    shufps    xmm9, xmm9, 055h
    mulss     xmm9, DWORD PTR kHalfF
    addss     xmm9, DWORD PTR kHalfF
ENDM

; Mb_AddBox light - xmm10 += soft box of the reflection vector.
Mb_AddBox MACRO light:REQ
    lea       rcx, light
    movaps    xmm0, xmm7
    call      Mb_Box
    addps     xmm10, xmm0
ENDM

FNX_BEGIN Mb_Oil, 16
    Mb_Height
    movaps    xmm0, xmm9
    lea       rcx, envCool
    call      Mb_Env
    movaps    xmm10, xmm0                    ; environment
    lea       rcx, ltKey
    movaps    xmm0, xmm7
    call      Mb_Box
    movaps    xmm11, xmm0                    ; the key light alone
    addps     xmm10, xmm0
    Mb_AddBox ltFill
    Mb_AddBox ltRed
    Mb_AddBox ltCyan
    mulps     xmm10, XMMWORD PTR kLumW
    HSUM3     xmm0, xmm10, xmm1, xmm2
    maxss     xmm0, DWORD PTR kZeroF
    minss     xmm0, DWORD PTR kLumMax        ; luminance
    mulss     xmm0, DWORD PTR kGain1
    addss     xmm0, DWORD PTR kGain0
    shufps    xmm0, xmm0, 000h
    movaps    xmm12, xmm0                    ; 0.10 + 0.95 lum
    movaps    xmm0, xmm6
    shufps    xmm0, xmm0, 0AAh               ; nz
    movss     xmm13, DWORD PTR kOneF
    subss     xmm13, xmm0
    mulss     xmm13, DWORD PTR kFilm1        ; 1.1 (1 - nz)
    movaps    xmm0, xmm9
    mulss     xmm0, DWORD PTR kFilm2
    addss     xmm13, xmm0                    ; + 0.4 h
    movaps    xmm0, xmm6
    mulss     xmm0, DWORD PTR kFilm3
    addss     xmm13, xmm0                    ; + 0.1 nx: the phase of the film
    movaps    xmm0, xmm13
    call      G3_SinCos
    movss     DWORD PTR [rsp+XLOC], xmm1
    movaps    xmm0, xmm13
    addss     xmm0, DWORD PTR kPhase1
    call      G3_SinCos
    movss     DWORD PTR [rsp+XLOC+4], xmm1
    movaps    xmm0, xmm13
    addss     xmm0, DWORD PTR kPhase2
    call      G3_SinCos
    movss     DWORD PTR [rsp+XLOC+8], xmm1
    mov       DWORD PTR [rsp+XLOC+12], 0
    movaps    xmm0, XMMWORD PTR [rsp+XLOC]
    mulps     xmm0, XMMWORD PTR kHalf4
    addps     xmm0, XMMWORD PTR kHalf4       ; film colour
    mulps     xmm0, xmm12
    mulps     xmm11, XMMWORD PTR kKey35
    addps     xmm0, xmm11
    FNX_RET
FN_END Mb_Oil

FNX_BEGIN Mb_Gold, 0
    Mb_Height
    movaps    xmm0, xmm9
    lea       rcx, envWarm
    call      Mb_Env
    movaps    xmm10, xmm0
    Mb_AddBox ltGoldKey
    Mb_AddBox ltGoldFil
    movaps    xmm0, XMMWORD PTR kOne4
    subps     xmm0, XMMWORD PTR kF0
    mulps     xmm0, xmm8
    addps     xmm0, XMMWORD PTR kF0          ; Schlick
    mulps     xmm0, xmm10
    mulps     xmm0, XMMWORD PTR kGoldTint
    FNX_RET
FN_END Mb_Gold

FNX_BEGIN Mb_Teal, 0
    movaps    xmm0, xmm6
    mulps     xmm0, XMMWORD PTR kTealL
    HSUM3     xmm0, xmm0, xmm1, xmm2
    maxss     xmm0, DWORD PTR kZeroF
    minss     xmm0, DWORD PTR kOneF          ; n . L
    mulss     xmm0, DWORD PTR kBody1
    addss     xmm0, DWORD PTR kBody0
    shufps    xmm0, xmm0, 000h
    mulps     xmm0, XMMWORD PTR kTealBody
    movaps    xmm10, xmm0                    ; diffuse
    lea       rcx, ltKey
    movaps    xmm0, xmm7
    call      Mb_Box
    mulps     xmm0, XMMWORD PTR kKey90
    addps     xmm10, xmm0
    movaps    xmm0, xmm8
    mulss     xmm0, DWORD PTR kRim3
    shufps    xmm0, xmm0, 000h
    mulps     xmm0, XMMWORD PTR kTealRim
    addps     xmm0, xmm10
    FNX_RET
FN_END Mb_Teal

FNX_BEGIN Mb_Glass, 0
    movaps    xmm9, xmm6
    shufps    xmm9, xmm9, 000h               ; nx
    movaps    xmm10, xmm9
    mulps     xmm10, XMMWORD PTR kHalf4
    movaps    xmm11, XMMWORD PTR kHalf4
    subps     xmm11, xmm10                   ; 0.5 - 0.5 nx
    addps     xmm10, XMMWORD PTR kHalf4      ; 0.5 + 0.5 nx
    mulps     xmm11, XMMWORD PTR kCyanTint
    mulps     xmm10, XMMWORD PTR kMagTint
    addps     xmm10, xmm11                   ; tint
    movaps    xmm0, xmm6
    shufps    xmm0, xmm0, 0AAh
    movss     xmm12, DWORD PTR kOneF
    subss     xmm12, xmm0                    ; 1 - nz
    xorps     xmm13, xmm13
    comiss    xmm12, DWORD PTR kTiny
    jbe       gl_edge
    movaps    xmm0, xmm12
    call      Mth_Log2f
    mulss     xmm0, DWORD PTR kEdgeP
    call      Mth_Exp2f
    movaps    xmm13, xmm0                    ; (1 - nz) ^ 2.2
gl_edge:
    mulss     xmm13, DWORD PTR kEdge1
    addss     xmm13, DWORD PTR kEdge0
    shufps    xmm13, xmm13, 000h
    mulps     xmm10, xmm13
    lea       rcx, ltKey
    movaps    xmm0, xmm7
    call      Mb_Box
    mulps     xmm0, XMMWORD PTR kKey35
    addps     xmm0, xmm10
    FNX_RET
FN_END Mb_Glass

; ---------------------------------------------------------------------------
; Mat_Build(rcx = dst DWORD[256 * 256] BGRA, edx = MAT_*)
; ---------------------------------------------------------------------------
FN_BEGIN Mb_InitEnv, 0
    cmp       DWORD PTR envReady, 0
    jne       ie_done
    lea       rcx, envCool
    mov       edx, ENV_N
    lea       r8, keysCool
    call      Pal_FromKeys
    lea       rcx, envWarm
    mov       edx, ENV_N
    lea       r8, keysWarm
    call      Pal_FromKeys
    mov       DWORD PTR envReady, 1
ie_done:
    FN_RET
FN_END Mb_InitEnv

; Mb_Normal - from (nx, ny) in xmm0 / xmm2: xmm6 = n, xmm7 = r, xmm8 = fres.
; (A macro, not a function: an FNX frame would restore xmm6 .. xmm8 on return.)
Mb_Normal MACRO
    movaps    xmm3, xmm0
    mulss     xmm3, xmm3
    movaps    xmm4, xmm2
    mulss     xmm4, xmm4
    movss     xmm1, DWORD PTR kOneF
    subss     xmm1, xmm3
    subss     xmm1, xmm4
    maxss     xmm1, DWORD PTR kZeroF
    sqrtss    xmm1, xmm1                     ; nz
    PACK3     xmm6, xmm0, xmm2, xmm1         ; n
    movaps    xmm3, xmm1
    addss     xmm3, xmm3                     ; 2 nz
    movaps    xmm4, xmm3
    mulss     xmm4, xmm0                     ; rx
    movaps    xmm5, xmm3
    mulss     xmm5, xmm2                     ; ry
    mulss     xmm3, xmm1
    subss     xmm3, DWORD PTR kOneF          ; rz = 2 nz^2 - 1
    PACK3     xmm7, xmm4, xmm5, xmm3         ; r
    movss     xmm3, DWORD PTR kOneF
    subss     xmm3, xmm1                     ; 1 - nz
    movaps    xmm4, xmm3
    mulss     xmm4, xmm4
    mulss     xmm4, xmm4                     ; (1 - nz)^4
    mulss     xmm4, xmm3                     ; (1 - nz)^5
    shufps    xmm4, xmm4, 000h
    movaps    xmm8, xmm4                     ; fres
ENDM

FNX_BEGIN Mat_Build, 16
    mov       r12, rcx
    lea       rax, matTab
    mov       r13, QWORD PTR [rax+rdx*8]
    call      Mb_InitEnv
    xor       r14d, r14d                     ; row
mb_row:
    xor       r15d, r15d                     ; column
mb_col:
    cvtsi2ss  xmm0, r15d
    addss     xmm0, DWORD PTR kHalfF
    mulss     xmm0, DWORD PTR kInv128
    subss     xmm0, DWORD PTR kOneF          ; nx
    cvtsi2ss  xmm1, r14d
    addss     xmm1, DWORD PTR kHalfF
    mulss     xmm1, DWORD PTR kInv128
    movss     xmm2, DWORD PTR kOneF
    subss     xmm2, xmm1                     ; ny
    movaps    xmm1, xmm0
    mulss     xmm1, xmm1
    movaps    xmm3, xmm2
    mulss     xmm3, xmm3
    addss     xmm1, xmm3
    comiss    xmm1, DWORD PTR kOneF
    jbe       mb_disc
    sqrtss    xmm1, xmm1                     ; outside the disc: the nearest point of the rim
    divss     xmm0, xmm1
    divss     xmm2, xmm1
mb_disc:
    Mb_Normal
    call      r13
    call      Mb_Pack
    mov       DWORD PTR [r12], eax
    add       r12, 4
    inc       r15d
    cmp       r15d, 256
    jb        mb_col
    inc       r14d
    cmp       r14d, 256
    jb        mb_row
    FNX_RET
FN_END Mat_Build

END
