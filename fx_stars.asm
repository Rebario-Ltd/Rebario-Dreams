; ============================================================================
; fx_stars.asm - scene 3 "WARP": hyperspace starfield over a layered nebula.
; ----------------------------------------------------------------------------
; Star positions are a pure function of time (camera travel D(t) wraps the
; depth range), so no per-frame state exists.  Every star is drawn as an
; additive streak from its head to the position it had a moment ago; the
; streak length follows the ship speed, which accelerates through the scene.
;   speed(t) = 0.4 + 5 * (t / 15 s)^2     units / ms
;   travel(t) = integral of speed
; ============================================================================
INCLUDE common.inc

STAR_N   EQU 1800
FOCAL    EQU 300
ZMASK    EQU 4095
MAX_STEP EQU 96
GLOW_SZ  EQU 360

; one streak request (all coordinates are screen pixels)
STRK STRUCT
    x0    SDWORD ?
    y0    SDWORD ?
    x1    SDWORD ?
    y1    SDWORD ?
    inten DWORD ?                         ; 0..256 at the head, fades to 0 at the tail
    color DWORD ?                         ; 0x00RRGGBB
STRK ENDS

V_FB     EQU LOC + 0
V_ST     EQU LOC + 8                      ; STRK, 24 bytes
V_CX     EQU LOC + 32
V_CY     EQU LOC + 36
V_D      EQU LOC + 40
V_L      EQU LOC + 44
V_SP     EQU LOC + 48
V_OX1    EQU LOC + 52
V_OY1    EQU LOC + 56
V_OX2    EQU LOC + 60
V_OY2    EQU LOC + 64
V_DM     EQU LOC + 72                     ; DMASK, 56 bytes

.const
ALIGN 16
nebKeysA DWORD 5
         DWORD 0 * 257,   0000000Ah
         DWORD 90 * 257,  0005103Ah
         DWORD 150 * 257, 000A3A5Ah
         DWORD 200 * 257, 001C2A7Ah
         DWORD 65536,     003A4AA8h
nebKeysB DWORD 4
         DWORD 0 * 257,   00000000h
         DWORD 120 * 257, 0014063Ah
         DWORD 190 * 257, 004A1070h
         DWORD 65536,     009A2A9Ah
hueTab   DWORD 00C8DCFFh, 00FFFFFFh, 00FFF0B4h, 00FFB478h
         DWORD 0096B4FFh, 00A0F0FFh, 00FFB4DCh, 00E8E8FFh

.data?
ALIGN 16
strNeb   BYTE 262144 DUP (?)              ; 512 x 512 tileable cloud noise
strPalA  DWORD 256 DUP (?)
strPalB  DWORD 256 DUP (?)
strGlow  BYTE 16 DUP (?)                  ; TXMASK
strData  BYTE STAR_N * 8 DUP (?)          ; { SWORD x, SWORD y, WORD z0, BYTE bri, BYTE hue }

.code

; ---------------------------------------------------------------------------
; Fx_Stars_Init - nebula texture, palettes, star table, glow sprite.
; ---------------------------------------------------------------------------
FN_BEGIN Fx_Stars_Init, 0
    lea  rcx, strNeb
    mov  edx, 9
    mov  r8d, 7
    mov  r9d, 5 OR (31 SHL 8)
    call Mth_Fbm
    lea  rcx, strPalA
    mov  edx, 256
    lea  r8, nebKeysA
    call Pal_FromKeys
    lea  rcx, strPalB
    mov  edx, 256
    lea  r8, nebKeysB
    call Pal_FromKeys
    mov  ecx, 0C0FFEEh
    call Mth_Seed
    lea  rdi, strData
    xor  ebx, ebx
