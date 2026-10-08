; ============================================================================
; fx_title.asm - scene 0 "REBARIO DREAMS": an outrun sunset.
; ----------------------------------------------------------------------------
; Back to front: sky gradient, twinkling stars, sun glow, striped sun, ground
; gradient, sun reflection, two mountain ridges with neon edges, a perspective
; grid locked to the beat, a chrome title that glitches in, subtitle and the
; credit line "created with <heart> by Paul Deecalov (c) 2026".
; The scene is a pure function of its local time: the sun rises during the
; first 3.8 s, the title glitches in at 1.4 s, everything else is periodic.
; ============================================================================
INCLUDE common.inc

HORIZON   EQU 208                         ; first ground row
GROUND_H  EQU SCR_H - HORIZON
SUN_CX    EQU 320
SUN_CY    EQU 160
SUN_R     EQU 94
SUN_RISE  EQU 170                         ; px below its final place at t = 0
STAR_N    EQU 150
STAR_H    EQU 150                         ; stars live above this row
GLOW_SZ   EQU 460
MTN_PAL   EQU 96                          ; rows of shaded rock below a ridge
GRID_K    EQU 1000                        ; perspective constant
GRID_ZS   EQU 1024                        ; grid line spacing in z (8.8)
GRID_Z0   EQU 1536
GRID_N    EQU 34
GRID_NV   EQU 7                           ; vertical lanes each side of the centre
GRID_HCOL EQU 00FF2EA6h
GRID_VCOL EQU 0030D8FFh
REFL_COL  EQU 00FF7A5Ah
TITLE_AT  EQU 1400                        ; title appears (ms)
GLITCH_MS EQU 1300                        ; length of the glitch phase
TXT_CY    EQU 118                         ; centre of the visible letters, not GDI's line box
TITLE_EM  EQU 64                          ; was 50; render larger, never stretch a small bitmap
TITLE_MIN EQU 32                          ; stop if a pathological fallback font cannot fit
TITLE_MAX_W EQU SCR_W - 32                ; includes FONT_PAD on both sides
TITLE_ROWS EQU 256                        ; capacity of the per-row colour / glitch tables
TITLE_GLOW_R EQU 4                        ; was 7: compact neon, not a fog around the letters
TITLE_SUB_GAP EQU 14                      ; minimum gap below the visible title body
SIG_ROW   EQU SCR_H - 40                  ; top row of the credit line canvases

; Renders a string into a mask (rsi = FONTREQ *).
TIT_FONT MACRO dstSym:REQ, textSym:REQ, hgt:REQ, wgt:REQ, fce:REQ, itl:REQ, trk:REQ
    lea  rax, dstSym
    mov  QWORD PTR [rsi+FONTREQ.dst], rax
    lea  rax, textSym
    mov  QWORD PTR [rsi+FONTREQ.text], rax
    mov  DWORD PTR [rsi+FONTREQ.height], hgt
    mov  DWORD PTR [rsi+FONTREQ.weight], wgt
    mov  DWORD PTR [rsi+FONTREQ.face], fce
    mov  DWORD PTR [rsi+FONTREQ.italic], itl
    mov  DWORD PTR [rsi+FONTREQ.track], trk
    mov  rcx, rsi
    call Font_Render
ENDM

; Fills titDm for one Gfx_DrawMask call (px/py/alp/md: registers or immediates).
DM_FILL MACRO txm:REQ, px:REQ, py:REQ, col:REQ, alp:REQ, md:REQ
    lea  rax, titDm
    mov  QWORD PTR [rax+DMASK.dst], r12
    lea  rcx, txm
    mov  QWORD PTR [rax+DMASK.tx], rcx
    mov  DWORD PTR [rax+DMASK.x], px
    mov  DWORD PTR [rax+DMASK.y], py
    mov  DWORD PTR [rax+DMASK.color], col
    mov  DWORD PTR [rax+DMASK.alpha], alp
    mov  DWORD PTR [rax+DMASK.mode], md
ENDM

.const
ALIGN 16
k256f       REAL4 256.0

titSkyKeys  DWORD 6
            DWORD 0,     000A0424h
            DWORD 13000, 00220C56h
            DWORD 28000, 00661A8Ch
            DWORD 43000, 00C8307Eh
            DWORD 55000, 00FF6A58h
            DWORD 65536, 00FFB866h
titGndKeys  DWORD 4
            DWORD 0,     00B02890h
            DWORD 14000, 00441068h
            DWORD 36000, 001A0840h
            DWORD 65536, 000A0422h
titSunKeys  DWORD 5
            DWORD 0,     00FFF8B0h
            DWORD 17500, 00FFD24Ah
            DWORD 36000, 00FF8A3Ah
            DWORD 50000, 00FF3C7Ah
            DWORD 65536, 00D81E9Ch
titMtnKeysA DWORD 3
            DWORD 0,     005A2CA0h
            DWORD 30000, 002A1260h
            DWORD 65536, 00160A34h
titMtnKeysB DWORD 3
            DWORD 0,     002C1068h
            DWORD 30000, 00140A34h
            DWORD 65536, 00080418h
; chrome: white sky, blue, dark horizon band, pink flash, hot pink, magenta
titChromeKeys DWORD 7
            DWORD 0,     00FFFFFFh
            DWORD 19661, 009AD8FFh
            DWORD 30802, 002C4ECCh
            DWORD 32768, 00140C48h
            DWORD 34734, 00FFB0E8h
            DWORD 49152, 00FF4CB0h
            DWORD 65536, 00B8209Ch

; ridge parameters: step1, off1, step2, off2, step3, off3, w1, w2, w3, base, scale0, scaleRange
mtnParamsA  DWORD 7, 300, 19, 1700, 47, 900, 30, 14, 7, 6, 40, 216
mtnParamsB  DWORD 11, 2300, 29, 400, 61, 3300, 22, 10, 5, 4, 20, 236

szTitle     BYTE "REBARIO DREAMS", 0
szSub       BYTE "A 64-BIT ASSEMBLY DEMOSCENE", 0

