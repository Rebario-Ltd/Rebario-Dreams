; ============================================================================
; g3_mesh.asm - mesh construction shared by all shapes (see g3.inc).
; ----------------------------------------------------------------------------
;   Msh_Grid        periodic parametric surface -> indexed triangles
;   Msh_Flat        triangle list from a point table -> flat shaded mesh
;   Msh_FixWinding  turns every triangle so that it faces along its normals
;   Msh_Volume      signed volume (a quality check: positive = wound outwards)
; Triangles are counter-clockwise seen from outside, which is what the
; rasteriser treats as front-facing.
; ============================================================================
INCLUDE common.inc
INCLUDE g3.inc

.const
ALIGN 16
kMask3   DWORD 0FFFFFFFFh, 0FFFFFFFFh, 0FFFFFFFFh, 0
kSixth   REAL4 0.16666667

.code

; ---------------------------------------------------------------------------
; Msh_FixWinding(rcx = MESH *)
; A triangle whose geometric normal (b - a) x (c - a) points against the sum of
; its vertex normals gets its last two indices swapped.
; ---------------------------------------------------------------------------
FNX_BEGIN Msh_FixWinding, 0
    mov       r8, QWORD PTR [rcx+MESH.verts]
    mov       r9, QWORD PTR [rcx+MESH.idx]
    mov       r10d, DWORD PTR [rcx+MESH.nTris]
    test      r10d, r10d
    jz        fw_done
fw_tri:
    movzx     eax, WORD PTR [r9]
    movzx     edx, WORD PTR [r9+2]
    movzx     r11d, WORD PTR [r9+4]
    shl       eax, 5
    shl       edx, 5
    shl       r11d, 5
    add       rax, r8
    add       rdx, r8
    add       r11, r8
    movaps    xmm0, XMMWORD PTR [rax]
    movaps    xmm1, XMMWORD PTR [rdx]
    movaps    xmm2, XMMWORD PTR [r11]
    subps     xmm1, xmm0                      ; b - a
    subps     xmm2, xmm0                      ; c - a
    VCROSS    xmm3, xmm1, xmm2, xmm4, xmm5    ; geometric normal
    movaps    xmm0, XMMWORD PTR [rax+16]
    addps     xmm0, XMMWORD PTR [rdx+16]
    addps     xmm0, XMMWORD PTR [r11+16]      ; sum of the vertex normals
    mulps     xmm3, xmm0
    HSUM3     xmm1, xmm3, xmm4, xmm5
    xorps     xmm4, xmm4
    comiss    xmm1, xmm4
    jae       fw_next                         ; faces along the normals: keep
    movzx     eax, WORD PTR [r9+2]
    movzx     edx, WORD PTR [r9+4]
    mov       WORD PTR [r9+2], dx
    mov       WORD PTR [r9+4], ax
fw_next:
    add       r9, 6
    dec       r10d
    jnz       fw_tri
fw_done:
    FNX_RET
FN_END Msh_FixWinding

; ---------------------------------------------------------------------------
; Msh_Grid(rcx = MESH * (out), rdx = GRID *)
; Samples surf at (i / nu, j / nv), i = 0 .. nu-1, j = 0 .. nv-1 (nv inclusive
; when the surface is open in v) and joins neighbours with two triangles per
; cell; the seam is closed by index wrap-around.  Pole triangles of a sphere
; degenerate to zero area and are dropped by the rasteriser.
; ---------------------------------------------------------------------------
FN_BEGIN Msh_Grid, 0
    mov       rsi, rcx                        ; MESH *
    mov       rdi, rdx                        ; GRID *
    mov       r12d, DWORD PTR [rdi+GRID.nu]
    mov       r13d, DWORD PTR [rdi+GRID.nv]
    lea       r14d, [r13+1]
    sub       r14d, DWORD PTR [rdi+GRID.wrapV] ; vertex rows along v
    mov       eax, r12d
    imul      eax, r14d
    mov       DWORD PTR [rsi+MESH.nVerts], eax
    shl       eax, 5
    mov       ecx, eax
    call      Mem_Alloc
    mov       QWORD PTR [rsi+MESH.verts], rax
    mov       eax, r12d
    imul      eax, r13d
    add       eax, eax
    mov       DWORD PTR [rsi+MESH.nTris], eax
    imul      ecx, eax, 6
    call      Mem_Alloc
    mov       QWORD PTR [rsi+MESH.idx], rax
    xor       ebx, ebx                        ; i
