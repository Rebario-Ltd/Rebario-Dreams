; ============================================================================
; signature.asm - "created with <heart> by Paul Deecalov (c) 2026": the credit
;                 line of the first scene and of the last one.
; ----------------------------------------------------------------------------
; The text path of font.asm is ANSI, and a heart taken from a font would be one
; flat colour anyway, so the line is built from three parts.  "created with"
; and "by Paul Deecalov (c) 2026" go through GDI like every other caption; the
; heart is computed from a formula (Msk_Heart), which makes it red, crisp at any
; size and independent of the fonts installed.
;
; The parts are laid on two canvases of the same size:
;
;     sigText    created with  [  hole  ]  by Paul Deecalov (c) 2026
;     sigHeart                 [ heart  ]
;
; A scene draws both at the same place: sigText in the colour of its own
; captions, sigHeart in SIG_RED.  The heart box is SIG_HEART pixels wide, it
; has SIG_GAP clear pixels to either text and it is centred on the ink of the
; text, not on the mask (the masks carry empty margins, see FONT_PAD).
; ============================================================================
INCLUDE common.inc

SIG_FACE   EQU 1                         ; Bahnschrift, like the other captions
SIG_HEIGHT EQU 15                        ; em height of the two texts
SIG_WEIGHT EQU 400
SIG_TRACK  EQU 2                         ; extra pixels between characters
SIG_INK    EQU 64                        ; coverage from which a pixel counts as ink

HT_LOG     EQU 2                         ; the heart takes HT_SS x HT_SS samples per pixel
HT_SS      EQU 1 SHL HT_LOG

.const
szSigLeft  BYTE "created with", 0
szSigRight BYTE "by Paul Deecalov (c) 2026", 0
; The curve (x^2 + y^2 - 1)^3 - x^2 * y^3 <= 0 spans x -1.139..1.139 and
; y -1.0..1.236.  The box of the mask is 2.4 curve units wide and tall, centred
; on y = 0.118, so the heart fills 95 % of it across and 93 % up and down.
kHtHalf    REAL4 1.2                     ; half the width of the box in curve units
kHtCentre  REAL4 0.118                   ; curve y of the middle of the box
kHtOne     REAL4 1.0
kHtZero    REAL4 0.0

.data?
ALIGN 16
sigText    BYTE 16 DUP (?)               ; TXMASK
sigHeart   BYTE 16 DUP (?)               ; TXMASK
sigLeft    BYTE 16 DUP (?)               ; TXMASK: "created with"
sigRight   BYTE 16 DUP (?)               ; TXMASK: "by Paul Deecalov (c) 2026"
sigBox     BYTE 16 DUP (?)               ; TXMASK: the heart before it is placed
sigReq     BYTE 48 DUP (?)               ; FONTREQ
htStep     REAL4 ?                       ; curve units per half sample

.code

; ---------------------------------------------------------------------------
; Hrt_Inside(ecx = u, edx = v) -> eax = 1 when the sample lies inside the heart.
; u and v count half samples from the middle of the box; they are odd, so the
; samples of a row mirror each other exactly.  The sample is at
; (u * htStep, centre - v * htStep).  Leaf.
; ---------------------------------------------------------------------------
LEAF_BEGIN Hrt_Inside
    movss    xmm1, DWORD PTR htStep
    cvtsi2ss xmm0, ecx
    mulss    xmm0, xmm1                    ; x
    mulss    xmm0, xmm0                    ; x^2
    cvtsi2ss xmm2, edx
    mulss    xmm2, xmm1
    movss    xmm3, DWORD PTR kHtCentre
    subss    xmm3, xmm2                    ; y
    movaps   xmm2, xmm3
    mulss    xmm2, xmm2                    ; y^2
    mulss    xmm3, xmm2                    ; y^3
    mulss    xmm3, xmm0                    ; x^2 * y^3
    addss    xmm2, xmm0                    ; x^2 + y^2
    subss    xmm2, DWORD PTR kHtOne        ; x^2 + y^2 - 1
    movaps   xmm4, xmm2
    mulss    xmm4, xmm2
    mulss    xmm4, xmm2                    ; (x^2 + y^2 - 1)^3
    subss    xmm4, xmm3                    ; f(x, y), <= 0 inside
    xor      eax, eax
    comiss   xmm4, DWORD PTR kHtZero
    setbe    al
    ret
LEAF_END Hrt_Inside