.data?
ALIGN 16
titSkyPal   DWORD HORIZON DUP (?)
titGndPal   DWORD GROUND_H DUP (?)
titSunPal   DWORD 256 DUP (?)
titMtnPalA  DWORD MTN_PAL DUP (?)
titMtnPalB  DWORD MTN_PAL DUP (?)
titMtnA     WORD SCR_W DUP (?)
titMtnB     WORD SCR_W DUP (?)
titRowPal   DWORD TITLE_ROWS DUP (?)
titOff      DWORD TITLE_ROWS DUP (?)
titInkTop   DWORD ?                       ; first non-empty glyph row
titInkEnd   DWORD ?                       ; exclusive last non-empty glyph row
titSubRow   DWORD ?                       ; subtitle mask origin, derived from the title
ALIGN 8
titMask     BYTE 16 DUP (?)               ; TXMASK: title
titGlow     BYTE 16 DUP (?)               ; TXMASK: blurred title
titOutline  BYTE 16 DUP (?)               ; TXMASK: 1 px dilation, built once at init
titSub      BYTE 16 DUP (?)
titHeartGlow BYTE 16 DUP (?)              ; TXMASK: blurred heart of the credit line
titSunGlow  BYTE 16 DUP (?)
titDm       BYTE 64 DUP (?)               ; DMASK
titReq      BYTE 48 DUP (?)               ; FONTREQ

.code

; ---------------------------------------------------------------------------
; Small leaf helpers
; ---------------------------------------------------------------------------
; Tit_Ramp(ecx = ms since start, edx = duration) -> eax = clamp(ecx * 256 / edx, 0, 256)
LEAF_BEGIN Tit_Ramp
    test ecx, ecx
    jle  rp_zero
    shl  ecx, 8
    mov  eax, ecx
    mov  ecx, edx
    xor  edx, edx
    div  ecx
    cmp  eax, 256
    jbe  rp_ret
    mov  eax, 256
rp_ret:
    ret
rp_zero:
    xor  eax, eax
    ret
LEAF_END Tit_Ramp

; Tit_SunEase(ecx = t) -> eax = smoothstep(t / 3800) * 256
LEAF_BEGIN Tit_SunEase
    mov  eax, ecx
    shl  eax, 8
    xor  edx, edx
    mov  ecx, 3800
    div  ecx
    cmp  eax, 256
    jbe  se_u
    mov  eax, 256
se_u:
    mov  ecx, eax
    imul ecx, ecx
    add  eax, eax
    mov  edx, 768
    sub  edx, eax
    imul ecx, edx
    shr  ecx, 16
    mov  eax, ecx
    ret
LEAF_END Tit_SunEase

; Tit_Ridge(ecx = angle index) -> eax = 32767 - |sin| (pointy peaks)
LEAF_BEGIN Tit_Ridge
    and  ecx, 4095
    lea  rdx, gSinTab
    movsx eax, WORD PTR [rdx+rcx*2]
    cdq
    xor  eax, edx
    sub  eax, edx
    mov  ecx, 32767
    sub  ecx, eax
    mov  eax, ecx
    ret
LEAF_END Tit_Ridge

; Tit_EdgePix(rcx = pixel *, edx = colour, r8d = coverage 0..256) - anti-aliased edge.
LEAF_BEGIN Tit_EdgePix
    mov  eax, DWORD PTR [rcx]
    PIXMIX eax, edx, r8d, r9d, r11d
    mov  DWORD PTR [rcx], eax
    ret
LEAF_END Tit_EdgePix

; ---------------------------------------------------------------------------
; Tit_MtnLayer(rcx = dst WORD[640], rdx = params) - ridged-sine skyline with a
; low valley in the middle of the screen so the sun stays visible.
; ---------------------------------------------------------------------------
FN_BEGIN Tit_MtnLayer, 0
    mov  rdi, rcx
    mov  rsi, rdx
    xor  ebx, ebx
ml_x:
    mov  eax, ebx
    sub  eax, SCR_W / 2
    cdq
    xor  eax, edx
    sub  eax, edx                          ; |x - 320|
    sub  eax, 60
    jns  ml_v1
    xor  eax, eax
ml_v1:
    shl  eax, 8
    xor  edx, edx
    mov  ecx, 170
    div  ecx                               ; (d - 60) * 256 / 170
    cmp  eax, 256
    jbe  ml_v2
    mov  eax, 256
ml_v2:
    mov  ecx, eax
    imul ecx, ecx
    add  eax, eax
    mov  edx, 768
    sub  edx, eax
    imul ecx, edx
    shr  ecx, 16
    mov  r12d, ecx                         ; valley smoothstep 0..256
    mov  ecx, ebx
    imul ecx, DWORD PTR [rsi]
    add  ecx, DWORD PTR [rsi+4]
    call Tit_Ridge
    imul eax, DWORD PTR [rsi+24]
    mov  r13d, eax
    mov  ecx, ebx
    imul ecx, DWORD PTR [rsi+8]
    add  ecx, DWORD PTR [rsi+12]
    call Tit_Ridge
    imul eax, DWORD PTR [rsi+28]
    add  r13d, eax
    mov  ecx, ebx
    imul ecx, DWORD PTR [rsi+16]
    add  ecx, DWORD PTR [rsi+20]
    call Tit_Ridge
    imul eax, DWORD PTR [rsi+32]
    add  r13d, eax
    shr  r13d, 15
    add  r13d, DWORD PTR [rsi+36]          ; + base height
    mov  eax, r12d
    imul eax, DWORD PTR [rsi+44]
    shr  eax, 8
    add  eax, DWORD PTR [rsi+40]           ; scale = s0 + valley * range / 256
    imul eax, r13d
    shr  eax, 8
    mov  WORD PTR [rdi+rbx*2], ax
    inc  ebx
    cmp  ebx, SCR_W
    jb   ml_x
    FN_RET
FN_END Tit_MtnLayer

