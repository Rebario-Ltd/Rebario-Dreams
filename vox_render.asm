; ============================================================================
; vox_render.asm - voxel-space ray caster for scene 7 "TERRA".
; ----------------------------------------------------------------------------
; Classic height-field rendering, front to back: for every distance step z the
; map line perpendicular to the view direction is sampled (bilinear height and
; colour from the packed cell arrays), projected to a screen row and, if it
; rises above what is already drawn in that column (the "y buffer"), the gap
; is filled with a colour gradient from the new sample down to the previous
; one (no stair-step terraces).  Distance steps grow with z (dz = 1 + z / 128).
; Water texels (alpha > 0) reflect the horizon sky more and more with distance
; (Fresnel-like) and receive sparkling sun glitter; everything fades into the
; horizon colour with distance.  The sky is a palette gradient plus the sun
; (additive glow table + anti-aliased disc).
; ============================================================================
INCLUDE common.inc
INCLUDE vox.inc

SUN_COL   EQU 00FFBE5Ah                   ; colour the sky is tinted with around the sun
DISC_COL  EQU 00FFFFF0h                   ; sun disc
GLIT_COL  EQU 00FFB86Ah                   ; glitter colour

.const
ALIGN 16
vxSkyKeys DWORD 6
          DWORD 0,     00FFC88Ch
          DWORD 6554,  00FAAA82h
          DWORD 19661, 00DE808Ch
          DWORD 36045, 007E60A0h
          DWORD 52429, 00344282h
          DWORD 65536, 00162252h
kG1       REAL4 -0.000147213             ; -log2(e) / (2 * 70^2)
kG2       REAL4 -0.0000125234            ; -log2(e) / (2 * 240^2)
k055      REAL4 0.55
k035      REAL4 0.35
k255      REAL4 255.0
kGlowEdge REAL4 0.03629              ; glow value at the table end (cut-off)
kGlowNorm REAL4 1.03766              ; 1 / (1 - edge)

.data?
ALIGN 16
vxp       BYTE 96 DUP (?)
vxSkyPal  DWORD 256 DUP (?)
vxGlow    BYTE 1024 DUP (?)
vxRecipF  REAL4 368 DUP (?)
vxCols    DWORD SCR_W * 2 DUP (?)         ; per column: top row drawn so far, its colour
vxFogCol  DWORD ?
vxReflCol DWORD ?

.code

; ---------------------------------------------------------------------------
; Vox_InitTables - sky palette, sun glow profile, 1 / n table of the gradients.
; ---------------------------------------------------------------------------
FN_BEGIN Vox_InitTables, 16
    lea  rcx, vxSkyPal
    mov  edx, 256
    lea  r8, vxSkyKeys
    call Pal_FromKeys
    lea  rax, vxSkyPal
    mov  ecx, DWORD PTR [rax+5*4]
    mov  DWORD PTR vxFogCol, ecx           ; haze = colour just above the horizon
    mov  ecx, DWORD PTR [rax+15*4]
    mov  DWORD PTR vxReflCol, ecx          ; what the water mirrors
    lea  rsi, vxRecipF
    xor  ebx, ebx
    xorps xmm0, xmm0
    movss DWORD PTR [rsi], xmm0
it_rcp:
    inc  ebx
    cvtsi2ss xmm0, ebx
    movss xmm1, DWORD PTR kOneF
    divss xmm1, xmm0
    movss DWORD PTR [rsi+rbx*4], xmm1
    cmp  ebx, SCR_H
    jb   it_rcp
    xor  ebx, ebx
it_glow:                                   ; two Gaussians: tight core + wide halo
    mov  eax, ebx
    shl  eax, 8
    add  eax, 128
    cvtsi2ss xmm0, eax                     ; r^2 (pixels)
    movss DWORD PTR [rsp+LOC], xmm0
    mulss xmm0, DWORD PTR kG1
    call Mth_Exp2f
    mulss xmm0, DWORD PTR k055
    movss DWORD PTR [rsp+LOC+4], xmm0
    movss xmm0, DWORD PTR [rsp+LOC]
    mulss xmm0, DWORD PTR kG2
    call Mth_Exp2f
    mulss xmm0, DWORD PTR k035
    addss xmm0, DWORD PTR [rsp+LOC+4]
    subss xmm0, DWORD PTR kGlowEdge        ; reaches zero exactly at the edge: no seam
    xorps xmm1, xmm1
    maxss xmm0, xmm1
    mulss xmm0, DWORD PTR kGlowNorm
    mulss xmm0, DWORD PTR k255
    cvtss2si eax, xmm0
    lea  rdx, vxGlow
    mov  BYTE PTR [rdx+rbx], al
    inc  ebx
    cmp  ebx, 1024
    jb   it_glow
    xor  eax, eax
    FN_RET
