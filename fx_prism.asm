; ============================================================================
; fx_prism.asm - scene 8 "PRISM": real-time software 3D.
; ----------------------------------------------------------------------------
; A procedural torus knot in iridescent oil, golden and ceramic spheres on
; orbits, a golden ring, tumbling cubes and a big glass icosahedron are drawn
; by the z-buffer rasteriser of g3_*.asm (2 x 2 supersampled, matcap shaded,
; glass blended additively) in front of a slowly turning spectrum fan.
;
; The scene is a pure function of its local time T = lt / 1000 s:
;   * every object grows with an ease-out-back curve at its own birth time
;     (the knot at once, the last cube at 10.6 s) and pulses with the kick;
;   * orbits, spins and a gentle camera sway are plain functions of T;
;   * from 12.6 s the finale pushes the camera in, widens the orbits, blows
;     the objects up and spins everything faster (smoothstep g over 3.6 s);
;     an object that gets nearer than 3 units to the camera shrinks to
;     nothing (smoothstep) instead of being clipped.
; The backdrop is built from 320 x 180 tables (angle, glow colour, fade) once;
; per frame only the 12 rays and their spectrum colours rotate.
;
; Fx_Prism_Init   builds the meshes, the four matcaps and the backdrop tables;
; Fx_Prism_Render (rcx = fb, edx = local ms);
; Pz_Backdrop     (rcx = fb, edx = local ms) draws the backdrop alone;
; Pz_Place        (rcx = object, rdx = XFORM *) -> eax = 1 when it is visible.
; ============================================================================
INCLUDE common.inc
INCLUDE g3.inc
INCLUDE prism.inc

.const
ALIGN 16
kPzBaseK    REAL4 51.0, 12.75, 17.85, 0.0     ; glow colour * 255 as B, G, R
kPzBase0    REAL4 18.35, 5.6, 5.6, 0.0        ; dark base * 255 + 0.5 as B, G, R
kPzHue      REAL4 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 1.0, 1.0, 1.0, 0.0, 0.33, 0.67
kPzMilli    REAL4 0.001
kPzFin0     REAL4 12.6                        ; the finale starts ...
kPzFinInv   REAL4 0.27777778                  ; ... and lasts 3.6 s
kPzZc0      REAL4 12.5                        ; camera distance
kPzZcSpan   REAL4 2.5                         ; pulled in by this much in the finale
kPzPulse    REAL4 0.00019531250               ; 0.05 / 256 per kick unit
kPzSway     REAL4 0.06                        ; camera sway: turns per second ...
kPzSwayAmp  REAL4 0.03                        ; ... and its amplitude in turns
kPzOrbitK   REAL4 0.7                         ; orbits widen by this much in the finale
kPzGrowK    REAL4 0.45                        ; solids grow by this much
kPzExK      REAL4 0.3                         ; extra spin 0.3 g^2 turns
kPzMinS     REAL4 0.01                        ; smaller solids are not drawn
kPzInv160   REAL4 0.00625
kPzInv90    REAL4 0.011111111
kPzTurn     REAL4 10430.378                   ; 65536 / 2 pi
kPzGlowK    REAL4 -2.564792                   ; exp(-r^2 / 0.75^2) as a power of two
kPzFadeK    REAL4 -1.781105                   ; exp(-r^2 / 0.9^2)
kPz76       REAL4 76.5                        ; 0.30 * 255: strength of the rays
kPz255      REAL4 255.0
kPzInv4096  REAL4 0.000244140625