; ---------------------------------------------------------------------------
; Tit_BuildTitle - a large, width-fitted wordmark without bitmap resampling.
; ---------------------------------------------------------------------------
FN_BEGIN Tit_BuildTitle, 0
    lea  rsi, titReq
    TIT_FONT titMask, szTitle, TITLE_EM, 900, 0, 1, 1
    lea  rcx, titReq
    mov  edx, TITLE_MAX_W
    mov  r8d, TITLE_ROWS
    mov  r9d, TITLE_MIN
    call Font_FitMask
    FN_RET
FN_END Tit_BuildTitle

; ---------------------------------------------------------------------------
; Tit_TitleMetrics - chrome over the actual ink, optical centre and subtitle.
; ---------------------------------------------------------------------------
FN_BEGIN Tit_TitleMetrics, 0
    lea  rcx, titMask
    lea  rdx, titRowPal
    lea  r8, titChromeKeys
    call Font_RowPalInk
    mov  titInkTop, eax
    mov  titInkEnd, edx
    add  eax, edx
    shr  eax, 1
    mov  ecx, TXT_CY
    sub  ecx, eax
    add  ecx, edx
    add  ecx, TITLE_SUB_GAP - FONT_PAD
    mov  titSubRow, ecx
    FN_RET
FN_END Tit_TitleMetrics

; ---------------------------------------------------------------------------
; Tit_BuildOutline - shares the wordmark contour operation with the finale.
; ---------------------------------------------------------------------------
LEAF_BEGIN Tit_BuildOutline
    lea  rcx, titMask
    lea  rdx, titOutline
    jmp  Font_Outline
LEAF_END Tit_BuildOutline

; ---------------------------------------------------------------------------
; Tit_BuildTexts - title, outline, glow, chrome, subtitle and credit line.
; ---------------------------------------------------------------------------
FN_BEGIN Tit_BuildTexts, 0
    call Tit_BuildTitle
    call Tit_TitleMetrics
    call Tit_BuildOutline
    lea  rcx, titMask
    lea  rdx, titGlow
    mov  r8d, TITLE_GLOW_R
    call Font_Glow
    lea  rsi, titReq
    TIT_FONT titSub, szSub, 20, 500, 1, 0, 7
    call Sig_Init                          ; "created with <heart> by Paul Deecalov (c) 2026"
    lea  rcx, sigHeart
    lea  rdx, titHeartGlow
    mov  r8d, 5
    call Font_Glow
    FN_RET
FN_END Tit_BuildTexts

FN_BEGIN Fx_Title_Init, 0
    lea  rcx, titSkyPal
    mov  edx, HORIZON
    lea  r8, titSkyKeys
    call Pal_FromKeys
    lea  rcx, titGndPal
    mov  edx, GROUND_H
    lea  r8, titGndKeys
    call Pal_FromKeys
    lea  rcx, titSunPal
    mov  edx, 256
    lea  r8, titSunKeys
    call Pal_FromKeys
    lea  rcx, titMtnPalA
    mov  edx, MTN_PAL
    lea  r8, titMtnKeysA
    call Pal_FromKeys
    lea  rcx, titMtnPalB
    mov  edx, MTN_PAL
    lea  r8, titMtnKeysB
    call Pal_FromKeys
    lea  rcx, titMtnA
    lea  rdx, mtnParamsA
    call Tit_MtnLayer
    lea  rcx, titMtnB
    lea  rdx, mtnParamsB
    call Tit_MtnLayer
    call Tit_BuildTexts
    lea  rcx, titSunGlow
    mov  edx, GLOW_SZ
    mov  r8d, 2
    call Msk_Radial
    xor  eax, eax
    FN_RET
FN_END Fx_Title_Init

; ---------------------------------------------------------------------------
; Tit_Sky(rcx = fb, edx = boot 0..256) - gradient rows above the horizon.
; ---------------------------------------------------------------------------
FN_BEGIN Tit_Sky, 0
    mov  rdi, rcx
    mov  r13d, edx
    lea  rsi, titSkyPal
    xor  ebx, ebx
ts_row:
    mov  eax, DWORD PTR [rsi+rbx*4]
    PIXSCALE eax, r13d, ecx
    mov  ecx, SCR_W
    rep  stosd
    inc  ebx
    cmp  ebx, HORIZON
    jb   ts_row
    FN_RET
FN_END Tit_Sky

; ---------------------------------------------------------------------------
; Tit_Stars(rcx = fb, edx = t, r8d = boot) - hash-placed twinkling stars; every
; eighth one gets a small cross.
; ---------------------------------------------------------------------------
FN_BEGIN Tit_Stars, 0
    mov  r12, rcx
    mov  r13d, edx
    mov  ebp, r8d
    xor  ebx, ebx
st_lp:
    mov  ecx, ebx
    mov  edx, 3
    mov  r8d, 17
    call Mth_Hash2
    mov  r14d, eax
    mov  ecx, ebx
    mov  edx, 5
    mov  r8d, 29
    call Mth_Hash2
    mov  r15d, eax
    movzx eax, r14w
    imul eax, SCR_W
    shr  eax, 16
    mov  esi, eax                          ; x
    movzx eax, r15w
    imul eax, STAR_H
    shr  eax, 16
    mov  edi, eax                          ; y
    mov  eax, r14d
    shr  eax, 16
    and  eax, 127
    add  eax, 80                           ; base brightness 80..207
    mov  ecx, r14d
    shr  ecx, 24
    and  ecx, 63
    shl  ecx, 3
    add  ecx, 220                          ; twinkle speed
    imul ecx, r13d
    shr  ecx, 8
    mov  edx, r15d
    shr  edx, 16
    add  ecx, edx
    and  ecx, 4095
    lea  rdx, gSinTab
    movsx ecx, WORD PTR [rdx+rcx*2]
    imul ecx, 110
    sar  ecx, 15
    add  ecx, 146                          ; 36..256
    imul eax, ecx
    shr  eax, 8
    mov  ecx, STAR_H
    sub  ecx, edi
    imul ecx, 437
    shr  ecx, 8                            ; fade towards the horizon
    cmp  ecx, 256
    jbe  st_fade
    mov  ecx, 256