si_lp:
    call Mth_Rand
    shr  eax, 20
    sub  eax, 2048
    mov  WORD PTR [rdi], ax                ; x
    call Mth_Rand
    shr  eax, 20
    sub  eax, 2048
    mov  WORD PTR [rdi+2], ax              ; y
    call Mth_Rand
    shr  eax, 20
    mov  WORD PTR [rdi+4], ax              ; z0
    call Mth_Rand
    mov  ecx, eax
    and  ecx, 127
    add  ecx, 100
    mov  BYTE PTR [rdi+6], cl              ; brightness 100..227
    shr  eax, 8
    and  eax, 7
    mov  BYTE PTR [rdi+7], al              ; colour class
    add  rdi, 8
    inc  ebx
    cmp  ebx, STAR_N
    jb   si_lp
    lea  rcx, strGlow
    mov  edx, GLOW_SZ
    mov  r8d, 2
    call Msk_Radial
    xor  eax, eax
    FN_RET
FN_END Fx_Stars_Init

; ---------------------------------------------------------------------------
; Str_Streak(rcx = fb, rdx = STRK *) - additive line, linear fade head -> tail.
; At most MAX_STEP pixels are drawn, starting at the head.
; ---------------------------------------------------------------------------
FN_BEGIN Str_Streak, 0
    mov  rdi, rcx
    mov  rsi, rdx
    mov  r12d, DWORD PTR [rsi+STRK.x1]
    sub  r12d, DWORD PTR [rsi+STRK.x0]     ; dx
    mov  r13d, DWORD PTR [rsi+STRK.y1]
    sub  r13d, DWORD PTR [rsi+STRK.y0]     ; dy
    mov  eax, r12d
    cdq
    xor  eax, edx
    sub  eax, edx                          ; |dx|
    mov  ecx, r13d
    mov  edx, ecx
    sar  edx, 31
    xor  ecx, edx
    sub  ecx, edx                          ; |dy|
    cmp  eax, ecx
    cmovb eax, ecx
    mov  r15d, eax                         ; m = major axis length
    test r15d, r15d
    jnz  sk_m
    mov  r15d, 1
sk_m:
    mov  r14d, r15d                        ; steps
    cmp  r14d, MAX_STEP
    jbe  sk_steps
    mov  r14d, MAX_STEP
sk_steps:
    mov  eax, r12d
    shl  eax, 16
    cdq
    idiv r15d
    mov  r12d, eax                         ; x step, 16.16 per pixel of the major axis
    mov  eax, r13d
    shl  eax, 16
    cdq
    idiv r15d
    mov  r13d, eax                         ; y step
    mov  ebx, DWORD PTR [rsi+STRK.x0]
    shl  ebx, 16
    add  ebx, 8000h
    mov  ebp, DWORD PTR [rsi+STRK.y0]
    shl  ebp, 16
    add  ebp, 8000h
    mov  r10d, DWORD PTR [rsi+STRK.inten]
    shl  r10d, 8
    mov  eax, r10d
    xor  edx, edx
    lea  ecx, [r14+1]
    div  ecx
    mov  r11d, eax                         ; intensity decrement per step
    mov  r9d, DWORD PTR [rsi+STRK.color]
    xor  esi, esi
sk_lp:
    mov  eax, ebx
    sar  eax, 16
    mov  edx, ebp
    sar  edx, 16
    cmp  eax, SCR_W
    jae  sk_skip
    cmp  edx, SCR_H
    jae  sk_skip
    imul edx, SCR_W
    add  edx, eax
    mov  ecx, r10d
    shr  ecx, 8
    mov  eax, r9d
    PIXSCALE eax, ecx, r8d
    movd xmm0, eax
    movd xmm1, DWORD PTR [rdi+rdx*4]
    paddusb xmm0, xmm1
    movd DWORD PTR [rdi+rdx*4], xmm0
sk_skip:
    add  ebx, r12d
    add  ebp, r13d
    sub  r10d, r11d
    inc  esi
    cmp  esi, r14d
    jbe  sk_lp
    FN_RET
FN_END Str_Streak

; ---------------------------------------------------------------------------
; Str_Nebula(rcx = fb, edx = local ms) - two drifting cloud layers.
; ---------------------------------------------------------------------------
FN_BEGIN Str_Nebula, 0
    mov  rdi, rcx
    mov  r13d, edx
    shr  r13d, 6                           ; layer 1 drift in x (texels)
    mov  r14d, edx
    shr  r14d, 8                           ; layer 1 drift in y
    mov  r15d, edx
    shr  r15d, 5                           ; layer 2 drifts faster (parallax)
    lea  r8, strNeb
    lea  r9, strPalA
    lea  r10, strPalB
    xor  r12d, r12d                        ; y
