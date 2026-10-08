; ============================================================================
; g3.inc - declarations of the software 3D renderer
;          g3_math.asm (angles, matrices), g3_mesh.asm / g3_shapes.asm (meshes),
;          g3_raster.asm (triangle set-up and scan conversion), g3_draw.asm
;          (render target, transformation, resolve) and g3_mat.asm (matcaps);
;          used by the PRISM scene (fx_prism.asm) and by selftest_g3.asm.
; ----------------------------------------------------------------------------
; Conventions
;   * view space: x right, y up, z forward, the camera sits at the origin;
;   * a triangle is front-facing when its outward normal (p1 - p0) x (p2 - p0)
;     points at the camera.  On the screen (y points down) that is the same as
;     A = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0) > 0;
;   * the picture is rendered 2 x 2 supersampled (1280 x 720) and resolved to
;     640 x 360 with a box filter; sample centres lie at (i + 0.5, j + 0.5);
;   * a sample belongs to a triangle when its centre is inside, edges follow
;     the half-open rule [top, bottom) x [left, right), so triangles that share
;     an edge never overlap and never leave a gap;
;   * depth is stored as w = 1 / z (larger = nearer, 0 = nothing drawn yet);
;   * shading is a matcap: the view-space normal indexes a 256 x 256 texture.
; Matrices (MAT3) are three columns of four floats (x y z 0), 48 bytes.
; ============================================================================

G3_W       EQU 1280             ; supersampled target
G3_H       EQU 720
G3_PITCH   EQU 5120             ; bytes per row of the colour and the depth target
G3_PIX     EQU 921600
G3_BYTES   EQU 3686400
G3_GUARD   EQU 8192             ; canary bytes in front of and behind each target
G3_TEXN    EQU 65536            ; texels of a matcap (256 x 256, BGRA)
G3_TEXB    EQU 262144
G3_MAXV    EQU 2048             ; most vertices of one mesh

G3M_OPAQUE EQU 0                ; depth test and write, back faces are culled
G3M_GLASS  EQU 1                ; depth test only, both faces, additive blending

; Projected vertex (32 bytes).  The attribute vector (w, u, v) is contiguous so
; that the rasteriser interpolates all three with one packed operation.
PV STRUCT
    sx   REAL4 ?                ; position in supersampled pixels
    sy   REAL4 ?
    pad0 REAL4 2 DUP (?)
    w    REAL4 ?                ; 1 / z; <= 0 marks an unusable vertex
    tu   REAL4 ?                ; matcap coordinates, 0 .. 255.9
    tv   REAL4 ?
    pad1 REAL4 ?
PV ENDS

; Rasteriser state of one triangle (16-byte aligned).  Per edge (lane 3 is
; never used): the top and bottom y, x at the top and dx / dy.
TRI STRUCT
    etop REAL4 4 DUP (?)
    ebot REAL4 4 DUP (?)
    exs  REAL4 4 DUP (?)
    eslp REAL4 4 DUP (?)
    gx   REAL4 4 DUP (?)        ; d(w, u, v) / dx
    gy   REAL4 4 DUP (?)        ; d(w, u, v) / dy
    a0   REAL4 4 DUP (?)        ; (w, u, v) at vertex 0
    orig REAL4 4 DUP (?)        ; (x0, y0) of vertex 0
    row0 DWORD ?                ; first row
    row1 DWORD ?                ; one past the last row
    pad  DWORD 2 DUP (?)
TRI ENDS

; Triangle mesh: nVerts * 32 bytes (position x y z 0, normal x y z 0) and
; nTris * 3 word indices.  Winding is counter-clockwise seen from outside.
MESH STRUCT
    nVerts DWORD ?
    nTris  DWORD ?
    verts  QWORD ?
    idx    QWORD ?
MESH ENDS

; Object -> view space:  p' = s * (c0 * x + c1 * y + c2 * z) + t.
XFORM STRUCT
    c0 REAL4 4 DUP (?)
    c1 REAL4 4 DUP (?)
    c2 REAL4 4 DUP (?)
    t  REAL4 4 DUP (?)
    s  REAL4 4 DUP (?)          ; the scale in every lane
XFORM ENDS