ALIGN 16
; mesh, matcap, mode | birth, 1 / growth time, scale, orbit radius |
; orbit speed, phase, tilt x, tilt y | start angles | spin per second
; (opaque solids first, the glass last: it blends over what is behind it)
pzObjs      DWORD PZM_KNOT, MAT_OIL, G3M_OPAQUE, 0
            REAL4 0.0, 0.45454547, 1.0, 0.0
            REAL4 0.0, 0.0, 0.0, 0.0
            REAL4 0.10, 0.0, 0.0, 0.0
            REAL4 0.021, 0.055, 0.012, 0.0
            DWORD PZM_SPHERE, MAT_GOLD, G3M_OPAQUE, 0
            REAL4 3.0, 1.0, 0.62, 4.6
            REAL4 0.070, 0.0, 0.08, 0.10
            REAL4 0.0, 0.0, 0.0, 0.0
            REAL4 0.0, 0.0, 0.0, 0.0
            DWORD PZM_SPHERE, MAT_TEAL, G3M_OPAQUE, 0
            REAL4 3.6, 1.0, 0.50, 4.9
            REAL4 -0.050, 0.50, -0.12, 0.0
            REAL4 0.0, 0.0, 0.0, 0.0
            REAL4 0.0, 0.0, 0.0, 0.0
            DWORD PZM_RING, MAT_GOLD, G3M_OPAQUE, 0
            REAL4 5.0, 0.8333333, 3.40, 0.0
            REAL4 0.0, 0.0, 0.0, 0.0
            REAL4 0.14, 0.0, 0.0, 0.0
            REAL4 0.010, 0.040, 0.025, 0.0
            DWORD PZM_CUBE, MAT_TEAL, G3M_OPAQUE, 0
            REAL4 9.6, 1.0, 0.55, 6.2
            REAL4 0.045, 0.000, 0.05, 0.0
            REAL4 0.0, 0.0, 0.0, 0.0
            REAL4 0.050, 0.080, 0.030, 0.0
            DWORD PZM_CUBE, MAT_OIL, G3M_OPAQUE, 0
            REAL4 10.1, 1.0, 0.55, 6.2
            REAL4 0.045, 0.333, 0.05, 0.0
            REAL4 0.20, 0.0, 0.0, 0.0
            REAL4 0.050, 0.080, 0.030, 0.0
            DWORD PZM_CUBE, MAT_GOLD, G3M_OPAQUE, 0
            REAL4 10.6, 1.0, 0.55, 6.2
            REAL4 0.045, 0.667, 0.05, 0.0
            REAL4 0.40, 0.0, 0.0, 0.0
            REAL4 0.050, 0.080, 0.030, 0.0
            DWORD PZM_ICO, MAT_GLASS, G3M_GLASS, 0
            REAL4 8.0, 0.71428573, 4.00, 0.0
            REAL4 0.0, 0.0, 0.0, 0.0
            REAL4 0.0, 0.0, 0.0, 0.0
            REAL4 0.030, 0.050, 0.000, 0.0

.data?
ALIGN 16
pzCam       REAL4 12 DUP (?)            ; camera rotation (MAT3)
ALIGN 16
pzXf        XFORM <>                    ; transformation of the solid being drawn
ALIGN 16
pzMeshes    MESH PZ_MESHES DUP (<>)
pzTex       QWORD ?                     ; MAT_COUNT matcaps of G3_TEXB bytes
pzT         REAL4 ?                     ; time in seconds
pzG         REAL4 ?                     ; finale 0 .. 1
pzEx        REAL4 ?                     ; extra spin of the finale
pzZc        REAL4 ?                     ; camera distance
pzPulse     REAL4 ?                     ; 1 + 0.05 kick
ALIGN 16
pzAng       WORD PZ_BN DUP (?)          ; angle of a backdrop cell, 1 / 65536 turn
ALIGN 16
pzBase      DWORD PZ_BN DUP (?)         ; dark base + glow, BGRA
pzFade      BYTE PZ_BN DUP (?)          ; strength of the rays: 0.3 * fade * 255
ALIGN 16
pzHalf      DWORD PZ_BN DUP (?)         ; the backdrop before the 2 x enlargement
pzRay       BYTE 4096 DUP (?)           ; ray profile ((1 + cos) / 2) ^ 6 * 255
ALIGN 16
pzHue       DWORD 256 DUP (?)           ; spectrum around the circle

.code

; ---------------------------------------------------------------------------
; Pz_Meshes - the five solids.
; ---------------------------------------------------------------------------
FN_BEGIN Pz_Meshes, 0
    lea       rbx, pzMeshes
    mov       rcx, rbx
    call      Msh_Knot
    lea       rcx, [rbx+PZM_RING*PZ_MSZ]
    call      Msh_Ring
    lea       rcx, [rbx+PZM_SPHERE*PZ_MSZ]
    call      Msh_Sphere
    lea       rcx, [rbx+PZM_CUBE*PZ_MSZ]
    call      Msh_Cube
    lea       rcx, [rbx+PZM_ICO*PZ_MSZ]
    call      Msh_Ico
    FN_RET
