; ============================================================================
; selftest_g3.asm - built-in checks of the 3D renderer, part 1: angles,
;                   matrices, easing curves and the five solids
;                   (part of SiliconDreams.exe /selftest; the rasteriser is
;                   checked in selftest_g3r.asm, the matcaps in selftest_g3m.asm).
; ----------------------------------------------------------------------------
;   * sin / cos of an angle in turns against known values, for negative angles
;     and angles beyond a turn as well,
;   * R = Rz * Ry * Rx: three quarter turns map (1, 2, 3) to (3, 2, -1) (this
;     fixes the order and the signs), a general rotation has orthonormal
;     columns and is right-handed, MatMul equals applying the matrices one
;     after the other (and in the right order),
;   * smoothstep and ease-out-back at their key points,
;   * every solid: the vertex count, indices in range, unit normals, every
;     triangle faces along its normals (winding) and the enclosed volume equals
;     the value computed independently (a Python replica of the construction).
; ============================================================================
INCLUDE common.inc
INCLUDE g3.inc

SQ_TRIGN    EQU 7
SQ_SMOOTHN  EQU 6
SQ_BACKN    EQU 6

.const
ALIGN 16
kSqAbs      DWORD 7FFFFFFFh, 7FFFFFFFh, 7FFFFFFFh, 7FFFFFFFh
kSqTol      REAL4 1.0e-5, 1.0e-5, 1.0e-5, 1.0e-5
kSqTolN     REAL4 0.002                  ; |n|^2 - 1 of a unit normal
kSqNegEps   REAL4 -1.0e-7                ; a triangle may be this far against its normals (degenerate ones)
kSqOne      REAL4 1.0
kSqQuarter  REAL4 0.25
kSqA1       REAL4 0.1
kSqA2       REAL4 0.2
kSqA3       REAL4 0.3
kSqB1       REAL4 0.15
kSqB2       REAL4 -0.05
kSqB3       REAL4 0.4

ALIGN 16
sqVecA      REAL4 1.0, 2.0, 3.0, 0.0
sqVecR      REAL4 3.0, 2.0, -1.0, 0.0    ; (Rz Ry Rx) (1, 2, 3) with three quarter turns
sqVecB      REAL4 1.0, -2.0, 0.5, 0.0
sqVecZ      REAL4 0.0, 0.0, 1.0, 0.0
sqVecX      REAL4 1.0, 0.0, 0.0, 0.0

; turns, sin, cos
sqTrig      REAL4  0.0,        0.0,         1.0
            REAL4  0.125,      0.70710678,  0.70710678
            REAL4  0.1,        0.58778525,  0.80901699
            REAL4 -0.25,      -1.0,         0.0
            REAL4  1.75,      -1.0,         0.0
            REAL4  0.3333333,  0.8660254,  -0.5
            REAL4 -1.1,       -0.58778525,  0.80901699

; first column, second column, expected dot product of the columns of a rotation
sqDotTab    DWORD 0, 0
            REAL4 1.0
            DWORD 16, 16
            REAL4 1.0
            DWORD 32, 32
            REAL4 1.0
            DWORD 0, 16
            REAL4 0.0
            DWORD 0, 32
            REAL4 0.0
            DWORD 16, 32
            REAL4 0.0

; x, expected value
sqSmooth    REAL4 0.0, 0.0
            REAL4 1.0, 1.0
            REAL4 0.5, 0.5
            REAL4 0.25, 0.15625
            REAL4 -1.0, 0.0              ; clamped
            REAL4 2.0, 1.0
sqBack      REAL4 0.0, 0.0
            REAL4 1.0, 1.0
            REAL4 0.8, 1.04645056        ; overshoot: 1 + 2.70158 (-0.2)^3 + 1.70158 (-0.2)^2
            REAL4 0.5, 1.0876975
            REAL4 2.0, 1.0
            REAL4 -1.0, 0.0

kVolKnot    REAL4 16.803
kTolKnot    REAL4 0.02
kVolRing    REAL4 0.274
kTolRing    REAL4 0.003
kVolSphere  REAL4 4.12194                ; 32 x 16 cells
kTolSphere  REAL4 0.001
kVolCube    REAL4 8.0
kVolIco     REAL4 2.53615
kTolSolid   REAL4 0.001

