; ============================================================================
; selftest_g3r.asm - built-in checks of the 3D renderer, part 2: rasteriser,
;                    render targets and mesh drawing
;                    (part of SiliconDreams.exe /selftest).
; ----------------------------------------------------------------------------
; The triangles are hand-made vertices in the layout of PV (screen position,
; w = 1 / z, matcap coordinates).  The test matcap holds the value index + 1 in
; every texel, so a pixel tells which texel it came from.
;   * the right triangle with 100-sample legs covers exactly 4950 samples,
;   * two triangles sharing a diagonal cover a 61 x 74 rectangle exactly once
;     (additive mode would show an overlap as 2, a gap as 0),
;   * a rectangle whose four edges run through sample centres covers exactly
;     the half-open [left, right) x [top, bottom): the top-left rule; a sample
;     exactly on a middle vertex stays outside (its right-hand edges),
;   * eight triangles of every shape (flat top, flat bottom, sliver, tiny,
;     clipped by the screen, drawn back-to-front through glass) against a
;     per-sample point-in-triangle oracle in double precision,
;   * culling, the depth test in both drawing orders, the interpolated matcap
;     coordinates (axis-aligned and skew triangle), clipping, a vertex behind
;     the camera, the near plane at z = 0.5,
;   * the 2 x 2 resolve keeps a backdrop bit-exact and averages an edge (a
;     column and a row of samples),
;   * a cube in front of the camera lands on the analytically computed
;     222 x 222 samples; translation, scale, rotation and the matcap of a
;     tilted cube (two faces, two different normals) are checked,
;   * a sphere, and finally the canary bytes around both render targets.
; ============================================================================
INCLUDE common.inc
INCLUDE g3.inc

; One projected vertex in the layout of PV.
PVX MACRO x:REQ, y:REQ, w:REQ, u:REQ, v:REQ
    REAL4 x, y, 0.0, 0.0, w, u, v, 0.0
ENDM

RQ_RIGHT_N   EQU 4950                    ; samples inside (0, 0) (100, 0) (0, 100)
RQ_RECT_N    EQU 4514                    ; 61 x 74
RQ_TIE_N     EQU 600                     ; 30 x 20
RQ_NEAR_N    EQU 900000                  ; 1250 x 720
RQ_CUBE_N    EQU 49284                   ; 222 x 222
RQ_DIAMOND_N EQU 49612                   ; see Rt_Spin
RQ_CANARY    EQU 0CDCDCDCDh

.const
ALIGN 16
kSqAbsD     DWORD 0FFFFFFFFh, 7FFFFFFFh, 0FFFFFFFFh, 7FFFFFFFh   ; |x| of two doubles
kSqBand     REAL8 0.25                   ; samples this close to an edge line are not judged
kSqHalfD    REAL8 0.5
kRqTen      REAL4 10.0
kRqFive     REAL4 5.0
kRqOne      REAL4 1.0
kRqHalf     REAL4 0.5
kRqTurn16   REAL4 0.0625                 ; 22.5 degrees
kRqEighth   REAL4 0.125
kRqNear1    REAL4 2.6                    ; cube centres for Rt_Near: the front face lies at 1.6,
kRqNear2    REAL4 1.6                    ; 0.6 (just in front of the near plane)
kRqNear3    REAL4 1.4                    ; and 0.4 (behind it)

ALIGN 16
kRqIdent    REAL4 1.0, 0.0, 0.0, 0.0
            REAL4 0.0, 1.0, 0.0, 0.0
            REAL4 0.0, 0.0, 1.0, 0.0

; ---- triangles (three PV each, front-facing unless the name says Rev) ---------------------
ALIGN 16
trRight     LABEL REAL4
            PVX   0.0,   0.0, 1.0, 0.0, 0.0
            PVX 100.0,   0.0, 1.0, 0.0, 0.0
            PVX   0.0, 100.0, 1.0, 0.0, 0.0
trRightRev  LABEL REAL4
            PVX   0.0,   0.0, 1.0, 0.0, 0.0
            PVX   0.0, 100.0, 1.0, 0.0, 0.0
            PVX 100.0,   0.0, 1.0, 0.0, 0.0
trRectA     LABEL REAL4
            PVX  10.3,  20.7, 1.0, 0.0, 0.0
            PVX  71.3,  20.7, 1.0, 0.0, 0.0
            PVX  71.3,  94.7, 1.0, 0.0, 0.0
trRectB     LABEL REAL4
            PVX  10.3,  20.7, 1.0, 0.0, 0.0
            PVX  71.3,  94.7, 1.0, 0.0, 0.0
            PVX  10.3,  94.7, 1.0, 0.0, 0.0
trNear      LABEL REAL4                  ; w = 0.2, matcap column 10
            PVX   0.0,   0.0, 0.2, 10.0, 0.0
            PVX 100.0,   0.0, 0.2, 10.0, 0.0
            PVX   0.0, 100.0, 0.2, 10.0, 0.0
trFar       LABEL REAL4                  ; w = 0.1, matcap column 20
            PVX  10.0,   0.0, 0.1, 20.0, 0.0
            PVX 110.0,   0.0, 0.1, 20.0, 0.0
            PVX  10.0, 100.0, 0.1, 20.0, 0.0
trTex       LABEL REAL4                  ; u = 2.55 x, v = 2.55 y
            PVX   0.0,   0.0, 1.0,   0.0,   0.0
            PVX 100.0,   0.0, 1.0, 255.0,   0.0
            PVX   0.0, 100.0, 1.0,   0.0, 255.0
trBehind    LABEL REAL4                  ; one vertex has w = 0 (at or behind the camera)
            PVX   0.0,   0.0, 1.0, 0.0, 0.0
            PVX 100.0,   0.0, 0.0, 0.0, 0.0
            PVX   0.0, 100.0, 1.0, 0.0, 0.0
trHuge      LABEL REAL4                  ; larger than the whole target
            PVX -4000.5, -4000.5, 1.0, 0.0, 0.0
            PVX  9000.5, -3000.5, 1.0, 0.0, 0.0
            PVX -3500.5,  8000.5, 1.0, 0.0, 0.0
trOutL      LABEL REAL4
            PVX -300.0, 100.0, 1.0, 0.0, 0.0
            PVX -100.0, 100.0, 1.0, 0.0, 0.0
            PVX -200.0, 300.0, 1.0, 0.0, 0.0
trOutR      LABEL REAL4
            PVX 1400.0, 100.0, 1.0, 0.0, 0.0
            PVX 1600.0, 100.0, 1.0, 0.0, 0.0
            PVX 1500.0, 300.0, 1.0, 0.0, 0.0