mg_i:
    xor       ebp, ebp                        ; j
mg_j:
    cvtsi2ss  xmm0, ebx
    cvtsi2ss  xmm2, r12d
    divss     xmm0, xmm2                      ; u = i / nu
    cvtsi2ss  xmm1, ebp
    cvtsi2ss  xmm2, r13d
    divss     xmm1, xmm2                      ; v = j / nv
    call      QWORD PTR [rdi+GRID.surf]
    mov       eax, ebx
    imul      eax, r14d
    add       eax, ebp
    shl       eax, 5
    mov       rdx, QWORD PTR [rsi+MESH.verts]
    movaps    XMMWORD PTR [rdx+rax], xmm0
    movaps    XMMWORD PTR [rdx+rax+16], xmm1
    inc       ebp
    cmp       ebp, r14d
    jb        mg_j
    inc       ebx
    cmp       ebx, r12d
    jb        mg_i
    mov       r8, QWORD PTR [rsi+MESH.idx]
    xor       ebx, ebx
mg_ci:
    lea       r9d, [rbx+1]
    xor       eax, eax
    cmp       r9d, r12d
    cmovae    r9d, eax                        ; i1 = (i + 1) mod nu
    xor       ebp, ebp
mg_cj:
    lea       r10d, [rbp+1]
    cmp       r10d, r14d
    jb        mg_jw
    xor       r10d, r10d                      ; j1 wraps in a periodic mesh
mg_jw:
    mov       eax, ebx
    imul      eax, r14d                       ; first vertex of column i
    mov       r11d, r9d
    imul      r11d, r14d                      ; first vertex of column i1
    lea       ecx, [rax+rbp]                  ; a = (i, j)
    lea       edx, [r11+rbp]                  ; b = (i1, j)
    mov       WORD PTR [r8], cx               ; triangle (a, b, c)
    mov       WORD PTR [r8+2], dx
    lea       edx, [r11+r10]                  ; c = (i1, j1)
    mov       WORD PTR [r8+4], dx
    mov       WORD PTR [r8+6], cx             ; triangle (a, c, d)
    mov       WORD PTR [r8+8], dx
    lea       edx, [rax+r10]                  ; d = (i, j1)
    mov       WORD PTR [r8+10], dx
    add       r8, 12
    inc       ebp
    cmp       ebp, r13d
    jb        mg_cj
    inc       ebx
    cmp       ebx, r12d
    jb        mg_ci
    mov       rcx, rsi
    call      Msh_FixWinding
    FN_RET
FN_END Msh_Grid

; ---------------------------------------------------------------------------
; Msh_Flat(rcx = MESH * (out), rdx = float points[3 per point],
;          r8 = BYTE faces[3 per triangle], r9d = triangle count)
; Every triangle gets its own three vertices carrying the face normal (flat
; shading).  The winding is chosen so that the normal points away from the
; origin, which holds for the convex, origin-centred solids used here.  The
; point table needs one spare float behind it (a vector is loaded per point).
; ---------------------------------------------------------------------------
FNX_BEGIN Msh_Flat, 16
    mov       rsi, rcx
    mov       r12, rdx                        ; points
    mov       r13, r8                         ; faces
    mov       r14d, r9d                       ; triangles
    lea       eax, [r14+r14*2]
    mov       DWORD PTR [rsi+MESH.nVerts], eax
    mov       DWORD PTR [rsi+MESH.nTris], r14d
    shl       eax, 5
    mov       ecx, eax
    call      Mem_Alloc
    mov       QWORD PTR [rsi+MESH.verts], rax
    mov       rdi, rax                        ; vertex write pointer
    imul      ecx, r14d, 6
    call      Mem_Alloc
    mov       QWORD PTR [rsi+MESH.idx], rax
    mov       r15, rax                        ; index write pointer
    movaps    xmm15, XMMWORD PTR kMask3
    xor       ebx, ebx                        ; triangle
