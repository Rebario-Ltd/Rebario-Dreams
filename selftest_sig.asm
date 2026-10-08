; ============================================================================
; selftest_sig.asm - built-in checks of the credit line "created with <heart>
;                    by Paul Deecalov (c) 2026" (part of /selftest;
;                    "/selftest sig" runs only these).
; ----------------------------------------------------------------------------
; The line lives on two masks of the same size (sigText, sigHeart), the heart
; is computed by Msk_Heart, and the first and the last scene draw both.  Nobody
; can look at the demo in an automated run, so the checks pin down what a
; viewer would notice:
;   * Msk_Heart: mirror symmetry, the share of the box it fills with soft
;     edges, the cleft on top and the tip below, and the exact coverage of a
;     14 px heart against a reference (heart-ref.py, the same single-precision
;     formula in numpy);
;   * the layout: both canvases have the same size, the heart fills a box of
;     SIG_HEART pixels, the text leaves that hole clear, SIG_GAP pixels to
;     either side, the heart is centred on the text, the words are the right
;     ones in the right order, and Sig_Init builds it all only once;
;   * the scenes: the same moment is rendered twice, once as it is and once
;     with a part of the line wiped from its mask.  The heart may change the
;     frame only inside its box and must make it redder there, the text may
;     change it only inside the canvas and must not be red, the glow or halo
;     of the heart may reach no further than the blur does from the box of the
;     heart, the halo of the text stays inside the canvas, and before the
;     line's time (4.0 s in the title, 12.3 s of the last scene) wiping any
;     of them changes nothing.
; ============================================================================
INCLUDE common.inc

SG_SIZE      EQU 14                      ; the heart under test, pixels
SG_SUM       EQU 31656                   ; its coverage sum (heart-ref.py)
SG_AREA      EQU 255 * SG_SIZE * SG_SIZE ; coverage sum of a completely filled box
SG_INK       EQU 32                      ; coverage from which text counts as ink here
SG_INK_ROWS  EQU 128                     ; ... when its rows are measured
SG_ROW       EQU SCR_H - 40              ; top row of the canvases in the title
SG_CRED_ROW  EQU 232                     ; centre row of the canvases in the last scene
SG_T_BEFORE  EQU 3900                    ; title: just before the line starts (4.0 s)
SG_T_SHOWN   EQU 4800                    ;        just after it has faded in (0.7 s)
SG_V_BEFORE  EQU 8 * SCENE_MS - TRANS_MS + 12200     ; last scene, 12.2 s of its time: the line starts at 12.3 s
SG_V_SHOWN   EQU 8 * SCENE_MS - TRANS_MS + 13400     ;                13.4 s: it has faded in (1.0 s)
SG_RED_GAIN  EQU 60                      ; a pixel of the heart gains this much in (red - green)
SG_MIN_HEART EQU 130                     ; pixels the heart changes in a frame (measured 144 and 163; its mask has 144 with coverage)
SG_MIN_RED   EQU 100                     ; ... of them clearly redder (measured 130 and 132)
SG_MIN_TEXT  EQU 800                     ; pixels the text changes (measured 1239 and 1782)
SG_MAX_RED   EQU 150                     ; ... of them may get redder (measured 53 and 0; the text in the colour of the heart: over 1000)
SG_SPREAD    EQU 10                      ; how far Font_Glow(.., 5) spreads a mask: two box blurs of radius 5

; A glow or a halo that a scene draws around the line: its mask, how many
; pixels of the frame it may change (the range is measured) and the name of its check.
SGGLOW STRUCT
    glow    QWORD ?                      ; TXMASK *, 0 ends the table
    least   DWORD ?
    most    DWORD ?
    report  QWORD ?
    reach   DWORD ?                      ; 0: it may change the canvas, else: no further than this from the box of the heart
    pad     DWORD ?
SGGLOW ENDS

; One scene to check: when it shows the line, when it does not yet, where the
; canvases stand on the screen, the names of its checks and its glows.
SGCASE STRUCT
    scene   DWORD ?
    shown   DWORD ?                      ; demo time with the whole line on the screen
    before  DWORD ?                      ; demo time before the line starts
    row     DWORD ?                      ; screen row of the canvases ...
    centred DWORD ?                      ; ... 1: their centre row, 0: their top row
    pad     DWORD ?
    nHeart  QWORD ?                      ; names of the checks
    nText   QWORD ?
    nLate   QWORD ?
    glows   QWORD ?                      ; SGGLOW[], ended by an entry without a mask
SGCASE ENDS