trOutT      LABEL REAL4
            PVX  100.0, -300.0, 1.0, 0.0, 0.0
            PVX  300.0, -300.0, 1.0, 0.0, 0.0
            PVX  200.0, -100.0, 1.0, 0.0, 0.0
trOutB      LABEL REAL4
            PVX  100.0,  900.0, 1.0, 0.0, 0.0
            PVX  300.0,  900.0, 1.0, 0.0, 0.0
            PVX  200.0, 1100.0, 1.0, 0.0, 0.0
trHalfA     LABEL REAL4                  ; the strip [0, 1) x [0, 2): one column of a pixel's samples
            PVX   0.0,   0.0, 1.0, 1.0, 128.0
            PVX   1.0,   0.0, 1.0, 1.0, 128.0
            PVX   1.0,   2.0, 1.0, 1.0, 128.0
trHalfB     LABEL REAL4
            PVX   0.0,   0.0, 1.0, 1.0, 128.0
            PVX   1.0,   2.0, 1.0, 1.0, 128.0
            PVX   0.0,   2.0, 1.0, 1.0, 128.0
trHalfC     LABEL REAL4                  ; the strip [0, 2) x [0, 1): one row of a pixel's samples
            PVX   0.0,   0.0, 1.0, 1.0, 128.0
            PVX   2.0,   0.0, 1.0, 1.0, 128.0
            PVX   2.0,   1.0, 1.0, 1.0, 128.0
trHalfD     LABEL REAL4
            PVX   0.0,   0.0, 1.0, 1.0, 128.0
            PVX   2.0,   1.0, 1.0, 1.0, 128.0
            PVX   0.0,   1.0, 1.0, 1.0, 128.0
trTieA      LABEL REAL4                  ; the rectangle [10.5, 40.5) x [10.5, 30.5): every edge, and
            PVX  10.5,  10.5, 1.0, 0.0, 0.0   ; the diagonal too, runs through sample centres
            PVX  40.5,  10.5, 1.0, 0.0, 0.0
            PVX  40.5,  30.5, 1.0, 0.0, 0.0
trTieB      LABEL REAL4
            PVX  10.5,  10.5, 1.0, 0.0, 0.0
            PVX  40.5,  30.5, 1.0, 0.0, 0.0
            PVX  10.5,  30.5, 1.0, 0.0, 0.0
trMid       LABEL REAL4                  ; the middle vertex (72.5, 55.5) lies on a sample centre, right of
            PVX  15.8,  27.5, 1.0, 0.0, 0.0   ; the long edge; in single precision the edge from above
            PVX  72.5,  55.5, 1.0, 0.0, 0.0   ; reaches x = 72.5000076 in that row (see Rt_Vertex)
            PVX  20.5,  80.5, 1.0, 0.0, 0.0
trSkew      LABEL REAL4                  ; a different matcap coordinate at every vertex
            PVX  20.2,  10.4, 1.0,  10.0, 200.0
            PVX 170.8,  40.6, 1.0, 240.0,  30.0
            PVX  60.4, 150.2, 1.0, 100.0, 120.0

; ---- triangles for the oracle --------------------------------------------------------------
trOr1       LABEL REAL4                  ; general, the middle vertex on the left
            PVX  30.4,  20.7, 1.0, 0.0, 0.0
            PVX 180.9,  70.3, 1.0, 0.0, 0.0
            PVX  60.2, 190.6, 1.0, 0.0, 0.0
trOr1Rev    LABEL REAL4                  ; the same one, seen from behind
            PVX  30.4,  20.7, 1.0, 0.0, 0.0
            PVX  60.2, 190.6, 1.0, 0.0, 0.0
            PVX 180.9,  70.3, 1.0, 0.0, 0.0
trOr2       LABEL REAL4                  ; flat top
            PVX  50.6,  40.3, 1.0, 0.0, 0.0
            PVX 200.2,  40.3, 1.0, 0.0, 0.0
            PVX 120.4, 180.8, 1.0, 0.0, 0.0
trOr3       LABEL REAL4                  ; flat bottom
            PVX 100.5,  30.2, 1.0, 0.0, 0.0
            PVX 190.7, 160.4, 1.0, 0.0, 0.0
            PVX  20.3, 160.4, 1.0, 0.0, 0.0
trOr4       LABEL REAL4                  ; sliver, 3 samples wide and 390 high
            PVX 300.5,  10.5, 1.0, 0.0, 0.0
            PVX 303.9, 400.5, 1.0, 0.0, 0.0
            PVX 298.2, 405.1, 1.0, 0.0, 0.0
trOr5       LABEL REAL4                  ; the middle vertex on the right
            PVX 400.2,  50.3, 1.0, 0.0, 0.0
            PVX 520.8, 120.1, 1.0, 0.0, 0.0
            PVX 380.5, 200.9, 1.0, 0.0, 0.0
trOr6       LABEL REAL4                  ; a handful of samples
            PVX 700.3, 300.4, 1.0, 0.0, 0.0
            PVX 702.9, 301.1, 1.0, 0.0, 0.0
            PVX 700.9, 304.2, 1.0, 0.0, 0.0
trClipA     LABEL REAL4                  ; leaves the target at the left and at the top
            PVX -60.5, -40.25, 1.0, 0.0, 0.0
            PVX 300.7,  10.5,  1.0, 0.0, 0.0
            PVX  40.3, 250.9,  1.0, 0.0, 0.0
trClipB     LABEL REAL4                  ; leaves it at the right and at the bottom
            PVX 1200.3, 600.5, 1.0, 0.0, 0.0
            PVX 1400.7, 650.2, 1.0, 0.0, 0.0
            PVX 1250.6, 900.9, 1.0, 0.0, 0.0

; what to draw, what to compare it with, in which mode (0 opaque, 1 glass)
rqOracleTab QWORD trOr1, trOr1, 0
            QWORD trOr2, trOr2, 0
            QWORD trOr3, trOr3, 0
            QWORD trOr4, trOr4, 0
            QWORD trOr5, trOr5, 0
            QWORD trOr6, trOr6, 0
            QWORD trClipA, trClipA, 0
            QWORD trClipB, trClipB, 0
            QWORD trOr1Rev, trOr1, 1
            QWORD 0, 0, 0

; x, y, 1 when the sample belongs to the triangle trRight
rqCovTab    DWORD 0, 0, 1
            DWORD 98, 0, 1
            DWORD 99, 0, 0
            DWORD 0, 98, 1
            DWORD 0, 99, 0
            DWORD 49, 49, 1
            DWORD 49, 50, 0
            DWORD 50, 50, 0
RQ_COVN     EQU 8

