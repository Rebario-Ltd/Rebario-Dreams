; ============================================================================
; fx_roto.asm - scene 5 "MANDALA": a kaleidoscope looking into a Julia set.
; ----------------------------------------------------------------------------
; Init builds a 512 x 512 texture of the smooth escape time of the Julia set
; (16-bit values; the interior is coloured by an orbit trap so the field stays
; continuous), a polar table (angle, radius) for the 640 x 360 screen and a
; cyclic 1024 entry palette.
; Per frame every pixel folds its angle into a mirrored 30 degree wedge
; (6 fold symmetry), turns that wedge into texture coordinates around a centre
; that drifts over the texture, samples it bilinearly (reflecting addressing,
; so the 512 texture tiles without seams) and looks the value up in the
; palette, which scrolls.  Zoom pulses on the kick.
; ============================================================================
INCLUDE common.inc

ROT_TEX   EQU 512
ROT_N     EQU 6                          ; wedges: 2 * N with the mirror
ROT_WEDGE EQU 683                        ; 4096 / N as a 16-bit multiplier
ROT_MAXIT EQU 96
ROT_GLOW  EQU 320

L_ROTA    EQU LOC + 0
L_PHI     EQU LOC + 4
L_ZOOM    EQU LOC + 8
L_CX      EQU LOC + 12
L_CY      EQU LOC + 16
L_SHIFT   EQU LOC + 20
L_END     EQU LOC + 24
L_FB      EQU LOC + 32
L_DM      EQU LOC + 64                   ; DMASK (56 bytes)

.const
ALIGN 16
rkC319    REAL4 319.5
rkC179    REAL4 179.5
rkC255    REAL4 255.5
rkSc      REAL4 0.00625                  ; 3.2 / 512: the texture spans [-1.6, 1.6]
rkCx      REAL4 -0.7269                  ; Julia constant
rkCy      REAL4 0.1889
rkEsc     REAL4 256.0                    ; escape radius squared
rkBig     REAL4 1.0e9
rkOne     REAL4 1.0
rkFour    REAL4 4.0
rkSixteen REAL4 16.0
rkMaxIt   REAL4 96.0
rkK512    REAL4 512.0
rkMax     REAL4 65535.0
rkHalf    REAL4 0.5
rkAng     REAL4 10430.378                ; 65536 / (2 pi)

; cyclic palette with dark troughs between the bright bands
rotKeys   DWORD 10
          DWORD 0,     000A0224h
          DWORD 7000,  002A0E90h
          DWORD 16000, 001670F0h
          DWORD 24000, 008CE8FFh
          DWORD 29000, 00FFFFFFh
          DWORD 34000, 00FFC850h
          DWORD 42000, 00FF3C8Ch
          DWORD 50000, 008A1CC8h
          DWORD 58000, 002A0A60h
          DWORD 65536, 000A0224h
.data?
ALIGN 16
rotTex    WORD ROT_TEX * ROT_TEX DUP (?)
rotPol    DWORD SCR_PIX DUP (?)          ; angle16 | radius * 16 << 16
rotPal    DWORD 1024 DUP (?)
rotRef    WORD 1024 DUP (?)              ; reflecting address: i, then 1023 - i
rotGlow   BYTE 16 DUP (?)                ; TXMASK

.code

; ---------------------------------------------------------------------------
; Rot_BuildPolar - per screen pixel: angle (0..65535) and radius * 16.
; ---------------------------------------------------------------------------
FN_BEGIN Rot_BuildPolar, 16
    lea  rdi, rotPol
    xor  r12d, r12d
bp_row:
    cvtsi2ss xmm0, r12d
    subss xmm0, DWORD PTR rkC179
    movss DWORD PTR [rsp+LOC], xmm0        ; dy
    xor  r13d, r13d
