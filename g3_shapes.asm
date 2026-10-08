; ============================================================================
; g3_shapes.asm - the solids of the PRISM scene (see g3.inc).
; ----------------------------------------------------------------------------
;   knot    (2, 3) torus knot swept by a circle: the curve is
;             p(s) = ((2 + cos 3s') cos 2s', (2 + cos 3s') sin 2s', sin 3s')
;           (s' = 2 pi s), the frame is built from the analytic tangent and the
;           position vector (b = t x p, n = b x t), the tube radius is 0.42
;   ring    torus R = 1, r = 0.12
;   sphere  unit sphere, poles on the y axis
;   cube    edge 2, flat shaded;   ico   icosahedron, circumradius 1, flat shaded
; Surface evaluators take u in xmm0 and v in xmm1 (turns) and return the
; position in xmm0 and the unit normal in xmm1.
; ============================================================================
INCLUDE common.inc
INCLUDE g3.inc

; Registers a surface evaluator may use are all of them: the FNX frame keeps
; the caller's xmm6..xmm15, and the frame's first 16 local bytes serve PACK3.

.const
ALIGN 16
kKnotR   REAL4 0.42                       ; tube radius of the knot
kRingR   REAL4 1.0                        ; ring: distance of the tube centre
kRingr   REAL4 0.12                       ; ring: tube radius

; cube: point i has +1 where bit 0 / 1 / 2 of i is set (x / y / z)
cubePts  REAL4 -1.0, -1.0, -1.0,   1.0, -1.0, -1.0,  -1.0,  1.0, -1.0,   1.0,  1.0, -1.0
         REAL4 -1.0, -1.0,  1.0,   1.0, -1.0,  1.0,  -1.0,  1.0,  1.0,   1.0,  1.0,  1.0
         REAL4 0.0
cubeFaces BYTE 1, 3, 7,  1, 7, 5          ; +x
          BYTE 0, 4, 6,  0, 6, 2          ; -x
          BYTE 2, 6, 7,  2, 7, 3          ; +y
          BYTE 0, 1, 5,  0, 5, 4          ; -y
          BYTE 4, 5, 7,  4, 7, 6          ; +z
          BYTE 0, 2, 3,  0, 3, 1          ; -z

; icosahedron: (0, +-1, +-phi) and its cyclic permutations, scaled to radius 1
icoPts   REAL4 -0.5257311,  0.8506508,  0.0          ;  0
         REAL4  0.5257311,  0.8506508,  0.0          ;  1
         REAL4 -0.5257311, -0.8506508,  0.0          ;  2
         REAL4  0.5257311, -0.8506508,  0.0          ;  3
         REAL4  0.0, -0.5257311,  0.8506508          ;  4
         REAL4  0.0,  0.5257311,  0.8506508          ;  5
         REAL4  0.0, -0.5257311, -0.8506508          ;  6
         REAL4  0.0,  0.5257311, -0.8506508          ;  7
         REAL4  0.8506508,  0.0, -0.5257311          ;  8
         REAL4  0.8506508,  0.0,  0.5257311          ;  9
         REAL4 -0.8506508,  0.0, -0.5257311          ; 10
         REAL4 -0.8506508,  0.0,  0.5257311          ; 11
         REAL4 0.0
icoFaces BYTE 0, 11, 5,   0, 5, 1,    0, 1, 7,    0, 7, 10,   0, 10, 11
         BYTE 1, 5, 9,    5, 11, 4,   11, 10, 2,  10, 7, 6,   7, 1, 8
         BYTE 3, 9, 4,    3, 4, 2,    3, 2, 6,    3, 6, 8,    3, 8, 9
         BYTE 4, 9, 5,    2, 4, 11,   6, 2, 10,   8, 6, 7,    9, 8, 1

.code

; ---------------------------------------------------------------------------
; Shp_Sphere - P = N = (sin t cos p, cos t, sin t sin p), p = u, t = v / 2.
; ---------------------------------------------------------------------------
FNX_BEGIN Shp_Sphere, 16
    movaps    xmm6, xmm0                      ; u
    movaps    xmm0, xmm1
    mulss     xmm0, DWORD PTR kG3Half         ; latitude in turns
    call      G3_SinCos
    movaps    xmm7, xmm0                      ; sin t
    movaps    xmm8, xmm1                      ; cos t
    movaps    xmm0, xmm6
    call      G3_SinCos                       ; sin p, cos p
    movaps    xmm2, xmm7
    mulss     xmm2, xmm1                      ; x = sin t cos p
    mulss     xmm7, xmm0                      ; z = sin t sin p
    PACK3     xmm0, xmm2, xmm8, xmm7
    movaps    xmm1, xmm0
    FNX_RET
FN_END Shp_Sphere

; ---------------------------------------------------------------------------
; Shp_Ring - c = R (cos u, 0, sin u); N = (cos v cos u, sin v, cos v sin u);
; P = c + r N.
; ---------------------------------------------------------------------------
FNX_BEGIN Shp_Ring, 16
    movaps    xmm6, xmm0                      ; u
    movaps    xmm0, xmm1
    call      G3_SinCos
    movaps    xmm7, xmm0                      ; sin v
    movaps    xmm8, xmm1                      ; cos v
    movaps    xmm0, xmm6
    call      G3_SinCos                       ; sin u, cos u
    movaps    xmm2, xmm8
    mulss     xmm2, xmm1                      ; cos v cos u
    movaps    xmm3, xmm8
    mulss     xmm3, xmm0                      ; cos v sin u
    PACK3     xmm4, xmm2, xmm7, xmm3          ; N
    movss     xmm5, DWORD PTR kRingR
    mulss     xmm1, xmm5                      ; R cos u
    mulss     xmm0, xmm5                      ; R sin u
    xorps     xmm2, xmm2
    PACK3     xmm6, xmm1, xmm2, xmm0          ; c
    movss     xmm1, DWORD PTR kRingr
    shufps    xmm1, xmm1, 000h
    movaps    xmm0, xmm4
    mulps     xmm0, xmm1
    addps     xmm0, xmm6                      ; P = c + r N
    movaps    xmm1, xmm4
    FNX_RET
FN_END Shp_Ring

; ---------------------------------------------------------------------------
; Shp_Knot - see the header.  With A = 2 + cos 3s' the tangent direction is
; t = (-2 A sin 2s' - 3 sin 3s' cos 2s', 2 A cos 2s' - 3 sin 3s' sin 2s', 3 cos 3s').
; ---------------------------------------------------------------------------
FNX_BEGIN Shp_Knot, 16
    movaps    xmm6, xmm1                      ; v
    movaps    xmm7, xmm0                      ; u
    addss     xmm0, xmm0                      ; 2 u
    call      G3_SinCos
    movaps    xmm8, xmm0                      ; su = sin 2s'
    movaps    xmm9, xmm1                      ; cu = cos 2s'
    movaps    xmm0, xmm7
    mulss     xmm0, DWORD PTR kG3Three        ; 3 u
    call      G3_SinCos
    movaps    xmm10, xmm0                     ; sq = sin 3s'
    movaps    xmm11, xmm1                     ; cq = cos 3s'
    movss     xmm12, DWORD PTR kG3Two
    addss     xmm12, xmm11                    ; A
    movaps    xmm2, xmm12
    mulss     xmm2, xmm9                      ; A cu
    movaps    xmm3, xmm12
    mulss     xmm3, xmm8                      ; A su
    PACK3     xmm13, xmm2, xmm3, xmm10        ; p
    movaps    xmm4, xmm10
    mulss     xmm4, DWORD PTR kG3Three        ; 3 sq
    movaps    xmm5, xmm4
    mulss     xmm5, xmm9                      ; 3 sq cu
    mulss     xmm4, xmm8                      ; 3 sq su
    addss     xmm3, xmm3                      ; 2 A su
    addss     xmm2, xmm2                      ; 2 A cu
    xorps     xmm0, xmm0
    subss     xmm0, xmm3
    subss     xmm0, xmm5                      ; tx
    subss     xmm2, xmm4                      ; ty
    movaps    xmm1, xmm11
    mulss     xmm1, DWORD PTR kG3Three        ; tz
    PACK3     xmm14, xmm0, xmm2, xmm1         ; t
    VCROSS    xmm0, xmm14, xmm13, xmm1, xmm2
    VNORM     xmm0, xmm1, xmm2, xmm3, xmm4    ; b = t x p
    VCROSS    xmm5, xmm0, xmm14, xmm1, xmm2
    VNORM     xmm5, xmm1, xmm2, xmm3, xmm4    ; n = b x t
    movaps    xmm15, xmm5
    movaps    xmm14, xmm0                     ; b
    movaps    xmm0, xmm6
    call      G3_SinCos                       ; sin v, cos v
    shufps    xmm0, xmm0, 000h
    shufps    xmm1, xmm1, 000h
    mulps     xmm0, xmm14                     ; sin v * b
    mulps     xmm1, xmm15                     ; cos v * n
    addps     xmm1, xmm0                      ; unit normal of the tube
    movss     xmm2, DWORD PTR kKnotR
    shufps    xmm2, xmm2, 000h
    movaps    xmm0, xmm1
    mulps     xmm0, xmm2
    addps     xmm0, xmm13                     ; P = p + r d
    FNX_RET
FN_END Shp_Knot

; ---------------------------------------------------------------------------
; Builders: rcx = MESH * (out).
; ---------------------------------------------------------------------------
GRIDBUILD MACRO fname:REQ, surfFn:REQ, cellsU:REQ, cellsV:REQ, wrap:REQ
FN_BEGIN fname, 32
    lea       rdx, [rsp+LOC]
    lea       rax, surfFn
    mov       QWORD PTR [rdx+GRID.surf], rax
    mov       DWORD PTR [rdx+GRID.nu], cellsU
    mov       DWORD PTR [rdx+GRID.nv], cellsV
    mov       DWORD PTR [rdx+GRID.wrapV], wrap
    call      Msh_Grid
    FN_RET
FN_END fname
ENDM

GRIDBUILD Msh_Knot,   Shp_Knot,   144, 12, 1       ; 1728 vertices, 3456 triangles
GRIDBUILD Msh_Ring,   Shp_Ring,    48, 14, 1       ;  672 vertices, 1344 triangles
GRIDBUILD Msh_Sphere, Shp_Sphere,  32, 16, 0       ;  544 vertices, 1024 triangles

FN_BEGIN Msh_Cube, 0
    lea       rdx, cubePts
    lea       r8, cubeFaces
    mov       r9d, 12
    call      Msh_Flat
    FN_RET
FN_END Msh_Cube

FN_BEGIN Msh_Ico, 0
    lea       rdx, icoPts
    lea       r8, icoFaces
    mov       r9d, 20
    call      Msh_Flat
    FN_RET
FN_END Msh_Ico

END