; x, y, 1 when the sample belongs to the rectangle of trTieA + trTieB: columns 10 .. 39, rows 10 .. 29
rqTieTab    DWORD 10, 10, 1                  ; the left and the top edge belong to it
            DWORD 39, 10, 1
            DWORD 10, 29, 1
            DWORD 39, 29, 1
            DWORD 9, 10, 0
            DWORD 10, 9, 0
            DWORD 40, 10, 0                  ; the right and the bottom edge do not
            DWORD 40, 29, 0
            DWORD 10, 30, 0
            DWORD 39, 30, 0
RQ_TIEN     EQU 10

; x, y, 1 when the sample belongs to the triangle trMid
rqMidTab    DWORD 71, 55, 1                  ; next to the vertex
            DWORD 72, 55, 0                  ; on the vertex: it lies on right edges only
            DWORD 69, 56, 1                  ; one row below, the edge running to the lower left
            DWORD 70, 56, 0
RQ_MIDN     EQU 4

; x, y, value of trSkew there: (v << 8 | u) + 1 of the exact barycentric (u, v), computed in
; double precision (the fractions lie between 0.12 and 0.88, far from any rounding)
rqSkewTab   DWORD  30,  14, 47899            ; u  26.172  v 187.838
            DWORD 150,  38, 13522            ; u 209.425  v  52.397
            DWORD  62, 139, 30821            ; u 100.792  v 120.552
            DWORD  80,  59, 31343            ; u 110.128  v 122.206
            DWORD 100,  99, 23189            ; u 148.487  v  90.172
            DWORD  45,  80, 39487            ; u  62.759  v 154.352
            DWORD 120,  45, 21159            ; u 166.435  v  82.841
            DWORD  70, 110, 30571            ; u 106.365  v 119.565
RQ_SKEWN    EQU 8

; the front face of the cube at z = 9: samples 529 .. 750 and 249 .. 470
rqCubeTab   DWORD 640, 360, 1
            DWORD 528, 360, 0
            DWORD 529, 360, 1
            DWORD 750, 360, 1
            DWORD 751, 360, 0
            DWORD 640, 248, 0
            DWORD 640, 249, 1
            DWORD 640, 470, 1
            DWORD 640, 471, 0
RQ_CUBEN    EQU 9

; the same cube moved by +1 in x: the face starts exactly at the sample 640
rqShiftTab  DWORD 639, 360, 0
            DWORD 640, 360, 1
            DWORD 861, 360, 1
            DWORD 862, 360, 0
RQ_SHIFTN   EQU 4

; the cube turned by an eighth of a turn about z: a diamond, the middle row spans 483 .. 796
rqSpinTab   DWORD 482, 360, 0
            DWORD 483, 360, 1
            DWORD 796, 360, 1
            DWORD 797, 360, 0
            DWORD 640, 360, 1
            DWORD 529, 249, 0               ; the corner of the unturned square is empty now
RQ_SPINN    EQU 6

szRaCover   BYTE "3d raster: a triangle covers exactly the samples whose centres lie inside", 0
szRaEdge    BYTE "3d raster: triangles sharing an edge leave no gap and no overlap", 0
szRaTie     BYTE "3d raster: samples exactly on an edge follow the top-left rule", 0
szRaVertex  BYTE "3d raster: a sample exactly on the middle vertex stays outside (the edge above ends there)", 0
szRaOracle  BYTE "3d raster: every shape matches a per-sample oracle (flat, sliver, tiny, clipped, glass)", 0
szRaCull    BYTE "3d raster: back faces are culled, glass shows both sides", 0
szRaDepth   BYTE "3d raster: the depth test keeps the nearer triangle in either drawing order", 0
szRaTex     BYTE "3d raster: matcap coordinates are interpolated across the triangle", 0
szRaSkew    BYTE "3d raster: matcap coordinates of a skew triangle match the barycentric values", 0
szRaClip    BYTE "3d raster: larger and outside triangles are clipped to the target", 0
szRaBehind  BYTE "3d raster: a vertex behind the camera drops the triangle", 0
szRaNear    BYTE "3d draw: a vertex nearer than 0.5 takes its triangle with it", 0
szRaResolve BYTE "3d target: the 2x2 resolve keeps a backdrop and averages an edge (column and row)", 0
szRaCube    BYTE "3d draw: a cube in front of the camera covers the computed 222 x 222 samples", 0
szRaShift   BYTE "3d draw: the translation of the transform moves the face by exact amounts", 0
szRaScale   BYTE "3d draw: scale and distance (half size at half the distance, same face)", 0
szRaSpin    BYTE "3d draw: a turn about z makes a diamond of the computed 49612 samples", 0
szRaTilt    BYTE "3d draw: normals follow the rotation (tilted cube shows two matcap texels)", 0
szRaSphere  BYTE "3d draw: a sphere has the right size and a centred matcap", 0
szRaGuard   BYTE "3d target: nothing was written outside the render targets", 0

.data?
ALIGN 16
rqCube      MESH <>
rqSphere    MESH <>
rqXf        XFORM <>
rqMat       REAL4 12 DUP (?)
rqTex       DWORD G3_TEXN DUP (?)

.code

; ---------------------------------------------------------------------------
; Counting and probing the supersampled colour target.
; ---------------------------------------------------------------------------
; Rq_CountNz -> eax = number of samples that are not zero.
LEAF_BEGIN Rq_CountNz
    mov       r8, QWORD PTR g3Color
    mov       ecx, G3_PIX
    xor       eax, eax
cz_lp:
    cmp       DWORD PTR [r8], 0
    setne     dl
    movzx     edx, dl
    add       eax, edx
    add       r8, 4
    dec       ecx
    jnz       cz_lp
    ret
LEAF_END Rq_CountNz

; Rq_CountEq(ecx = value) -> eax = number of samples equal to value.
LEAF_BEGIN Rq_CountEq
    mov       r8, QWORD PTR g3Color
    mov       r9d, G3_PIX
    xor       eax, eax
ce_lp:
    cmp       DWORD PTR [r8], ecx
    sete      dl
    movzx     edx, dl
    add       eax, edx
    add       r8, 4
    dec       r9d
    jnz       ce_lp
    ret
LEAF_END Rq_CountEq

; Rq_At(ecx = x, edx = y) -> eax = the sample at (x, y) of the colour target.
LEAF_BEGIN Rq_At
    mov       rax, QWORD PTR g3Color
    imul      edx, edx, G3_W
    add       ecx, edx
    mov       eax, DWORD PTR [rax+rcx*4]
    ret
LEAF_END Rq_At

; Rq_Guard(rcx = target) -> eax = 1 when the canary bytes before and behind it are intact.
LEAF_BEGIN Rq_Guard
    mov       eax, RQ_CANARY
    lea       r8, [rcx-G3_GUARD]
    mov       edx, G3_GUARD / 4
gd_lo:
    cmp       DWORD PTR [r8], eax
    jne       gd_bad
    add       r8, 4
    dec       edx
    jnz       gd_lo
    lea       r8, [rcx+G3_BYTES]
    mov       edx, G3_GUARD / 4