fl_tri:
    movzx     eax, BYTE PTR [r13]
    lea       eax, [rax+rax*2]
    movups    xmm0, XMMWORD PTR [r12+rax*4]
    andps     xmm0, xmm15                     ; a
    movzx     eax, BYTE PTR [r13+1]
    lea       eax, [rax+rax*2]
    movups    xmm1, XMMWORD PTR [r12+rax*4]
    andps     xmm1, xmm15                     ; b
    movzx     eax, BYTE PTR [r13+2]
    lea       eax, [rax+rax*2]
    movups    xmm2, XMMWORD PTR [r12+rax*4]
    andps     xmm2, xmm15                     ; c
    movaps    xmm3, xmm1
    subps     xmm3, xmm0
    movaps    xmm4, xmm2
    subps     xmm4, xmm0
    VCROSS    xmm5, xmm3, xmm4, xmm6, xmm7    ; face normal, not normalised
    movaps    xmm6, xmm0
    addps     xmm6, xmm1
    addps     xmm6, xmm2                      ; 3 x centroid
    mulps     xmm6, xmm5
    HSUM3     xmm7, xmm6, xmm8, xmm9
    xorps     xmm8, xmm8
    comiss    xmm7, xmm8
    jae       fl_out
    movaps    xmm6, xmm1                      ; faces inwards: swap b and c
    movaps    xmm1, xmm2
    movaps    xmm2, xmm6
    xorps     xmm5, XMMWORD PTR kG3SignV
fl_out:
    VNORM     xmm5, xmm6, xmm7, xmm8, xmm9
    movaps    XMMWORD PTR [rdi], xmm0
    movaps    XMMWORD PTR [rdi+16], xmm5
    movaps    XMMWORD PTR [rdi+32], xmm1
    movaps    XMMWORD PTR [rdi+48], xmm5
    movaps    XMMWORD PTR [rdi+64], xmm2
    movaps    XMMWORD PTR [rdi+80], xmm5
    add       rdi, 96
    lea       eax, [rbx+rbx*2]
    mov       WORD PTR [r15], ax
    inc       eax
    mov       WORD PTR [r15+2], ax
    inc       eax
    mov       WORD PTR [r15+4], ax
    add       r15, 6
    add       r13, 3
    inc       ebx
    cmp       ebx, r14d
    jb        fl_tri
    FNX_RET
FN_END Msh_Flat

; ---------------------------------------------------------------------------
; Msh_Volume(rcx = MESH *) -> xmm0 = sum of a . (b x c) / 6 over all triangles.
; ---------------------------------------------------------------------------
FNX_BEGIN Msh_Volume, 0
    mov       r8, QWORD PTR [rcx+MESH.verts]
    mov       r9, QWORD PTR [rcx+MESH.idx]
    mov       r10d, DWORD PTR [rcx+MESH.nTris]
    xorps     xmm6, xmm6
    test      r10d, r10d
    jz        mv_done
mv_tri:
    movzx     eax, WORD PTR [r9]
    movzx     edx, WORD PTR [r9+2]
    movzx     r11d, WORD PTR [r9+4]
    shl       eax, 5
    shl       edx, 5
    shl       r11d, 5
    movaps    xmm0, XMMWORD PTR [r8+rax]
    movaps    xmm1, XMMWORD PTR [r8+rdx]
    movaps    xmm2, XMMWORD PTR [r8+r11]
    VCROSS    xmm3, xmm1, xmm2, xmm4, xmm5    ; b x c
    mulps     xmm3, xmm0
    HSUM3     xmm0, xmm3, xmm4, xmm5
    addss     xmm6, xmm0
    add       r9, 6
    dec       r10d
    jnz       mv_tri
mv_done:
    mulss     xmm6, DWORD PTR kSixth
    movaps    xmm0, xmm6
    FNX_RET
FN_END Msh_Volume

END
