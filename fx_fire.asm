; ============================================================================
; fx_fire.asm - scene 6 "INFERNO": a burning title.
; ----------------------------------------------------------------------------
; A 160 x 90 heat field is advanced in fixed 33 ms ticks: every cell takes the
; average of four cells in the rows below it (a slow sideways "wind" bends the
; flames), cools slightly and is replaced at the bottom by random fuel; the
; letters of the title inject heat as well, so flames lick up from them.
; Heat only ever flows upwards, so after FIRE_WARM (>= rows) ticks the field
; no longer depends on its initial state: a seek or a screenshot simply
; clears the field and replays the last FIRE_WARM ticks, giving exactly the
; picture continuous playback would show (the scene stays a pure function of
; time).  The heat is mapped through a black-body palette, enlarged 4x with
; two bilinear passes, and overlaid with the crisp letters (heat-haze
; wobble), a glow and rising embers.
; ============================================================================
INCLUDE common.inc

FIRE_W     EQU 160
FIRE_H     EQU 90
FIRE_STR   EQU 164                       ; row stride: 2 margin cells each side
FIRE_ROWS  EQU FIRE_H + 2                ; two hidden source rows below the picture
FIRE_TICK  EQU 33                        ; ms per simulation step
FIRE_WARM  EQU 100                       ; steps replayed after a seek
FIRE_K     EQU 61                        ; four-tap sum * K / 256 (cooling per row)
FIRE_LIGHT EQU 70                        ; tick at which the letters ignite (2.3 s)
TXT_CY     EQU 232                       ; centre row of the title
EMB_N      EQU 72
EMB_COL    EQU 00FF8A28h

; Fills fireDm (rax) for one Gfx_DrawMask call; the caller loads rcx and calls.
FDM_SET MACRO txm:REQ, col:REQ, alp:REQ, md:REQ
    lea  rax, fireDm
    mov  QWORD PTR [rax+DMASK.dst], r12
    lea  rcx, txm
    mov  QWORD PTR [rax+DMASK.tx], rcx
    mov  ecx, DWORD PTR fireTx
    mov  DWORD PTR [rax+DMASK.x], ecx
    mov  ecx, DWORD PTR fireTy
    mov  DWORD PTR [rax+DMASK.y], ecx
    mov  DWORD PTR [rax+DMASK.color], col
    mov  DWORD PTR [rax+DMASK.alpha], alp
    mov  DWORD PTR [rax+DMASK.mode], md
    lea  rcx, fireOff
    mov  QWORD PTR [rax+DMASK.rowOff], rcx
    mov  QWORD PTR [rax+DMASK.rowPal], 0
ENDM

.const
ALIGN 16
; black body: near-black red, dark red, red, orange, amber, yellow, pale, white
fireKeys    DWORD 8
            DWORD 0,     000C0204h
            DWORD 9000,  00400806h
            DWORD 20000, 00B01808h
            DWORD 31000, 00F04A10h
            DWORD 41000, 00FF9A1Eh
            DWORD 51000, 00FFD850h
            DWORD 59500, 00FFF4B0h
            DWORD 65536, 00FFFFFFh
fireTxtKeys DWORD 4
            DWORD 0,     00FFFBE8h
            DWORD 20000, 00FFE264h
            DWORD 44000, 00FF9422h
            DWORD 65536, 00E04010h
szFire      BYTE "ASSEMBLY", 0

.data
fireTick    DWORD 0                      ; tick the heat field is valid for
fireValid   DWORD 0
fireTx      DWORD 0                      ; title mask position
fireTy      DWORD 0

.data?
ALIGN 16
fireHeat    BYTE FIRE_STR * FIRE_ROWS DUP (?)
ALIGN 16
fireFuel    BYTE FIRE_W * FIRE_H DUP (?)
ALIGN 16
fireImg     DWORD FIRE_W * FIRE_H DUP (?)
ALIGN 16
fireMid     DWORD FIRE_W * 2 * FIRE_H * 2 DUP (?)
firePal     DWORD 256 DUP (?)
fireRowPal  DWORD 256 DUP (?)
fireOff     DWORD 256 DUP (?)
fireTxt     BYTE 16 DUP (?)              ; TXMASK: letters
fireGlow    BYTE 16 DUP (?)              ; TXMASK: tight glow
fireHalo    BYTE 16 DUP (?)              ; TXMASK: wide dark halo
fireReq     BYTE 48 DUP (?)              ; FONTREQ
fireDm      BYTE 64 DUP (?)              ; DMASK