bp_px:
    cvtsi2ss xmm1, r13d
    subss xmm1, DWORD PTR rkC319
    movss DWORD PTR [rsp+LOC+4], xmm1      ; dx
    mulss xmm1, xmm1
    movss xmm2, DWORD PTR [rsp+LOC]
    mulss xmm2, xmm2
    addss xmm1, xmm2
    sqrtss xmm1, xmm1
    mulss xmm1, DWORD PTR rkSixteen
    addss xmm1, DWORD PTR rkHalf
    cvttss2si r14d, xmm1                   ; radius * 16
    movss xmm0, DWORD PTR [rsp+LOC]
    movss xmm1, DWORD PTR [rsp+LOC+4]
    call Mth_Atan2f
    mulss xmm0, DWORD PTR rkAng
    cvtss2si eax, xmm0
    and  eax, 0FFFFh
    shl  r14d, 16
    or   eax, r14d
    mov  DWORD PTR [rdi], eax
    add  rdi, 4
    inc  r13d
    cmp  r13d, SCR_W
    jb   bp_px
    inc  r12d
    cmp  r12d, SCR_H
    jb   bp_row
    FN_RET
FN_END Rot_BuildPolar

; ---------------------------------------------------------------------------
; Rot_BuildFractal - smooth escape time of z -> z^2 + c, as 16-bit values
; (iterations * 512).  Escaped points: mu = n + 4 - log2(log2 |z|^2);
; interior points: 96 + 16 * min(1, orbit trap distance).
; ---------------------------------------------------------------------------
FNX_BEGIN Rot_BuildFractal, 0
    lea  rdi, rotTex
    movss xmm6, DWORD PTR rkCx
    movss xmm7, DWORD PTR rkCy
    movss xmm8, DWORD PTR rkEsc
    xor  r12d, r12d
bf_row:
    cvtsi2ss xmm9, r12d
    subss xmm9, DWORD PTR rkC255
    mulss xmm9, DWORD PTR rkSc             ; y of this row
    xor  r13d, r13d
bf_px:
    cvtsi2ss xmm0, r13d
    subss xmm0, DWORD PTR rkC255
    mulss xmm0, DWORD PTR rkSc             ; zx
    movaps xmm1, xmm9                      ; zy
    movss xmm10, DWORD PTR rkBig           ; orbit trap
    xor  ecx, ecx
bf_it:
    movaps xmm2, xmm0
    mulss xmm2, xmm2                       ; x^2
    movaps xmm3, xmm1
    mulss xmm3, xmm3                       ; y^2
    movaps xmm4, xmm2
    addss xmm4, xmm3                       ; |z|^2
    comiss xmm4, xmm8
    ja   bf_esc
    minss xmm10, xmm4
    mulss xmm1, xmm0
    addss xmm1, xmm1
    addss xmm1, xmm7                       ; zy = 2 zx zy + cy
    subss xmm2, xmm3
    addss xmm2, xmm6                       ; zx = x^2 - y^2 + cx
    movaps xmm0, xmm2
    inc  ecx
    cmp  ecx, ROT_MAXIT
    jb   bf_it
    sqrtss xmm0, xmm10
    minss xmm0, DWORD PTR rkOne
    mulss xmm0, DWORD PTR rkSixteen
    addss xmm0, DWORD PTR rkMaxIt
    jmp  bf_store
bf_esc:
    movaps xmm0, xmm4
    mov  r14d, ecx
    call Mth_Log2f
    call Mth_Log2f
    cvtsi2ss xmm1, r14d
    addss xmm1, DWORD PTR rkFour
    subss xmm1, xmm0
    xorps xmm0, xmm0
    maxss xmm0, xmm1
bf_store:
    mulss xmm0, DWORD PTR rkK512
    minss xmm0, DWORD PTR rkMax
    cvttss2si eax, xmm0
    mov  WORD PTR [rdi], ax
    add  rdi, 2
    inc  r13d
    cmp  r13d, ROT_TEX
    jb   bf_px
    inc  r12d
    cmp  r12d, ROT_TEX
    jb   bf_row
    FNX_RET