FN_END Vox_InitTables

.const
ALIGN 4
kOneF     REAL4 1.0

.code

; ---------------------------------------------------------------------------
; Vox_Sun - additive glow around the sun and its anti-aliased disc (sky rows).
; ---------------------------------------------------------------------------
FN_BEGIN Vox_Sun, 16
    lea  rsi, vxp
    mov  r12d, DWORD PTR [rsi+VXP.sunX]
    cmp  r12d, -500
    jl   su_done
    cmp  r12d, 1140
    jg   su_done
    mov  r13d, DWORD PTR [rsi+VXP.sunY]
    mov  r14, QWORD PTR [rsi+VXP.fb]
    mov  eax, r12d                         ; column range [x0, x1)
    sub  eax, 500
    xor  ecx, ecx
    test eax, eax
    cmovs eax, ecx
    mov  DWORD PTR [rsp+LOC], eax
    lea  eax, [r12+500]
    mov  ecx, SCR_W
    cmp  eax, ecx
    cmova eax, ecx
    mov  DWORD PTR [rsp+LOC+4], eax
    mov  ebx, r13d                         ; row range [y0, y1)
    sub  ebx, 500
    xor  ecx, ecx
    test ebx, ebx
    cmovs ebx, ecx
    mov  r15d, DWORD PTR [rsi+VXP.hor]
    add  r15d, 24
su_row:
    cmp  ebx, r15d
    jge  su_done
    cmp  ebx, SCR_H
    jge  su_done
    mov  eax, ebx
    sub  eax, r13d
    imul eax, eax
    mov  ebp, eax                          ; dy^2
    mov  ecx, DWORD PTR [rsp+LOC]
su_px:
    mov  eax, ecx
    sub  eax, r12d
    imul eax, eax
    add  eax, ebp
    mov  r10d, eax                         ; r^2
    cmp  eax, 261120
    jae  su_pn
    shr  eax, 8
    lea  rdx, vxGlow
    movzx r11d, BYTE PTR [rdx+rax]
    mov  eax, ebx
    imul eax, SCR_W
    add  eax, ecx
    lea  rdi, [r14+rax*4]
    mov  r8d, DWORD PTR [rdi]
    mov  r9d, SUN_COL
    PIXMIX r8d, r9d, r11d, eax, edx
    mov  DWORD PTR [rdi], r8d
    cmp  r10d, 729
    jae  su_pn
    mov  eax, 729                          ; disc: 2-pixel soft edge
    sub  eax, r10d
    imul eax, 2521
    shr  eax, 10
    mov  edx, 256
    cmp  eax, edx
    cmova eax, edx
    mov  r8d, DWORD PTR [rdi]
    mov  r9d, DISC_COL
    PIXMIX r8d, r9d, eax, r10d, r11d
    mov  DWORD PTR [rdi], r8d
su_pn:
    inc  ecx
    cmp  ecx, DWORD PTR [rsp+LOC+4]
    jl   su_px
    inc  ebx
    jmp  su_row
su_done:
    FN_RET
FN_END Vox_Sun

; ---------------------------------------------------------------------------
; Vox_Sky - palette gradient (index grows with the height above the horizon).
; ---------------------------------------------------------------------------
FN_BEGIN Vox_Sky, 0
    lea  rsi, vxp
    mov  r14, QWORD PTR [rsi+VXP.fb]
    xor  ebx, ebx
sk_row:
    mov  eax, DWORD PTR [rsi+VXP.hor]
    sub  eax, ebx
    imul eax, 198
    sar  eax, 8
    xor  ecx, ecx
    test eax, eax
    cmovs eax, ecx
    mov  ecx, 255
    cmp  eax, ecx
    cmova eax, ecx
    lea  rdx, vxSkyPal
    mov  eax, DWORD PTR [rdx+rax*4]
    mov  rdi, r14
    mov  ecx, SCR_W
    rep  stosd
    mov  r14, rdi
    inc  ebx
    cmp  ebx, SCR_H
    jb   sk_row
    call Vox_Sun
    FN_RET
FN_END Vox_Sky