FN_END Pz_Meshes

; Pz_Matcaps - one matcap per material, back to back.
FN_BEGIN Pz_Matcaps, 0
    mov       ecx, MAT_COUNT * G3_TEXB
    call      Mem_Alloc
    mov       QWORD PTR pzTex, rax
    mov       rbx, rax
    xor       esi, esi
pm_lp:
    mov       rcx, rbx
    mov       edx, esi
    call      Mat_Build
    add       rbx, G3_TEXB
    inc       esi
    cmp       esi, MAT_COUNT
    jb        pm_lp
    FN_RET
FN_END Pz_Matcaps

; ---------------------------------------------------------------------------
; Pz_BuildRays - the ray profile: ((1 + cos 2 pi x) / 2) ^ 6 for x = i / 4096.
; ---------------------------------------------------------------------------
FN_BEGIN Pz_BuildRays, 0
    lea       rdi, pzRay
    xor       ebx, ebx
pr_lp:
    cvtsi2ss  xmm0, ebx
    mulss     xmm0, DWORD PTR kPzInv4096
    call      G3_SinCos                       ; xmm1 = cos
    mulss     xmm1, DWORD PTR kG3Half
    addss     xmm1, DWORD PTR kG3Half         ; h = (1 + cos) / 2
    movaps    xmm0, xmm1
    mulss     xmm0, xmm0                      ; h^2
    movaps    xmm2, xmm0
    mulss     xmm2, xmm2                      ; h^4
    mulss     xmm0, xmm2                      ; h^6
    mulss     xmm0, DWORD PTR kPz255
    addss     xmm0, DWORD PTR kG3Half
    cvttss2si eax, xmm0
    mov       BYTE PTR [rdi+rbx], al
    inc       ebx
    cmp       ebx, 4096
    jb        pr_lp
    FN_RET
FN_END Pz_BuildRays

; ---------------------------------------------------------------------------
; Pz_BgPixel(ecx = x, edx = y, r8d = index) - angle, glow colour and ray
; strength of one backdrop cell; (dx, dy) = position in -1 .. 1.
; ---------------------------------------------------------------------------
FN_BEGIN Pz_BgPixel, 16
    mov       esi, r8d
    cvtsi2ss  xmm0, ecx
    addss     xmm0, DWORD PTR kG3Half
    mulss     xmm0, DWORD PTR kPzInv160
    subss     xmm0, DWORD PTR kG3One          ; dx
    cvtsi2ss  xmm1, edx
    addss     xmm1, DWORD PTR kG3Half
    mulss     xmm1, DWORD PTR kPzInv90
    subss     xmm1, DWORD PTR kG3One          ; dy
    movss     DWORD PTR [rsp+LOC], xmm0
    movss     DWORD PTR [rsp+LOC+4], xmm1
    mulss     xmm0, xmm0
    mulss     xmm1, xmm1
    addss     xmm0, xmm1
    movss     DWORD PTR [rsp+LOC+8], xmm0     ; r^2
    movss     xmm0, DWORD PTR [rsp+LOC+4]
    movss     xmm1, DWORD PTR [rsp+LOC]
    call      Mth_Atan2f                      ; radians
    mulss     xmm0, DWORD PTR kPzTurn
    cvttss2si eax, xmm0
    lea       rdx, pzAng
    mov       WORD PTR [rdx+rsi*2], ax        ; modulo one turn
    movss     xmm0, DWORD PTR [rsp+LOC+8]
    mulss     xmm0, DWORD PTR kPzGlowK
    call      Mth_Exp2f                       ; glow
    shufps    xmm0, xmm0, 000h
    mulps     xmm0, XMMWORD PTR kPzBaseK
    addps     xmm0, XMMWORD PTR kPzBase0
    cvttps2dq xmm0, xmm0
    packssdw  xmm0, xmm0
    packuswb  xmm0, xmm0
    movd      eax, xmm0
    lea       rdx, pzBase
    mov       DWORD PTR [rdx+rsi*4], eax
    movss     xmm0, DWORD PTR [rsp+LOC+8]
    mulss     xmm0, DWORD PTR kPzFadeK
    call      Mth_Exp2f                       ; fade
    mulss     xmm0, DWORD PTR kPz76
    addss     xmm0, DWORD PTR kG3Half
    cvttss2si eax, xmm0
    lea       rdx, pzFade
    mov       BYTE PTR [rdx+rsi], al
    FN_RET
