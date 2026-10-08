; ============================================================================
; selftest_g3m.asm - built-in checks of the 3D renderer, part 3: the matcaps
;                    (part of SiliconDreams.exe /selftest).
; ----------------------------------------------------------------------------
;   * integer powers of the soft boxes against exact values,
;   * 32 texels of the four matcaps (centre, four directions, a corner outside
;     the disc, a point near the rim, and a point on the key light highlight
;     of every material) against the output of the Python
;     prototype the formulas were tuned on (every channel within 4 levels:
;     the prototype works in double precision with an exact gradient, the
;     demo in single precision with a 4096-entry gradient),
;   * building a matcap twice gives the same picture.
; ============================================================================
INCLUDE common.inc
INCLUDE g3.inc

MT_ROWS     EQU 32

.const
ALIGN 16
kMtTol      BYTE 16 DUP (4)              ; allowed difference per channel
kMtAbs      DWORD 7FFFFFFFh, 7FFFFFFFh, 7FFFFFFFh, 7FFFFFFFh
kMtEps      REAL4 0.00001
kMtP1       REAL4 0.9
kMtP1Want   REAL4 0.06461082               ; 0.9 ^ 26
kMtP2       REAL4 1.5
kMtP2Want   REAL4 17.0859375               ; 1.5 ^ 7 (exact)
kMtP3       REAL4 0.5
kMtP3Want   REAL4 0.0009765625             ; 0.5 ^ 10 (exact)

; material, x, y, 0x00RRGGBB of the Python prototype
matRef      DWORD MAT_OIL  , 128, 128, 09D02C8h
            DWORD MAT_OIL  , 128,  40, 0153F0Ah
            DWORD MAT_OIL  ,  40, 128, 00D86E9h
            DWORD MAT_OIL  , 200, 128, 009C8FFh
            DWORD MAT_OIL  , 128, 230, 0011621h
            DWORD MAT_OIL  ,  20,  20, 08D09E1h
            DWORD MAT_OIL  , 235, 100, 0FFE508h
            DWORD MAT_GOLD , 128, 128, 0FFBF3Ah
            DWORD MAT_GOLD , 128,  40, 0735925h
            DWORD MAT_GOLD ,  40, 128, 0FFC03Bh
            DWORD MAT_GOLD , 200, 128, 0FFFF4Bh
            DWORD MAT_GOLD , 128, 230, 01D1205h
            DWORD MAT_GOLD ,  20,  20, 0FFF2CAh
            DWORD MAT_GOLD , 235, 100, 0F3B53Ch
            DWORD MAT_TEAL , 128, 128, 0046774h
            DWORD MAT_TEAL , 128,  40, 0058394h
            DWORD MAT_TEAL ,  40, 128, 0047281h
            DWORD MAT_TEAL , 200, 128, 0023E45h
            DWORD MAT_TEAL , 128, 230, 0031B1Eh
            DWORD MAT_TEAL ,  20,  20, 0E9FFFFh
            DWORD MAT_TEAL , 235, 100, 0093B42h
            DWORD MAT_GLASS, 128, 128, 00F0A16h
            DWORD MAT_GLASS, 128,  40, 0181024h
            DWORD MAT_GLASS,  40, 128, 00C1528h
            DWORD MAT_GLASS, 200, 128, 01A0A19h
            DWORD MAT_GLASS, 128, 230, 0241937h
            DWORD MAT_GLASS,  20,  20, 0549BFFh
            DWORD MAT_GLASS, 235, 100, 0511843h
; the key light: the soft box and its colour, the weight it has in each material
            DWORD MAT_OIL  ,  95,  81, 0DCFFFFh
            DWORD MAT_GOLD , 101,  59, 0F5B63Fh      ; the key colour shows in red here
            DWORD MAT_TEAL ,  89, 101, 089F7F5h      ; the weight of the key light
            DWORD MAT_GLASS,  95,  81, 0D1BEB1h

szMtPow     BYTE "3d material: integer powers of the soft boxes", 0
szMtRef     BYTE "3d material: oil, gold, teal and glass match the prototype texels", 0
szMtSame    BYTE "3d material: building a matcap twice gives the same picture", 0

.data?
ALIGN 16
mtTexA      DWORD G3_TEXN DUP (?)
mtTexB      DWORD G3_TEXN DUP (?)

.code