FN_END Rot_BuildFractal

FN_BEGIN Fx_Roto_Init, 0
    lea  rdi, rotRef                       ; reflecting address table
    xor  ecx, ecx
ri_ref:
    mov  eax, 1023
    sub  eax, ecx
    cmp  ecx, ROT_TEX
    cmovb eax, ecx
    mov  WORD PTR [rdi+rcx*2], ax
    inc  ecx
    cmp  ecx, 1024
    jb   ri_ref
    call Rot_BuildPolar
    call Rot_BuildFractal
    lea  rcx, rotPal
    mov  edx, 1024
    lea  r8, rotKeys
    call Pal_FromKeys
    lea  rcx, rotGlow
    mov  edx, ROT_GLOW
    mov  r8d, 2
    call Msk_Radial
    xor  eax, eax
    FN_RET
FN_END Fx_Roto_Init

; ---------------------------------------------------------------------------
; Fx_Roto_Render(rcx = fb, edx = local ms)
; ---------------------------------------------------------------------------
FN_BEGIN Fx_Roto_Render, 128
    mov  QWORD PTR [rsp+L_FB], rcx
    mov  r12d, edx
    lea  rbp, gSinTab
    imul eax, r12d, 4                      ; fold rotation: one turn per 16 s
    and  eax, 0FFFFh
    mov  DWORD PTR [rsp+L_ROTA], eax
    imul eax, r12d, 7                      ; sector turning inside the texture
    shr  eax, 4
    mov  DWORD PTR [rsp+L_PHI], eax
    imul eax, r12d, 3                      ; zoom breathes, plus a kick punch
    shr  eax, 2
    and  eax, 4095
    movsx eax, WORD PTR [rbp+rax*2]
    imul eax, 135
    sar  eax, 15
    add  eax, 312
    mov  ecx, gKick
    shr  ecx, 3
    add  ecx, 256
    imul eax, ecx
    shr  eax, 8
    mov  DWORD PTR [rsp+L_ZOOM], eax
    imul eax, r12d, 5                      ; texture centre drifts (8.8 texels)
    shr  eax, 4
    and  eax, 4095
    movsx eax, WORD PTR [rbp+rax*2]
    imul eax, 70
    sar  eax, 15
    add  eax, 280
    shl  eax, 8
    mov  DWORD PTR [rsp+L_CX], eax
    imul eax, r12d, 3
    shr  eax, 3
    add  eax, 700
    and  eax, 4095
    movsx eax, WORD PTR [rbp+rax*2]
    imul eax, 50
    sar  eax, 15
    add  eax, 245
    shl  eax, 8
    mov  DWORD PTR [rsp+L_CY], eax
    mov  eax, r12d                         ; palette scroll
    shr  eax, 3
    mov  ecx, gKick
    shr  ecx, 3
    add  eax, ecx
    mov  DWORD PTR [rsp+L_SHIFT], eax
    lea  rsi, rotPol
    mov  rdi, QWORD PTR [rsp+L_FB]
    lea  rax, [rdi+SCR_BYTES]
    mov  QWORD PTR [rsp+L_END], rax
    lea  r13, rotTex
    lea  r14, rotPal
    lea  r15, rotRef