gd_hi:
    cmp       DWORD PTR [r8], eax
    jne       gd_bad
    add       r8, 4
    dec       edx
    jnz       gd_hi
    mov       eax, 1
    ret
gd_bad:
    xor       eax, eax
    ret
LEAF_END Rq_Guard

; Rq_Within(eax = value, ecx = centre, r8d = tolerance) -> eax = 1 when |value - centre| <= tolerance.
LEAF_BEGIN Rq_Within
    sub       eax, ecx
    cdq
    xor       eax, edx
    sub       eax, edx
    cmp       eax, r8d
    setbe     al
    movzx     eax, al
    ret
LEAF_END Rq_Within

; ---------------------------------------------------------------------------
; Frames and the test matcap.
; ---------------------------------------------------------------------------
; Rq_SameFrames(rcx = a, rdx = b) -> eax = 1 when both 640 x 360 frames are identical.
LEAF_BEGIN Rq_SameFrames
    mov       r8d, SCR_PIX
sf_lp:
    mov       eax, DWORD PTR [rcx]
    cmp       eax, DWORD PTR [rdx]
    jne       sf_no
    add       rcx, 4
    add       rdx, 4
    dec       r8d
    jnz       sf_lp
    mov       eax, 1
    ret
sf_no:
    xor       eax, eax
    ret
LEAF_END Rq_SameFrames

; Rq_Pattern(rcx = frame) - a different value in every pixel.
LEAF_BEGIN Rq_Pattern
    xor       eax, eax
    mov       edx, 9E3779B1h
pa_lp:
    mov       r8d, eax
    imul      r8d, edx
    xor       r8d, 00A5A5A5h
    mov       DWORD PTR [rcx+rax*4], r8d
    inc       eax
    cmp       eax, SCR_PIX
    jb        pa_lp
    ret
LEAF_END Rq_Pattern

; Rq_FillTex - texel i = i + 1.
LEAF_BEGIN Rq_FillTex
    lea       r8, rqTex
    xor       eax, eax
ft_lp:
    lea       edx, [rax+1]
    mov       DWORD PTR [r8+rax*4], edx
    inc       eax
    cmp       eax, G3_TEXN
    jb        ft_lp
    ret
LEAF_END Rq_FillTex

; Rq_Xf(rcx = XFORM *, rdx = MAT3 *, xmm0 / xmm1 / xmm2 = translation, xmm3 = scale)
LEAF_BEGIN Rq_Xf
    movaps    xmm4, XMMWORD PTR [rdx]
    movaps    XMMWORD PTR [rcx+XFORM.c0], xmm4
    movaps    xmm4, XMMWORD PTR [rdx+16]
    movaps    XMMWORD PTR [rcx+XFORM.c1], xmm4
    movaps    xmm4, XMMWORD PTR [rdx+32]
    movaps    XMMWORD PTR [rcx+XFORM.c2], xmm4
    movss     DWORD PTR [rcx+XFORM.t], xmm0
    movss     DWORD PTR [rcx+XFORM.t+4], xmm1
    movss     DWORD PTR [rcx+XFORM.t+8], xmm2
    mov       DWORD PTR [rcx+XFORM.t+12], 0
    shufps    xmm3, xmm3, 000h
    movaps    XMMWORD PTR [rcx+XFORM.s], xmm3
    ret
LEAF_END Rq_Xf

; ---------------------------------------------------------------------------
; Drawing.
; ---------------------------------------------------------------------------
; Rq_Clear - black backdrop, nothing drawn yet.
FN_BEGIN Rq_Clear, 0
    mov       rcx, QWORD PTR gFbA
    xor       edx, edx
    call      Gfx_Fill
    mov       rcx, QWORD PTR gFbA
    call      G3_Begin
    FN_RET
FN_END Rq_Clear

; Rq_Draw(rcx = three PV, edx = G3M_*) - one triangle through set-up and scan.
FN_BEGIN Rq_Draw, 0
    mov       DWORD PTR g3Mode, edx
    lea       rax, rqTex
    mov       QWORD PTR g3Tex, rax
    lea       rdx, [rcx+32]
    lea       r8, [rcx+64]
    call      G3_TriSetup
    test      eax, eax
    jz        dw_out
    call      G3_TriScan
dw_out:
    FN_RET
FN_END Rq_Draw

; Rq_DrawMesh(rcx = MESH *) - through G3_Draw with the transform in rqXf (opaque).
FN_BEGIN Rq_DrawMesh, 0
    lea       rdx, rqXf
    lea       r8, rqTex
    mov       r9d, G3M_OPAQUE
    call      G3_Draw
    FN_RET
FN_END Rq_DrawMesh

; Rq_CubeAt(rdx = MAT3 *, xmm0 / xmm1 / xmm2 = translation, xmm3 = scale) -> eax = samples covered.
FN_BEGIN Rq_CubeAt, 0
    lea       rcx, rqXf
    call      Rq_Xf
    call      Rq_Clear
    lea       rcx, rqCube
    call      Rq_DrawMesh
    call      Rq_CountNz
    FN_RET
FN_END Rq_CubeAt

; Rq_Pts(rcx = table of (x, y, covered), edx = rows) -> eax = 1 when every sample matches.
FN_BEGIN Rq_Pts, 0
    mov       rsi, rcx
    mov       edi, edx
    mov       ebx, 1
pt_lp:
    mov       ecx, DWORD PTR [rsi]
    mov       edx, DWORD PTR [rsi+4]
    call      Rq_At
    test      eax, eax
    setnz     al
    movzx     eax, al
    cmp       eax, DWORD PTR [rsi+8]
    sete      al
    movzx     eax, al
    and       ebx, eax
    add       rsi, 12
    dec       edi
    jnz       pt_lp
    mov       eax, ebx
    FN_RET
FN_END Rq_Pts

; Rq_Vals(rcx = table of (x, y, value), edx = rows) -> eax = 1 when every sample has exactly its value.
FN_BEGIN Rq_Vals, 0
    mov       rsi, rcx
    mov       edi, edx
    mov       ebx, 1
vl_lp:
    mov       ecx, DWORD PTR [rsi]
    mov       edx, DWORD PTR [rsi+4]
    call      Rq_At
    cmp       eax, DWORD PTR [rsi+8]
    sete      al
    movzx     eax, al
    and       ebx, eax
    add       rsi, 12
    dec       edi
    jnz       vl_lp
    mov       eax, ebx
    FN_RET
FN_END Rq_Vals