; ---------------------------------------------------------------------------
; Msk_Heart(rcx = TXMASK * out, edx = size) - a size x size coverage mask with
; a heart on it.  Every pixel takes HT_SS x HT_SS samples; the coverage is the
; share of them inside the curve, scaled to 0..255.  Allocates the pixels.
; ---------------------------------------------------------------------------
FN_BEGIN Msk_Heart, 0
    mov  rbx, rcx
    mov  r12d, edx                         ; size
    mov  DWORD PTR [rbx+TXMASK.w], edx
    mov  DWORD PTR [rbx+TXMASK.h], edx
    mov  ecx, edx
    imul ecx, edx
    call Mem_Alloc
    mov  QWORD PTR [rbx+TXMASK.pix], rax
    mov  rdi, rax
    lea  r13d, [r12*HT_SS]                 ; samples across the box
    cvtsi2ss xmm0, r13d
    movss    xmm1, DWORD PTR kHtHalf
    divss    xmm1, xmm0
    movss    DWORD PTR htStep, xmm1        ; the half width of the box over the samples across it
    xor  esi, esi                          ; row
hm_row:
    xor  ebp, ebp                          ; column
hm_px:
    xor  r14d, r14d                        ; samples inside the heart
    xor  r15d, r15d                        ; sample number 0 .. HT_SS^2 - 1
hm_smp:
    mov  eax, r15d
    and  eax, HT_SS - 1
    lea  ecx, [rax+rbp*HT_SS]              ; sample column
    lea  ecx, [rcx*2+1]
    sub  ecx, r13d                         ; u: odd, mirrored around the middle
    mov  eax, r15d
    shr  eax, HT_LOG
    lea  edx, [rax+rsi*HT_SS]              ; sample row
    lea  edx, [rdx*2+1]
    sub  edx, r13d                         ; v
    call Hrt_Inside
    add  r14d, eax
    inc  r15d
    cmp  r15d, HT_SS * HT_SS
    jb   hm_smp
    imul eax, r14d, 255                    ; coverage = (inside * 255 + half) / (HT_SS^2)
    add  eax, HT_SS * HT_SS / 2
    shr  eax, 2 * HT_LOG
    mov  BYTE PTR [rdi], al
    inc  rdi
    inc  ebp
    cmp  ebp, r12d
    jb   hm_px
    inc  esi
    cmp  esi, r12d
    jb   hm_row
    FN_RET
FN_END Msk_Heart

; ---------------------------------------------------------------------------
; Sig_Text(rcx = TXMASK * out, rdx = ASCIIZ text) - one of the two texts.
; ---------------------------------------------------------------------------
FN_BEGIN Sig_Text, 0
    lea  rax, sigReq
    mov  QWORD PTR [rax+FONTREQ.dst], rcx
    mov  QWORD PTR [rax+FONTREQ.text], rdx
    mov  DWORD PTR [rax+FONTREQ.height], SIG_HEIGHT
    mov  DWORD PTR [rax+FONTREQ.weight], SIG_WEIGHT
    mov  DWORD PTR [rax+FONTREQ.face], SIG_FACE
    mov  DWORD PTR [rax+FONTREQ.italic], 0
    mov  DWORD PTR [rax+FONTREQ.track], SIG_TRACK
    mov  rcx, rax
    call Font_Render
    FN_RET
FN_END Sig_Text

; ---------------------------------------------------------------------------
; Sig_Canvas(rcx = TXMASK * out, edx = width, r8d = height) - an empty mask.
; ---------------------------------------------------------------------------
FN_BEGIN Sig_Canvas, 0
    mov  rbx, rcx
    mov  DWORD PTR [rbx+TXMASK.w], edx
    mov  DWORD PTR [rbx+TXMASK.h], r8d
    mov  ecx, edx
    imul ecx, r8d
    call Mem_Alloc
    mov  QWORD PTR [rbx+TXMASK.pix], rax
    FN_RET
FN_END Sig_Canvas

; ---------------------------------------------------------------------------
; Sig_Blit(rcx = TXMASK * canvas, rdx = TXMASK * part, r8d = x, r9d = y)
; Copies the part onto the canvas.  The rectangle must lie inside the canvas;
; Sig_Init arranges that, and the parts of the line never overlap in ink.
; ---------------------------------------------------------------------------
FN_BEGIN Sig_Blit, 0
    mov  r10d, DWORD PTR [rcx+TXMASK.w]    ; pitch of the canvas
    mov  rdi, QWORD PTR [rcx+TXMASK.pix]
    mov  eax, r9d
    imul eax, r10d
    add  eax, r8d
    add  rdi, rax                          ; first byte of the target
    mov  rsi, QWORD PTR [rdx+TXMASK.pix]
    mov  r11d, DWORD PTR [rdx+TXMASK.w]
    mov  ebx, DWORD PTR [rdx+TXMASK.h]