.const
szSgOnce    BYTE "sig: Sig_Init builds the line only once", 0
szSgMirror  BYTE "sig: the heart is mirror-symmetric", 0
szSgFill    BYTE "sig: the heart fills 55..70 % of its box and has soft edges", 0
szSgShape   BYTE "sig: the heart has a cleft on top and a tip below", 0
szSgRef     BYTE "sig: the heart equals the reference coverage (sum 31656 at 14 px)", 0
szSgSame    BYTE "sig: the text and the heart have canvases of the same size", 0
szSgBox     BYTE "sig: the heart fills a box of SIG_HEART pixels, no more", 0
szSgHole    BYTE "sig: the text leaves the box of the heart clear", 0
szSgGap     BYTE "sig: the heart has SIG_GAP pixels (up to four more) to the text on either side, evenly", 0
szSgMid     BYTE "sig: the heart is centred on the text", 0
szSgWords   BYTE "sig: the words are ""created with"" and ""by Paul Deecalov (c) 2026"", in this order", 0
szSgTHeart  BYTE "sig: title - the heart is drawn in red inside its box", 0
szSgTText   BYTE "sig: title - the text is drawn inside its canvas, not in red", 0
szSgTGlow   BYTE "sig: title - the red glow lies around the heart, no further than it blurs", 0
szSgTLate   BYTE "sig: title - nothing of the line is drawn before 4.0 s", 0
szSgVHeart  BYTE "sig: credits - the heart is drawn in red inside its box", 0
szSgVText   BYTE "sig: credits - the text is drawn inside its canvas, not in red", 0
szSgVHaloT  BYTE "sig: credits - the dark halo lies around the text inside the canvas", 0
szSgVHaloH  BYTE "sig: credits - the dark red halo lies around the heart, no further than it blurs", 0
szSgVLate   BYTE "sig: credits - nothing of the line is drawn before 12.3 s", 0
szWantLeft  BYTE "created with", 0
szWantRight BYTE "by Paul Deecalov (c) 2026", 0

ALIGN 8
sgTGlows    SGGLOW <titHeartGlow, 450, 900, szSgTGlow, SG_SPREAD, 0>        ; measured 622
            SGGLOW <0, 0, 0, 0, 0, 0>
sgVGlows    SGGLOW <vxHLine, 7000, 11000, szSgVHaloT, 0, 0>                 ; measured 8924
            SGGLOW <vxHHeart, 500, 900, szSgVHaloH, SG_SPREAD, 0>           ; measured 660
            SGGLOW <0, 0, 0, 0, 0, 0>
sgCases     SGCASE <0, SG_T_SHOWN, SG_T_BEFORE, SG_ROW, 0, 0, szSgTHeart, szSgTText, szSgTLate, sgTGlows>
            SGCASE <8, SG_V_SHOWN, SG_V_BEFORE, SG_CRED_ROW, 1, 0, szSgVHeart, szSgVText, szSgVLate, sgVGlows>
SG_CASES    EQU 2
.ERRNZ ($ - sgCases) - SG_CASES * SIZEOF SGCASE

.data?
ALIGN 16
sgMask      BYTE 16 DUP (?)              ; TXMASK of the heart under test
sgFbA       QWORD ?                      ; the frame as it is
sgFbB       QWORD ?                      ; the same frame with a part of the line wiped
sgBak       QWORD ?                      ; the wiped mask, kept for putting it back
sgBx0       SDWORD ?                     ; Sg_Bounds: the box of the ink, columns / rows inclusive
sgBx1       SDWORD ?
sgBy0       SDWORD ?
sgBy1       SDWORD ?
sgHx0       SDWORD ?                     ; box of the heart in its canvas
sgHx1       SDWORD ?
sgHy0       SDWORD ?
sgHy1       SDWORD ?
sgLx0       SDWORD ?                     ; columns of the ink of the text left of the heart
sgLx1       SDWORD ?
sgRx0       SDWORD ?                     ; ... and right of it
sgRx1       SDWORD ?
sgRcX0      SDWORD ?                     ; Sg_Diff: the rectangle (end excluded)
sgRcY0      SDWORD ?
sgRcX1      SDWORD ?
sgRcY1      SDWORD ?
sgRedder    DWORD ?                      ; Sg_Diff: pixels inside it that gained in red
sgLeft      SDWORD ?                     ; the canvases on the screen: left column ...
sgTop       SDWORD ?                     ; ... and top row

.code

; ---------------------------------------------------------------------------
; Sg_StrEq(rcx = a, rdx = b) -> eax = 1 when the two ASCIIZ strings are equal.
; ---------------------------------------------------------------------------
LEAF_BEGIN Sg_StrEq
se_lp:
    mov    al, BYTE PTR [rcx]
    cmp    al, BYTE PTR [rdx]
    jne    se_no
    inc    rcx
    inc    rdx
    test   al, al
    jnz    se_lp
    mov    eax, 1
    ret
se_no:
    xor    eax, eax
    ret
LEAF_END Sg_StrEq

; ---------------------------------------------------------------------------
; Sg_Stats(rcx = TXMASK *) -> eax = sum of the coverage, edx = number of pixels
; that are neither empty nor full.
; ---------------------------------------------------------------------------
LEAF_BEGIN Sg_Stats
    mov    r8, QWORD PTR [rcx+TXMASK.pix]
    mov    r9d, DWORD PTR [rcx+TXMASK.w]
    imul   r9d, DWORD PTR [rcx+TXMASK.h]
    xor    eax, eax
    xor    edx, edx