; ---------------------------------------------------------------------------
; Rq_Oracle(rcx = three PV of a front-facing triangle) -> eax = samples of the
; colour target whose coverage differs from the exact point-in-triangle test
; (doubles; samples within a quarter of a square pixel of an edge line are not
; judged: the rasteriser works in single precision).
; Edge functions e_k = c_k + a_k x + b_k y, positive inside.
; ---------------------------------------------------------------------------
ROWSTART MACRO e:REQ, a:REQ, b:REQ, c:REQ
    movsd     e, b
    mulsd     e, xmm3
    addsd     e, c
    movsd     xmm4, a
    mulsd     xmm4, QWORD PTR kSqHalfD
    addsd     e, xmm4
ENDM

JUDGE MACRO e:REQ
    xorpd     xmm3, xmm3
    comisd    e, xmm3
    seta      al
    and       r8b, al                         ; inside only when every e > 0
    movapd    xmm3, e
    andpd     xmm3, XMMWORD PTR kSqAbsD
    comisd    xmm15, xmm3
    seta      al                              ; the band is wider than |e|
    or        r9b, al
ENDM

FNX_BEGIN Rq_Oracle, 0
    cvtss2sd  xmm0, DWORD PTR [rcx]           ; x0
    cvtss2sd  xmm1, DWORD PTR [rcx+4]         ; y0
    cvtss2sd  xmm2, DWORD PTR [rcx+32]        ; x1
    cvtss2sd  xmm3, DWORD PTR [rcx+36]        ; y1
    cvtss2sd  xmm4, DWORD PTR [rcx+64]        ; x2
    cvtss2sd  xmm5, DWORD PTR [rcx+68]        ; y2
    movsd     xmm6, xmm2
    mulsd     xmm6, xmm5
    movsd     xmm7, xmm4
    mulsd     xmm7, xmm3
    subsd     xmm6, xmm7                      ; c0 = x1 y2 - x2 y1
    movsd     xmm9, xmm3
    subsd     xmm9, xmm5                      ; a0 = y1 - y2
    movsd     xmm12, xmm4
    subsd     xmm12, xmm2                     ; b0 = x2 - x1
    movsd     xmm7, xmm4
    mulsd     xmm7, xmm1
    movsd     xmm8, xmm0
    mulsd     xmm8, xmm5
    subsd     xmm7, xmm8                      ; c1 = x2 y0 - x0 y2
    movsd     xmm10, xmm5
    subsd     xmm10, xmm1                     ; a1 = y2 - y0
    movsd     xmm13, xmm0
    subsd     xmm13, xmm4                     ; b1 = x0 - x2
    movsd     xmm8, xmm0
    mulsd     xmm8, xmm3
    movsd     xmm14, xmm2
    mulsd     xmm14, xmm1
    subsd     xmm8, xmm14                     ; c2 = x0 y1 - x1 y0
    movsd     xmm11, xmm1
    subsd     xmm11, xmm3                     ; a2 = y0 - y1
    movsd     xmm14, xmm2
    subsd     xmm14, xmm0                     ; b2 = x1 - x0
    movsd     xmm15, QWORD PTR kSqBand
    xor       ebx, ebx
    mov       rsi, QWORD PTR g3Color
    xor       edi, edi
or_row:
    cvtsi2sd  xmm3, edi
    addsd     xmm3, QWORD PTR kSqHalfD        ; y + 0.5
    ROWSTART  xmm0, xmm9, xmm12, xmm6
    ROWSTART  xmm1, xmm10, xmm13, xmm7
    ROWSTART  xmm2, xmm11, xmm14, xmm8
    xor       ecx, ecx
or_col:
    mov       r8d, 1
    xor       r9d, r9d
    JUDGE     xmm0
    JUDGE     xmm1
    JUDGE     xmm2
    xor       eax, eax
    cmp       DWORD PTR [rsi+rcx*4], 0
    setne     al
    test      r9d, r9d
    jnz       or_skip
    cmp       eax, r8d
    je        or_skip
    inc       ebx
or_skip:
    addsd     xmm0, xmm9
    addsd     xmm1, xmm10
    addsd     xmm2, xmm11
    inc       ecx
    cmp       ecx, G3_W
    jb        or_col
    add       rsi, G3_PITCH
    inc       edi
    cmp       edi, G3_H
    jb        or_row
    mov       eax, ebx
    FNX_RET
FN_END Rq_Oracle

; ---------------------------------------------------------------------------
; Rt_Cover - the right triangle.
; ---------------------------------------------------------------------------
FN_BEGIN Rt_Cover, 0
    call      Rq_Clear
    lea       rcx, trRight
    mov       edx, G3M_OPAQUE
    call      Rq_Draw
    call      Rq_CountNz
    xor       ebx, ebx
    cmp       eax, RQ_RIGHT_N
    sete      bl
    lea       rcx, rqCovTab
    mov       edx, RQ_COVN
    call      Rq_Pts
    and       ebx, eax
    mov       edx, ebx
    lea       rcx, szRaCover
    call      St_Report
    FN_RET
FN_END Rt_Cover

; ---------------------------------------------------------------------------
; Rt_Edge - a rectangle from two triangles in additive mode: every covered
; sample must be exactly 1 (texel 0), the count the area of the rectangle.
; ---------------------------------------------------------------------------
FN_BEGIN Rt_Edge, 0
    call      Rq_Clear
    lea       rcx, trRectA
    mov       edx, G3M_GLASS
    call      Rq_Draw
    lea       rcx, trRectB
    mov       edx, G3M_GLASS
    call      Rq_Draw
    call      Rq_CountNz
    mov       esi, eax
    mov       ecx, 1
    call      Rq_CountEq
    xor       ebx, ebx
    cmp       eax, RQ_RECT_N
    sete      bl
    cmp       esi, RQ_RECT_N
    sete      cl
    and       bl, cl
    movzx     edx, bl
    lea       rcx, szRaEdge
    call      St_Report
    FN_RET
FN_END Rt_Edge

; ---------------------------------------------------------------------------
; Rt_Tie - a rectangle whose edges lie exactly on sample centres (x and y =
; n + 0.5): the left and the top edge belong to it, the right and the bottom
; edge do not.  Samples on the diagonal go to exactly one of the two triangles.
; The 30 x 20 samples come out as 600, every one of them hit exactly once.
; ---------------------------------------------------------------------------
FN_BEGIN Rt_Tie, 0
    call      Rq_Clear
    lea       rcx, trTieA
    mov       edx, G3M_GLASS
    call      Rq_Draw
    lea       rcx, trTieB
    mov       edx, G3M_GLASS
    call      Rq_Draw
    call      Rq_CountNz
    mov       esi, eax
    mov       ecx, 1
    call      Rq_CountEq
    xor       ebx, ebx
    cmp       eax, RQ_TIE_N
    sete      bl
    cmp       esi, RQ_TIE_N
    sete      cl
    and       bl, cl
    lea       rcx, rqTieTab
    mov       edx, RQ_TIEN
    call      Rq_Pts
    and       bl, al
    movzx     edx, bl
    lea       rcx, szRaTie
    call      St_Report
    FN_RET
