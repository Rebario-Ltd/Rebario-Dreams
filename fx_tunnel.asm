; ============================================================================
; fx_tunnel.asm - scene 2 "WORMHOLE": table-driven neon panel tunnel.
; ----------------------------------------------------------------------------
; Init precomputes, for a padded screen, the polar angle, the inverse radius
; (depth) and a fog factor of every pixel.  A frame is then only integer math
; on those tables: (angle, depth + travel) -> panel cell + position inside the
; cell -> palette colour * bevel + glowing edge line -> fog.  Edges are
; evaluated analytically, so they stay smooth at any magnification.
; The padding lets the vanishing point sway without recomputing anything.
; ============================================================================
INCLUDE common.inc

TUN_PX   EQU 64
TUN_PY   EQU 48
TUN_W    EQU SCR_W + 2 * TUN_PX
TUN_H    EQU SCR_H + 2 * TUN_PY
TUN_N    EQU TUN_W * TUN_H
GLOW_SZ  EQU 240
LINE_W   EQU 26                           ; width of the glowing edge, bevel units

V_FB     EQU LOC + 0
V_DV     EQU LOC + 8
V_DU     EQU LOC + 12
V_PH     EQU LOC + 16
V_OX     EQU LOC + 20
V_OY     EQU LOC + 24
V_DM     EQU LOC + 32                     ; DMASK, 56 bytes

.const
ALIGN 16
kTHalf   REAL4 0.5
kTOne    REAL4 1.0
kTCenX   REAL4 384.0
kTCenY   REAL4 228.0
kTInv2Pi REAL4 0.15915494
kT65536  REAL4 65536.0
kT65535  REAL4 65535.0
kTDepth  REAL4 150000.0
kTFogOff REAL4 6.0
kTFogInv REAL4 0.0083333333              ; 1 / 120
kTThree  REAL4 3.0
kTTwo    REAL4 2.0
kT255    REAL4 255.0

; four colour families: dark blues (0..63), cyan (64..127), magenta (128..191), gold (192..255)
tunKeys  DWORD 13
         DWORD 0 * 257,   00000006h
         DWORD 24 * 257,  0006143Ah
         DWORD 63 * 257,  000B2A6Ah
         DWORD 64 * 257,  0003424Fh
         DWORD 100 * 257, 000AA6C8h
         DWORD 127 * 257, 006CF0FFh
         DWORD 128 * 257, 003A0F6Eh
         DWORD 160 * 257, 00B0209Ah
         DWORD 191 * 257, 00FF5FC8h
         DWORD 192 * 257, 008A2A10h
         DWORD 224 * 257, 00FF8A1Ch
         DWORD 250 * 257, 00FFE9A0h
         DWORD 65536,     00FFFFFFh

.data?
ALIGN 16
tunPanel BYTE 512 DUP (?)                ; palette index per panel (16 deep x 32 around)
tunPal   DWORD 256 DUP (?)
tunFog   DWORD 256 DUP (?)
tunFill  DWORD 128 DUP (?)               ; bevel brightness by distance from the edge
tunLine  DWORD 128 DUP (?)               ; edge line colour by distance from the edge
tunGlow  BYTE 16 DUP (?)                 ; TXMASK
tunU     WORD TUN_N DUP (?)              ; polar angle, 0..65535
tunV     WORD TUN_N DUP (?)              ; depth * 16
tunF     BYTE TUN_N DUP (?)              ; fog 0..255

.code

; ---------------------------------------------------------------------------
; Tun_BuildPanels - colour family and brightness of every panel (hash based).
; ---------------------------------------------------------------------------
FN_BEGIN Tun_BuildPanels, 0
    lea  rdi, tunPanel
    xor  esi, esi                          ; panel row (depth)
pb_row:
    xor  ebx, ebx                          ; panel column (around)
pb_px:
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, 4321
    call Mth_Hash2
    mov  r12d, eax
    shr  eax, 8
    and  eax, 15                           ; class 0..15
    mov  r13d, r12d
    shr  r13d, 20
    and  r13d, 31                          ; brightness variation
    cmp  eax, 7
    jb   pb_unlit
    cmp  eax, 10
    jb   pb_cyan
    cmp  eax, 13
    jb   pb_mag
    cmp  eax, 15
    jb   pb_gold
    mov  eax, 255                          ; class 15: white-gold hot panel
    jmp  pb_store