.code

; ---------------------------------------------------------------------------
; Fire_BuildFuel - downsamples the letters (4 x 4 boxes) to the heat grid.
; ---------------------------------------------------------------------------
FN_BEGIN Fire_BuildFuel, 0
    lea  rax, fireTxt
    mov  r12, QWORD PTR [rax+TXMASK.pix]
    mov  r13d, DWORD PTR [rax+TXMASK.w]
    mov  r14d, DWORD PTR [rax+TXMASK.h]
    lea  rdi, fireFuel
    xor  esi, esi                          ; gy
bf_gy:
    xor  ebx, ebx                          ; gx
bf_gx:
    xor  ebp, ebp                          ; coverage sum
    xor  r8d, r8d                          ; dy
bf_dy:
    mov  eax, esi
    shl  eax, 2
    add  eax, r8d
    sub  eax, DWORD PTR fireTy             ; row inside the mask
    cmp  eax, r14d
    jae  bf_dyn
    imul eax, r13d
    xor  r9d, r9d                          ; dx
bf_dx:
    mov  ecx, ebx
    shl  ecx, 2
    add  ecx, r9d
    sub  ecx, DWORD PTR fireTx             ; column inside the mask
    cmp  ecx, r13d
    jae  bf_dxn
    add  ecx, eax
    movzx edx, BYTE PTR [r12+rcx]
    add  ebp, edx
bf_dxn:
    inc  r9d
    cmp  r9d, 4
    jb   bf_dx
bf_dyn:
    inc  r8d
    cmp  r8d, 4
    jb   bf_dy
    shr  ebp, 4
    mov  BYTE PTR [rdi], bpl
    inc  rdi
    inc  ebx
    cmp  ebx, FIRE_W
    jb   bf_gx
    inc  esi
    cmp  esi, FIRE_H
    jb   bf_gy
    FN_RET
FN_END Fire_BuildFuel

FN_BEGIN Fx_Fire_Init, 0
    lea  rcx, firePal
    mov  edx, 256
    lea  r8, fireKeys
    call Pal_FromKeys
    lea  rsi, fireReq
    lea  rax, fireTxt
    mov  QWORD PTR [rsi+FONTREQ.dst], rax
    lea  rax, szFire
    mov  QWORD PTR [rsi+FONTREQ.text], rax
    mov  DWORD PTR [rsi+FONTREQ.height], 104
    mov  DWORD PTR [rsi+FONTREQ.weight], 400
    mov  DWORD PTR [rsi+FONTREQ.face], 3
    mov  DWORD PTR [rsi+FONTREQ.italic], 0
    mov  DWORD PTR [rsi+FONTREQ.track], 8
    mov  rcx, rsi
    call Font_Render
    lea  rcx, fireTxt
    lea  rdx, fireGlow
    mov  r8d, 4
    call Font_Glow
    lea  rcx, fireTxt
    lea  rdx, fireHalo
    mov  r8d, 8
    call Font_Glow
    lea  rbx, fireTxt
    mov  eax, SCR_W
    sub  eax, DWORD PTR [rbx+TXMASK.w]
    shr  eax, 1
    mov  DWORD PTR fireTx, eax
    mov  eax, DWORD PTR [rbx+TXMASK.h]
    shr  eax, 1
    mov  edx, TXT_CY
    sub  edx, eax
    mov  DWORD PTR fireTy, edx
    lea  rcx, fireTxt                      ; letter gradient over the glyph body
    lea  rdx, fireRowPal
    lea  r8, fireTxtKeys
    call Font_RowPal
    call Fire_BuildFuel
    xor  eax, eax
    FN_RET
FN_END Fx_Fire_Init

; ---------------------------------------------------------------------------
; Fire_Step(ecx = tick) - one simulation step (deterministic in the tick).
; r13d = xorshift-free LCG state seeded from a hash of the tick.
; ---------------------------------------------------------------------------
FN_BEGIN Fire_Step, 0
    mov  r12d, ecx
    xor  edx, edx
    mov  r8d, 77
    call Mth_Hash2
    mov  r13d, eax
    lea  r15, gSinTab
    lea  rbx, fireHeat
    lea  rdi, [rbx + FIRE_H * FIRE_STR + 2]
    xor  ecx, ecx