FN_END Rt_Tie

; ---------------------------------------------------------------------------
; Rt_Vertex - a vertex on a sample centre.  The sample (72, 55) lies exactly
; on the middle vertex of trMid, i.e. on two right-hand edges, and stays empty.
; In that row only the edge that starts at the vertex is active (its x is the
; vertex itself, exactly); the edge that ends there must not count: in single
; precision it reaches 72.5000076, which would pull the sample inside.
; ---------------------------------------------------------------------------
FN_BEGIN Rt_Vertex, 0
    call      Rq_Clear
    lea       rcx, trMid
    mov       edx, G3M_OPAQUE
    call      Rq_Draw
    lea       rcx, rqMidTab
    mov       edx, RQ_MIDN
    call      Rq_Pts
    mov       edx, eax
    lea       rcx, szRaVertex
    call      St_Report
    FN_RET
FN_END Rt_Vertex

; ---------------------------------------------------------------------------
; Rt_Oracle - every row of rqOracleTab: draw, then compare with the oracle.
; ---------------------------------------------------------------------------
FN_BEGIN Rt_Oracle, 0
    lea       rbx, rqOracleTab
    xor       r12d, r12d
or_next:
    mov       rsi, QWORD PTR [rbx]
    test      rsi, rsi
    jz        or_done
    call      Rq_Clear
    mov       rcx, rsi
    mov       edx, DWORD PTR [rbx+16]
    call      Rq_Draw
    mov       rcx, QWORD PTR [rbx+8]
    call      Rq_Oracle
    add       r12d, eax
    add       rbx, 24
    jmp       or_next
or_done:
    xor       edx, edx
    test      r12d, r12d
    setz      dl
    lea       rcx, szRaOracle
    call      St_Report
    FN_RET
FN_END Rt_Oracle

; ---------------------------------------------------------------------------
; Rt_Cull - a back face is dropped in opaque mode; glass draws it as a front face.
; ---------------------------------------------------------------------------
FN_BEGIN Rt_Cull, 0
    call      Rq_Clear
    lea       rcx, trRightRev
    mov       edx, G3M_OPAQUE
    call      Rq_Draw
    call      Rq_CountNz
    mov       ebx, eax                        ; must stay 0
    call      Rq_Clear
    lea       rcx, trRight
    mov       edx, G3M_GLASS
    call      Rq_Draw
    call      Rq_CountNz
    mov       r12d, eax
    call      Rq_Clear
    lea       rcx, trRightRev
    mov       edx, G3M_GLASS
    call      Rq_Draw
    call      Rq_CountNz
    xor       edx, edx
    test      ebx, ebx
    setz      dl
    cmp       r12d, RQ_RIGHT_N
    sete      cl
    and       dl, cl
    cmp       eax, RQ_RIGHT_N
    sete      cl
    and       dl, cl
    lea       rcx, szRaCull
    call      St_Report
    FN_RET
FN_END Rt_Cull

; ---------------------------------------------------------------------------
; Rq_DepthPair(rcx = first triangle, rdx = second) -> eax = 1 when the sample in
; the overlap shows the near colour (11), the near-only the same and the far-only
; the far colour (21).
; ---------------------------------------------------------------------------
FN_BEGIN Rq_DepthPair, 0
    mov       rsi, rdx
    mov       rdi, rcx
    call      Rq_Clear
    mov       rcx, rdi
    mov       edx, G3M_OPAQUE
    call      Rq_Draw
    mov       rcx, rsi
    mov       edx, G3M_OPAQUE
    call      Rq_Draw
    mov       ecx, 30
    mov       edx, 10
    call      Rq_At
    xor       ebx, ebx
    cmp       eax, 11
    sete      bl                              ; overlap: the near triangle
    mov       ecx, 2
    mov       edx, 2
    call      Rq_At
    cmp       eax, 11
    sete      cl
    and       bl, cl                          ; only the near triangle
    mov       ecx, 100
    mov       edx, 5
    call      Rq_At
    cmp       eax, 21
    sete      cl
    and       bl, cl                          ; only the far triangle
    movzx     eax, bl
    FN_RET
FN_END Rq_DepthPair

FN_BEGIN Rt_Depth, 0
    lea       rcx, trFar
    lea       rdx, trNear
    call      Rq_DepthPair
    mov       ebx, eax
    lea       rcx, trNear
    lea       rdx, trFar
    call      Rq_DepthPair
    and       ebx, eax
    mov       edx, ebx
    lea       rcx, szRaDepth
    call      St_Report
    FN_RET
FN_END Rt_Depth

; ---------------------------------------------------------------------------
; Rt_Tex - u = 2.55 (x + 0.5), v = 2.55 (y + 0.5): texel (v << 8 | u), value + 1.
; ---------------------------------------------------------------------------
FN_BEGIN Rt_Tex, 0
    call      Rq_Clear
    lea       rcx, trTex
    mov       edx, G3M_OPAQUE
    call      Rq_Draw
    xor       ebx, ebx
    mov       ecx, 10
    mov       edx, 6
    call      Rq_At
    cmp       eax, 16 * 256 + 26 + 1
    sete      bl
    mov       ecx, 3
    mov       edx, 1
    call      Rq_At
    cmp       eax, 3 * 256 + 8 + 1
    sete      cl
    and       bl, cl
    mov       ecx, 40
    mov       edx, 30
    call      Rq_At
    cmp       eax, 77 * 256 + 103 + 1
    sete      cl
    and       bl, cl
    movzx     edx, bl
    lea       rcx, szRaTex
    call      St_Report
    FN_RET
FN_END Rt_Tex

; ---------------------------------------------------------------------------
; Rt_Skew - a triangle that is aligned with neither axis, with a different
; matcap coordinate at every vertex: eight samples against the exact values.
; ---------------------------------------------------------------------------
FN_BEGIN Rt_Skew, 0
    call      Rq_Clear
    lea       rcx, trSkew
    mov       edx, G3M_OPAQUE
    call      Rq_Draw
    lea       rcx, rqSkewTab
    mov       edx, RQ_SKEWN
    call      Rq_Vals
    mov       edx, eax
    lea       rcx, szRaSkew
    call      St_Report
    FN_RET
FN_END Rt_Skew