pb_unlit:
    lea  eax, [r13+4]
    jmp  pb_store
pb_cyan:
    lea  eax, [r13+92]
    jmp  pb_store
pb_mag:
    lea  eax, [r13+150]
    jmp  pb_store
pb_gold:
    lea  eax, [r13+214]
pb_store:
    mov  BYTE PTR [rdi], al
    inc  rdi
    inc  ebx
    cmp  ebx, 32
    jb   pb_px
    inc  esi
    cmp  esi, 16
    jb   pb_row
    FN_RET
FN_END Tun_BuildPanels

; ---------------------------------------------------------------------------
; Tun_BuildLuts - bevel brightness and edge-line colour (integer only).
; ---------------------------------------------------------------------------
FN_BEGIN Tun_BuildLuts, 0
    xor  ecx, ecx
bl_lp:
    mov  eax, ecx
    shr  eax, 1
    add  eax, ecx
    add  eax, 96                           ; cushion: 96 at the edge .. 256 in the middle
    cmp  eax, 256
    jbe  bl_fill
    mov  eax, 256
bl_fill:
    lea  rdx, tunFill
    mov  DWORD PTR [rdx+rcx*4], eax
    xor  r8d, r8d                          ; line intensity
    mov  eax, LINE_W
    sub  eax, ecx
    jbe  bl_line
    imul eax, eax                          ; (W - d)^2 * 255 / W^2
    imul eax, eax, 255
    xor  edx, edx
    mov  r9d, LINE_W * LINE_W
    div  r9d
    mov  r8d, eax
bl_line:
    mov  eax, r8d                          ; cyan-white: R = 0.5 g, G = 0.8 g, B = g
    shr  eax, 1
    shl  eax, 16
    imul edx, r8d, 205
    shr  edx, 8
    shl  edx, 8
    or   eax, edx
    or   eax, r8d
    lea  rdx, tunLine
    mov  DWORD PTR [rdx+rcx*4], eax
    inc  ecx
    cmp  ecx, 128
    jb   bl_lp
    FN_RET
FN_END Tun_BuildLuts

; ---------------------------------------------------------------------------
; Tun_BuildTables - angle, depth and fog for every pixel of the padded screen.
; Locals: +0 dx, +4 dy, +8 r.
; ---------------------------------------------------------------------------
FN_BEGIN Tun_BuildTables, 16
    xor  r12d, r12d                        ; table row
    xor  r13d, r13d                        ; running index
tt_row:
    cvtsi2ss xmm1, r12d
    addss xmm1, DWORD PTR kTHalf
    subss xmm1, DWORD PTR kTCenY
    movss DWORD PTR [rsp+LOC+4], xmm1      ; dy
    xor  r14d, r14d                        ; table column
tt_px:
    cvtsi2ss xmm0, r14d
    addss xmm0, DWORD PTR kTHalf
    subss xmm0, DWORD PTR kTCenX
    movss DWORD PTR [rsp+LOC], xmm0        ; dx
    mulss xmm0, xmm0
    movss xmm1, DWORD PTR [rsp+LOC+4]
    mulss xmm1, xmm1
    addss xmm0, xmm1
    sqrtss xmm0, xmm0
    movss DWORD PTR [rsp+LOC+8], xmm0      ; r
    movss xmm0, DWORD PTR [rsp+LOC+4]      ; atan2(dy, dx)
    movss xmm1, DWORD PTR [rsp+LOC]
    call Mth_Atan2f
    mulss xmm0, DWORD PTR kTInv2Pi
    addss xmm0, DWORD PTR kTHalf
    mulss xmm0, DWORD PTR kT65536
    cvttss2si eax, xmm0
    and  eax, 0FFFFh
    lea  rdx, tunU
    mov  WORD PTR [rdx+r13*2], ax
    movss xmm1, DWORD PTR [rsp+LOC+8]      ; depth = D / max(r, 1)
    movss xmm2, DWORD PTR kTOne
    maxss xmm1, xmm2
    movss xmm0, DWORD PTR kTDepth
    divss xmm0, xmm1
    minss xmm0, DWORD PTR kT65535
    cvttss2si eax, xmm0
    lea  rdx, tunV
    mov  WORD PTR [rdx+r13*2], ax
    movss xmm0, DWORD PTR [rsp+LOC+8]      ; fog = smoothstep((r - 6) / 120)
    subss xmm0, DWORD PTR kTFogOff
    mulss xmm0, DWORD PTR kTFogInv
    xorps xmm3, xmm3
    maxss xmm0, xmm3
    minss xmm0, DWORD PTR kTOne
    movaps xmm1, xmm0
    mulss xmm1, DWORD PTR kTTwo
    movss xmm2, DWORD PTR kTThree
    subss xmm2, xmm1
    mulss xmm0, xmm0
    mulss xmm0, xmm2
    mulss xmm0, DWORD PTR kT255
    cvttss2si eax, xmm0
    lea  rdx, tunF
    mov  BYTE PTR [rdx+r13], al
    inc  r13d
    inc  r14d
    cmp  r14d, TUN_W
    jb   tt_px
    inc  r12d
    cmp  r12d, TUN_H
    jb   tt_row
    FN_RET