rt_px:
    mov  eax, DWORD PTR [rsi]
    mov  r11d, eax
    shr  r11d, 16                          ; radius * 16
    movzx eax, ax                          ; angle
    add  eax, DWORD PTR [rsp+L_ROTA]
    imul eax, ROT_N
    and  eax, 0FFFFh
    mov  ecx, eax
    xor  ecx, 0FFFFh
    test eax, 8000h
    cmovnz eax, ecx                        ; mirror: fold into 0..32767
    imul eax, ROT_WEDGE
    shr  eax, 16                           ; wedge angle in 4096ths of a turn
    add  eax, DWORD PTR [rsp+L_PHI]
    and  eax, 4095
    movsx ecx, WORD PTR [rbp+rax*2]        ; sin
    add  eax, 1024
    and  eax, 4095
    movsx edx, WORD PTR [rbp+rax*2]        ; cos
    imul r11d, DWORD PTR [rsp+L_ZOOM]
    shr  r11d, 8                           ; radius in texels * 16
    imul edx, r11d
    sar  edx, 11
    add  edx, DWORD PTR [rsp+L_CX]         ; u (8.8 texels)
    imul ecx, r11d
    sar  ecx, 11
    add  ecx, DWORD PTR [rsp+L_CY]         ; v
    mov  r8d, edx
    and  r8d, 255                          ; fu
    sar  edx, 8
    mov  r9d, ecx
    and  r9d, 255                          ; fv
    sar  ecx, 8
    mov  eax, edx
    and  eax, 1023
    movzx eax, WORD PTR [r15+rax*2]        ; x0
    inc  edx
    and  edx, 1023
    movzx edx, WORD PTR [r15+rdx*2]        ; x1
    mov  r10d, ecx
    and  r10d, 1023
    movzx r10d, WORD PTR [r15+r10*2]       ; y0
    inc  ecx
    and  ecx, 1023
    movzx ecx, WORD PTR [r15+rcx*2]        ; y1
    shl  r10d, 9
    shl  ecx, 9
    lea  r11d, [r10+rax]
    movzx ebx, WORD PTR [r13+r11*2]        ; t00
    lea  r11d, [r10+rdx]
    movzx r12d, WORD PTR [r13+r11*2]       ; t10
    sub  r12d, ebx
    imul r12d, r8d
    sar  r12d, 8
    add  ebx, r12d                         ; upper row
    lea  r11d, [rcx+rax]
    movzx r10d, WORD PTR [r13+r11*2]       ; t01
    lea  r11d, [rcx+rdx]
    movzx edx, WORD PTR [r13+r11*2]        ; t11
    sub  edx, r10d
    imul edx, r8d
    sar  edx, 8
    add  r10d, edx                         ; lower row
    sub  r10d, ebx
    imul r10d, r9d
    sar  r10d, 8
    add  ebx, r10d                         ; 0..65535 (iterations * 512)
    shr  ebx, 1                            ; 256 palette steps per iteration
    add  ebx, DWORD PTR [rsp+L_SHIFT]
    mov  eax, DWORD PTR [rsi]
    shr  eax, 19                           ; + radius / 2: rings that flow outwards
    sub  ebx, eax
    and  ebx, 1023
    mov  eax, DWORD PTR [r14+rbx*4]
    mov  DWORD PTR [rdi], eax
    add  rdi, 4
    add  rsi, 4
    cmp  rdi, QWORD PTR [rsp+L_END]
    jb   rt_px
    lea  rax, [rsp+L_DM]                   ; additive glow in the centre
    mov  rcx, QWORD PTR [rsp+L_FB]
    mov  QWORD PTR [rax+DMASK.dst], rcx
    lea  rcx, rotGlow
    mov  QWORD PTR [rax+DMASK.tx], rcx
    mov  DWORD PTR [rax+DMASK.x], SCR_W / 2 - ROT_GLOW / 2
    mov  DWORD PTR [rax+DMASK.y], SCR_H / 2 - ROT_GLOW / 2
    mov  DWORD PTR [rax+DMASK.color], 00FFB0E8h
    mov  ecx, gKick
    shr  ecx, 1
    add  ecx, 40
    mov  DWORD PTR [rax+DMASK.alpha], ecx
    mov  DWORD PTR [rax+DMASK.mode], 1
    mov  QWORD PTR [rax+DMASK.rowPal], 0
    mov  QWORD PTR [rax+DMASK.rowOff], 0
    mov  rcx, rax
    call Gfx_DrawMask
    FN_RET
FN_END Fx_Roto_Render

END