ss_lp:
    movzx  r10d, BYTE PTR [r8]
    add    eax, r10d
    dec    r10d
    cmp    r10d, 253                       ; 1..254 -> 0..253; 0 wraps around
    ja     ss_hard
    inc    edx
ss_hard:
    inc    r8
    dec    r9d
    jnz    ss_lp
    ret
LEAF_END Sg_Stats

; ---------------------------------------------------------------------------
; Sg_RowSum(rcx = TXMASK *, edx = row) -> eax = coverage sum of that row.
; ---------------------------------------------------------------------------
LEAF_BEGIN Sg_RowSum
    mov    r9d, DWORD PTR [rcx+TXMASK.w]
    mov    r8, QWORD PTR [rcx+TXMASK.pix]
    imul   edx, r9d
    add    r8, rdx
    xor    eax, eax
rs_lp:
    movzx  edx, BYTE PTR [r8]
    add    eax, edx
    inc    r8
    dec    r9d
    jnz    rs_lp
    ret
LEAF_END Sg_RowSum

; ---------------------------------------------------------------------------
; Sg_Mirror -> eax = 1 when every row of the heart reads the same from both ends.
; ---------------------------------------------------------------------------
LEAF_BEGIN Sg_Mirror
    lea    rax, sgMask
    mov    r8, QWORD PTR [rax+TXMASK.pix]
    mov    eax, 1
    xor    r9d, r9d                        ; row
sm_row:
    xor    ecx, ecx                        ; column
sm_px:
    mov    edx, r9d
    imul   edx, SG_SIZE
    lea    r10d, [rdx+rcx]                 ; this pixel
    lea    r11d, [rdx+SG_SIZE-1]
    sub    r11d, ecx                       ; its mirror image
    mov    dl, BYTE PTR [r8+r10]
    cmp    dl, BYTE PTR [r8+r11]
    je     sm_same
    xor    eax, eax
sm_same:
    inc    ecx
    cmp    ecx, SG_SIZE
    jb     sm_px
    inc    r9d
    cmp    r9d, SG_SIZE
    jb     sm_row
    ret
LEAF_END Sg_Mirror

; ---------------------------------------------------------------------------
; St_SigHeart - Msk_Heart: symmetry, fill, cleft and tip, and the reference.
; ---------------------------------------------------------------------------
FN_BEGIN St_SigHeart, 0
    lea    rcx, sgMask
    mov    edx, SG_SIZE
    call   Msk_Heart
    call   Sg_Mirror
    mov    edx, eax
    lea    rcx, szSgMirror
    call   St_Report
    lea    rcx, sgMask
    call   Sg_Stats
    mov    ebx, eax                        ; coverage sum
    mov    esi, edx                        ; soft pixels
    imul   eax, ebx, 100
    xor    edx, edx
    cmp    eax, 55 * SG_AREA
    setae  dl
    cmp    eax, 70 * SG_AREA
    setbe  cl
    and    dl, cl
    cmp    esi, 20
    setae  cl
    and    dl, cl
    movzx  edx, dl
    lea    rcx, szSgFill
    call   St_Report
    xor    edx, edx
    cmp    ebx, SG_SUM
    sete   dl
    lea    rcx, szSgRef
    call   St_Report
    call   St_SigShape
    FN_RET
FN_END St_SigHeart

; ---------------------------------------------------------------------------
; St_SigShape - the heart dips between its lobes and narrows to a tip.
; ---------------------------------------------------------------------------
FN_BEGIN St_SigShape, 0
    lea    rax, sgMask
    mov    rsi, QWORD PTR [rax+TXMASK.pix]
    movzx  eax, BYTE PTR [rsi+SG_SIZE+SG_SIZE/2-1]       ; row 1, the middle left of the cleft
    add    eax, 64
    movzx  ecx, BYTE PTR [rsi+SG_SIZE+SG_SIZE/2-3]       ; row 1, on the left lobe
    cmp    eax, ecx
    setbe  bl                              ; the cleft is at least 64 below the lobe
    lea    rcx, sgMask
    mov    edx, 4
    call   Sg_RowSum
    mov    edi, eax                        ; the widest part
    lea    rcx, sgMask
    mov    edx, SG_SIZE - 2
    call   Sg_RowSum
    mov    esi, eax                        ; the row above the last
    shl    eax, 2
    cmp    eax, edi
    setb   cl
    and    bl, cl                          ; narrower than a quarter of the widest
    lea    rcx, sgMask
    mov    edx, SG_SIZE - 1
    call   Sg_RowSum
    cmp    eax, esi
    setb   cl
    and    bl, cl                          ; and still narrowing
    lea    rcx, sgMask
    xor    edx, edx
    call   Sg_RowSum
    cmp    eax, edi
    setb   cl
    and    bl, cl                          ; the top row only holds the tops of the lobes
    movzx  edx, bl
    lea    rcx, szSgShape
    call   St_Report
    FN_RET