st_fade:
    imul eax, ecx
    shr  eax, 8
    imul eax, ebp
    shr  eax, 8                            ; brightness 0..255
    jz   st_next
    imul ecx, eax, 217
    shr  ecx, 8
    shl  ecx, 16
    imul edx, eax, 230
    shr  edx, 8
    shl  edx, 8
    or   ecx, edx
    or   ecx, eax                          ; cool white
    mov  r8d, edi
    imul r8d, SCR_W
    add  r8d, esi
    lea  r8, [r12+r8*4]
    mov  r9d, DWORD PTR [r8]
    PIXADD r9d, ecx, xmm0, xmm1
    mov  DWORD PTR [r8], r9d
    test ebx, 7
    jnz  st_next
    cmp  esi, 1
    jb   st_next
    cmp  esi, SCR_W - 2
    ja   st_next
    test edi, edi
    jz   st_next
    shr  ecx, 1
    and  ecx, 007F7F7Fh
    mov  r9d, DWORD PTR [r8-4]
    PIXADD r9d, ecx, xmm0, xmm1
    mov  DWORD PTR [r8-4], r9d
    mov  r9d, DWORD PTR [r8+4]
    PIXADD r9d, ecx, xmm0, xmm1
    mov  DWORD PTR [r8+4], r9d
    mov  r9d, DWORD PTR [r8-SCR_W*4]
    PIXADD r9d, ecx, xmm0, xmm1
    mov  DWORD PTR [r8-SCR_W*4], r9d
    mov  r9d, DWORD PTR [r8+SCR_W*4]
    PIXADD r9d, ecx, xmm0, xmm1
    mov  DWORD PTR [r8+SCR_W*4], r9d
st_next:
    inc  ebx
    cmp  ebx, STAR_N
    jb   st_lp
    FN_RET
FN_END Tit_Stars

; ---------------------------------------------------------------------------
; Tit_Sun(rcx = fb, edx = t) - additive glow, then the disc: vertical colour
; ramp, soft left/right edges, horizontal slits that grow towards the bottom
; and scroll slowly.  Rows at or below the horizon are not drawn.
; ---------------------------------------------------------------------------
FN_BEGIN Tit_Sun, 0
    mov  r12, rcx
    mov  r13d, edx
    mov  ecx, edx
    call Tit_SunEase
    mov  ecx, 256
    sub  ecx, eax
    imul ecx, SUN_RISE
    shr  ecx, 8
    add  ecx, SUN_CY
    mov  r14d, ecx                         ; centre row
    mov  eax, gKick
    shr  eax, 6
    add  eax, SUN_R
    mov  r15d, eax                         ; radius, breathing with the kick
    DM_FILL titSunGlow, SUN_CX - GLOW_SZ / 2, 0, 00FF3C98h, 0, 1
    lea  rax, titDm
    mov  ecx, r14d
    sub  ecx, GLOW_SZ / 2
    mov  DWORD PTR [rax+DMASK.y], ecx
    mov  ecx, gKick
    shr  ecx, 2
    add  ecx, 110
    mov  DWORD PTR [rax+DMASK.alpha], ecx
    mov  QWORD PTR [rax+DMASK.rowPal], 0
    mov  QWORD PTR [rax+DMASK.rowOff], 0
    mov  rcx, rax
    call Gfx_DrawMask
    mov  ebx, r14d
    sub  ebx, r15d                         ; first row of the disc
    jns  su_row
    xor  ebx, ebx
su_row:
    cmp  ebx, HORIZON
    jae  su_done
    mov  esi, ebx
    sub  esi, r14d                         ; dy
    cmp  esi, r15d
    jg   su_done
    mov  ecx, r15d
    imul ecx, ecx
    mov  eax, esi
    imul eax, eax
    sub  ecx, eax                          ; R^2 - dy^2
    jle  su_next
    cvtsi2ss xmm0, ecx
    sqrtss xmm0, xmm0
    mulss xmm0, DWORD PTR k256f
    cvttss2si r9d, xmm0                    ; half width, 8.8
    test esi, esi
    jle  su_noslit
    imul eax, esi, 14
    cdq
    idiv r15d                              ; slit thickness 0..14
    mov  ecx, r13d
    shr  ecx, 6                            ; scroll
    mov  edx, ebx
    sub  edx, ecx
    and  edx, 15
    cmp  edx, eax
    jb   su_next                           ; this row is inside a slit
su_noslit:
    mov  eax, ebx
    mov  ecx, r14d
    sub  ecx, r15d
    sub  eax, ecx                          ; y - top
    imul eax, 255
    lea  ecx, [r15*2]
    xor  edx, edx
    div  ecx
    lea  rdx, titSunPal
    mov  r10d, DWORD PTR [rdx+rax*4]       ; row colour
    mov  eax, gKick
    shr  eax, 3
    imul eax, eax, 010101h
    PIXADD r10d, eax, xmm0, xmm1
    mov  eax, ebx
    imul eax, SCR_W
    lea  rdi, [r12+rax*4]                  ; row start
    mov  eax, SUN_CX * 256
    sub  eax, r9d
    mov  ebp, eax                          ; xl
    lea  esi, [rax+r9*2]                   ; xr
    shr  eax, 8
    lea  rcx, [rdi+rax*4]
    mov  r8d, ebp
    and  r8d, 255
    neg  r8d
    add  r8d, 256                          ; left coverage
    mov  edx, r10d
    call Tit_EdgePix
    mov  eax, esi
    shr  eax, 8
    lea  rcx, [rdi+rax*4]
    mov  r8d, esi
    and  r8d, 255                          ; right coverage
    mov  edx, r10d
    call Tit_EdgePix
    mov  eax, ebp
    shr  eax, 8
    inc  eax
    mov  ecx, esi
    shr  ecx, 8
    sub  ecx, eax                          ; interior pixels
    jle  su_next
    lea  rdi, [rdi+rax*4]
    mov  eax, r10d
    rep  stosd