FN_END Tun_BuildTables

FN_BEGIN Fx_Tunnel_Init, 0
    call Tun_BuildPanels
    call Tun_BuildLuts
    lea  rcx, tunPal
    mov  edx, 256
    lea  r8, tunKeys
    call Pal_FromKeys
    call Tun_BuildTables
    lea  rcx, tunGlow
    mov  edx, GLOW_SZ
    mov  r8d, 2
    call Msk_Radial
    xor  eax, eax
    FN_RET
FN_END Fx_Tunnel_Init

; ---------------------------------------------------------------------------
; Tun_Travel(ecx = local ms) -> eax = position of the camera along the tunnel
; (256 units per panel) at the beat state published by Tl_Update.
; The camera flies steadily, two panels per beat (the beat counter plus the
; phase inside the beat), with a swell of +-20 units that makes it a little
; faster on the beat and slower half a beat later, plus a slow drift.  It
; used to jump two panels on the beat and stand still in between, which read
; as a stutter.  Touches only eax, ecx, edx.
; ---------------------------------------------------------------------------
LEAF_BEGIN Tun_Travel
    imul ecx, ecx, 5
    shr  ecx, 4                            ; slow constant drift
    mov  eax, DWORD PTR gBeatNo
    shl  eax, 9                            ; 512 depth units (2 panels) per beat
    add  eax, ecx
    mov  edx, DWORD PTR gBeat16
    mov  ecx, edx
    shr  ecx, 7                            ; the phase: 0..511 over the beat
    add  eax, ecx
    shr  edx, 4                            ; 4096 steps per beat
    lea  rcx, gSinTab
    movsx edx, WORD PTR [rcx+rdx*2]
    imul edx, 20
    sar  edx, 15                           ; swell of the speed, +-20 units
    add  eax, edx
    ret
LEAF_END Tun_Travel

; ---------------------------------------------------------------------------
; Fx_Tunnel_Render(rcx = fb, edx = local ms)
; The camera flies on at a steady speed (Tun_Travel); gKick only brightens the
; tunnel and its light.  The vanishing point sways.
; ---------------------------------------------------------------------------
FN_BEGIN Fx_Tunnel_Render, 96
    mov  QWORD PTR [rsp+V_FB], rcx
    mov  r15d, edx                         ; t
    mov  ecx, r15d
    call Tun_Travel
    mov  DWORD PTR [rsp+V_DV], eax
    imul eax, r15d, 105
    shr  eax, 6
    mov  DWORD PTR [rsp+V_DU], eax         ; roll: one turn in ~40 s
    imul eax, r15d, 3
    shr  eax, 1
    mov  DWORD PTR [rsp+V_PH], eax         ; twist phase
    lea  rsi, gSinTab
    imul eax, r15d, 600
    shr  eax, 10
    and  eax, 4095
    movsx eax, WORD PTR [rsi+rax*2]
    imul eax, 44
    sar  eax, 15
    mov  DWORD PTR [rsp+V_OX], eax         ; horizontal sway
    imul eax, r15d, 430
    shr  eax, 10
    add  eax, 1000
    and  eax, 4095
    movsx eax, WORD PTR [rsi+rax*2]
    imul eax, 30
    sar  eax, 15
    mov  DWORD PTR [rsp+V_OY], eax         ; vertical sway
    xor  ecx, ecx                          ; fog LUT: the kick brightens the tunnel
tf_lut:
    mov  eax, gKick
    shr  eax, 1
    add  eax, 256
    imul eax, ecx
    shr  eax, 8
    cmp  eax, 256
    jbe  tf_set
    mov  eax, 256
