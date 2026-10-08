; ============================================================================
; g3_draw.asm - render targets, vertex transformation, mesh drawing and the
;               anti-aliasing resolve of the software 3D renderer (g3.inc).
; ----------------------------------------------------------------------------
; Frame:  G3_Begin(backdrop)  replicates the 640 x 360 picture 2 x 2 into the
;                             colour target and clears the depth
;         G3_Draw(...)        any number of meshes
;         G3_Resolve(dst)     box filter 2 x 2 -> 640 x 360
; Where nothing was drawn the four samples of a pixel are equal, so the resolve
; returns the backdrop unchanged (exactly); on silhouettes it blends.
; The targets are allocated with a canary guard of G3_GUARD bytes on both sides
; so that the self test can prove that nothing is drawn outside.
; ============================================================================
INCLUDE common.inc
INCLUDE g3.inc

G3_CANARY EQU 0CDCDCDCDh

.const
ALIGN 16
kProjMul  REAL4 1000.0, -1000.0, 0.0, 0.0   ; focal length in supersampled pixels, y is flipped
kProjAdd  REAL4 640.0, 360.0, 0.0, 0.0      ; the optical axis
kOneV     REAL4 1.0, 1.0, 1.0, 1.0
kTexMul   REAL4 0.0, 127.4, -127.4, 0.0     ; matcap u = 127.5 + 127.4 nx, v = 127.5 - 127.4 ny
kTexAdd   REAL4 0.0, 127.5, 127.5, 0.0
kZNear    REAL4 0.5                         ; nearer vertices make the triangle unusable

.data?
ALIGN 16
g3Color   QWORD ?
g3Z       QWORD ?
g3Tex     QWORD ?
g3Mode    DWORD ?
ALIGN 16
g3Pv      PV G3_MAXV DUP (<>)

.code

; ---------------------------------------------------------------------------
; G3_AllocTarget -> rax = G3_BYTES of zeroed memory with canary guards around.
; ---------------------------------------------------------------------------
FN_BEGIN G3_AllocTarget, 0
    mov       ecx, G3_BYTES + 2 * G3_GUARD
    call      Mem_Alloc
    mov       rbx, rax
    mov       rdi, rbx
    mov       eax, G3_CANARY
    mov       ecx, G3_GUARD / 4
    rep       stosd
    lea       rdi, [rbx+G3_GUARD+G3_BYTES]
    mov       ecx, G3_GUARD / 4
    rep       stosd
    lea       rax, [rbx+G3_GUARD]
    FN_RET
FN_END G3_AllocTarget

FN_BEGIN G3_Init, 0
    cmp       QWORD PTR g3Color, 0            ; once is enough: every user may call it
    jne       gi_done
    call      G3_AllocTarget
    mov       QWORD PTR g3Color, rax
    call      G3_AllocTarget
    mov       QWORD PTR g3Z, rax
gi_done:
    xor       eax, eax
    FN_RET
FN_END G3_Init

; ---------------------------------------------------------------------------
; G3_Begin(rcx = backdrop 640 x 360 BGRA) - every source pixel becomes a 2 x 2
; block of the colour target; the depth target is cleared to 0 (nothing drawn).
; ---------------------------------------------------------------------------
FN_BEGIN G3_Begin, 0
    mov       rsi, rcx
    mov       rdi, QWORD PTR g3Color
    mov       r8d, SCR_H
gb_row:
    xor       eax, eax
gb_blk:
    movdqa    xmm0, XMMWORD PTR [rsi+rax]     ; four source pixels
    movdqa    xmm1, xmm0
    punpckldq xmm0, xmm0                      ; p0 p0 p1 p1
    punpckhdq xmm1, xmm1                      ; p2 p2 p3 p3
    movdqa    XMMWORD PTR [rdi+rax*2], xmm0
    movdqa    XMMWORD PTR [rdi+rax*2+16], xmm1
    movdqa    XMMWORD PTR [rdi+rax*2+G3_PITCH], xmm0
    movdqa    XMMWORD PTR [rdi+rax*2+G3_PITCH+16], xmm1
    add       eax, 16
    cmp       eax, SCR_W * 4
    jb        gb_blk
    add       rsi, SCR_W * 4
    add       rdi, G3_PITCH * 2
    dec       r8d
    jnz       gb_row
    mov       rdi, QWORD PTR g3Z
    xor       eax, eax
    mov       ecx, G3_PIX
    rep       stosd
    FN_RET
FN_END G3_Begin

; ---------------------------------------------------------------------------
; G3_Resolve(rcx = dst 640 x 360) - eight samples of two rows give four pixels:
; the rows are averaged first, then neighbouring samples (pavgb rounds up).
; ---------------------------------------------------------------------------
FN_BEGIN G3_Resolve, 0
    mov       rdi, rcx
    mov       rsi, QWORD PTR g3Color
    mov       r8d, SCR_H