su_next:
    inc  ebx
    jmp  su_row
su_done:
    FN_RET
FN_END Tit_Sun

; ---------------------------------------------------------------------------
; Tit_Ground(rcx = fb, edx = boot) - gradient rows from the horizon down.
; ---------------------------------------------------------------------------
FN_BEGIN Tit_Ground, 0
    lea  rdi, [rcx+HORIZON*SCR_W*4]
    mov  r13d, edx
    lea  rsi, titGndPal
    xor  ebx, ebx
tg_row:
    mov  eax, DWORD PTR [rsi+rbx*4]
    PIXSCALE eax, r13d, ecx
    mov  ecx, SCR_W
    rep  stosd
    inc  ebx
    cmp  ebx, GROUND_H
    jb   tg_row
    FN_RET
FN_END Tit_Ground

; ---------------------------------------------------------------------------
; Tit_Reflect(rcx = fb, edx = t) - the sun's reflection: broken horizontal
; stripes (thinner towards the horizon) under the sun, fading with distance.
; ---------------------------------------------------------------------------
FN_BEGIN Tit_Reflect, 0
    mov  r12, rcx
    mov  r13d, edx
    mov  ecx, edx
    call Tit_SunEase
    mov  r14d, eax                         ; sun rise progress
    mov  r15d, r13d
    shr  r15d, 6                           ; stripe scroll
    xor  ebx, ebx                          ; rows below the horizon
rf_row:
    mov  eax, 16384
    lea  ecx, [rbx+10]
    xor  edx, edx
    div  ecx
    add  eax, r15d
    and  eax, 15
    cmp  eax, 8
    jae  rf_next                           ; gap between stripes
    mov  eax, GROUND_H
    sub  eax, ebx
    imul eax, 437
    shr  eax, 8                            ; 256 at the horizon, 0 at the bottom
    imul eax, eax
    imul eax, 200
    shr  eax, 16
    imul eax, r14d
    shr  eax, 8
    jz   rf_next
    mov  esi, eax                          ; peak strength
    mov  eax, ebx
    shr  eax, 1
    add  eax, 56
    mov  edx, gKick
    shr  edx, 5
    add  eax, edx
    mov  ebp, eax                          ; half width
    lea  eax, [rbx+HORIZON]
    imul eax, SCR_W * 4
    lea  rdi, [r12+rax]
    mov  eax, esi
    shl  eax, 8
    xor  edx, edx
    div  ebp
    mov  r8d, eax                          ; strength lost per pixel (8.8)
    mov  r9d, esi
    shl  r9d, 8                            ; running strength
    xor  ecx, ecx                          ; distance from the centre column
rf_px:
    mov  r10d, r9d
    shr  r10d, 8
    jz   rf_next
    mov  edx, SUN_CX
    sub  edx, ecx
    lea  rdx, [rdi+rdx*4]
    ADDPIXW rdx, REFL_COL, r10d, r11d, eax
    test ecx, ecx
    jz   rf_step
    mov  edx, SUN_CX
    add  edx, ecx
    lea  rdx, [rdi+rdx*4]
    ADDPIXW rdx, REFL_COL, r10d, r11d, eax
rf_step:
    sub  r9d, r8d
    inc  ecx
    cmp  ecx, ebp
    jbe  rf_px
rf_next:
    inc  ebx
    cmp  ebx, GROUND_H
    jb   rf_row
    FN_RET
FN_END Tit_Reflect

; ---------------------------------------------------------------------------
; Tit_DrawLayer(rcx = fb, rdx = heights WORD[640], r8 = palette, r9d = ridge colour)
; Columns of shaded rock standing on the horizon, lit along the ridge.
; ---------------------------------------------------------------------------
FN_BEGIN Tit_DrawLayer, 0
    mov  r12, rcx
    mov  rsi, rdx
    mov  r13, r8
    mov  r14d, r9d
    xor  ebx, ebx
dl_x:
    movzx ecx, WORD PTR [rsi+rbx*2]
    test ecx, ecx
    jz   dl_next
    mov  eax, HORIZON
    sub  eax, ecx
    imul eax, SCR_W
    add  eax, ebx
    lea  rdi, [r12+rax*4]
    mov  r15, rdi                          ; ridge pixel
    xor  r8d, r8d
dl_col:
    mov  edx, r8d
    cmp  edx, MTN_PAL - 1
    jbe  dl_c
    mov  edx, MTN_PAL - 1
dl_c:
    mov  eax, DWORD PTR [r13+rdx*4]
    mov  DWORD PTR [rdi], eax
    add  rdi, SCR_W * 4
    inc  r8d
    cmp  r8d, ecx
    jb   dl_col
    ADDPIXW r15, r14d, 256, eax, edx
    lea  rcx, [r15-SCR_W*4]
    ADDPIXW rcx, r14d, 110, eax, edx
dl_next:
    inc  ebx
    cmp  ebx, SCR_W
    jb   dl_x
    FN_RET
FN_END Tit_DrawLayer

; ---------------------------------------------------------------------------
; Tit_Mountains(rcx = fb, edx = t) - back ridge (violet) and front ridge (pink).
; ---------------------------------------------------------------------------
FN_BEGIN Tit_Mountains, 0
    mov  r12, rcx
    mov  eax, gKick
    shr  eax, 2
    mov  r13d, eax                         ; beat accent
    lea  edx, [rax+150]
    mov  r9d, 00A058FFh
    PIXSCALE r9d, edx, ecx
    mov  rcx, r12
    lea  rdx, titMtnA
    lea  r8, titMtnPalA
    call Tit_DrawLayer
    lea  edx, [r13+190]
    cmp  edx, 256
    jbe  mt_b
    mov  edx, 256
mt_b:
    mov  r9d, 00FF40B8h
    PIXSCALE r9d, edx, ecx
    mov  rcx, r12
    lea  rdx, titMtnB
    lea  r8, titMtnPalB
    call Tit_DrawLayer
    FN_RET