; Mt_Close(ecx = a, edx = b) -> eax = 1 when every colour channel differs by at most 4.
LEAF_BEGIN Mt_Close
    movd      xmm0, ecx
    movd      xmm1, edx
    movdqa    xmm2, xmm0
    psubusb   xmm0, xmm1
    psubusb   xmm1, xmm2
    por       xmm0, xmm1                     ; |a - b| per byte
    psubusb   xmm0, XMMWORD PTR kMtTol
    movd      eax, xmm0
    and       eax, 00FFFFFFh
    setz      al
    movzx     eax, al
    ret
LEAF_END Mt_Close

; Mt_Pow1(xmm0 = x, ecx = exponent, xmm1 = expected) -> eax = 1 when x ^ exponent is close.
FN_BEGIN Mt_Pow1, 16
    movss     DWORD PTR [rsp+LOC], xmm1
    call      Mb_Pow
    subss     xmm0, DWORD PTR [rsp+LOC]
    andps     xmm0, XMMWORD PTR kMtAbs
    comiss    xmm0, DWORD PTR kMtEps
    setbe     al
    setnp     cl
    and       al, cl
    movzx     eax, al
    FN_RET
FN_END Mt_Pow1

FN_BEGIN Mt_Pow, 0
    movss     xmm0, DWORD PTR kMtP1
    mov       ecx, 26
    movss     xmm1, DWORD PTR kMtP1Want
    call      Mt_Pow1
    mov       ebx, eax
    movss     xmm0, DWORD PTR kMtP2
    mov       ecx, 7
    movss     xmm1, DWORD PTR kMtP2Want
    call      Mt_Pow1
    and       ebx, eax
    movss     xmm0, DWORD PTR kMtP3
    mov       ecx, 10
    movss     xmm1, DWORD PTR kMtP3Want
    call      Mt_Pow1
    and       ebx, eax
    mov       edx, ebx
    lea       rcx, szMtPow
    call      St_Report
    FN_RET
FN_END Mt_Pow

; ---------------------------------------------------------------------------
; Mt_Ref - every row of matRef against the texel of the matcap built for it.
; ---------------------------------------------------------------------------
FN_BEGIN Mt_Ref, 0
    lea       rsi, matRef
    mov       edi, MT_ROWS
    mov       r12d, -1                       ; material built so far
    mov       ebx, 1
rf_row:
    mov       eax, DWORD PTR [rsi]
    cmp       eax, r12d
    je        rf_have
    mov       r12d, eax
    lea       rcx, mtTexA
    mov       edx, eax
    call      Mat_Build
rf_have:
    mov       eax, DWORD PTR [rsi+8]
    shl       eax, 8
    add       eax, DWORD PTR [rsi+4]         ; y * 256 + x
    lea       rdx, mtTexA
    mov       ecx, DWORD PTR [rdx+rax*4]
    mov       edx, DWORD PTR [rsi+12]
    call      Mt_Close
    and       ebx, eax
    add       rsi, 16
    dec       edi
    jnz       rf_row
    mov       edx, ebx
    lea       rcx, szMtRef
    call      St_Report
    FN_RET
FN_END Mt_Ref

; Mt_SameBuf(rcx = a, rdx = b) -> eax = 1 when both matcaps are identical.
LEAF_BEGIN Mt_SameBuf
    mov       r8d, G3_TEXN
sb_lp:
    mov       eax, DWORD PTR [rcx]
    cmp       eax, DWORD PTR [rdx]
    jne       sb_no
    add       rcx, 4
    add       rdx, 4
    dec       r8d
    jnz       sb_lp
    mov       eax, 1
    ret
sb_no:
    xor       eax, eax
    ret
LEAF_END Mt_SameBuf

; Mt_Same - a matcap built twice is identical (and not empty).
FN_BEGIN Mt_Same, 0
    lea       rcx, mtTexA
    mov       edx, MAT_OIL
    call      Mat_Build
    lea       rcx, mtTexB
    mov       edx, MAT_OIL
    call      Mat_Build
    lea       rcx, mtTexA
    lea       rdx, mtTexB
    call      Mt_SameBuf
    mov       ebx, eax
    lea       rax, mtTexA
    cmp       DWORD PTR [rax+(128*256+128)*4], 0
    setne     al                             ; and not an empty picture
    and       bl, al
    movzx     edx, bl
    lea       rcx, szMtSame
    call      St_Report
    FN_RET
FN_END Mt_Same

; ---------------------------------------------------------------------------
; St_G3Mat - all matcap checks.
; ---------------------------------------------------------------------------
FN_BEGIN St_G3Mat, 0
    call      Mt_Pow
    call      Mt_Ref
    call      Mt_Same
    FN_RET
FN_END St_G3Mat

END