; ---------------------------------------------------------------------------
; Vox_Step(ecx = z, 24.8) - map position of column 0, per-column step, screen
; scale, fog / reflection / glitter weights of one distance step.
; ---------------------------------------------------------------------------
FN_BEGIN Vox_Step, 0
    mov  r12d, ecx
    lea  rsi, vxp
    mov  eax, VX_F SHL 16
    xor  edx, edx
    div  r12d
    mov  QWORD PTR [rsi+VXP.kk], rax       ; y = horizon + dh * kk >> 16
    movsxd rax, DWORD PTR [rsi+VXP.fwdX]
    imul rax, r12
    sar  rax, 7
    mov  r13, rax                          ; heading * z, 16.16
    movsxd rax, DWORD PTR [rsi+VXP.fwdY]
    imul rax, r12
    sar  rax, 7
    mov  r14, rax
    mov  ebx, VX_F
    movsxd rax, DWORD PTR [rsi+VXP.fwdY]   ; right vector = (-fwdY, fwdX)
    neg  rax
    imul rax, r12
    sar  rax, 7
    cqo
    idiv rbx
    mov  r8, rax                           ; map step per column
    movsxd rax, DWORD PTR [rsi+VXP.fwdX]
    imul rax, r12
    sar  rax, 7
    cqo
    idiv rbx
    mov  r9, rax
    mov  rax, r8                           ; column 0 sits 319.5 steps left of centre
    imul rax, 319
    mov  rdx, r8
    sar  rdx, 1
    add  rax, rdx
    movsxd rcx, DWORD PTR [rsi+VXP.camX]
    add  rcx, r13
    sub  rcx, rax
    mov  DWORD PTR [rsi+VXP.baseX], ecx
    mov  rax, r9
    imul rax, 319
    mov  rdx, r9
    sar  rdx, 1
    add  rax, rdx
    movsxd rcx, DWORD PTR [rsi+VXP.camY]
    add  rcx, r14
    sub  rcx, rax
    mov  DWORD PTR [rsi+VXP.baseY], ecx
    mov  DWORD PTR [rsi+VXP.colDX], r8d
    mov  DWORD PTR [rsi+VXP.colDY], r9d
    mov  eax, r12d                         ; fog = 1.25 * (z / zfar)^2
    xor  edx, edx
    mov  ecx, VX_ZFAR
    div  ecx
    imul eax, eax
    imul eax, 5
    shr  eax, 10
    mov  edx, 256
    cmp  eax, edx
    cmova eax, edx
    shr  eax, 1
    mov  DWORD PTR [rsi+VXP.fogW], eax
    mov  eax, r12d                         ; water mirrors the haze from 25 cells on
    sub  eax, 6400
    jns  st_fr
    xor  eax, eax
st_fr:
    xor  edx, edx
    mov  ecx, 330
    div  ecx
    mov  edx, 256
    cmp  eax, edx
    cmova eax, edx
    imul eax, 119
    shr  eax, 8
    add  eax, 5
    mov  DWORD PTR [rsi+VXP.fresW], eax
    mov  eax, r12d                         ; glitter path widens with distance
    imul eax, 141
    shr  eax, 16
    add  eax, 18
    mov  ecx, eax
    mov  eax, 65536
    xor  edx, edx
    div  ecx
    mov  DWORD PTR [rsi+VXP.rw], eax
    mov  eax, r12d
    imul eax, 58
    shr  eax, 16
    mov  edx, 160
    sub  edx, eax
    xor  eax, eax
    test edx, edx
    cmovs edx, eax
    mov  eax, 128
    cmp  edx, eax
    cmova edx, eax
    mov  DWORD PTR [rsi+VXP.gfade], edx
    FN_RET
FN_END Vox_Step

; ---------------------------------------------------------------------------
; Vox_Span - paints a column segment as a gradient.
;   edi = column, edx = new top row, eax = new colour, r12 = column state,
;   rsi = vxp, xmm15 = 0.  Clobbers rax, rcx, rdx, xmm0..xmm3.
; ---------------------------------------------------------------------------
LEAF_BEGIN Vox_Span
    test edx, edx
    jns  sp_pos
    xor  edx, edx
sp_pos:
    mov  ecx, DWORD PTR [r12+rdi*8]        ; previous top row
    cmp  ecx, SCR_H
    movd xmm0, eax
    je   sp_first
    sub  ecx, edx
    jle  sp_done
    movd xmm1, DWORD PTR [r12+rdi*8+4]
    jmp  sp_setup