FN_END St_SigShape

; ---------------------------------------------------------------------------
; Sg_Bounds(rcx = TXMASK *, edx = threshold, r8d = first column, r9d = end
; column) -> eax = 1 when a pixel in those columns reaches the threshold;
; sgBx0..sgBy1 = the box of such pixels (inclusive).  The columns are clipped
; to the mask, so a heart that has gone missing (its box is then 7FFFFFFFh..-1)
; makes the checks fail instead of reading far outside the mask.
; ---------------------------------------------------------------------------
FN_BEGIN Sg_Bounds, 0
    mov    rsi, QWORD PTR [rcx+TXMASK.pix]
    mov    r12d, DWORD PTR [rcx+TXMASK.w]
    mov    r13d, DWORD PTR [rcx+TXMASK.h]
    mov    r14d, 7FFFFFFFh                 ; first column
    mov    r15d, -1                        ; last column
    mov    edi, 7FFFFFFFh                  ; first row
    mov    ebp, -1                         ; last row
    xor    ebx, ebx                        ; row
    test   r8d, r8d
    cmovs  r8d, ebx
    cmp    r9d, r12d
    cmovg  r9d, r12d
    cmp    r8d, r9d
    jge    sb_done                         ; no columns, no ink
sb_row:
    mov    ecx, r8d
sb_px:
    mov    eax, ebx
    imul   eax, r12d
    add    eax, ecx
    cmp    BYTE PTR [rsi+rax], dl
    jb     sb_next
    cmp    ecx, r14d
    cmovl  r14d, ecx
    cmp    ecx, r15d
    cmovg  r15d, ecx
    cmp    ebx, edi
    cmovl  edi, ebx
    cmp    ebx, ebp
    cmovg  ebp, ebx
sb_next:
    inc    ecx
    cmp    ecx, r9d
    jb     sb_px
    inc    ebx
    cmp    ebx, r13d
    jb     sb_row
sb_done:
    mov    DWORD PTR sgBx0, r14d
    mov    DWORD PTR sgBx1, r15d
    mov    DWORD PTR sgBy0, edi
    mov    DWORD PTR sgBy1, ebp
    xor    eax, eax
    test   r15d, r15d
    setns  al
    FN_RET
FN_END Sg_Bounds

; ---------------------------------------------------------------------------
; Sg_Measure - boxes of the ink: the heart in its canvas, the text left and
; right of it (sgHx0.., sgLx0.., sgRx0..).
; ---------------------------------------------------------------------------
FN_BEGIN Sg_Measure, 0
    lea    rcx, sigHeart
    mov    edx, 1
    xor    r8d, r8d
    mov    r9d, DWORD PTR [rcx+TXMASK.w]
    call   Sg_Bounds
    mov    eax, DWORD PTR sgBx0
    mov    DWORD PTR sgHx0, eax
    mov    eax, DWORD PTR sgBx1
    mov    DWORD PTR sgHx1, eax
    mov    eax, DWORD PTR sgBy0
    mov    DWORD PTR sgHy0, eax
    mov    eax, DWORD PTR sgBy1
    mov    DWORD PTR sgHy1, eax
    lea    rcx, sigText
    mov    edx, SG_INK
    xor    r8d, r8d
    mov    r9d, DWORD PTR sgHx0
    call   Sg_Bounds
    mov    eax, DWORD PTR sgBx0
    mov    DWORD PTR sgLx0, eax
    mov    eax, DWORD PTR sgBx1
    mov    DWORD PTR sgLx1, eax
    lea    rcx, sigText
    mov    edx, SG_INK
    mov    r8d, DWORD PTR sgHx1
    inc    r8d
    mov    r9d, DWORD PTR [rcx+TXMASK.w]
    call   Sg_Bounds
    mov    eax, DWORD PTR sgBx0
    mov    DWORD PTR sgRx0, eax
    mov    eax, DWORD PTR sgBx1
    mov    DWORD PTR sgRx1, eax
    FN_RET
FN_END Sg_Measure