szSqTrig    BYTE "3d math: sin / cos of an angle in turns (negative and above a turn too)", 0
szSqRot     BYTE "3d math: R = Rz Ry Rx order and signs, a rotation is orthonormal and right-handed", 0
szSqMul     BYTE "3d math: MatMul(A, B) applies B first, then A", 0
szSqSmooth  BYTE "3d math: smoothstep at its key points and clamped", 0
szSqBack    BYTE "3d math: ease-out-back starts at 0, overshoots, ends at 1", 0
szSqKnot    BYTE "3d solid: torus knot - closed, outward, volume 16.8", 0
szSqRing    BYTE "3d solid: ring - closed, outward, volume 0.274", 0
szSqSphere  BYTE "3d solid: sphere - closed, outward, volume 4.122", 0
szSqCube    BYTE "3d solid: cube - 12 flat faces, outward, volume 8", 0
szSqIco     BYTE "3d solid: icosahedron - 20 flat faces, outward, volume 2.536", 0

.data?
ALIGN 16
sqMatA      REAL4 12 DUP (?)
sqMatB      REAL4 12 DUP (?)
sqMatC      REAL4 12 DUP (?)
sqKnot      MESH <>
sqRing      MESH <>
sqSphere    MESH <>
sqCube      MESH <>
sqIco       MESH <>

.code

; ---------------------------------------------------------------------------
; Sq_Vec3 / Sq_Vec2 (xmm0 = value, xmm1 = expected) -> eax = 1 when the first
; three / two lanes agree within 1e-5 (NaN fails).
; ---------------------------------------------------------------------------
LEAF_BEGIN Sq_Vec3
    subps     xmm0, xmm1
    andps     xmm0, XMMWORD PTR kSqAbs
    cmpnleps  xmm0, XMMWORD PTR kSqTol
    movmskps  ecx, xmm0
    xor       eax, eax
    test      ecx, 7
    setz      al
    ret
LEAF_END Sq_Vec3

LEAF_BEGIN Sq_Vec2
    subps     xmm0, xmm1
    andps     xmm0, XMMWORD PTR kSqAbs
    cmpnleps  xmm0, XMMWORD PTR kSqTol
    movmskps  ecx, xmm0
    xor       eax, eax
    test      ecx, 3
    setz      al
    ret
LEAF_END Sq_Vec2

; Sq_Close(xmm0 = value, xmm1 = expected) -> eax = 1 when they differ by at most 1e-5.
LEAF_BEGIN Sq_Close
    subss     xmm0, xmm1
    andps     xmm0, XMMWORD PTR kSqAbs
    comiss    xmm0, DWORD PTR kSqTol
    setbe     al
    setnp     cl
    and       al, cl
    movzx     eax, al
    ret
LEAF_END Sq_Close

; Sq_Dot(xmm0 = a, xmm1 = b) -> xmm0 = a . b (three lanes); clobbers xmm2, xmm3.
LEAF_BEGIN Sq_Dot
    mulps     xmm0, xmm1
    HSUM3     xmm0, xmm0, xmm2, xmm3
    ret
LEAF_END Sq_Dot

; ---------------------------------------------------------------------------
; Sq_SC(xmm0 = turns, xmm1 = expected sin, xmm2 = expected cos) -> eax = 1 when
; G3_SinCos returns both.
; ---------------------------------------------------------------------------
FN_BEGIN Sq_SC, 16
    movss     DWORD PTR [rsp+LOC], xmm1
    movss     DWORD PTR [rsp+LOC+4], xmm2
    call      G3_SinCos
    unpcklps  xmm0, xmm1                     ; (sin, cos, ., .)
    movq      xmm1, QWORD PTR [rsp+LOC]      ; (expected sin, expected cos, 0, 0)
    call      Sq_Vec2
    FN_RET
FN_END Sq_SC

FN_BEGIN Sq_Trig, 0
    lea       rbx, sqTrig
    mov       esi, 1
    mov       edi, SQ_TRIGN
