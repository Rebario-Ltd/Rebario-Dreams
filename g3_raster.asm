; ============================================================================
; g3_raster.asm - triangle set-up and scan conversion (see g3.inc).
; ----------------------------------------------------------------------------
; G3_TriSetup  culls the triangle, derives the plane equations of the
;              attributes (w, u, v) and the SoA edge table into g3t
; G3_TriScan   walks the rows of g3t:  per row the active edges (top <= y <
;              bottom, y = row + 0.5) give the left and right end, the span is
;              [ceil(left - 0.5), ceil(right - 0.5)), and the attribute vector
;              (w, u, v) advances by its x gradient from sample to sample.
;
; The attribute vector is interpolated affinely in screen space (w = 1 / z is
; exactly affine; the matcap coordinates are interpolated linearly, which is
; what an environment-mapped shader does anyway).  Every sample is tested
; against the depth buffer (w greater = nearer); opaque triangles write depth
; and colour, glass triangles only add their colour (paddusb).
; ============================================================================
INCLUDE common.inc
INCLUDE g3.inc

.const
ALIGN 16
kBigV     REAL4 1.0e30, 1.0e30, 1.0e30, 1.0e30
kNBigV    REAL4 -1.0e30, -1.0e30, -1.0e30, -1.0e30
kAreaEps  REAL4 0.001                     ; twice the smallest area that is drawn
kWF       REAL4 1280.0
kHF       REAL4 720.0

.data?
ALIGN 16
g3t       TRI <>

.code

; ---------------------------------------------------------------------------
; EDGE k, pa, pb - fills lane k of the edge table (r15 = &g3t) for the edge
; pa -> pb: the end with the smaller y is the top.  A horizontal edge never
; crosses a sample row and gets an empty range (top > bottom).
; ---------------------------------------------------------------------------
EDGE MACRO k:REQ, pa:REQ, pb:REQ
    LOCAL lOrd, lOff, lDone
    movss     xmm0, DWORD PTR [pa+PV.sx]
    movss     xmm1, DWORD PTR [pa+PV.sy]
    movss     xmm2, DWORD PTR [pb+PV.sx]
    movss     xmm3, DWORD PTR [pb+PV.sy]
    comiss    xmm1, xmm3
    je        lOff
    jb        lOrd
    movaps    xmm4, xmm0
    movaps    xmm0, xmm2
    movaps    xmm2, xmm4
    movaps    xmm4, xmm1
    movaps    xmm1, xmm3
    movaps    xmm3, xmm4
lOrd:
    movss     DWORD PTR [r15+TRI.etop+4*k], xmm1
    movss     DWORD PTR [r15+TRI.ebot+4*k], xmm3
    movss     DWORD PTR [r15+TRI.exs+4*k], xmm0
    subss     xmm2, xmm0
    subss     xmm3, xmm1
    divss     xmm2, xmm3
    movss     DWORD PTR [r15+TRI.eslp+4*k], xmm2
    jmp       lDone
lOff:
    mov       DWORD PTR [r15+TRI.etop+4*k], 7149F2CAh      ; +1e30
    mov       DWORD PTR [r15+TRI.ebot+4*k], 0F149F2CAh     ; -1e30
    mov       DWORD PTR [r15+TRI.exs+4*k], 0
    mov       DWORD PTR [r15+TRI.eslp+4*k], 0
lDone:
ENDM

; ---------------------------------------------------------------------------
; G3_TriSetup(rcx, rdx, r8 = PV * of the three vertices) -> eax = 1 when the
; triangle has to be scanned.  Rejected: a vertex behind the near plane
; (w <= 0), zero area, back faces (opaque mode), triangles outside the target.
; In glass mode a back face is turned around (vertices 1 and 2 swapped).
; ---------------------------------------------------------------------------
FNX_BEGIN G3_TriSetup, 0
    lea       r15, g3t
ts_top:
    movss     xmm0, DWORD PTR [rcx+PV.w]
    minss     xmm0, DWORD PTR [rdx+PV.w]
    minss     xmm0, DWORD PTR [r8+PV.w]
    comiss    xmm0, DWORD PTR kG3Zero
    jbe       ts_reject                       ; a vertex is unusable
    movlps    xmm0, QWORD PTR [rcx]           ; (x0, y0)
    movlps    xmm1, QWORD PTR [rdx]
    movlps    xmm2, QWORD PTR [r8]
    subps     xmm1, xmm0                      ; (dx1, dy1)
    subps     xmm2, xmm0                      ; (dx2, dy2)
    movaps    xmm3, xmm2
    shufps    xmm3, xmm3, 0E1h                ; (dy2, dx2)
    mulps     xmm3, xmm1                      ; (dx1 dy2, dy1 dx2)
    movaps    xmm4, xmm3
    shufps    xmm4, xmm4, 055h
    subss     xmm3, xmm4                      ; A = dx1 dy2 - dy1 dx2
    cmp       DWORD PTR g3Mode, G3M_OPAQUE
    jne       ts_both
    comiss    xmm3, DWORD PTR kAreaEps
    jbe       ts_reject                       ; back face or sliver
    jmp       ts_area