; ---------------------------------------------------------------------------
; St_SigPlace - where the heart stands between the two texts.
; ---------------------------------------------------------------------------
FN_BEGIN St_SigPlace, 0
    call   Sg_Measure
    mov    eax, DWORD PTR sgHx1            ; the box: SIG_HEART x SIG_HEART
    sub    eax, DWORD PTR sgHx0
    cmp    eax, SIG_HEART - 1
    sete   bl
    mov    eax, DWORD PTR sgHy1
    sub    eax, DWORD PTR sgHy0
    cmp    eax, SIG_HEART - 1
    sete   cl
    and    bl, cl
    movzx  edx, bl
    lea    rcx, szSgBox
    call   St_Report
    lea    rcx, sigText                    ; no ink of the text where the heart is
    mov    edx, SG_INK
    mov    r8d, DWORD PTR sgHx0
    mov    r9d, DWORD PTR sgHx1
    inc    r9d
    call   Sg_Bounds
    xor    edx, edx
    test   eax, eax
    sete   dl
    lea    rcx, szSgHole
    call   St_Report
    mov    esi, DWORD PTR sgHx0            ; gap on the left: SIG_GAP .. SIG_GAP + 4 (measured 8)
    sub    esi, DWORD PTR sgLx1
    dec    esi
    mov    edi, DWORD PTR sgRx0            ; ... and on the right (measured 7)
    sub    edi, DWORD PTR sgHx1
    dec    edi
    lea    eax, [rsi-SIG_GAP]
    cmp    eax, 4
    setbe  bl                              ; (below SIG_GAP the unsigned value wraps around)
    lea    eax, [rdi-SIG_GAP]
    cmp    eax, 4
    setbe  cl
    and    bl, cl
    lea    eax, [rsi+2]
    sub    eax, edi                        ; the two gaps differ by at most two pixels
    cmp    eax, 4
    setbe  cl
    and    bl, cl
    movzx  edx, bl
    lea    rcx, szSgGap
    call   St_Report
    call   St_SigMiddle
    FN_RET
FN_END St_SigPlace

; ---------------------------------------------------------------------------
; St_SigMiddle - the heart sits on the middle of the rows of the left text
; (half a pixel of tolerance either way).
; ---------------------------------------------------------------------------
FN_BEGIN St_SigMiddle, 0
    lea    rcx, sigText
    mov    edx, SG_INK_ROWS
    xor    r8d, r8d
    mov    r9d, DWORD PTR sgHx0
    call   Sg_Bounds
    mov    eax, DWORD PTR sgBy0
    add    eax, DWORD PTR sgBy1            ; twice the middle row of the text
    sub    eax, DWORD PTR sgHy0
    sub    eax, DWORD PTR sgHy1            ; minus twice the middle row of the heart
    inc    eax
    xor    edx, edx
    cmp    eax, 2
    setbe  dl                              ; -1 .. +1
    lea    rcx, szSgMid
    call   St_Report
    FN_RET
FN_END St_SigMiddle

; ---------------------------------------------------------------------------
; St_SigWords - the two texts, in the right order (the second is twice as long).
; ---------------------------------------------------------------------------
FN_BEGIN St_SigWords, 0
    lea    rcx, szSigLeft
    lea    rdx, szWantLeft
    call   Sg_StrEq
    mov    ebx, eax
    lea    rcx, szSigRight
    lea    rdx, szWantRight
    call   Sg_StrEq
    and    ebx, eax
    mov    eax, DWORD PTR sgLx1            ; the text on the left is the shorter one
    sub    eax, DWORD PTR sgLx0
    imul   eax, 3
    mov    ecx, DWORD PTR sgRx1
    sub    ecx, DWORD PTR sgRx0
    add    ecx, ecx
    cmp    eax, ecx
    setbe  al                              ; right >= 1.5 x left (the strings are 25 and 12 characters)
    movzx  eax, al
    and    ebx, eax
    mov    edx, ebx
    lea    rcx, szSgWords
    call   St_Report
    FN_RET
FN_END St_SigWords

; ---------------------------------------------------------------------------
; St_SigLayout - the canvases.  Nothing is measured unless both exist.
; ---------------------------------------------------------------------------
FN_BEGIN St_SigLayout, 0
    lea    rsi, sigText
    lea    rdi, sigHeart
    xor    ebx, ebx
    cmp    QWORD PTR [rsi+TXMASK.pix], 0
    je     sl_same
    cmp    QWORD PTR [rdi+TXMASK.pix], 0
    je     sl_same
    mov    eax, DWORD PTR [rsi+TXMASK.w]
    cmp    eax, DWORD PTR [rdi+TXMASK.w]
    sete   bl
    mov    eax, DWORD PTR [rsi+TXMASK.h]
    cmp    eax, DWORD PTR [rdi+TXMASK.h]
    sete   cl
    and    bl, cl
sl_same:
    movzx  edx, bl
    lea    rcx, szSgSame
    call   St_Report
    test   ebx, ebx
    jz     sl_done                         ; (the checks below would read nothing)
    call   St_SigPlace
    call   St_SigWords
sl_done:
    FN_RET
FN_END St_SigLayout

; ---------------------------------------------------------------------------
; Sg_Diff -> eax = pixels that differ between sgFbA and sgFbB inside the
; rectangle sgRcX0.. (end excluded), edx = those outside it; sgRedder = the
; pixels inside that are redder in sgFbA by SG_RED_GAIN in (red - green).
; ---------------------------------------------------------------------------
RMG MACRO dst:REQ, src:REQ, tmp:REQ        ; dst = red - green of the BGRA pixel in src
    mov    dst, src
    shr    dst, 16
    and    dst, 255
    mov    tmp, src
    shr    tmp, 8
    and    tmp, 255
    sub    dst, tmp