tf_set:
    lea  rdx, tunFog
    mov  DWORD PTR [rdx+rcx*4], eax
    inc  ecx
    cmp  ecx, 256
    jb   tf_lut
    mov  rdi, QWORD PTR [rsp+V_FB]
    lea  rbp, gSinTab
    lea  r10, tunPanel
    lea  r11, tunPal
    xor  r12d, r12d                        ; y
tn_row:
    mov  eax, r12d
    add  eax, TUN_PY
    add  eax, DWORD PTR [rsp+V_OY]
    imul eax, TUN_W
    add  eax, TUN_PX
    add  eax, DWORD PTR [rsp+V_OX]
    cdqe
    lea  rsi, tunU
    lea  rsi, [rsi+rax*2]
    lea  r8, tunV
    lea  r8, [r8+rax*2]
    lea  r9, tunF
    add  r9, rax
    xor  ecx, ecx
tn_px:
    movzx eax, WORD PTR [rsi+rcx*2]        ; angle
    movzx edx, WORD PTR [r8+rcx*2]         ; depth
    add  edx, DWORD PTR [rsp+V_DV]
    mov  ebx, edx
    add  ebx, ebx
    add  ebx, DWORD PTR [rsp+V_PH]
    and  ebx, 4095
    movsx ebx, WORD PTR [rbp+rbx*2]
    sar  ebx, 4                            ; twist, about +-1 panel
    add  eax, ebx
    add  eax, DWORD PTR [rsp+V_DU]
    mov  ebx, eax
    shr  ebx, 11
    and  ebx, 31                           ; panel column
    and  eax, 2047                         ; position inside the panel (u)
    mov  r13d, edx
    shr  r13d, 8
    and  r13d, 15
    shl  r13d, 5
    add  r13d, ebx
    movzx r13d, BYTE PTR [r10+r13]         ; palette index of the panel
    mov  ebx, 2047
    sub  ebx, eax
    cmp  eax, ebx
    cmovb ebx, eax                         ; distance to the nearer vertical edge
    shr  ebx, 3
    and  edx, 255                          ; position inside the panel (v)
    mov  r14d, 255
    sub  r14d, edx
    cmp  edx, r14d
    cmovb r14d, edx                        ; distance to the nearer horizontal edge
    cmp  ebx, r14d
    cmova ebx, r14d                        ; d = min of both, 0..127
    mov  eax, DWORD PTR [r11+r13*4]
    lea  r15, tunFill
    mov  edx, DWORD PTR [r15+rbx*4]
    PIXSCALE eax, edx, r14d
    lea  r15, tunLine
    mov  edx, DWORD PTR [r15+rbx*4]
    PIXADD eax, edx, xmm0, xmm1
    movzx edx, BYTE PTR [r9+rcx]
    lea  r15, tunFog
    mov  edx, DWORD PTR [r15+rdx*4]
    PIXSCALE eax, edx, r14d
    mov  DWORD PTR [rdi], eax
    add  rdi, 4
    inc  ecx
    cmp  ecx, SCR_W
    jb   tn_px
    inc  r12d
    cmp  r12d, SCR_H
    jb   tn_row
    lea  rdi, [rsp+V_DM]                   ; light at the end of the tunnel
    mov  rax, QWORD PTR [rsp+V_FB]
    mov  QWORD PTR [rdi+DMASK.dst], rax
    lea  rax, tunGlow
    mov  QWORD PTR [rdi+DMASK.tx], rax
    mov  eax, SCR_W / 2 - GLOW_SZ / 2
    sub  eax, DWORD PTR [rsp+V_OX]
    mov  DWORD PTR [rdi+DMASK.x], eax
    mov  eax, SCR_H / 2 - GLOW_SZ / 2
    sub  eax, DWORD PTR [rsp+V_OY]
    mov  DWORD PTR [rdi+DMASK.y], eax
    mov  DWORD PTR [rdi+DMASK.color], 00B4D8FFh
    mov  eax, gKick
    shr  eax, 2
    add  eax, 170
    mov  DWORD PTR [rdi+DMASK.alpha], eax
    mov  DWORD PTR [rdi+DMASK.mode], 1
    mov  QWORD PTR [rdi+DMASK.rowPal], 0
    mov  QWORD PTR [rdi+DMASK.rowOff], 0
    mov  rcx, rdi
    call Gfx_DrawMask
    FN_RET
FN_END Fx_Tunnel_Render

END