fs_src:                                    ; fuel in the two hidden rows
    imul r13d, r13d, 1664525
    add  r13d, 1013904223
    mov  r8d, r13d
    shr  r8d, 25
    add  r8d, 130                          ; raw fuel 130..257
    imul eax, ecx, 53                      ; slow envelope: tall and short burners
    imul edx, r12d, 23
    add  eax, edx
    and  eax, 4095
    movsx eax, WORD PTR [r15+rax*2]
    imul edx, ecx, 29
    imul r9d, r12d, 17
    sub  edx, r9d
    and  edx, 4095
    movsx edx, WORD PTR [r15+rdx*2]
    add  eax, edx
    sar  eax, 10                           ; +-64
    add  eax, 176                          ; 112..240
    imul eax, r8d
    shr  eax, 8
    mov  edx, 255
    cmp  eax, edx
    cmova eax, edx
    mov  BYTE PTR [rdi+rcx], al
    mov  BYTE PTR [rdi+rcx+FIRE_STR], al
    inc  ecx
    cmp  ecx, FIRE_W
    jb   fs_src
    lea  rdi, [rbx + 2]                    ; row 0, column 0
    xor  esi, esi                          ; y
fs_row:
    imul r14d, esi, 300                    ; wind phase of this row
    imul ebp, r12d, 41
    add  r14d, ebp
    xor  ecx, ecx
fs_px:
    imul eax, ecx, 85                      ; diagonal bands of sideways wind
    add  eax, r14d
    and  eax, 4095
    movsx eax, WORD PTR [r15+rax*2]
    xor  edx, edx
    cmp  eax, 16000
    jle  fs_w1
    mov  edx, 1
fs_w1:
    cmp  eax, -16000
    jge  fs_w2
    mov  edx, -1
fs_w2:
    lea  r8, [rdi+rcx+FIRE_STR]
    movsxd rdx, edx
    add  r8, rdx                           ; cell below, shifted by the wind
    movzx eax, BYTE PTR [r8-1]
    movzx edx, BYTE PTR [r8]
    add  eax, edx
    movzx edx, BYTE PTR [r8+1]
    add  eax, edx
    movzx edx, BYTE PTR [r8+FIRE_STR]
    add  eax, edx
    imul eax, FIRE_K
    shr  eax, 8
    imul r13d, r13d, 1664525
    add  r13d, 1013904223
    mov  edx, r13d
    shr  edx, 30                           ; random cooling 0..3
    sub  eax, edx
    jns  fs_st
    xor  eax, eax
fs_st:
    mov  BYTE PTR [rdi+rcx], al
    inc  ecx
    cmp  ecx, FIRE_W
    jb   fs_px
    add  rdi, FIRE_STR
    inc  esi
    cmp  esi, FIRE_H
    jb   fs_row
    cmp  r12d, FIRE_LIGHT                  ; the letters ignite at 2.3 s
    jl   fs_done
    lea  rsi, fireFuel
    lea  rdi, [rbx + 2]
    xor  edx, edx                          ; y
fs_fy:
    xor  ecx, ecx
fs_fx:
    movzx eax, BYTE PTR [rsi+rcx]
    cmp  eax, 40
    jb   fs_fn
    imul r13d, r13d, 1664525
    add  r13d, 1013904223
    shr  eax, 3
    add  eax, 160
    mov  r8d, r13d
    shr  r8d, 28
    add  eax, r8d                          ; 160..206
    imul r8d, ecx, 61                      ; envelope: tall and short tongues
    imul r9d, r12d, 29
    add  r8d, r9d
    and  r8d, 4095
    movsx r8d, WORD PTR [r15+r8*2]
    imul r9d, ecx, 37
    imul r10d, r12d, 19
    sub  r9d, r10d
    and  r9d, 4095
    movsx r9d, WORD PTR [r15+r9*2]
    add  r8d, r9d
    sar  r8d, 10                           ; +-64
    add  r8d, 192                          ; 128..256
    imul eax, r8d
    shr  eax, 8
    movzx r9d, BYTE PTR [rdi+rcx]
    cmp  r9d, eax
    cmovb r9d, eax
    mov  BYTE PTR [rdi+rcx], r9b
fs_fn:
    inc  ecx
    cmp  ecx, FIRE_W
    jb   fs_fx
    add  rsi, FIRE_W
    add  rdi, FIRE_STR
    inc  edx
    cmp  edx, FIRE_H
    jb   fs_fy
fs_done:
    FN_RET
FN_END Fire_Step