ENDM

FN_BEGIN Sg_Diff, 0
    mov    rsi, QWORD PTR sgFbA
    mov    rdi, QWORD PTR sgFbB
    xor    r12d, r12d                      ; differ inside
    xor    r13d, r13d                      ; differ outside
    mov    DWORD PTR sgRedder, 0
    xor    r14d, r14d                      ; y
sd_row:
    xor    r15d, r15d                      ; x
sd_px:
    mov    eax, r14d
    imul   eax, SCR_W
    add    eax, r15d
    mov    r8d, DWORD PTR [rsi+rax*4]
    mov    r9d, DWORD PTR [rdi+rax*4]
    cmp    r8d, r9d
    je     sd_next
    cmp    r15d, DWORD PTR sgRcX0
    jl     sd_out
    cmp    r15d, DWORD PTR sgRcX1
    jge    sd_out
    cmp    r14d, DWORD PTR sgRcY0
    jl     sd_out
    cmp    r14d, DWORD PTR sgRcY1
    jge    sd_out
    inc    r12d
    RMG    eax, r8d, r10d
    RMG    r11d, r9d, r10d
    sub    eax, r11d
    cmp    eax, SG_RED_GAIN
    jl     sd_next
    inc    DWORD PTR sgRedder
    jmp    sd_next
sd_out:
    inc    r13d
sd_next:
    inc    r15d
    cmp    r15d, SCR_W
    jb     sd_px
    inc    r14d
    cmp    r14d, SCR_H
    jb     sd_row
    mov    eax, r12d
    mov    edx, r13d
    FN_RET
FN_END Sg_Diff

; ---------------------------------------------------------------------------
; Sg_Pair(ecx = scene, edx = demo ms, r8 = TXMASK * part) - renders the scene
; into sgFbA, wipes the part, renders it into sgFbB and puts the part back.
; ---------------------------------------------------------------------------
FN_BEGIN Sg_Pair, 0
    mov    r12d, ecx
    mov    r13d, edx
    mov    r14, r8
    mov    rdx, QWORD PTR sgFbA
    mov    r8d, r13d
    call   Tl_RenderScene                  ; (ecx still holds the scene)
    mov    rsi, QWORD PTR [r14+TXMASK.pix]
    mov    ebx, DWORD PTR [r14+TXMASK.w]
    imul   ebx, DWORD PTR [r14+TXMASK.h]   ; bytes of the part
    mov    rdi, QWORD PTR sgBak
    mov    ecx, ebx
    rep    movsb                           ; keep it
    mov    rdi, QWORD PTR [r14+TXMASK.pix]
    mov    ecx, ebx
    xor    eax, eax
    rep    stosb                           ; wipe it
    mov    ecx, r12d
    mov    rdx, QWORD PTR sgFbB
    mov    r8d, r13d
    call   Tl_RenderScene
    mov    rsi, QWORD PTR sgBak
    mov    rdi, QWORD PTR [r14+TXMASK.pix]
    mov    ecx, ebx
    rep    movsb                           ; put it back
    FN_RET
FN_END Sg_Pair

; ---------------------------------------------------------------------------
; Sg_SetRect(ecx = x0, edx = y0, r8d = x1, r9d = y1) - the rectangle of Sg_Diff.
; ---------------------------------------------------------------------------
LEAF_BEGIN Sg_SetRect
    mov    DWORD PTR sgRcX0, ecx
    mov    DWORD PTR sgRcY0, edx
    mov    DWORD PTR sgRcX1, r8d
    mov    DWORD PTR sgRcY1, r9d
    ret
LEAF_END Sg_SetRect

; ---------------------------------------------------------------------------
; Sg_SetCanvas - the rectangle of Sg_Diff = the canvas on the screen, one
; pixel more to the right and down for a drop shadow.
; ---------------------------------------------------------------------------
FN_BEGIN Sg_SetCanvas, 0
    lea    rsi, sigText
    mov    ecx, DWORD PTR sgLeft
    mov    edx, DWORD PTR sgTop
    lea    r8d, [rcx+1]
    add    r8d, DWORD PTR [rsi+TXMASK.w]
    lea    r9d, [rdx+1]
    add    r9d, DWORD PTR [rsi+TXMASK.h]
    call   Sg_SetRect
    FN_RET
FN_END Sg_SetCanvas

; ---------------------------------------------------------------------------
; Sg_SetHeart(ecx = reach) - the rectangle of Sg_Diff = the box of the heart
; on the screen, `reach` pixels more on every side (what a glow may spread)
; and one more to the right and down for a drop shadow.
; ---------------------------------------------------------------------------
FN_BEGIN Sg_SetHeart, 0
    mov    r12d, ecx
    mov    ecx, DWORD PTR sgLeft
    add    ecx, DWORD PTR sgHx0
    sub    ecx, r12d
    mov    edx, DWORD PTR sgTop
    add    edx, DWORD PTR sgHy0
    sub    edx, r12d
    mov    r8d, DWORD PTR sgLeft
    add    r8d, DWORD PTR sgHx1
    lea    r8d, [r8+r12+2]                 ; (the last column of the box, end excluded, drop shadow)
    mov    r9d, DWORD PTR sgTop
    add    r9d, DWORD PTR sgHy1
    lea    r9d, [r9+r12+2]
    call   Sg_SetRect
    FN_RET