FN_END Pz_BgPixel

FN_BEGIN Pz_BuildBackdrop, 0
    lea       rcx, pzHue
    mov       edx, 256
    lea       r8, kPzHue
    call      Pal_Cosine
    xor       esi, esi                        ; cell index
    xor       ebx, ebx                        ; row
bb_row:
    xor       edi, edi                        ; column
bb_col:
    mov       ecx, edi
    mov       edx, ebx
    mov       r8d, esi
    call      Pz_BgPixel
    inc       esi
    inc       edi
    cmp       edi, PZ_BW
    jb        bb_col
    inc       ebx
    cmp       ebx, PZ_BH
    jb        bb_row
    FN_RET
FN_END Pz_BuildBackdrop

FN_BEGIN Fx_Prism_Init, 0
    call      G3_Init
    call      Pz_Meshes
    call      Pz_Matcaps
    call      Pz_BuildRays
    call      Pz_BuildBackdrop
    xor       eax, eax
    FN_RET
FN_END Fx_Prism_Init

; ---------------------------------------------------------------------------
; Pz_Frame(edx = local ms) - everything that is the same for every solid of the
; frame: time, finale, camera distance, the kick pulse and the camera matrix.
; ---------------------------------------------------------------------------
FN_BEGIN Pz_Frame, 0
    cvtsi2ss  xmm0, edx
    mulss     xmm0, DWORD PTR kPzMilli
    movss     DWORD PTR pzT, xmm0
    subss     xmm0, DWORD PTR kPzFin0
    mulss     xmm0, DWORD PTR kPzFinInv
    call      G3_Smooth                       ; finale g
    movss     DWORD PTR pzG, xmm0
    movaps    xmm1, xmm0
    mulss     xmm1, xmm0
    mulss     xmm1, DWORD PTR kPzExK
    movss     DWORD PTR pzEx, xmm1            ; 0.3 g^2
    mulss     xmm0, DWORD PTR kPzZcSpan
    movss     xmm1, DWORD PTR kPzZc0
    subss     xmm1, xmm0
    movss     DWORD PTR pzZc, xmm1            ; 12.5 - 2.5 g
    cvtsi2ss  xmm0, DWORD PTR gKick
    mulss     xmm0, DWORD PTR kPzPulse
    addss     xmm0, DWORD PTR kG3One
    movss     DWORD PTR pzPulse, xmm0
    movss     xmm0, DWORD PTR pzT
    mulss     xmm0, DWORD PTR kPzSway
    call      G3_SinCos
    mulss     xmm0, DWORD PTR kPzSwayAmp
    movaps    xmm1, xmm0                      ; y angle
    xorps     xmm0, xmm0
    xorps     xmm2, xmm2
    lea       rcx, pzCam
    call      G3_RotMat
    FN_RET
FN_END Pz_Frame

; ---------------------------------------------------------------------------
; Pz_Grow(rsi = object) -> xmm0 = scale: size * growth * pulse * finale.
; ---------------------------------------------------------------------------
FN_BEGIN Pz_Grow, 0
    movss     xmm0, DWORD PTR pzT
    subss     xmm0, DWORD PTR [rsi+PZOBJ.birth]
    mulss     xmm0, DWORD PTR [rsi+PZOBJ.durInv]
    call      G3_EaseBack
    mulss     xmm0, DWORD PTR [rsi+PZOBJ.scale]
    mulss     xmm0, DWORD PTR pzPulse
    movss     xmm1, DWORD PTR pzG
    mulss     xmm1, DWORD PTR kPzGrowK
    addss     xmm1, DWORD PTR kG3One
    mulss     xmm0, xmm1
    FN_RET
FN_END Pz_Grow