; ---------------------------------------------------------------------------
; Fire_Sync(ecx = tick) - brings the heat field to the given tick: steps
; forward during normal playback, replays FIRE_WARM ticks after a seek.
; ---------------------------------------------------------------------------
FN_BEGIN Fire_Sync, 0
    mov  r12d, ecx
    cmp  DWORD PTR fireValid, 0
    je   fy_rebuild
    mov  eax, r12d
    sub  eax, DWORD PTR fireTick
    js   fy_rebuild
    cmp  eax, 6
    ja   fy_rebuild
    mov  ebx, DWORD PTR fireTick
    jmp  fy_check
fy_rebuild:
    lea  rdi, fireHeat
    xor  eax, eax
    mov  ecx, FIRE_STR * FIRE_ROWS / 4
    rep  stosd
    mov  ebx, r12d
    sub  ebx, FIRE_WARM
fy_check:
    cmp  ebx, r12d
    jge  fy_done
    inc  ebx
    mov  ecx, ebx
    call Fire_Step
    jmp  fy_check
fy_done:
    mov  DWORD PTR fireTick, r12d
    mov  DWORD PTR fireValid, 1
    FN_RET
FN_END Fire_Sync

; ---------------------------------------------------------------------------
; Fire_Colorize - heat (+ a kick boost) through the palette into fireImg.
; ---------------------------------------------------------------------------
FN_BEGIN Fire_Colorize, 0
    lea  rsi, fireHeat
    add  rsi, 2
    lea  rdi, fireImg
    lea  r8, firePal
    mov  r9d, gKick
    shr  r9d, 4                            ; boost 0..16
    xor  edx, edx
cz_row:
    xor  ecx, ecx
cz_px:
    movzx eax, BYTE PTR [rsi+rcx]
    add  eax, r9d
    mov  r10d, 255
    cmp  eax, r10d
    cmova eax, r10d
    mov  eax, DWORD PTR [r8+rax*4]
    mov  DWORD PTR [rdi], eax
    add  rdi, 4
    inc  ecx
    cmp  ecx, FIRE_W
    jb   cz_px
    add  rsi, FIRE_STR
    inc  edx
    cmp  edx, FIRE_H
    jb   cz_row
    FN_RET
FN_END Fire_Colorize

; ---------------------------------------------------------------------------
; Fire_Text(rcx = fb, edx = t) - dark halo, orange glow and the glowing
; letters; the rows wobble like air above a flame.
; ---------------------------------------------------------------------------
FN_BEGIN Fire_Text, 0
    mov  r12, rcx
    mov  r13d, edx
    mov  ecx, r13d
    sub  ecx, 2300
    jle  ft_done
    shl  ecx, 8
    mov  eax, ecx
    xor  edx, edx
    mov  ecx, 600
    div  ecx
    mov  edx, 256
    cmp  eax, edx
    cmova eax, edx
    mov  r14d, eax                         ; opacity
    lea  rax, fireTxt
    mov  esi, DWORD PTR [rax+TXMASK.h]
    lea  rdi, fireOff
    xor  ebx, ebx
ft_row:
    imul eax, ebx, 110
    mov  ecx, r13d
    imul ecx, 6
    add  eax, ecx
    and  eax, 4095
    lea  rdx, gSinTab
    movsx eax, WORD PTR [rdx+rax*2]
    imul eax, 3
    sar  eax, 16                           ; heat haze, +-1 px
    mov  DWORD PTR [rdi+rbx*4], eax
    inc  ebx
    cmp  ebx, esi
    jb   ft_row
    imul ebx, r14d, 200
    shr  ebx, 8
    FDM_SET fireHalo, 00180400h, ebx, 0
    mov  rcx, rax
    call Gfx_DrawMask
    mov  ebx, gKick
    shr  ebx, 2
    add  ebx, 90
    imul ebx, r14d
    shr  ebx, 8
    FDM_SET fireGlow, 00FF5A10h, ebx, 1
    mov  rcx, rax
    call Gfx_DrawMask
    FDM_SET fireTxt, 00FFFFFFh, r14d, 0
    lea  rcx, fireRowPal
    mov  QWORD PTR [rax+DMASK.rowPal], rcx
    mov  rcx, rax
    call Gfx_DrawMask
ft_done:
    FN_RET
FN_END Fire_Text

; ---------------------------------------------------------------------------
; Fire_Embers(rcx = fb, edx = t) - sparks rising on their own cycles; every
; value derives from a hash of the spark index and the time.
; ---------------------------------------------------------------------------
FN_BEGIN Fire_Embers, 0
    mov  r12, rcx
    mov  r13d, edx
    xor  ebx, ebx