tg_lp:
    movss     xmm0, DWORD PTR [rbx]
    movss     xmm1, DWORD PTR [rbx+4]
    movss     xmm2, DWORD PTR [rbx+8]
    call      Sq_SC
    and       esi, eax
    add       rbx, 12
    dec       edi
    jnz       tg_lp
    mov       edx, esi
    lea       rcx, szSqTrig
    call      St_Report
    FN_RET
FN_END Sq_Trig

; ---------------------------------------------------------------------------
; Sq_Ortho(rcx = MAT3 *) -> eax = 1 when the columns are orthonormal and
; c0 x c1 = c2 (a proper rotation).
; ---------------------------------------------------------------------------
FN_BEGIN Sq_Ortho, 0
    mov       rsi, rcx
    lea       rdi, sqDotTab
    mov       r12d, 6
    mov       ebx, 1
or_lp:
    mov       eax, DWORD PTR [rdi]
    movaps    xmm0, XMMWORD PTR [rsi+rax]
    mov       eax, DWORD PTR [rdi+4]
    movaps    xmm1, XMMWORD PTR [rsi+rax]
    call      Sq_Dot
    movss     xmm1, DWORD PTR [rdi+8]
    call      Sq_Close
    and       ebx, eax
    add       rdi, 12
    dec       r12d
    jnz       or_lp
    movaps    xmm1, XMMWORD PTR [rsi]
    movaps    xmm2, XMMWORD PTR [rsi+16]
    VCROSS    xmm0, xmm1, xmm2, xmm3, xmm4   ; c0 x c1
    movaps    xmm1, XMMWORD PTR [rsi+32]
    call      Sq_Vec3
    and       eax, ebx
    FN_RET
FN_END Sq_Ortho

FN_BEGIN Sq_Rot, 0
    lea       rcx, sqMatA
    movss     xmm0, DWORD PTR kSqQuarter
    movaps    xmm1, xmm0
    movaps    xmm2, xmm0
    call      G3_RotMat
    lea       rcx, sqMatA
    movaps    xmm0, XMMWORD PTR sqVecA
    call      G3_MatVec
    movaps    xmm1, XMMWORD PTR sqVecR
    call      Sq_Vec3
    mov       ebx, eax
    lea       rcx, sqMatA
    movss     xmm0, DWORD PTR kSqA1
    movss     xmm1, DWORD PTR kSqA2
    movss     xmm2, DWORD PTR kSqA3
    call      G3_RotMat
    lea       rcx, sqMatA
    call      Sq_Ortho
    and       ebx, eax
    mov       edx, ebx
    lea       rcx, szSqRot
    call      St_Report
    FN_RET
FN_END Sq_Rot

; ---------------------------------------------------------------------------
; Sq_Mat - MatMul(A, B) v = A (B v), and in the right order: (Rx * Rz) x = z.
; ---------------------------------------------------------------------------
FNX_BEGIN Sq_Mat, 0
    lea       rcx, sqMatA
    movss     xmm0, DWORD PTR kSqA1
    movss     xmm1, DWORD PTR kSqA2
    movss     xmm2, DWORD PTR kSqA3
    call      G3_RotMat
    lea       rcx, sqMatB
    movss     xmm0, DWORD PTR kSqB1
    movss     xmm1, DWORD PTR kSqB2
    movss     xmm2, DWORD PTR kSqB3
    call      G3_RotMat
    lea       rcx, sqMatC
    lea       rdx, sqMatA
    lea       r8, sqMatB
    call      G3_MatMul
    lea       rcx, sqMatC
    movaps    xmm0, XMMWORD PTR sqVecB
    call      G3_MatVec
    movaps    xmm6, xmm0                      ; (A B) v
    lea       rcx, sqMatB
    movaps    xmm0, XMMWORD PTR sqVecB
    call      G3_MatVec
    lea       rcx, sqMatA
    call      G3_MatVec                       ; A (B v)
    movaps    xmm1, xmm6
    call      Sq_Vec3
    mov       ebx, eax
    call      Sq_MatOrder
    and       ebx, eax
    mov       edx, ebx
    lea       rcx, szSqMul
    call      St_Report
    FNX_RET