; ---------------------------------------------------------------------------
; Pz_Pos(rsi = object) -> xmm0 = centre in world space (before the camera).
; ---------------------------------------------------------------------------
FN_BEGIN Pz_Pos, 64
    movss     xmm0, DWORD PTR pzT
    mulss     xmm0, DWORD PTR [rsi+PZOBJ.orbitW]
    addss     xmm0, DWORD PTR [rsi+PZOBJ.orbitP]
    call      G3_SinCos                       ; xmm0 = sin, xmm1 = cos
    movss     xmm2, DWORD PTR pzG
    mulss     xmm2, DWORD PTR kPzOrbitK
    addss     xmm2, DWORD PTR kG3One
    mulss     xmm2, DWORD PTR [rsi+PZOBJ.orbitR]
    mulss     xmm1, xmm2                      ; x = r cos
    mulss     xmm0, xmm2                      ; z = r sin
    movss     DWORD PTR [rsp+LOC+48], xmm1
    mov       DWORD PTR [rsp+LOC+52], 0
    movss     DWORD PTR [rsp+LOC+56], xmm0
    mov       DWORD PTR [rsp+LOC+60], 0
    movss     xmm0, DWORD PTR [rsi+PZOBJ.tiltX]
    movss     xmm1, DWORD PTR [rsi+PZOBJ.tiltY]
    xorps     xmm2, xmm2
    lea       rcx, [rsp+LOC]
    call      G3_RotMat
    movaps    xmm0, XMMWORD PTR [rsp+LOC+48]
    lea       rcx, [rsp+LOC]
    call      G3_MatVec
    FN_RET
FN_END Pz_Pos

; ---------------------------------------------------------------------------
; Pz_Rot(rsi = object, rdi = XFORM *) - orientation: camera * spin, written to
; the three columns at the start of the XFORM.
; ---------------------------------------------------------------------------
FN_BEGIN Pz_Rot, 48
    movss     xmm0, DWORD PTR pzT
    shufps    xmm0, xmm0, 000h
    mulps     xmm0, XMMWORD PTR [rsi+PZOBJ.spin]
    addps     xmm0, XMMWORD PTR [rsi+PZOBJ.a0]
    movss     xmm1, DWORD PTR pzEx
    shufps    xmm1, xmm1, 000h
    addps     xmm0, xmm1                      ; angles about x, y, z in turns
    movaps    xmm1, xmm0
    shufps    xmm1, xmm1, 055h
    movaps    xmm2, xmm0
    shufps    xmm2, xmm2, 0AAh
    lea       rcx, [rsp+LOC]
    call      G3_RotMat
    mov       rcx, rdi
    lea       rdx, pzCam
    lea       r8, [rsp+LOC]
    call      G3_MatMul
    FN_RET
FN_END Pz_Rot

; ---------------------------------------------------------------------------
; Pz_Place(rcx = object, rdx = XFORM *) -> eax = 1 when the solid is visible.
; Size, position in view space (with the camera distance), the near fade
; smooth((z - 1) / 2) and the orientation go into the XFORM.
; ---------------------------------------------------------------------------
FNX_BEGIN Pz_Place, 0
    mov       rsi, rcx
    mov       rdi, rdx
    call      Pz_Grow
    movaps    xmm6, xmm0                      ; scale
    comiss    xmm6, DWORD PTR kPzMinS
    jbe       pp_hide
    call      Pz_Pos
    lea       rcx, pzCam
    call      G3_MatVec
    movss     xmm1, DWORD PTR pzZc
    pslldq    xmm1, 8                         ; (0, 0, zc, 0)
    addps     xmm0, xmm1
    movaps    xmm7, xmm0                      ; position in view space
    shufps    xmm0, xmm0, 0AAh
    subss     xmm0, DWORD PTR kG3One
    mulss     xmm0, DWORD PTR kG3Half
    call      G3_Smooth
    mulss     xmm6, xmm0                      ; near fade
    comiss    xmm6, DWORD PTR kPzMinS
    jbe       pp_hide
    call      Pz_Rot
    movaps    XMMWORD PTR [rdi+XFORM.t], xmm7
    shufps    xmm6, xmm6, 000h
    movaps    XMMWORD PTR [rdi+XFORM.s], xmm6
    mov       eax, 1
    FNX_RET
pp_hide:
    xor       eax, eax
    FNX_RET
FN_END Pz_Place