FN_END Sg_SetHeart

; ---------------------------------------------------------------------------
; Sg_LateOne(rcx = SGCASE *, rdx = TXMASK *) -> eax = 1 when wiping that mask
; changes nothing in the frame before the line starts.
; ---------------------------------------------------------------------------
FN_BEGIN Sg_LateOne, 0
    mov    r8, rdx
    mov    edx, DWORD PTR [rcx+SGCASE.before]
    mov    ecx, DWORD PTR [rcx+SGCASE.scene]
    call   Sg_Pair
    xor    ecx, ecx
    xor    edx, edx
    mov    r8d, SCR_W
    mov    r9d, SCR_H
    call   Sg_SetRect
    call   Sg_Diff
    or     eax, edx
    sete   al                              ; no difference anywhere
    movzx  eax, al
    FN_RET
FN_END Sg_LateOne

; ---------------------------------------------------------------------------
; Sg_Late(rcx = SGCASE *) -> eax = 1 when, before the line starts, wiping any
; of its masks (heart, text, glow, halos) changes nothing in the frame.
; ---------------------------------------------------------------------------
FN_BEGIN Sg_Late, 0
    mov    r12, rcx
    lea    rdx, sigHeart
    call   Sg_LateOne
    mov    ebx, eax
    mov    rcx, r12
    lea    rdx, sigText
    call   Sg_LateOne
    and    ebx, eax
    mov    rsi, QWORD PTR [r12+SGCASE.glows]
lt_glow:
    mov    rdx, QWORD PTR [rsi+SGGLOW.glow]
    test   rdx, rdx
    jz     lt_done
    mov    rcx, r12
    call   Sg_LateOne
    and    ebx, eax
    add    rsi, SIZEOF SGGLOW
    jmp    lt_glow
lt_done:
    mov    eax, ebx
    FN_RET
FN_END Sg_Late

; ---------------------------------------------------------------------------
; Sg_CaseHeart(rcx = SGCASE *) - wipe the heart: the frame may change only in
; its box, in at least SG_MIN_HEART pixels, and become redder there.
; ---------------------------------------------------------------------------
FN_BEGIN Sg_CaseHeart, 0
    mov    r12, rcx
    mov    ecx, DWORD PTR [r12+SGCASE.scene]
    mov    edx, DWORD PTR [r12+SGCASE.shown]
    lea    r8, sigHeart
    call   Sg_Pair
    xor    ecx, ecx
    call   Sg_SetHeart                     ; just its box
    call   Sg_Diff
    xor    ebx, ebx
    cmp    eax, SG_MIN_HEART
    setae  bl                              ; it changes the picture ...
    test   edx, edx
    sete   cl
    and    bl, cl                          ; ... nowhere else ...
    cmp    DWORD PTR sgRedder, SG_MIN_RED
    setae  cl
    and    bl, cl                          ; ... and makes it redder
    movzx  edx, bl
    mov    rcx, QWORD PTR [r12+SGCASE.nHeart]
    call   St_Report
    FN_RET
FN_END Sg_CaseHeart

; ---------------------------------------------------------------------------
; Sg_CaseText(rcx = SGCASE *) - wipe the text: the frame may change only inside
; the canvas, in at least SG_MIN_TEXT pixels, and not towards red.
; ---------------------------------------------------------------------------
FN_BEGIN Sg_CaseText, 0
    mov    r12, rcx
    mov    ecx, DWORD PTR [r12+SGCASE.scene]
    mov    edx, DWORD PTR [r12+SGCASE.shown]
    lea    r8, sigText
    call   Sg_Pair
    call   Sg_SetCanvas
    call   Sg_Diff
    xor    ebx, ebx
    cmp    eax, SG_MIN_TEXT
    setae  bl
    test   edx, edx
    sete   cl
    and    bl, cl
    cmp    DWORD PTR sgRedder, SG_MAX_RED
    setbe  cl
    and    bl, cl                          ; (the text in the colour of the heart would redden it all)
    movzx  edx, bl
    mov    rcx, QWORD PTR [r12+SGCASE.nText]
    call   St_Report
    FN_RET
FN_END Sg_CaseText