em_lp:
    mov  ecx, ebx
    mov  edx, 1
    mov  r8d, 55
    call Mth_Hash2
    mov  r14d, eax                         ; h1: column, phase
    mov  ecx, ebx
    mov  edx, 2
    mov  r8d, 56
    call Mth_Hash2
    mov  r15d, eax                         ; h2: period, speed
    mov  ebp, r15d
    and  ebp, 2047
    add  ebp, 2200                         ; period 2200..4247 ms
    movzx eax, r14w
    add  eax, r13d
    xor  edx, edx
    div  ebp
    mov  esi, edx                          ; age inside the cycle
    mov  eax, esi
    shl  eax, 8
    xor  edx, edx
    div  ebp
    mov  edi, eax                          ; progress 0..255
    mov  eax, r15d
    shr  eax, 12
    and  eax, 63
    add  eax, 300
    imul eax, esi
    xor  edx, edx
    div  ebp
    mov  r9d, 350
    sub  r9d, eax                          ; row
    mov  eax, r14d
    shr  eax, 16
    imul eax, SCR_W
    shr  eax, 16
    mov  r10d, eax                         ; column
    mov  eax, esi
    shr  eax, 3
    imul edx, ebx, 97
    add  eax, edx
    and  eax, 4095
    lea  rdx, gSinTab
    movsx eax, WORD PTR [rdx+rax*2]
    imul eax, 22
    sar  eax, 15
    add  r10d, eax                         ; sway
    lea  ecx, [r10-1]
    cmp  ecx, SCR_W - 3
    ja   em_next
    lea  ecx, [r9-1]
    cmp  ecx, SCR_H - 3
    ja   em_next
    mov  eax, 256
    sub  eax, edi
    imul eax, eax
    shr  eax, 8                            ; fades out quadratically
    mov  ecx, r13d
    shr  ecx, 1
    imul edx, ebx, 131
    add  ecx, edx
    and  ecx, 4095
    lea  rdx, gSinTab
    movsx ecx, WORD PTR [rdx+rcx*2]
    imul ecx, 86
    sar  ecx, 15
    add  ecx, 170                          ; flicker 84..256
    imul eax, ecx
    shr  eax, 8
    mov  r11d, eax
    mov  eax, r9d
    imul eax, SCR_W
    add  eax, r10d
    lea  rcx, [r12+rax*4]
    ADDPIXW rcx, EMB_COL, r11d, eax, edx
    imul r11d, 85
    shr  r11d, 8                           ; neighbours at a third
    lea  r8, [rcx-4]
    ADDPIXW r8, EMB_COL, r11d, eax, edx
    lea  r8, [rcx+4]
    ADDPIXW r8, EMB_COL, r11d, eax, edx
    lea  r8, [rcx-SCR_W*4]
    ADDPIXW r8, EMB_COL, r11d, eax, edx
    lea  r8, [rcx+SCR_W*4]
    ADDPIXW r8, EMB_COL, r11d, eax, edx
em_next:
    inc  ebx
    cmp  ebx, EMB_N
    jb   em_lp
    FN_RET
FN_END Fire_Embers

; ---------------------------------------------------------------------------
; Fx_Fire_Render(rcx = fb, edx = local ms)
; ---------------------------------------------------------------------------
FN_BEGIN Fx_Fire_Render, 16
    mov  QWORD PTR [rsp+LOC], rcx
    mov  DWORD PTR [rsp+LOC+8], edx
    mov  eax, edx
    xor  edx, edx
    mov  ecx, FIRE_TICK
    div  ecx
    mov  ecx, eax
    call Fire_Sync
    call Fire_Colorize
    lea  rcx, fireMid
    lea  rdx, fireImg
    mov  r8d, FIRE_W
    mov  r9d, FIRE_H
    call Gfx_Up2
    mov  rcx, QWORD PTR [rsp+LOC]
    lea  rdx, fireMid
    mov  r8d, FIRE_W * 2
    mov  r9d, FIRE_H * 2
    call Gfx_Up2
    mov  rcx, QWORD PTR [rsp+LOC]
    mov  edx, DWORD PTR [rsp+LOC+8]
    call Fire_Text
    mov  rcx, QWORD PTR [rsp+LOC]
    mov  edx, DWORD PTR [rsp+LOC+8]
    call Fire_Embers
    FN_RET
FN_END Fx_Fire_Render

END