sb_row:
    mov  rax, rdi
    mov  ecx, r11d
    rep  movsb
    lea  rdi, [rax+r10]                    ; the same column, next row
    dec  ebx
    jnz  sb_row
    FN_RET
FN_END Sig_Blit

; ---------------------------------------------------------------------------
; Sig_InkCentre(rcx = TXMASK *) -> eax = middle row of the ink (the rows that
; hold a pixel of SIG_INK or more); half the height when there is no ink.
; ---------------------------------------------------------------------------
FN_BEGIN Sig_InkCentre, 0
    mov  rsi, QWORD PTR [rcx+TXMASK.pix]
    mov  r12d, DWORD PTR [rcx+TXMASK.w]
    mov  r13d, DWORD PTR [rcx+TXMASK.h]
    mov  r14d, -1                          ; first row with ink
    xor  r15d, r15d                        ; last row with ink
    xor  ebx, ebx                          ; row
ic_row:
    xor  ecx, ecx
ic_px:
    cmp  BYTE PTR [rsi+rcx], SIG_INK
    jae  ic_ink
    inc  ecx
    cmp  ecx, r12d
    jb   ic_px
    jmp  ic_next
ic_ink:
    cmp  r14d, -1
    jne  ic_last
    mov  r14d, ebx
ic_last:
    mov  r15d, ebx
ic_next:
    add  rsi, r12                          ; next row
    inc  ebx
    cmp  ebx, r13d
    jb   ic_row
    mov  eax, r13d
    shr  eax, 1                            ; no ink at all: the middle of the mask
    cmp  r14d, -1
    je   ic_done
    lea  eax, [r14+r15+1]
    shr  eax, 1
ic_done:
    FN_RET
FN_END Sig_InkCentre

; ---------------------------------------------------------------------------
; Sig_Compose(ecx = width of the left text mask, edx = width of the right one,
;             r8d = the height of both, which is the same) - lays the parts on
; sigText and sigHeart.
; Both canvases have the same size, so a scene places them with one position.
; ---------------------------------------------------------------------------
FN_BEGIN Sig_Compose, 0
    mov  r12d, ecx
    mov  r13d, edx
    mov  r14d, r8d
    ; width: both texts without their inner margins, two gaps and the heart
    lea  r15d, [r12+r13-2*FONT_PAD+2*SIG_GAP+SIG_HEART]
    lea  rcx, sigText
    mov  edx, r15d
    mov  r8d, r14d
    call Sig_Canvas
    lea  rcx, sigHeart
    mov  edx, r15d
    mov  r8d, r14d
    call Sig_Canvas
    lea  rcx, sigText
    lea  rdx, sigLeft
    xor  r8d, r8d
    xor  r9d, r9d
    call Sig_Blit                          ; the left text at the origin
    lea  rcx, sigText
    lea  rdx, sigRight
    mov  r8d, r15d
    sub  r8d, r13d
    xor  r9d, r9d
    call Sig_Blit                          ; the right text flush with the right edge
    lea  rcx, sigLeft
    call Sig_InkCentre
    sub  eax, SIG_HEART / 2                ; the heart sits on the middle of the ink rows
    lea  rcx, sigHeart
    lea  rdx, sigBox
    lea  r8d, [r12-FONT_PAD+SIG_GAP]       ; SIG_GAP clear pixels after the ink of the left text
    mov  r9d, eax
    call Sig_Blit
    FN_RET
FN_END Sig_Compose

; ---------------------------------------------------------------------------
; Sig_Init - renders the line once; the title and the credits both ask for it.
; ---------------------------------------------------------------------------
FN_BEGIN Sig_Init, 0
    lea  rax, sigText
    cmp  QWORD PTR [rax+TXMASK.pix], 0
    jne  si_done
    lea  rcx, sigLeft
    lea  rdx, szSigLeft
    call Sig_Text
    lea  rcx, sigRight
    lea  rdx, szSigRight
    call Sig_Text
    lea  rcx, sigBox
    mov  edx, SIG_HEART
    call Msk_Heart
    lea  rax, sigLeft
    mov  ecx, DWORD PTR [rax+TXMASK.w]
    mov  r8d, DWORD PTR [rax+TXMASK.h]     ; GDI gives every string of a font the height of its line
    lea  rax, sigRight
    mov  edx, DWORD PTR [rax+TXMASK.w]
    call Sig_Compose
si_done:
    FN_RET
FN_END Sig_Init

END