FN_END Sq_Mat

; Sq_MatOrder -> eax = 1 when (Rx(1/4) * Rz(1/4)) (1, 0, 0) = (0, 0, 1): Rz turns x into y, Rx turns y into z.
FN_BEGIN Sq_MatOrder, 0
    lea       rcx, sqMatA
    movss     xmm0, DWORD PTR kSqQuarter
    xorps     xmm1, xmm1
    xorps     xmm2, xmm2
    call      G3_RotMat                       ; Rx
    lea       rcx, sqMatB
    xorps     xmm0, xmm0
    xorps     xmm1, xmm1
    movss     xmm2, DWORD PTR kSqQuarter
    call      G3_RotMat                       ; Rz
    lea       rcx, sqMatC
    lea       rdx, sqMatA
    lea       r8, sqMatB
    call      G3_MatMul
    lea       rcx, sqMatC
    movaps    xmm0, XMMWORD PTR sqVecX
    call      G3_MatVec
    movaps    xmm1, XMMWORD PTR sqVecZ
    call      Sq_Vec3
    FN_RET
FN_END Sq_MatOrder

; ---------------------------------------------------------------------------
; Sq_FnTab(rcx = function, rdx = table of (x, expected) floats, r8d = rows)
;   -> eax = 1 when the function returns the expected value on every row.
; ---------------------------------------------------------------------------
FN_BEGIN Sq_FnTab, 0
    mov       rsi, rcx
    mov       rbx, rdx
    mov       edi, r8d
    mov       r12d, 1
ft_lp:
    movss     xmm0, DWORD PTR [rbx]
    call      rsi
    movss     xmm1, DWORD PTR [rbx+4]
    call      Sq_Close
    and       r12d, eax
    add       rbx, 8
    dec       edi
    jnz       ft_lp
    mov       eax, r12d
    FN_RET
FN_END Sq_FnTab

FN_BEGIN Sq_Ease, 0
    lea       rcx, G3_Smooth
    lea       rdx, sqSmooth
    mov       r8d, SQ_SMOOTHN
    call      Sq_FnTab
    mov       edx, eax
    lea       rcx, szSqSmooth
    call      St_Report
    lea       rcx, G3_EaseBack
    lea       rdx, sqBack
    mov       r8d, SQ_BACKN
    call      Sq_FnTab
    mov       edx, eax
    lea       rcx, szSqBack
    call      St_Report
    FN_RET
FN_END Sq_Ease

; ---------------------------------------------------------------------------
; Sq_Scan(rcx = MESH *) -> eax = problems found: bit 0 an index beyond the
; vertices, bit 1 a normal that is not a unit vector, bit 2 a triangle whose
; winding disagrees with the normals of its vertices.
; ---------------------------------------------------------------------------
FNX_BEGIN Sq_Scan, 0
    mov       r8, QWORD PTR [rcx+MESH.verts]
    mov       r9, QWORD PTR [rcx+MESH.idx]
    mov       r10d, DWORD PTR [rcx+MESH.nVerts]
    mov       r11d, DWORD PTR [rcx+MESH.nTris]
    xor       ebx, ebx
    movss     xmm9, DWORD PTR kSqOne
    movss     xmm10, DWORD PTR kSqTolN
    movss     xmm11, DWORD PTR kSqNegEps
    mov       rsi, r8
    mov       edi, r10d
sn_vert:
    movaps    xmm0, XMMWORD PTR [rsi+16]
    mulps     xmm0, xmm0
    HSUM3     xmm1, xmm0, xmm2, xmm3
    subss     xmm1, xmm9
    andps     xmm1, XMMWORD PTR kSqAbs
    comiss    xmm10, xmm1
    jae       sn_vok
    or        ebx, 2
sn_vok:
    add       rsi, 32
    dec       edi
    jnz       sn_vert
    mov       rsi, r9
    mov       r12d, r11d
sn_tri:
    movzx     eax, WORD PTR [rsi]
    movzx     edx, WORD PTR [rsi+2]
    movzx     ecx, WORD PTR [rsi+4]
    cmp       eax, r10d
    jae       sn_bad
    cmp       edx, r10d
    jae       sn_bad
    cmp       ecx, r10d
    jb        sn_in