; Parametric surface for Msh_Grid.  surf is called with xmm0 = u and xmm1 = v
; (turns, 0 .. 1) and returns xmm0 = position, xmm1 = unit normal.
GRID STRUCT
    surf  QWORD ?
    nu    DWORD ?               ; cells around u (always periodic)
    nv    DWORD ?               ; cells along v
    wrapV DWORD ?               ; 1 = periodic in v, 0 = open (v = 0 .. 1 inclusive)
    pad   DWORD ?
GRID ENDS

; ---- vector helpers (SSE, xmm lanes x y z w) ----------------------------------
; d = a x b.  d must differ from a and b; clobbers t1 and t2.
VCROSS MACRO d:REQ, a:REQ, b:REQ, t1:REQ, t2:REQ
    movaps d, a
    shufps d, d, 0C9h           ; a.yzx
    movaps t1, b
    shufps t1, t1, 0D2h         ; b.zxy
    mulps  d, t1
    movaps t1, a
    shufps t1, t1, 0D2h         ; a.zxy
    movaps t2, b
    shufps t2, t2, 0C9h         ; b.yzx
    mulps  t1, t2
    subps  d, t1
ENDM

; d (low lane) = v.x + v.y + v.z; v is kept, d may equal v; clobbers t1 and t2.
HSUM3 MACRO d:REQ, v:REQ, t1:REQ, t2:REQ
    movaps t1, v
    shufps t1, t1, 055h
    movaps t2, v
    shufps t2, t2, 0AAh
    movaps d, v
    addss  d, t1
    addss  d, t2
ENDM

; v = v / |v| (three lanes, lane 3 must be 0); clobbers t1 .. t4.
VNORM MACRO v:REQ, t1:REQ, t2:REQ, t3:REQ, t4:REQ
    movaps t1, v
    mulps  t1, t1
    HSUM3  t4, t1, t2, t3
    sqrtss t4, t4
    shufps t4, t4, 000h
    divps  v, t4
ENDM

; d = c0 * v.x + c1 * v.y + c2 * v.z (matrix times vector); d must differ from v.
MATVEC MACRO d:REQ, v:REQ, c0:REQ, c1:REQ, c2:REQ, t1:REQ, t2:REQ
    movaps d, v
    shufps d, d, 000h
    mulps  d, c0
    movaps t1, v
    shufps t1, t1, 055h
    mulps  t1, c1
    movaps t2, v
    shufps t2, t2, 0AAh
    mulps  t2, c2
    addps  d, t1
    addps  d, t2
ENDM

; r = ceil(x) clamped to 0 .. hi (a float constant in memory); x is clobbered.
; NaN counts as 0.  The carry of the compare adds one when x was not integral.
CEILCLAMP MACRO r:REQ, x:REQ, t:REQ, hi:REQ
    maxss  x, DWORD PTR kG3Zero
    minss  x, DWORD PTR hi
    cvttss2si r, x
    cvtsi2ss t, r
    comiss t, x
    adc    r, 0
ENDM

; d = (x, y, z, 0) built from three scalars through the frame's first local bytes
; (the frame needs at least 16 bytes of locals; XLOC is the FNX_* offset).
PACK3 MACRO d:REQ, x:REQ, y:REQ, z:REQ
    movss  DWORD PTR [rsp+XLOC], x
    movss  DWORD PTR [rsp+XLOC+4], y
    movss  DWORD PTR [rsp+XLOC+8], z
    mov    DWORD PTR [rsp+XLOC+12], 0
    movaps d, XMMWORD PTR [rsp+XLOC]
ENDM

; ---- shared constants (g3_math.asm) -----------------------------------------------
EXTERNDEF kG3Zero:REAL4
EXTERNDEF kG3Half:REAL4
EXTERNDEF kG3One:REAL4
EXTERNDEF kG3Two:REAL4
EXTERNDEF kG3Three:REAL4
EXTERNDEF kG3SignV:DWORD
EXTERNDEF kG3AbsV:DWORD