ts_both:
    movaps    xmm4, xmm3
    andps     xmm4, XMMWORD PTR kG3AbsV
    comiss    xmm4, DWORD PTR kAreaEps
    jbe       ts_reject
    comiss    xmm3, DWORD PTR kG3Zero
    ja        ts_area
    xchg      rdx, r8                         ; glass: draw the back face as a front face
    jmp       ts_top
ts_area:
    movss     xmm4, DWORD PTR kG3One
    divss     xmm4, xmm3
    shufps    xmm4, xmm4, 000h                ; 1 / A
    movaps    xmm5, XMMWORD PTR [rcx+PV.w]    ; (w, u, v) of vertex 0
    movaps    xmm6, XMMWORD PTR [rdx+PV.w]
    subps     xmm6, xmm5                      ; da1
    movaps    xmm7, XMMWORD PTR [r8+PV.w]
    subps     xmm7, xmm5                      ; da2
    movaps    xmm8, xmm1
    shufps    xmm8, xmm8, 000h                ; dx1
    movaps    xmm9, xmm1
    shufps    xmm9, xmm9, 055h                ; dy1
    movaps    xmm10, xmm2
    shufps    xmm10, xmm10, 000h              ; dx2
    movaps    xmm11, xmm2
    shufps    xmm11, xmm11, 055h              ; dy2
    movaps    xmm12, xmm6
    mulps     xmm12, xmm11                    ; da1 dy2
    movaps    xmm13, xmm7
    mulps     xmm13, xmm9                     ; da2 dy1
    subps     xmm12, xmm13
    mulps     xmm12, xmm4                     ; d/dx = (da1 dy2 - da2 dy1) / A
    mulps     xmm7, xmm8                      ; da2 dx1
    mulps     xmm6, xmm10                     ; da1 dx2
    subps     xmm7, xmm6
    mulps     xmm7, xmm4                      ; d/dy = (da2 dx1 - da1 dx2) / A
    movaps    XMMWORD PTR [r15+TRI.gx], xmm12
    movaps    XMMWORD PTR [r15+TRI.gy], xmm7
    movaps    XMMWORD PTR [r15+TRI.a0], xmm5
    movaps    XMMWORD PTR [r15+TRI.orig], xmm0
    EDGE      0, rcx, rdx
    EDGE      1, rdx, r8
    EDGE      2, r8, rcx
    mov       DWORD PTR [r15+TRI.etop+12], 7149F2CAh       ; lane 3 never matches
    mov       DWORD PTR [r15+TRI.ebot+12], 0F149F2CAh
    mov       DWORD PTR [r15+TRI.exs+12], 0
    mov       DWORD PTR [r15+TRI.eslp+12], 0
    movss     xmm0, DWORD PTR [rcx+PV.sy]     ; first and one past the last row
    movaps    xmm1, xmm0
    movss     xmm2, DWORD PTR [rdx+PV.sy]
    minss     xmm0, xmm2
    maxss     xmm1, xmm2
    movss     xmm2, DWORD PTR [r8+PV.sy]
    minss     xmm0, xmm2
    maxss     xmm1, xmm2
    subss     xmm0, DWORD PTR kG3Half
    subss     xmm1, DWORD PTR kG3Half
    CEILCLAMP eax, xmm0, xmm2, kHF
    CEILCLAMP edx, xmm1, xmm2, kHF
    mov       DWORD PTR [r15+TRI.row0], eax
    mov       DWORD PTR [r15+TRI.row1], edx
    cmp       eax, edx
    jae       ts_reject
    mov       eax, 1
    FNX_RET
ts_reject:
    xor       eax, eax
    FNX_RET
FN_END G3_TriSetup

; ---------------------------------------------------------------------------
; ATTR2IDX - from the attribute vector in xmm0 to the matcap texel index in
; eax: ((int) v << 8 | (int) u) & 0FFFFh.  Clobbers xmm2, xmm3 and r11d.
; ---------------------------------------------------------------------------
ATTR2IDX MACRO
    cvttps2dq xmm2, xmm0
    movq      rax, xmm2
    shr       rax, 32                         ; u
    movhlps   xmm3, xmm2
    movd      r11d, xmm3                      ; v
    shl       r11d, 8
    or        eax, r11d
    movzx     eax, ax
ENDM