sn_bad:
    or        ebx, 1
    jmp       sn_next
sn_in:
    shl       eax, 5
    shl       edx, 5
    shl       ecx, 5
    add       rax, r8
    add       rdx, r8
    add       rcx, r8
    movaps    xmm0, XMMWORD PTR [rax]
    movaps    xmm1, XMMWORD PTR [rdx]
    movaps    xmm2, XMMWORD PTR [rcx]
    movaps    xmm3, XMMWORD PTR [rax+16]
    addps     xmm3, XMMWORD PTR [rdx+16]
    addps     xmm3, XMMWORD PTR [rcx+16]      ; sum of the vertex normals
    subps     xmm1, xmm0
    subps     xmm2, xmm0
    VCROSS    xmm4, xmm1, xmm2, xmm5, xmm6    ; geometric normal
    mulps     xmm4, xmm3
    HSUM3     xmm0, xmm4, xmm5, xmm6
    comiss    xmm0, xmm11
    jae       sn_next
    or        ebx, 4
sn_next:
    add       rsi, 6
    dec       r12d
    jnz       sn_tri
    mov       eax, ebx
    FNX_RET
FN_END Sq_Scan

; ---------------------------------------------------------------------------
; Sq_Mesh(rcx = MESH *, rdx = check name, r8d = vertices, r9d = triangles,
;         xmm0 = expected volume, xmm1 = tolerance) - reports one solid.
; ---------------------------------------------------------------------------
FNX_BEGIN Sq_Mesh, 0
    mov       rsi, rcx
    mov       rdi, rdx
    movaps    xmm6, xmm0
    movaps    xmm7, xmm1
    xor       ebx, ebx
    cmp       DWORD PTR [rsi+MESH.nVerts], r8d
    sete      bl
    cmp       DWORD PTR [rsi+MESH.nTris], r9d
    sete      al
    and       bl, al
    mov       rcx, rsi
    call      Sq_Scan
    test      eax, eax
    setz      al
    and       bl, al
    mov       rcx, rsi
    call      Msh_Volume
    subss     xmm0, xmm6
    andps     xmm0, XMMWORD PTR kSqAbs
    comiss    xmm7, xmm0
    setae     al
    and       bl, al
    movzx     edx, bl
    mov       rcx, rdi
    call      St_Report
    FNX_RET
FN_END Sq_Mesh

; Builds a solid and reports it: MESHCHK builder, mesh, check name, vertices, triangles, volume, tolerance.
MESHCHK MACRO build:REQ, mesh:REQ, nm:REQ, nv:REQ, nt:REQ, vol:REQ, tol:REQ
    lea       rcx, mesh
    call      build
    lea       rcx, mesh
    lea       rdx, nm
    mov       r8d, nv
    mov       r9d, nt
    movss     xmm0, DWORD PTR vol
    movss     xmm1, DWORD PTR tol
    call      Sq_Mesh
ENDM

FN_BEGIN Sq_Solids, 0
    MESHCHK   Msh_Knot, sqKnot, szSqKnot, 1728, 3456, kVolKnot, kTolKnot
    MESHCHK   Msh_Ring, sqRing, szSqRing, 672, 1344, kVolRing, kTolRing
    MESHCHK   Msh_Sphere, sqSphere, szSqSphere, 544, 1024, kVolSphere, kTolSphere
    MESHCHK   Msh_Cube, sqCube, szSqCube, 36, 12, kVolCube, kTolSolid
    MESHCHK   Msh_Ico, sqIco, szSqIco, 60, 20, kVolIco, kTolSolid
    FN_RET
FN_END Sq_Solids

; ---------------------------------------------------------------------------
; St_G3 - all checks of the 3D renderer.
; ---------------------------------------------------------------------------
FN_BEGIN St_G3, 0
    call      G3_Init
    call      Sq_Trig
    call      Sq_Rot
    call      Sq_Mat
    call      Sq_Ease
    call      Sq_Solids
    call      St_G3Mat
    call      St_G3Raster
    call      St_Prism
    FN_RET
FN_END St_G3

END