sp_first:                                  ; first sample of the column: flat
    sub  ecx, edx
    jle  sp_done
    movdqa xmm1, xmm0
sp_setup:
    mov  DWORD PTR [r12+rdi*8], edx
    mov  DWORD PTR [r12+rdi*8+4], eax
    punpcklbw xmm0, xmm15
    punpcklwd xmm0, xmm15
    cvtdq2ps xmm0, xmm0
    punpcklbw xmm1, xmm15
    punpcklwd xmm1, xmm15
    cvtdq2ps xmm1, xmm1
    subps xmm1, xmm0
    lea  rax, vxRecipF
    movss xmm2, DWORD PTR [rax+rcx*4]
    shufps xmm2, xmm2, 0
    mulps xmm1, xmm2                       ; colour step per row
    imul eax, edx, SCR_W
    add  eax, edi
    mov  rdx, QWORD PTR [rsi+VXP.fb]
    lea  rdx, [rdx+rax*4]
sp_lp:
    cvttps2dq xmm3, xmm0
    packssdw xmm3, xmm3
    packuswb xmm3, xmm3
    movd DWORD PTR [rdx], xmm3
    addps xmm0, xmm1
    add  rdx, SCR_W * 4
    dec  ecx
    jnz  sp_lp
sp_done:
    ret
LEAF_END Vox_Span

; ---------------------------------------------------------------------------
; Vox_Row - one distance step over all 640 columns.
;   rbx = colour cells, rbp = height cells, r12 = column state, rsi = vxp,
;   r8d / r9d = map position, r10d / r11d = per-column step, edi = column,
;   r13d / r14d = bilinear weights (later: r14d = water coverage), r15d = row.
;   xmm15 = 0, xmm14 = mirrored sky, xmm13 = haze, xmm12 = haze weight,
;   xmm11 = glitter colour.
; ---------------------------------------------------------------------------
FNX_BEGIN Vox_Row, 0
    lea  rsi, vxp
    lea  rbx, vxCCell
    lea  rbp, vxHCell
    lea  r12, vxCols
    mov  r8d, DWORD PTR [rsi+VXP.baseX]
    mov  r9d, DWORD PTR [rsi+VXP.baseY]
    mov  r10d, DWORD PTR [rsi+VXP.colDX]
    mov  r11d, DWORD PTR [rsi+VXP.colDY]
    pxor xmm15, xmm15
    movd xmm14, DWORD PTR vxReflCol
    punpcklbw xmm14, xmm15
    movd xmm13, DWORD PTR vxFogCol
    punpcklbw xmm13, xmm15
    mov  eax, GLIT_COL
    movd xmm11, eax
    punpcklbw xmm11, xmm15
    mov  eax, DWORD PTR [rsi+VXP.fogW]
    BCAST16 xmm12, eax
    xor  edi, edi
vr_col:
    mov  eax, r8d                          ; cell index and 7-bit fractions
    shr  eax, 16
    and  eax, 511
    mov  ecx, r9d
    shr  ecx, 16
    and  ecx, 511
    shl  ecx, 9
    or   eax, ecx
    mov  r13d, r8d
    shr  r13d, 9
    and  r13d, 127
    mov  r14d, r9d
    shr  r14d, 9
    and  r14d, 127
    movq xmm1, QWORD PTR [rbp+rax*8]       ; h00 h10 h01 h11
    mov  ecx, 128
    sub  ecx, r13d
    mov  edx, r13d
    shl  edx, 16
    or   edx, ecx
    movd xmm2, edx
    pshufd xmm2, xmm2, 0
    pmaddwd xmm1, xmm2                     ; two horizontal blends
    movd ecx, xmm1
    pshufd xmm1, xmm1, 1
    movd edx, xmm1
    mov  r15d, 128
    sub  r15d, r14d
    imul ecx, r15d
    imul edx, r14d
    add  ecx, edx
    shr  ecx, 14                           ; interpolated height
    mov  edx, DWORD PTR [rsi+VXP.camH]
    sub  edx, ecx
    movsxd rdx, edx
    imul rdx, QWORD PTR [rsi+VXP.kk]
    sar  rdx, 16
    add  edx, DWORD PTR [rsi+VXP.hor]      ; screen row of the sample
    mov  r15d, edx
    cmp  edx, DWORD PTR [r12+rdi*8]
    jge  vr_next                           ; hidden behind nearer terrain
    shl  eax, 4
    movdqu xmm0, XMMWORD PTR [rbx+rax]     ; c00 c10 c01 c11
    movdqa xmm1, xmm0
    punpcklbw xmm0, xmm15                  ; c00 | c10
    punpckhbw xmm1, xmm15                  ; c01 | c11
    psubw xmm1, xmm0
    BCAST16 xmm2, r14d
    pmullw xmm1, xmm2
    psraw xmm1, 7
    paddw xmm0, xmm1                       ; blended vertically
    pshufd xmm1, xmm0, 04Eh
    psubw xmm1, xmm0
    BCAST16 xmm2, r13d
    pmullw xmm1, xmm2
    psraw xmm1, 7
    paddw xmm0, xmm1                       ; low qword = B G R A words
    pextrw r14d, xmm0, 3                   ; water coverage
    test r14d, r14d
    jz   vr_fog
    mov  eax, r14d                         ; mirror the haze sky
    imul eax, DWORD PTR [rsi+VXP.fresW]
    shr  eax, 8
    BCAST16 xmm2, eax
    movdqa xmm1, xmm14
    psubw xmm1, xmm0
    pmullw xmm1, xmm2
    psraw xmm1, 7
    paddw xmm0, xmm1