FN_END Tit_Mountains

; ---------------------------------------------------------------------------
; Tit_HBand(rcx = fb, edx = centre row 8.8, r8d = thickness 8.8, r9d = colour)
; Adds an anti-aliased horizontal line across the ground.
; ---------------------------------------------------------------------------
FN_BEGIN Tit_HBand, 0
    mov  r12, rcx
    mov  r13d, r9d
    mov  eax, edx
    mov  ecx, r8d
    shr  ecx, 1
    sub  eax, ecx
    mov  r14d, eax                         ; top edge
    add  eax, r8d
    mov  r15d, eax                         ; bottom edge
    mov  ebx, r14d
    sar  ebx, 8                            ; first row
hb_row:
    cmp  ebx, HORIZON
    jl   hb_next
    cmp  ebx, SCR_H
    jge  hb_done
    mov  eax, ebx
    shl  eax, 8
    mov  ecx, r14d
    cmp  ecx, eax
    cmovl ecx, eax                         ; lo = max(top, row)
    lea  edx, [rax+256]
    cmp  edx, r15d
    cmovg edx, r15d                        ; hi = min(bottom, row + 1)
    sub  edx, ecx                          ; coverage 0..256
    jle  hb_next
    mov  eax, r13d
    PIXSCALE eax, edx, ecx
    movd xmm0, eax
    pshufd xmm0, xmm0, 0
    mov  eax, ebx
    imul eax, SCR_W * 4
    lea  rdi, [r12+rax]
    mov  ecx, SCR_W / 4
hb_px:
    movdqu xmm1, XMMWORD PTR [rdi]
    paddusb xmm1, xmm0
    movdqu XMMWORD PTR [rdi], xmm1
    add  rdi, 16
    dec  ecx
    jnz  hb_px
hb_next:
    inc  ebx
    mov  eax, ebx
    shl  eax, 8
    cmp  eax, r15d
    jl   hb_row
hb_done:
    FN_RET
FN_END Tit_HBand

; ---------------------------------------------------------------------------
; Tit_GridH(rcx = fb) - horizontal lines at z = Z0 + k * ZS - phase, phase tied
; to the beat so a line reaches the next one's place exactly on every beat.
; screen row = horizon + K / z; lines closer together than ~1 px fade out.
; ---------------------------------------------------------------------------
FN_BEGIN Tit_GridH, 0
    mov  r12, rcx
    mov  eax, gBeat16
    imul eax, GRID_ZS
    shr  eax, 16
    mov  r14d, eax                         ; phase 0..ZS-1
    xor  ebx, ebx
gh_k:
    mov  eax, ebx
    imul eax, GRID_ZS
    add  eax, GRID_Z0
    sub  eax, r14d                         ; z (8.8), never below 512
    mov  ecx, eax
    mov  eax, GRID_K * 65536
    xor  edx, edx
    div  ecx                               ; dy = K / z, 8.8 rows
    cmp  eax, GROUND_H * 256 + 1024
    ja   gh_next
    mov  esi, eax
    sub  eax, 3072
    jle  gh_next                           ; closer than 12 px to the horizon
    imul eax, 26
    shr  eax, 8
    cmp  eax, 256
    jbe  gh_i
    mov  eax, 256
gh_i:
    mov  ecx, gKick
    shr  ecx, 2
    add  ecx, 200
    imul eax, ecx
    shr  eax, 8
    cmp  eax, 256
    jbe  gh_i2
    mov  eax, 256
gh_i2:
    mov  edx, GRID_HCOL
    PIXSCALE edx, eax, ecx
    mov  r9d, edx
    mov  r8d, esi
    shr  r8d, 6
    add  r8d, 160                          ; thickness grows with proximity
    lea  edx, [rsi+HORIZON*256]
    mov  rcx, r12
    call Tit_HBand
gh_next:
    inc  ebx
    cmp  ebx, GRID_N
    jb   gh_k
    FN_RET
FN_END Tit_GridH

; ---------------------------------------------------------------------------
; Tit_GridV(rcx = fb, edx = t) - vertical lanes converging on the horizon:
; x = 320 + (lane + sway) * dy * 0.32, drawn per row with exact coverage.
; ---------------------------------------------------------------------------
FN_BEGIN Tit_GridV, 0
    mov  r12, rcx
    mov  eax, edx
    imul eax, 5
    shr  eax, 3
    and  eax, 4095
    lea  rcx, gSinTab
    movsx eax, WORD PTR [rcx+rax*2]
    imul eax, 110
    sar  eax, 15
    mov  r13d, eax                         ; sway in lane units (8.8)
    xor  ebx, ebx
gv_row:
    mov  eax, ebx
    shl  eax, 8
    add  eax, 128
    mov  esi, eax                          ; dy (8.8)
    sub  eax, 3072
    jle  gv_next
    imul eax, 26
    shr  eax, 8
    cmp  eax, 256
    jbe  gv_i
    mov  eax, 256
gv_i:
    mov  ecx, gKick
    shr  ecx, 2
    add  ecx, 200
    imul eax, ecx
    shr  eax, 8
    cmp  eax, 256
    jbe  gv_i2
    mov  eax, 256
gv_i2:
    mov  edx, GRID_VCOL
    PIXSCALE edx, eax, ecx
    mov  r14d, edx                         ; line colour at this depth
    mov  eax, esi
    shr  eax, 6
    add  eax, 200
    mov  r15d, eax                         ; line width (8.8)
    lea  eax, [rbx+HORIZON]
    imul eax, SCR_W * 4
    lea  rdi, [r12+rax]
    mov  ebp, -GRID_NV
gv_lane:
    mov  eax, ebp
    shl  eax, 8
    add  eax, r13d
    imul eax, esi
    sar  eax, 8
    imul eax, 82
    sar  eax, 8
    add  eax, SUN_CX * 256                 ; line centre (8.8 px)
    mov  ecx, r15d
    shr  ecx, 1
    sub  eax, ecx                          ; left edge
    lea  r11d, [rax+r15-1]
    sar  r11d, 8                           ; last pixel
    mov  r8d, eax
    sar  r8d, 8                            ; first pixel