gr_row:
    xor       eax, eax                        ; destination byte offset
    xor       edx, edx                        ; source byte offset
gr_blk:
    movdqa    xmm0, XMMWORD PTR [rsi+rdx]
    movdqa    xmm1, XMMWORD PTR [rsi+rdx+16]
    pavgb     xmm0, XMMWORD PTR [rsi+rdx+G3_PITCH]
    pavgb     xmm1, XMMWORD PTR [rsi+rdx+G3_PITCH+16]
    movdqa    xmm2, xmm0
    shufps    xmm0, xmm1, 088h                ; even samples
    shufps    xmm2, xmm1, 0DDh                ; odd samples
    pavgb     xmm0, xmm2
    movdqa    XMMWORD PTR [rdi+rax], xmm0
    add       eax, 16
    add       edx, 32
    cmp       eax, SCR_W * 4
    jb        gr_blk
    add       rdi, SCR_W * 4
    add       rsi, G3_PITCH * 2
    dec       r8d
    jnz       gr_row
    FN_RET
FN_END G3_Resolve

; ---------------------------------------------------------------------------
; G3_Draw(rcx = MESH *, rdx = XFORM *, r8 = matcap, r9d = G3M_*)
; Transforms every vertex to view space, projects it (w = 1 / z, vertices
; nearer than 0.5 get w = 0 and take their triangles with them) and derives the
; matcap coordinates from the rotated normal; then scan-converts the triangles.
; ---------------------------------------------------------------------------
FNX_BEGIN G3_Draw, 0
    mov       QWORD PTR g3Tex, r8
    mov       DWORD PTR g3Mode, r9d
    mov       rsi, rcx
    movaps    xmm8, XMMWORD PTR [rdx+XFORM.c0]
    movaps    xmm9, XMMWORD PTR [rdx+XFORM.c1]
    movaps    xmm10, XMMWORD PTR [rdx+XFORM.c2]
    movaps    xmm11, XMMWORD PTR [rdx+XFORM.t]
    movaps    xmm12, XMMWORD PTR [rdx+XFORM.s]
    movaps    xmm13, XMMWORD PTR kProjMul
    movaps    xmm14, XMMWORD PTR kProjAdd
    mov       r12, QWORD PTR [rsi+MESH.verts]
    mov       r13d, DWORD PTR [rsi+MESH.nVerts]
    lea       r14, g3Pv
dm_vert:
    movaps    xmm0, XMMWORD PTR [r12]         ; object-space position
    movaps    xmm1, XMMWORD PTR [r12+16]      ; and normal
    MATVEC    xmm2, xmm0, xmm8, xmm9, xmm10, xmm3, xmm4
    mulps     xmm2, xmm12
    addps     xmm2, xmm11                     ; view-space position
    MATVEC    xmm3, xmm1, xmm8, xmm9, xmm10, xmm4, xmm5
    movaps    xmm4, xmm2
    shufps    xmm4, xmm4, 0AAh                ; z in every lane
    comiss    xmm4, DWORD PTR kZNear
    jb        dm_bad
    movaps    xmm5, XMMWORD PTR kOneV
    divps     xmm5, xmm4                      ; w = 1 / z
    mulps     xmm2, xmm5
    mulps     xmm2, xmm13
    addps     xmm2, xmm14                     ; (sx, sy)
    movlps    QWORD PTR [r14], xmm2
    shufps    xmm3, xmm3, 050h                ; (nx, nx, ny, ny)
    mulps     xmm3, XMMWORD PTR kTexMul
    addps     xmm3, XMMWORD PTR kTexAdd       ; (0, u, v, 0)
    movss     xmm3, xmm5                      ; (w, u, v, 0)
    movaps    XMMWORD PTR [r14+16], xmm3
    jmp       dm_next
dm_bad:
    xorps     xmm0, xmm0
    movaps    XMMWORD PTR [r14+16], xmm0      ; w = 0
dm_next:
    add       r12, 32
    add       r14, 32
    dec       r13d
    jnz       dm_vert
    mov       r12, QWORD PTR [rsi+MESH.idx]
    mov       r13d, DWORD PTR [rsi+MESH.nTris]
    lea       r14, g3Pv
dm_tri:
    movzx     ecx, WORD PTR [r12]
    movzx     edx, WORD PTR [r12+2]
    movzx     r8d, WORD PTR [r12+4]
    shl       ecx, 5
    shl       edx, 5
    shl       r8d, 5
    add       rcx, r14
    add       rdx, r14
    add       r8, r14
    call      G3_TriSetup
    test      eax, eax
    jz        dm_skip
    call      G3_TriScan
dm_skip:
    add       r12, 6
    dec       r13d
    jnz       dm_tri
    FNX_RET
FN_END G3_Draw

END