; ---------------------------------------------------------------------------
; Rt_Clip - a triangle larger than the target covers every sample exactly once,
; four triangles beside the target draw nothing.
; ---------------------------------------------------------------------------
FN_BEGIN Rt_Clip, 0
    call      Rq_Clear
    lea       rcx, trHuge
    mov       edx, G3M_GLASS
    call      Rq_Draw
    mov       ecx, 1
    call      Rq_CountEq
    xor       ebx, ebx
    cmp       eax, G3_PIX
    sete      bl
    call      Rq_Clear
    lea       rcx, trOutL
    mov       edx, G3M_OPAQUE
    call      Rq_Draw
    lea       rcx, trOutR
    mov       edx, G3M_OPAQUE
    call      Rq_Draw
    lea       rcx, trOutT
    mov       edx, G3M_OPAQUE
    call      Rq_Draw
    lea       rcx, trOutB
    mov       edx, G3M_OPAQUE
    call      Rq_Draw
    call      Rq_CountNz
    test      eax, eax
    setz      cl
    and       bl, cl
    movzx     edx, bl
    lea       rcx, szRaClip
    call      St_Report
    FN_RET
FN_END Rt_Clip

FN_BEGIN Rt_Behind, 0
    call      Rq_Clear
    lea       rcx, trBehind
    mov       edx, G3M_OPAQUE
    call      Rq_Draw
    call      Rq_CountNz
    xor       edx, edx
    test      eax, eax
    setz      dl
    lea       rcx, szRaBehind
    call      St_Report
    FN_RET
FN_END Rt_Behind

; ---------------------------------------------------------------------------
; Rt_Near - vertices nearer than z = 0.5 are unusable and take their triangle
; with them.  The front face of the cube lies one unit before its centre:
;   centre 2.6: the face at z = 1.6 reaches 625 samples to each side of the
;               middle: columns 15 .. 1264 of all 720 rows (900000 samples),
;   centre 1.6: the face at z = 0.6 is wider than the target: every sample,
;   centre 1.4: the face at z = 0.4 is lost, the other five look away: nothing.
; ---------------------------------------------------------------------------
FN_BEGIN Rt_Near, 0
    lea       rdx, kRqIdent
    xorps     xmm0, xmm0
    xorps     xmm1, xmm1
    movss     xmm2, DWORD PTR kRqNear1
    movss     xmm3, DWORD PTR kRqOne
    call      Rq_CubeAt
    xor       ebx, ebx
    cmp       eax, RQ_NEAR_N
    sete      bl
    lea       rdx, kRqIdent
    xorps     xmm0, xmm0
    xorps     xmm1, xmm1
    movss     xmm2, DWORD PTR kRqNear2
    movss     xmm3, DWORD PTR kRqOne
    call      Rq_CubeAt
    cmp       eax, G3_PIX
    sete      cl
    and       bl, cl
    lea       rdx, kRqIdent
    xorps     xmm0, xmm0
    xorps     xmm1, xmm1
    movss     xmm2, DWORD PTR kRqNear3
    movss     xmm3, DWORD PTR kRqOne
    call      Rq_CubeAt
    test      eax, eax
    setz      cl
    and       bl, cl
    movzx     edx, bl
    lea       rcx, szRaNear
    call      St_Report
    FN_RET
FN_END Rt_Near

; ---------------------------------------------------------------------------
; Rq_Strip(rcx = first triangle, rdx = second) -> eax = 1 when the two
; triangles, which cover half of the four samples of pixel (0, 0) (one column
; or one row), resolve to the average of the texel (0x8002) and black, rounded
; up per channel (0x4001), and leave the pixels to the right and below black.
; ---------------------------------------------------------------------------
FN_BEGIN Rq_Strip, 0
    mov       rsi, rdx
    mov       rdi, rcx
    call      Rq_Clear
    mov       rcx, rdi
    mov       edx, G3M_GLASS
    call      Rq_Draw
    mov       rcx, rsi
    mov       edx, G3M_GLASS
    call      Rq_Draw
    mov       rcx, QWORD PTR gFbB
    call      G3_Resolve
    mov       rax, QWORD PTR gFbB
    xor       ebx, ebx
    cmp       DWORD PTR [rax], 00004001h
    sete      bl
    cmp       DWORD PTR [rax+4], 0
    sete      cl
    and       bl, cl
    cmp       DWORD PTR [rax+SCR_W*4], 0
    sete      cl
    and       bl, cl
    movzx     eax, bl
    FN_RET
FN_END Rq_Strip

; ---------------------------------------------------------------------------
; Rt_Resolve - Begin + Resolve return a patterned backdrop bit for bit; a strip
; covering one of the two sample columns of a pixel, and one covering one of
; the two sample rows, give 0x4001 (see Rq_Strip).
; ---------------------------------------------------------------------------
FN_BEGIN Rt_Resolve, 0
    mov       rcx, QWORD PTR gFbA
    call      Rq_Pattern
    mov       rcx, QWORD PTR gFbA
    call      G3_Begin
    mov       rcx, QWORD PTR gFbB
    call      G3_Resolve
    mov       rcx, QWORD PTR gFbA
    mov       rdx, QWORD PTR gFbB
    call      Rq_SameFrames
    mov       r12d, eax
    lea       rcx, trHalfA
    lea       rdx, trHalfB
    call      Rq_Strip
    and       r12d, eax
    lea       rcx, trHalfC
    lea       rdx, trHalfD
    call      Rq_Strip
    and       r12d, eax
    mov       edx, r12d
    lea       rcx, szRaResolve
    call      St_Report
    FN_RET
FN_END Rt_Resolve

; ---------------------------------------------------------------------------
; Rt_Cube - the cube at z = 10 without rotation: the front face is the square
; of 222 x 222 samples (1000 / 9 = 111.1 pixels to each side of the centre).
; ---------------------------------------------------------------------------
FN_BEGIN Rt_Cube, 0
    lea       rdx, kRqIdent
    xorps     xmm0, xmm0
    xorps     xmm1, xmm1
    movss     xmm2, DWORD PTR kRqTen
    movss     xmm3, DWORD PTR kRqOne
    call      Rq_CubeAt
    xor       ebx, ebx
    cmp       eax, RQ_CUBE_N
    sete      bl
    lea       rcx, rqCubeTab
    mov       edx, RQ_CUBEN
    call      Rq_Pts
    and       ebx, eax
    mov       ecx, 640
    mov       edx, 360
    call      Rq_At
    cmp       eax, 127 * 256 + 127 + 1        ; the normal faces the camera: matcap centre
    sete      cl
    and       bl, cl
    movzx     edx, bl
    lea       rcx, szRaCube
    call      St_Report
    FN_RET
FN_END Rt_Cube