gv_px:
    cmp  r8d, SCR_W - 1
    ja   gv_pxn
    mov  ecx, r8d
    shl  ecx, 8
    mov  r9d, eax
    cmp  r9d, ecx
    cmovl r9d, ecx                         ; lo = max(left, pixel)
    add  ecx, 256
    lea  r10d, [rax+r15]
    cmp  r10d, ecx
    cmovg r10d, ecx                        ; hi = min(right, pixel + 1)
    sub  r10d, r9d                         ; coverage
    jle  gv_pxn
    lea  rcx, [rdi+r8*4]
    ADDPIXW rcx, r14d, r10d, r9d, edx
gv_pxn:
    inc  r8d
    cmp  r8d, r11d
    jle  gv_px
    inc  ebp
    cmp  ebp, GRID_NV
    jle  gv_lane
gv_next:
    inc  ebx
    cmp  ebx, GROUND_H
    jb   gv_row
    FN_RET
FN_END Tit_GridV

; ---------------------------------------------------------------------------
; Tit_Title(rcx = fb, edx = t) - hard shadow, compact neon, outline and chrome.
; The entrance keeps its row glitches; afterwards the wordmark is pixel-stable.
; Every layer shares titOff so the outline never separates during a glitch.
; ---------------------------------------------------------------------------
FN_BEGIN Tit_Title, 0
    mov  r12, rcx
    mov  r13d, edx
    mov  ecx, r13d
    sub  ecx, TITLE_AT
    mov  edx, 500
    call Tit_Ramp
    test eax, eax
    jz   tt_done
    mov  r14d, eax                         ; opacity 0..256
    mov  ecx, r13d
    sub  ecx, TITLE_AT
    mov  edx, GLITCH_MS
    call Tit_Ramp
    mov  r15d, 256
    sub  r15d, eax                         ; glitch strength 256 -> 0
    mov  eax, r13d
    xor  edx, edx
    mov  ecx, 70
    div  ecx
    mov  ebp, eax                          ; glitch frame number
    test r15d, r15d
    jz   tt_rows
    mov  ecx, ebp
    mov  edx, 3
    mov  r8d, 5
    call Mth_Hash2
    and  eax, 3
    jnz  tt_rows
    shr  r14d, 2                           ; dim frame
tt_rows:
    lea  rax, titMask
    mov  esi, DWORD PTR [rax+TXMASK.h]
    lea  rdi, titOff
    xor  ebx, ebx
tt_row:
    xor  eax, eax
    test r15d, r15d
    jz   tt_store
    mov  ecx, ebx
    shr  ecx, 2
    mov  edx, ebp
    mov  r8d, 91
    call Mth_Hash2
    mov  edx, eax
    shr  edx, 8
    and  edx, 3                            ; only a quarter of the blocks move
    movzx eax, al
    sub  eax, 128
    imul eax, r15d
    sar  eax, 10
    xor  ecx, ecx
    test edx, edx
    cmovnz eax, ecx
tt_store:
    mov  DWORD PTR [rdi+rbx*4], eax
    inc  ebx
    cmp  ebx, esi
    jb   tt_row
    mov  eax, r13d                         ; vertical bob fades out with the glitch
    imul eax, 3
    shr  eax, 2
    and  eax, 4095
    lea  rcx, gSinTab
    movsx eax, WORD PTR [rcx+rax*2]
    imul eax, 3
    sar  eax, 15
    imul eax, r15d
    sar  eax, 8                            ; no whole-pixel jitter after the entrance
    mov  edx, titInkTop
    add  edx, titInkEnd
    shr  edx, 1
    sub  eax, edx
    add  eax, TXT_CY
    mov  esi, eax                          ; top row of the masks
    lea  rax, titMask
    mov  eax, DWORD PTR [rax+TXMASK.w]
    mov  edx, SCR_W
    sub  edx, eax
    sar  edx, 1                            ; signed centring remains safe if layout changes
    mov  edi, edx                          ; left column
    imul ebx, r14d, 220
    shr  ebx, 8                            ; crisp drop shadow
    lea  r10d, [rdi+1]
    lea  r11d, [rsi+3]
    DM_FILL titOutline, r10d, r11d, 00080018h, ebx, 0
    lea  rax, titDm
    lea  rcx, titOff
    mov  QWORD PTR [rax+DMASK.rowOff], rcx
    mov  QWORD PTR [rax+DMASK.rowPal], 0
    mov  rcx, rax
    call Gfx_DrawMask
    mov  ebx, gKick
    imul ebx, 64
    shr  ebx, 8
    add  ebx, 52                           ; 52..116: restrained glow preserves letter edges
    imul ebx, r14d
    shr  ebx, 8                            ; neon opacity
    DM_FILL titGlow, edi, esi, 00FF3CB4h, ebx, 1
    lea  rcx, titDm
    call Gfx_DrawMask
    DM_FILL titOutline, edi, esi, 00080018h, r14d, 0
    lea  rcx, titDm
    call Gfx_DrawMask
    DM_FILL titMask, edi, esi, 00FFFFFFh, r14d, 0
    lea  rax, titDm
    lea  rcx, titRowPal
    mov  QWORD PTR [rax+DMASK.rowPal], rcx
    mov  rcx, rax
    call Gfx_DrawMask
tt_done:
    FN_RET
FN_END Tit_Title