; Pz_Object(rcx = object) - places and draws one solid.
FN_BEGIN Pz_Object, 0
    mov       rsi, rcx
    lea       rdx, pzXf
    call      Pz_Place
    test      eax, eax
    jz        po_done
    mov       eax, DWORD PTR [rsi+PZOBJ.mesh]
    imul      eax, eax, PZ_MSZ
    lea       rcx, pzMeshes
    add       rcx, rax
    lea       rdx, pzXf
    mov       eax, DWORD PTR [rsi+PZOBJ.tex]
    imul      rax, rax, G3_TEXB
    mov       r8, QWORD PTR pzTex
    add       r8, rax
    mov       r9d, DWORD PTR [rsi+PZOBJ.mode]
    call      G3_Draw
po_done:
    FN_RET
FN_END Pz_Object

; ---------------------------------------------------------------------------
; Pz_Backdrop(rcx = fb, edx = local ms) - the spectrum fan.  Per cell: the ray
; profile at 12 * angle + phase (the fan turns 0.05 turns per second), the
; spectrum colour at angle + hue offset (0.03 turns per second), both scaled
; by the cell's ray strength and by the kick, added to the dark base colour;
; then enlarged to the full picture.
; ---------------------------------------------------------------------------
FN_BEGIN Pz_Backdrop, 0
    mov       r12, rcx
    mov       eax, edx
    imul      rax, rax, 214748                ; ms * 3.2768 = 0.05 turn / s in 1 / 65536
    shr       rax, 16
    movzx     r8d, ax                         ; ray phase
    mov       eax, edx
    imul      rax, rax, 128849                ; ms * 1.96608 = 0.03 turn / s
    shr       rax, 16
    movzx     r9d, ax                         ; hue offset
    mov       r10d, DWORD PTR gKick
    shr       r10d, 1
    add       r10d, 256                       ; 1 .. 1.5 pulse of the rays
    lea       rsi, pzAng
    lea       rbx, pzRay
    lea       rbp, pzFade
    lea       r13, pzHue
    lea       r14, pzBase
    lea       rdi, pzHalf
    pxor      xmm5, xmm5
    xor       ecx, ecx
bd_px:
    movzx     eax, WORD PTR [rsi+rcx*2]
    lea       edx, [rax+rax*2]
    shl       edx, 2                          ; 12 * angle
    add       edx, r8d
    and       edx, 0FFFFh
    shr       edx, 4
    movzx     edx, BYTE PTR [rbx+rdx]         ; ray profile
    movzx     r11d, BYTE PTR [rbp+rcx]
    imul      edx, r11d
    imul      edx, r10d
    shr       edx, 16                         ; strength 0 .. 115
    add       eax, r9d
    and       eax, 0FFFFh
    shr       eax, 8
    movd      xmm0, DWORD PTR [r13+rax*4]     ; spectrum colour
    punpcklbw xmm0, xmm5
    movd      xmm1, edx
    pshuflw   xmm1, xmm1, 000h
    pmullw    xmm0, xmm1
    psrlw     xmm0, 8
    packuswb  xmm0, xmm0
    movd      xmm2, DWORD PTR [r14+rcx*4]
    paddusb   xmm0, xmm2
    movd      DWORD PTR [rdi+rcx*4], xmm0
    inc       ecx
    cmp       ecx, PZ_BN
    jb        bd_px
    mov       rcx, r12
    lea       rdx, pzHalf
    mov       r8d, PZ_BW
    mov       r9d, PZ_BH
    call      Gfx_Up2
    FN_RET
FN_END Pz_Backdrop

; ---------------------------------------------------------------------------
; Fx_Prism_Render(rcx = fb, edx = local ms)
; ---------------------------------------------------------------------------
FN_BEGIN Fx_Prism_Render, 0
    mov       r12, rcx
    mov       r13d, edx
    call      Pz_Frame
    mov       rcx, r12
    mov       edx, r13d
    call      Pz_Backdrop
    mov       rcx, r12
    call      G3_Begin
    lea       rsi, pzObjs
    mov       ebx, PZ_OBJS
fr_obj:
    mov       rcx, rsi
    call      Pz_Object
    add       rsi, SIZEOF PZOBJ
    dec       ebx
    jnz       fr_obj
    mov       rcx, r12
    call      G3_Resolve
    xor       eax, eax
    FN_RET
FN_END Fx_Prism_Render

END