; ---------------------------------------------------------------------------
; G3_TriScan - draws the triangle prepared in g3t (see the header).
; Registers: xmm6 d/dx, xmm7 d/dy, xmm8 attributes at vertex 0, xmm9 (x0, y0),
; xmm10..13 the edge table, xmm14 y0 in every lane; ebx row, r12d last row + 1,
; r13 / r14 colour / depth base, rsi matcap, rdi / r10 row pointers.
; ---------------------------------------------------------------------------
FNX_BEGIN G3_TriScan, 0
    lea       r15, g3t
    movaps    xmm6, XMMWORD PTR [r15+TRI.gx]
    movaps    xmm7, XMMWORD PTR [r15+TRI.gy]
    movaps    xmm8, XMMWORD PTR [r15+TRI.a0]
    movaps    xmm9, XMMWORD PTR [r15+TRI.orig]
    movaps    xmm10, XMMWORD PTR [r15+TRI.etop]
    movaps    xmm11, XMMWORD PTR [r15+TRI.ebot]
    movaps    xmm12, XMMWORD PTR [r15+TRI.exs]
    movaps    xmm13, XMMWORD PTR [r15+TRI.eslp]
    movaps    xmm14, xmm9
    shufps    xmm14, xmm14, 055h
    mov       ebx, DWORD PTR [r15+TRI.row0]
    mov       r12d, DWORD PTR [r15+TRI.row1]
    mov       r13, QWORD PTR g3Color
    mov       r14, QWORD PTR g3Z
    mov       rsi, QWORD PTR g3Tex
sc_row:
    cvtsi2ss  xmm0, ebx
    addss     xmm0, DWORD PTR kG3Half
    shufps    xmm0, xmm0, 000h                ; sample row centre
    movaps    xmm1, xmm10
    cmpleps   xmm1, xmm0                      ; top <= y
    movaps    xmm2, xmm0
    cmpltps   xmm2, xmm11                     ; y < bottom
    andps     xmm1, xmm2                      ; active edges
    movaps    xmm3, xmm0
    subps     xmm3, xmm10
    mulps     xmm3, xmm13
    addps     xmm3, xmm12                     ; x of every edge at y
    andps     xmm3, xmm1                      ; zero where inactive
    movaps    xmm5, xmm1
    andnps    xmm5, XMMWORD PTR kBigV
    orps      xmm5, xmm3                      ; left candidates (inactive = +big)
    movaps    xmm2, xmm1
    andnps    xmm2, XMMWORD PTR kNBigV
    orps      xmm2, xmm3                      ; right candidates (inactive = -big)
    movhlps   xmm4, xmm5
    minps     xmm5, xmm4
    movaps    xmm4, xmm5
    shufps    xmm4, xmm4, 001h
    minss     xmm5, xmm4                      ; left end
    movhlps   xmm4, xmm2
    maxps     xmm2, xmm4
    movaps    xmm4, xmm2
    shufps    xmm4, xmm4, 001h
    maxss     xmm2, xmm4                      ; right end
    subss     xmm5, DWORD PTR kG3Half
    CEILCLAMP r8d, xmm5, xmm4, kWF            ; first sample
    subss     xmm2, DWORD PTR kG3Half
    CEILCLAMP r9d, xmm2, xmm4, kWF            ; one past the last sample
    cmp       r8d, r9d
    jae       sc_next
    cvtsi2ss  xmm0, r8d
    addss     xmm0, DWORD PTR kG3Half
    subss     xmm0, xmm9
    shufps    xmm0, xmm0, 000h                ; x of the first sample - x0
    mulps     xmm0, xmm6
    cvtsi2ss  xmm1, ebx
    addss     xmm1, DWORD PTR kG3Half
    subss     xmm1, xmm14
    shufps    xmm1, xmm1, 000h                ; y - y0
    mulps     xmm1, xmm7
    addps     xmm0, xmm1
    addps     xmm0, xmm8                      ; (w, u, v) at the first sample
    mov       eax, ebx
    imul      eax, eax, G3_PITCH
    lea       rdi, [r13+rax]
    lea       r10, [r14+rax]
    mov       ecx, r8d
    mov       edx, r9d
    cmp       DWORD PTR g3Mode, G3M_OPAQUE
    jne       sc_glass
sc_opq:
    movss     xmm1, DWORD PTR [r10+rcx*4]
    comiss    xmm0, xmm1
    jbe       sc_opq_nx                       ; behind what is already there
    movss     DWORD PTR [r10+rcx*4], xmm0
    ATTR2IDX
    mov       eax, DWORD PTR [rsi+rax*4]
    mov       DWORD PTR [rdi+rcx*4], eax
sc_opq_nx:
    addps     xmm0, xmm6
    inc       ecx
    cmp       ecx, edx
    jb        sc_opq
    jmp       sc_next
sc_glass:
    movss     xmm1, DWORD PTR [r10+rcx*4]
    comiss    xmm0, xmm1
    jbe       sc_gl_nx
    ATTR2IDX
    movd      xmm4, DWORD PTR [rsi+rax*4]
    movd      xmm5, DWORD PTR [rdi+rcx*4]
    paddusb   xmm4, xmm5
    movd      DWORD PTR [rdi+rcx*4], xmm4
sc_gl_nx:
    addps     xmm0, xmm6
    inc       ecx
    cmp       ecx, edx
    jb        sc_glass
sc_next:
    inc       ebx
    cmp       ebx, r12d
    jb        sc_row
    FNX_RET
FN_END G3_TriScan

END