; ---------------------------------------------------------------------------
; Tit_Caption(rcx = fb, rdx = TXMASK *, r8d = top row, r9d = opacity 0..256,
;             r10d = colour 0x00RRGGBB)
; One small centred caption with a one-pixel drop shadow.
; ---------------------------------------------------------------------------
FN_BEGIN Tit_Caption, 0
    test r9d, r9d
    jz   tc_done
    mov  r12, rcx
    mov  rbx, rdx
    mov  r14d, r8d
    mov  r15d, r9d
    mov  esi, r10d                         ; colour (the shadow call below clobbers r10)
    mov  r13d, SCR_W
    sub  r13d, DWORD PTR [rbx+TXMASK.w]
    shr  r13d, 1                           ; left column
    imul ebp, r15d, 170
    shr  ebp, 8                            ; shadow opacity
    lea  rax, titDm
    mov  QWORD PTR [rax+DMASK.dst], r12
    mov  QWORD PTR [rax+DMASK.tx], rbx
    lea  ecx, [r13+1]
    mov  DWORD PTR [rax+DMASK.x], ecx
    lea  ecx, [r14+1]
    mov  DWORD PTR [rax+DMASK.y], ecx
    mov  DWORD PTR [rax+DMASK.color], 00100020h
    mov  DWORD PTR [rax+DMASK.alpha], ebp
    mov  DWORD PTR [rax+DMASK.mode], 0
    mov  QWORD PTR [rax+DMASK.rowPal], 0
    mov  QWORD PTR [rax+DMASK.rowOff], 0
    mov  rcx, rax
    call Gfx_DrawMask
    lea  rax, titDm
    mov  DWORD PTR [rax+DMASK.x], r13d
    mov  DWORD PTR [rax+DMASK.y], r14d
    mov  DWORD PTR [rax+DMASK.color], esi
    mov  DWORD PTR [rax+DMASK.alpha], r15d
    mov  rcx, rax
    call Gfx_DrawMask
tc_done:
    FN_RET
FN_END Tit_Caption

; ---------------------------------------------------------------------------
; Tit_Signature(rcx = fb, edx = appearance 0..256)
; The credit line at the bottom: a soft red glow behind the heart, the text in
; the colour of the other captions, then the heart itself in SIG_RED.
; ---------------------------------------------------------------------------
FN_BEGIN Tit_Signature, 0
    test edx, edx
    jz   ts_done                           ; not there yet
    mov  r12, rcx
    mov  r13d, edx
    lea  rax, sigHeart
    mov  ebx, SCR_W
    sub  ebx, DWORD PTR [rax+TXMASK.w]
    shr  ebx, 1                            ; left column of both canvases
    imul r14d, r13d, 100
    shr  r14d, 8                           ; opacity of the glow
    mov  esi, SIG_ROW
    DM_FILL titHeartGlow, ebx, esi, SIG_RED, r14d, 1
    lea  rax, titDm
    mov  QWORD PTR [rax+DMASK.rowPal], 0
    mov  QWORD PTR [rax+DMASK.rowOff], 0
    mov  rcx, rax
    call Gfx_DrawMask
    imul r9d, r13d, 190                    ; the text keeps the 190 / 256 of the old tag line
    shr  r9d, 8
    mov  rcx, r12
    lea  rdx, sigText
    mov  r8d, SIG_ROW
    mov  r10d, 00C8F4FFh
    call Tit_Caption
    imul r9d, r13d, 240                    ; the heart a little stronger than the text
    shr  r9d, 8
    mov  rcx, r12
    lea  rdx, sigHeart
    mov  r8d, SIG_ROW
    mov  r10d, SIG_RED
    call Tit_Caption
ts_done:
    FN_RET
FN_END Tit_Signature

; ---------------------------------------------------------------------------
; Tit_Captions(rcx = fb, edx = t) - subtitle (2.5 s) and the credit line (4.0 s).
; ---------------------------------------------------------------------------
FN_BEGIN Tit_Captions, 0
    mov  r12, rcx
    mov  r13d, edx
    mov  ecx, r13d
    sub  ecx, 2500
    mov  edx, 700
    call Tit_Ramp
    mov  r9d, eax
    mov  rcx, r12
    lea  rdx, titSub
    mov  r8d, titSubRow                    ; follows the measured title, never overlaps
    mov  r10d, 00C8F4FFh
    call Tit_Caption
    mov  ecx, r13d
    sub  ecx, 4000
    mov  edx, 700
    call Tit_Ramp
    mov  edx, eax
    mov  rcx, r12
    call Tit_Signature
    FN_RET
FN_END Tit_Captions

; ---------------------------------------------------------------------------
; Fx_Title_Render(rcx = fb, edx = local ms)
; ---------------------------------------------------------------------------
FN_BEGIN Fx_Title_Render, 16
    mov  QWORD PTR [rsp+LOC], rcx
    mov  DWORD PTR [rsp+LOC+8], edx
    mov  ecx, edx
    mov  edx, 2200
    call Tit_Ramp
    mov  ebx, eax                          ; boot: the whole scene lights up in 2.2 s
    mov  rcx, QWORD PTR [rsp+LOC]
    mov  edx, ebx
    call Tit_Sky
    mov  rcx, QWORD PTR [rsp+LOC]
    mov  edx, DWORD PTR [rsp+LOC+8]
    mov  r8d, ebx
    call Tit_Stars
    mov  rcx, QWORD PTR [rsp+LOC]
    mov  edx, DWORD PTR [rsp+LOC+8]
    call Tit_Sun
    mov  rcx, QWORD PTR [rsp+LOC]
    mov  edx, ebx
    call Tit_Ground
    mov  rcx, QWORD PTR [rsp+LOC]
    mov  edx, DWORD PTR [rsp+LOC+8]
    call Tit_Reflect
    mov  rcx, QWORD PTR [rsp+LOC]
    mov  edx, DWORD PTR [rsp+LOC+8]
    call Tit_Mountains
    mov  rcx, QWORD PTR [rsp+LOC]
    call Tit_GridH
    mov  rcx, QWORD PTR [rsp+LOC]
    mov  edx, DWORD PTR [rsp+LOC+8]
    call Tit_GridV
    mov  rcx, QWORD PTR [rsp+LOC]
    mov  edx, DWORD PTR [rsp+LOC+8]
    call Tit_Title
    mov  rcx, QWORD PTR [rsp+LOC]
    mov  edx, DWORD PTR [rsp+LOC+8]
    call Tit_Captions
    FN_RET
FN_END Fx_Title_Render

END