vr_fog:
    movdqa xmm1, xmm13
    psubw xmm1, xmm0
    pmullw xmm1, xmm12
    psraw xmm1, 7
    paddw xmm0, xmm1
    test r14d, r14d
    jz   vr_pack
    mov  eax, edi                          ; sun glitter on water
    sub  eax, DWORD PTR [rsi+VXP.sunX]
    cdq
    xor  eax, edx
    sub  eax, edx
    imul eax, DWORD PTR [rsi+VXP.rw]
    mov  ecx, 65536
    sub  ecx, eax
    jle  vr_pack
    shr  ecx, 6
    imul ecx, ecx
    shr  ecx, 13
    imul ecx, DWORD PTR [rsi+VXP.gfade]
    shr  ecx, 7
    imul ecx, r14d
    shr  ecx, 8
    jz   vr_pack
    mov  eax, edi                          ; sparkle: half of the dashes are dim
    shr  eax, 1
    imul eax, 73856093
    mov  edx, DWORD PTR [rsi+VXP.step]
    imul edx, 19349663
    xor  eax, edx
    xor  eax, DWORD PTR [rsi+VXP.tb]
    imul eax, 1274126177
    shr  eax, 25
    mov  edx, 58
    cmp  eax, 64
    mov  eax, 128
    cmovb eax, edx
    imul ecx, eax
    shr  ecx, 7
    BCAST16 xmm2, ecx
    movdqa xmm1, xmm11
    pmullw xmm1, xmm2
    psrlw xmm1, 7
    paddw xmm0, xmm1
vr_pack:
    packuswb xmm0, xmm0
    movd eax, xmm0
    mov  edx, r15d
    call Vox_Span
vr_next:
    add  r8d, r10d
    add  r9d, r11d
    inc  edi
    cmp  edi, SCR_W
    jb   vr_col
    FNX_RET
FN_END Vox_Row

; ---------------------------------------------------------------------------
; Vox_Terrain - all distance steps, nearest first.
; ---------------------------------------------------------------------------
FN_BEGIN Vox_Terrain, 0
    lea  rdi, vxCols
    mov  ecx, SCR_W
    mov  eax, SCR_H
vt_init:
    mov  DWORD PTR [rdi], eax
    mov  DWORD PTR [rdi+4], 0
    add  rdi, 8
    dec  ecx
    jnz  vt_init
    mov  ebx, VX_ZNEAR * 256
    xor  r13d, r13d
vt_step:
    lea  rsi, vxp
    mov  DWORD PTR [rsi+VXP.step], r13d
    mov  ecx, ebx
    call Vox_Step
    call Vox_Row
    mov  eax, ebx
    shr  eax, 7
    add  eax, 256
    add  ebx, eax                          ; dz = 1 + z / 128
    inc  r13d
    cmp  ebx, VX_ZFAR * 256
    jb   vt_step
    FN_RET
FN_END Vox_Terrain

; ---------------------------------------------------------------------------
; Vox_Frame(rcx = fb) - sky, sun and terrain from the state in vxp.
; ---------------------------------------------------------------------------
FN_BEGIN Vox_Frame, 0
    lea  rsi, vxp
    mov  QWORD PTR [rsi+VXP.fb], rcx
    call Vox_Sky
    call Vox_Terrain
    FN_RET
FN_END Vox_Frame

END