sn_row:
    lea  eax, [r12+r14]
    and  eax, 511
    shl  eax, 9
    lea  rsi, [r8+rax]                     ; layer 1 row
    mov  eax, r12d
    shl  eax, 1
    add  eax, 40
    and  eax, 511
    shl  eax, 9
    lea  rbp, [r8+rax]                     ; layer 2 row (2x zoom)
    xor  ecx, ecx
sn_px:
    lea  eax, [rcx+r13]
    and  eax, 511
    movzx eax, BYTE PTR [rsi+rax]
    mov  eax, DWORD PTR [r9+rax*4]
    lea  edx, [rcx*2+r15]
    and  edx, 511
    movzx edx, BYTE PTR [rbp+rdx]
    mov  edx, DWORD PTR [r10+rdx*4]
    PIXADD eax, edx, xmm0, xmm1
    mov  DWORD PTR [rdi], eax
    add  rdi, 4
    inc  ecx
    cmp  ecx, SCR_W
    jb   sn_px
    inc  r12d
    cmp  r12d, SCR_H
    jb   sn_row
    FN_RET
FN_END Str_Nebula

; ---------------------------------------------------------------------------
; Str_Params(edx = local ms) - speed, travel and streak length into the
; caller-visible statics (strSpeed, strTravel, strLen).
; ---------------------------------------------------------------------------
.data?
strSpeed  DWORD ?                         ; units/ms * 256
strTravel DWORD ?                         ; travel modulo the depth range
strLen    DWORD ?                         ; streak length in depth units

.code
FN_BEGIN Str_Params, 0
    mov  r8d, edx                          ; t
    mov  r9, r8
    imul r9, r8                            ; t^2
    mov  r10, r9
    imul r10, r8                           ; t^3
    imul rax, r9, 1280
    xor  edx, edx
    mov  rcx, 225000000
    div  rcx
    add  eax, 102
    mov  strSpeed, eax                     ; 0.4 + 5 * (t / 15000)^2, x256
    imul eax, 40
    shr  eax, 8                            ; 40 ms of travel
    cmp  eax, 8
    jae  sp_len
    mov  eax, 8
sp_len:
    mov  strLen, eax                       ; ~40 ms of travel
    imul rax, r10, 1280
    xor  edx, edx
    mov  rcx, 675000000
    div  rcx
    imul rcx, r8, 102
    add  rax, rcx
    shr  rax, 8
    and  eax, ZMASK
    mov  strTravel, eax
    FN_RET
FN_END Str_Params

; ---------------------------------------------------------------------------
; Fx_Stars_Render(rcx = fb, edx = local ms)
; ---------------------------------------------------------------------------
FN_BEGIN Fx_Stars_Render, 160
    mov  QWORD PTR [rsp+V_FB], rcx
    mov  r15d, edx
    call Str_Params
    lea  rsi, gSinTab
    imul eax, r15d, 410
    shr  eax, 10
    and  eax, 4095
    movsx eax, WORD PTR [rsi+rax*2]
    imul eax, 16
    sar  eax, 15
    add  eax, SCR_W / 2
    mov  DWORD PTR [rsp+V_CX], eax         ; camera sway
    imul eax, r15d, 317
    shr  eax, 10
    add  eax, 900
    and  eax, 4095
    movsx eax, WORD PTR [rsi+rax*2]
    imul eax, 10
    sar  eax, 15
    add  eax, SCR_H / 2
    mov  DWORD PTR [rsp+V_CY], eax
    mov  rcx, QWORD PTR [rsp+V_FB]
    mov  edx, r15d
    call Str_Nebula
    lea  rsi, strData
    xor  r12d, r12d