; ---------------------------------------------------------------------------
; Rt_Shift - the cube moved by +1 in x: its face spans view x = 0 .. 2, so the
; first sample column is exactly 640 (no rounding in the way).
; ---------------------------------------------------------------------------
FN_BEGIN Rt_Shift, 0
    lea       rdx, kRqIdent
    movss     xmm0, DWORD PTR kRqOne
    xorps     xmm1, xmm1
    movss     xmm2, DWORD PTR kRqTen
    movss     xmm3, DWORD PTR kRqOne
    call      Rq_CubeAt
    xor       ebx, ebx
    cmp       eax, RQ_CUBE_N
    sete      bl
    lea       rcx, rqShiftTab
    mov       edx, RQ_SHIFTN
    call      Rq_Pts
    and       ebx, eax
    mov       edx, ebx
    lea       rcx, szRaShift
    call      St_Report
    FN_RET
FN_END Rt_Shift

; ---------------------------------------------------------------------------
; Rt_Scale - half the size at half the distance projects to the same face.
; ---------------------------------------------------------------------------
FN_BEGIN Rt_Scale, 0
    lea       rdx, kRqIdent
    xorps     xmm0, xmm0
    xorps     xmm1, xmm1
    movss     xmm2, DWORD PTR kRqFive
    movss     xmm3, DWORD PTR kRqHalf
    call      Rq_CubeAt
    xor       ebx, ebx
    cmp       eax, RQ_CUBE_N
    sete      bl
    lea       rcx, rqCubeTab
    mov       edx, RQ_CUBEN
    call      Rq_Pts
    and       ebx, eax
    mov       edx, ebx
    lea       rcx, szRaScale
    call      St_Report
    FN_RET
FN_END Rt_Scale

; ---------------------------------------------------------------------------
; Rt_Spin - an eighth of a turn about z turns the face into a diamond with the
; half-diagonal R = 1000 * sqrt(2) / 9 = 157.135.  Row k away from the middle
; has the half-width t = R - k - 0.5 = 156.635 - k and holds 2 * round(t)
; samples, 49612 in all (the middle row spans the samples 483 .. 796).
; ---------------------------------------------------------------------------
FN_BEGIN Rt_Spin, 0
    lea       rcx, rqMat
    xorps     xmm0, xmm0
    xorps     xmm1, xmm1
    movss     xmm2, DWORD PTR kRqEighth
    call      G3_RotMat
    lea       rdx, rqMat
    xorps     xmm0, xmm0
    xorps     xmm1, xmm1
    movss     xmm2, DWORD PTR kRqTen
    movss     xmm3, DWORD PTR kRqOne
    call      Rq_CubeAt
    xor       ebx, ebx
    cmp       eax, RQ_DIAMOND_N
    sete      bl
    lea       rcx, rqSpinTab
    mov       edx, RQ_SPINN
    call      Rq_Pts
    and       ebx, eax
    mov       edx, ebx
    lea       rcx, szRaSpin
    call      St_Report
    FN_RET
FN_END Rt_Spin

; ---------------------------------------------------------------------------
; Rt_Tilt - the cube turned by 22.5 degrees about x: the front face looks up
; (normal (0, 0.383, -0.924): texel row 78), the bottom face (0, -0.924, -0.383)
; shows below it (texel row 245).
; ---------------------------------------------------------------------------
FN_BEGIN Rt_Tilt, 0
    lea       rcx, rqMat
    movss     xmm0, DWORD PTR kRqTurn16
    xorps     xmm1, xmm1
    xorps     xmm2, xmm2
    call      G3_RotMat
    lea       rdx, rqMat
    xorps     xmm0, xmm0
    xorps     xmm1, xmm1
    movss     xmm2, DWORD PTR kRqTen
    movss     xmm3, DWORD PTR kRqOne
    call      Rq_CubeAt
    mov       ecx, 640
    mov       edx, 360
    call      Rq_At
    xor       ebx, ebx
    cmp       eax, 78 * 256 + 127 + 1
    sete      bl
    mov       ecx, 640
    mov       edx, 456
    call      Rq_At
    cmp       eax, 245 * 256 + 127 + 1
    sete      cl
    and       bl, cl
    movzx     edx, bl
    lea       rcx, szRaTilt
    call      St_Report
    FN_RET
FN_END Rt_Tilt

; ---------------------------------------------------------------------------
; Rt_Sphere - unit sphere at z = 10: silhouette radius 1000 / sqrt(99) = 100.5
; samples (area 31730, a little less for the polygon), the pixel in the middle
; has its matcap coordinates near (127, 127).
; ---------------------------------------------------------------------------
FN_BEGIN Rt_Sphere, 0
    lea       rcx, rqSphere
    call      Msh_Sphere
    lea       rcx, rqXf
    lea       rdx, kRqIdent
    xorps     xmm0, xmm0
    xorps     xmm1, xmm1
    movss     xmm2, DWORD PTR kRqTen
    movss     xmm3, DWORD PTR kRqOne
    call      Rq_Xf
    call      Rq_Clear
    lea       rcx, rqSphere
    call      Rq_DrawMesh
    call      Rq_CountNz
    xor       ebx, ebx
    cmp       eax, 30800
    setae     bl
    cmp       eax, 31800
    setbe     cl
    and       bl, cl
    mov       ecx, 640
    mov       edx, 360
    call      Rq_At
    dec       eax                             ; texel index
    mov       esi, eax
    movzx     eax, al                         ; u
    mov       ecx, 127
    mov       r8d, 4
    call      Rq_Within
    and       bl, al
    mov       eax, esi
    shr       eax, 8                          ; v
    mov       ecx, 127
    mov       r8d, 4
    call      Rq_Within
    and       bl, al
    movzx     edx, bl
    lea       rcx, szRaSphere
    call      St_Report
    FN_RET
FN_END Rt_Sphere

FN_BEGIN Rt_Guard, 0
    mov       rcx, QWORD PTR g3Color
    call      Rq_Guard
    mov       ebx, eax
    mov       rcx, QWORD PTR g3Z
    call      Rq_Guard
    and       ebx, eax
    mov       edx, ebx
    lea       rcx, szRaGuard
    call      St_Report
    FN_RET
FN_END Rt_Guard

; ---------------------------------------------------------------------------
; St_G3Raster - all checks of the rasteriser and the targets.
; ---------------------------------------------------------------------------
FN_BEGIN St_G3Raster, 0
    call      Rq_FillTex
    lea       rcx, rqCube
    call      Msh_Cube
    call      Rt_Cover
    call      Rt_Edge
    call      Rt_Tie
    call      Rt_Vertex
    call      Rt_Oracle
    call      Rt_Cull
    call      Rt_Depth
    call      Rt_Tex
    call      Rt_Skew
    call      Rt_Clip
    call      Rt_Behind
    call      Rt_Near
    call      Rt_Resolve
    call      Rt_Cube
    call      Rt_Shift
    call      Rt_Scale
    call      Rt_Spin
    call      Rt_Tilt
    call      Rt_Sphere
    call      Rt_Guard
    FN_RET
FN_END St_G3Raster

END