; ---------------------------------------------------------------------------
; Sg_CaseGlow(rcx = SGCASE *, rdx = SGGLOW *) - wipe a glow or a halo: the
; frame may change only inside the canvas (a glow of the heart: no further
; from its box than the blur spreads), in as many pixels as it was measured
; to change.
; ---------------------------------------------------------------------------
FN_BEGIN Sg_CaseGlow, 0
    mov    r12, rcx
    mov    r13, rdx
    mov    r8, QWORD PTR [r13+SGGLOW.glow]
    mov    ecx, DWORD PTR [r12+SGCASE.scene]
    mov    edx, DWORD PTR [r12+SGCASE.shown]
    call   Sg_Pair
    mov    ecx, DWORD PTR [r13+SGGLOW.reach]
    test   ecx, ecx
    jz     cg_canvas
    call   Sg_SetHeart
    jmp    cg_diff
cg_canvas:
    call   Sg_SetCanvas
cg_diff:
    call   Sg_Diff
    xor    ebx, ebx
    cmp    eax, DWORD PTR [r13+SGGLOW.least]
    setae  bl
    cmp    eax, DWORD PTR [r13+SGGLOW.most]
    setbe  cl
    and    bl, cl
    test   edx, edx
    sete   cl
    and    bl, cl
    movzx  edx, bl
    mov    rcx, QWORD PTR [r13+SGGLOW.report]
    call   St_Report
    FN_RET
FN_END Sg_CaseGlow

; ---------------------------------------------------------------------------
; Sg_Case(rcx = SGCASE *) - the checks of one scene.
; ---------------------------------------------------------------------------
FN_BEGIN Sg_Case, 0
    mov    r12, rcx
    lea    rsi, sigText
    mov    eax, SCR_W
    sub    eax, DWORD PTR [rsi+TXMASK.w]
    shr    eax, 1
    mov    DWORD PTR sgLeft, eax           ; the canvases are centred on the screen
    mov    eax, DWORD PTR [r12+SGCASE.row]
    cmp    DWORD PTR [r12+SGCASE.centred], 0
    je     sc_top
    mov    ecx, DWORD PTR [rsi+TXMASK.h]
    shr    ecx, 1
    sub    eax, ecx                        ; a centre row: top = centre - height / 2
sc_top:
    mov    DWORD PTR sgTop, eax
    mov    rcx, r12
    call   Sg_CaseHeart
    mov    rcx, r12
    call   Sg_CaseText
    mov    rdi, QWORD PTR [r12+SGCASE.glows]
sc_glow:
    cmp    QWORD PTR [rdi+SGGLOW.glow], 0
    je     sc_late
    mov    rcx, r12
    mov    rdx, rdi
    call   Sg_CaseGlow
    add    rdi, SIZEOF SGGLOW
    jmp    sc_glow
sc_late:
    mov    rcx, r12
    call   Sg_Late
    mov    edx, eax
    mov    rcx, QWORD PTR [r12+SGCASE.nLate]
    call   St_Report
    FN_RET
FN_END Sg_Case

; ---------------------------------------------------------------------------
; St_SigOnce - a second Sig_Init leaves both canvases where they are.
; ---------------------------------------------------------------------------
FN_BEGIN St_SigOnce, 0
    lea    rax, sigText
    mov    rbx, QWORD PTR [rax+TXMASK.pix]
    lea    rax, sigHeart
    mov    rsi, QWORD PTR [rax+TXMASK.pix]
    call   Sig_Init
    xor    edx, edx
    lea    rax, sigText
    cmp    rbx, QWORD PTR [rax+TXMASK.pix]
    sete   dl
    lea    rax, sigHeart
    cmp    rsi, QWORD PTR [rax+TXMASK.pix]
    sete   cl
    and    dl, cl
    test   rbx, rbx
    setnz  cl
    and    dl, cl                          ; (and they were built in the first place)
    movzx  edx, dl
    lea    rcx, szSgOnce
    call   St_Report
    FN_RET
FN_END St_SigOnce

; ---------------------------------------------------------------------------
; St_Sig - every check of the credit line.
; ---------------------------------------------------------------------------
FN_BEGIN St_Sig, 0
    call   St_SigOnce
    call   St_SigHeart
    call   St_SigLayout
    lea    rax, sigText
    cmp    QWORD PTR [rax+TXMASK.pix], 0
    je     sg_done                         ; nothing was built: the checks above have failed
    mov    ecx, SCR_BYTES
    call   Mem_Alloc
    mov    QWORD PTR sgFbA, rax
    mov    ecx, SCR_BYTES
    call   Mem_Alloc
    mov    QWORD PTR sgFbB, rax
    lea    rax, sigText
    mov    ecx, DWORD PTR [rax+TXMASK.w]
    imul   ecx, DWORD PTR [rax+TXMASK.h]
    call   Mem_Alloc
    mov    QWORD PTR sgBak, rax            ; room for the canvas that is wiped
    xor    ebx, ebx
sg_case:
    imul   ecx, ebx, SIZEOF SGCASE
    lea    rax, sgCases
    add    rcx, rax
    call   Sg_Case
    inc    ebx
    cmp    ebx, SG_CASES
    jb     sg_case
sg_done:
    FN_RET
FN_END St_Sig

END