sr_lp:
    movzx ecx, WORD PTR [rsi+4]
    sub  ecx, strTravel
    and  ecx, ZMASK                        ; depth of the head
    cmp  ecx, 24
    jb   sr_next
    movsx eax, WORD PTR [rsi]
    imul eax, FOCAL
    mov  r8d, eax                          ; x * F
    movsx eax, WORD PTR [rsi+2]
    imul eax, FOCAL
    mov  r9d, eax                          ; y * F
    mov  eax, r8d
    cdq
    idiv ecx
    mov  r10d, eax                         ; head offset x
    mov  eax, r9d
    cdq
    idiv ecx
    mov  r11d, eax                         ; head offset y
    lea  eax, [r10+440]
    cmp  eax, 880
    ja   sr_next
    lea  eax, [r11+280]
    cmp  eax, 560
    ja   sr_next
    mov  ebx, ecx
    add  ebx, strLen                       ; depth of the tail
    mov  eax, r8d
    cdq
    idiv ebx
    mov  r13d, eax                         ; tail offset x
    mov  eax, r9d
    cdq
    idiv ebx
    mov  r14d, eax                         ; tail offset y
    mov  eax, ZMASK
    sub  eax, ecx
    shr  eax, 4                            ; nearness 0..255
    movzx edx, BYTE PTR [rsi+6]
    imul eax, edx
    shr  eax, 8                            ; base intensity
    cmp  ecx, 700
    jae  sr_kick
    mov  edx, 700
    sub  edx, ecx
    shr  edx, 2
    add  eax, edx                          ; very close stars flare
sr_kick:
    mov  edx, gKick
    imul edx, eax
    shr  edx, 9
    add  eax, edx
    cmp  eax, 256
    jbe  sr_fill
    mov  eax, 256
sr_fill:
    lea  rdi, [rsp+V_ST]
    mov  DWORD PTR [rdi+STRK.inten], eax
    mov  eax, DWORD PTR [rsp+V_CX]
    lea  edx, [rax+r10]
    mov  DWORD PTR [rdi+STRK.x0], edx
    add  eax, r13d
    mov  DWORD PTR [rdi+STRK.x1], eax
    mov  eax, DWORD PTR [rsp+V_CY]
    lea  edx, [rax+r11]
    mov  DWORD PTR [rdi+STRK.y0], edx
    add  eax, r14d
    mov  DWORD PTR [rdi+STRK.y1], eax
    movzx eax, BYTE PTR [rsi+7]
    lea  rdx, hueTab
    mov  eax, DWORD PTR [rdx+rax*4]
    mov  DWORD PTR [rdi+STRK.color], eax
    mov  rcx, QWORD PTR [rsp+V_FB]
    mov  rdx, rdi
    call Str_Streak
sr_next:
    add  rsi, 8
    inc  r12d
    cmp  r12d, STAR_N
    jb   sr_lp
    lea  rdi, [rsp+V_DM]                   ; hyperspace glow, grows with speed
    mov  rax, QWORD PTR [rsp+V_FB]
    mov  QWORD PTR [rdi+DMASK.dst], rax
    lea  rax, strGlow
    mov  QWORD PTR [rdi+DMASK.tx], rax
    mov  eax, DWORD PTR [rsp+V_CX]
    sub  eax, GLOW_SZ / 2
    mov  DWORD PTR [rdi+DMASK.x], eax
    mov  eax, DWORD PTR [rsp+V_CY]
    sub  eax, GLOW_SZ / 2
    mov  DWORD PTR [rdi+DMASK.y], eax
    mov  DWORD PTR [rdi+DMASK.color], 00A8C8FFh
    mov  eax, strSpeed
    shr  eax, 3
    mov  edx, gKick
    shr  edx, 3
    add  eax, edx
    cmp  eax, 230
    jbe  sr_alpha
    mov  eax, 230
sr_alpha:
    mov  DWORD PTR [rdi+DMASK.alpha], eax
    mov  DWORD PTR [rdi+DMASK.mode], 1
    mov  QWORD PTR [rdi+DMASK.rowPal], 0
    mov  QWORD PTR [rdi+DMASK.rowOff], 0
    mov  rcx, rdi
    call Gfx_DrawMask
    FN_RET
FN_END Fx_Stars_Render

END