; ---- g3_math.asm ----------------------------------------------------------------------
EXTERNDEF G3_SinCos:PROC        ; xmm0 = angle in turns -> xmm0 = sin, xmm1 = cos
EXTERNDEF G3_RotMat:PROC        ; rcx = dst MAT3, xmm0 / xmm1 / xmm2 = turns about x / y / z: R = Rz * Ry * Rx
EXTERNDEF G3_MatMul:PROC        ; rcx = dst MAT3, rdx = A, r8 = B: dst = A * B
EXTERNDEF G3_MatVec:PROC        ; rcx = MAT3, xmm0 = (x, y, z, 0) -> xmm0 = M * v
EXTERNDEF G3_Smooth:PROC        ; xmm0 = x -> clamp(x, 0, 1) smoothstepped
EXTERNDEF G3_EaseBack:PROC      ; xmm0 = x -> ease-out-back of clamp(x, 0, 1) (0 at 0, 1 at 1, overshoots)

; ---- g3_mesh.asm / g3_shapes.asm --------------------------------------------------------
EXTERNDEF Msh_Grid:PROC         ; rcx = MESH * (out), rdx = GRID *: periodic parametric surface
EXTERNDEF Msh_Flat:PROC         ; rcx = MESH * (out), rdx = float points[], r8 = BYTE faces[3 * n], r9d = n
EXTERNDEF Msh_FixWinding:PROC   ; rcx = MESH *: make every triangle face along its vertex normals
EXTERNDEF Msh_Volume:PROC       ; rcx = MESH * -> xmm0 = signed volume (positive when wound outwards)
EXTERNDEF Msh_Knot:PROC         ; rcx = MESH *: (2, 3) torus knot, 1728 vertices
EXTERNDEF Msh_Ring:PROC         ; rcx = MESH *: thin torus (R = 1, r = 0.12)
EXTERNDEF Msh_Sphere:PROC       ; rcx = MESH *: unit sphere
EXTERNDEF Msh_Cube:PROC         ; rcx = MESH *: cube with edge 2, flat shaded
EXTERNDEF Msh_Ico:PROC          ; rcx = MESH *: icosahedron with circumradius 1, flat shaded

; ---- g3_raster.asm ---------------------------------------------------------------------
EXTERNDEF g3t:TRI               ; state of the triangle being drawn
EXTERNDEF G3_TriSetup:PROC      ; rcx, rdx, r8 = PV * (3 vertices) -> eax = 1 when the triangle is drawn
EXTERNDEF G3_TriScan:PROC       ; draws the triangle prepared by G3_TriSetup

; ---- g3_draw.asm -----------------------------------------------------------------------
EXTERNDEF g3Color:QWORD         ; supersampled colour target, G3_BYTES
EXTERNDEF g3Z:QWORD             ; supersampled depth target, G3_BYTES
EXTERNDEF g3Tex:QWORD           ; matcap used by the rasteriser
EXTERNDEF g3Mode:DWORD          ; G3M_*
EXTERNDEF g3Pv:PV               ; projected vertices of the mesh being drawn
EXTERNDEF G3_Init:PROC          ; allocates the targets (with canary guards)
EXTERNDEF G3_Begin:PROC         ; rcx = 640 x 360 backdrop: replicate it 2 x 2 and clear the depth
EXTERNDEF G3_Resolve:PROC       ; rcx = dst 640 x 360: box-filter the supersampled colour
EXTERNDEF G3_Draw:PROC          ; rcx = MESH *, rdx = XFORM *, r8 = matcap, r9d = G3M_*

; ---- g3_mat.asm --------------------------------------------------------------------------
MAT_OIL    EQU 0                ; iridescent oil film on chrome
MAT_GOLD   EQU 1
MAT_TEAL   EQU 2                ; glossy ceramic
MAT_GLASS  EQU 3                ; additive glass (cyan to magenta, bright rim)
MAT_COUNT  EQU 4
EXTERNDEF Mat_Build:PROC        ; rcx = dst DWORD[G3_TEXN] BGRA, edx = MAT_*
EXTERNDEF Mb_Pow:PROC           ; xmm0 = x, ecx = n >= 1 -> xmm0 = x ^ n (the soft box falloff)

; ---- helpers of the self tests (selftest_g3r.asm) ------------------------------------
EXTERNDEF Rq_Guard:PROC         ; rcx = render target -> eax = 1 when its canary guards are intact
EXTERNDEF Rq_SameFrames:PROC    ; rcx, rdx = 640 x 360 frames -> eax = 1 when they are identical
EXTERNDEF Mt_Close:PROC         ; ecx, edx = two colours -> eax = 1 when every channel differs by at most 4
