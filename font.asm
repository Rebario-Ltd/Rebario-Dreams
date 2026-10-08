; ============================================================================
; font.asm - text -> 8-bit coverage masks through GDI (anti-aliased fonts)
; ----------------------------------------------------------------------------
; Masks carry PAD pixels of empty margin on every side so that a later blur
; (glow) never clips.
; ============================================================================
INCLUDE common.inc
INCLUDE win.inc

.const
szFace0 BYTE "Segoe UI Black", 0
szFace1 BYTE "Bahnschrift", 0
szFace2 BYTE "Consolas", 0
szFace3 BYTE "Impact", 0
szFace4 BYTE "Segoe UI Light", 0
szFontErr BYTE "GDI text rendering failed", 0
ALIGN 8
faceTab QWORD szFace0, szFace1, szFace2, szFace3, szFace4

.code

; ---------------------------------------------------------------------------
; Font_Render(rcx = FONTREQ *) - renders req.text into a freshly allocated mask.
; Locals: +0 hdc, +8 font, +16 old font, +24 bitmap, +32 old bitmap, +40 bits,
;         +48 SIZE, +56 BITMAPINFOHEADER (40 bytes)
; ---------------------------------------------------------------------------
FN_BEGIN Font_Render, 112
    mov  rbx, rcx
    mov  rsi, QWORD PTR [rbx+FONTREQ.text]
    xor  r12d, r12d
fr_len:
    cmp  BYTE PTR [rsi+r12], 0
    je   fr_len_end
    inc  r12d
    jmp  fr_len
fr_len_end:                                ; r12d = text length
    xor  ecx, ecx
    call CreateCompatibleDC
    mov  QWORD PTR [rsp+LOC], rax
    mov  ecx, DWORD PTR [rbx+FONTREQ.height]
    neg  ecx
    xor  edx, edx
    xor  r8d, r8d
    xor  r9d, r9d
    mov  eax, DWORD PTR [rbx+FONTREQ.weight]
    mov  QWORD PTR [rsp+32], rax
    mov  eax, DWORD PTR [rbx+FONTREQ.italic]
    mov  QWORD PTR [rsp+40], rax
    mov  QWORD PTR [rsp+48], 0             ; underline
    mov  QWORD PTR [rsp+56], 0             ; strike-out
    mov  QWORD PTR [rsp+64], 1             ; DEFAULT_CHARSET
    mov  QWORD PTR [rsp+72], 4             ; OUT_TT_PRECIS
    mov  QWORD PTR [rsp+80], 0             ; CLIP_DEFAULT_PRECIS
    mov  QWORD PTR [rsp+88], 4             ; ANTIALIASED_QUALITY
    mov  QWORD PTR [rsp+96], 0             ; DEFAULT_PITCH | FF_DONTCARE
    mov  eax, DWORD PTR [rbx+FONTREQ.face]
    lea  rdx, faceTab
    mov  rax, QWORD PTR [rdx+rax*8]
    mov  QWORD PTR [rsp+104], rax
    call CreateFontA
    mov  QWORD PTR [rsp+LOC+8], rax
    mov  rcx, QWORD PTR [rsp+LOC]
    mov  rdx, rax
    call SelectObject
    mov  QWORD PTR [rsp+LOC+16], rax
    mov  rcx, QWORD PTR [rsp+LOC]
    mov  edx, DWORD PTR [rbx+FONTREQ.track]
    call SetTextCharacterExtra
    mov  rcx, QWORD PTR [rsp+LOC]
    mov  rdx, rsi
    mov  r8d, r12d
    lea  r9, [rsp+LOC+48]
    call GetTextExtentPoint32A
    mov  r13d, DWORD PTR [rsp+LOC+48]      ; cx (GDI already includes the character extra)
    add  r13d, FONT_PAD * 2                ; mask width
    mov  r14d, DWORD PTR [rsp+LOC+52]      ; cy
    add  r14d, FONT_PAD * 2                ; mask height
    lea  rdi, [rsp+LOC+56]                 ; BITMAPINFOHEADER
    xor  eax, eax
    mov  ecx, 10
    rep  stosd
    mov  DWORD PTR [rsp+LOC+56], 40
    mov  DWORD PTR [rsp+LOC+60], r13d
    mov  eax, r14d
    neg  eax
    mov  DWORD PTR [rsp+LOC+64], eax       ; top-down
    mov  WORD PTR [rsp+LOC+68], 1
    mov  WORD PTR [rsp+LOC+70], 32
    mov  rcx, QWORD PTR [rsp+LOC]
    lea  rdx, [rsp+LOC+56]
    xor  r8d, r8d
    lea  r9, [rsp+LOC+40]
    mov  QWORD PTR [rsp+32], 0
    mov  QWORD PTR [rsp+40], 0
    call CreateDIBSection
    mov  QWORD PTR [rsp+LOC+24], rax
    test rax, rax
    jnz  fr_bmp_ok
    lea  rcx, szFontErr
    call Sys_Fatal
fr_bmp_ok:
    mov  rcx, QWORD PTR [rsp+LOC]
    mov  rdx, rax
    call SelectObject
    mov  QWORD PTR [rsp+LOC+32], rax
    mov  rcx, QWORD PTR [rsp+LOC]
    mov  edx, TRANSPARENT
    call SetBkMode
    mov  rcx, QWORD PTR [rsp+LOC]
    mov  edx, 00FFFFFFh
    call SetTextColor
    mov  rcx, QWORD PTR [rsp+LOC]
    mov  edx, FONT_PAD
    mov  r8d, FONT_PAD
    mov  r9, rsi
    mov  DWORD PTR [rsp+32], r12d
    mov  DWORD PTR [rsp+36], 0
    call TextOutA
    call GdiFlush
    mov  eax, r13d
    imul eax, r14d
    mov  r15d, eax                         ; pixel count
    mov  ecx, eax
    call Mem_Alloc
    mov  rdi, rax
    mov  rcx, QWORD PTR [rbx+FONTREQ.dst]
    mov  DWORD PTR [rcx+TXMASK.w], r13d
    mov  DWORD PTR [rcx+TXMASK.h], r14d
    mov  QWORD PTR [rcx+TXMASK.pix], rdi
    mov  rsi, QWORD PTR [rsp+LOC+40]       ; DIB bits (BGRA)
    xor  ecx, ecx
fr_copy:
    mov  al, BYTE PTR [rsi+rcx*4]
    mov  BYTE PTR [rdi+rcx], al
    inc  ecx
    cmp  ecx, r15d
    jb   fr_copy
    mov  rcx, QWORD PTR [rsp+LOC]
    mov  rdx, QWORD PTR [rsp+LOC+32]
    call SelectObject
    mov  rcx, QWORD PTR [rsp+LOC]
    mov  rdx, QWORD PTR [rsp+LOC+16]
    call SelectObject
    mov  rcx, QWORD PTR [rsp+LOC+24]
    call DeleteObject
    mov  rcx, QWORD PTR [rsp+LOC+8]
    call DeleteObject
    mov  rcx, QWORD PTR [rsp+LOC]
    call DeleteDC
    FN_RET
FN_END Font_Render

; ---------------------------------------------------------------------------
; Font_Glow(rcx = TXMASK * src, rdx = TXMASK * out, r8d = radius)
; Copies the mask and blurs it twice (soft glow, same dimensions).
; ---------------------------------------------------------------------------
FN_BEGIN Font_Glow, 0
    mov  rsi, rcx
    mov  rbx, rdx
    mov  r12d, r8d
    mov  eax, DWORD PTR [rsi+TXMASK.w]
    mov  r13d, eax
    imul eax, DWORD PTR [rsi+TXMASK.h]
    mov  r14d, eax
    mov  ecx, eax
    call Mem_Alloc
    mov  rdi, rax
    mov  DWORD PTR [rbx+TXMASK.w], r13d
    mov  eax, DWORD PTR [rsi+TXMASK.h]
    mov  DWORD PTR [rbx+TXMASK.h], eax
    mov  QWORD PTR [rbx+TXMASK.pix], rdi
    mov  rsi, QWORD PTR [rsi+TXMASK.pix]
    mov  ecx, r14d
    rep  movsb
    mov  r15, QWORD PTR [rbx+TXMASK.pix]
    mov  ebp, 2
fg_pass:
    mov  rcx, r15
    mov  edx, r13d
    mov  r8d, DWORD PTR [rbx+TXMASK.h]
    mov  r9d, r12d
    call Msk_BoxBlur
    dec  ebp
    jnz  fg_pass
    FN_RET
FN_END Font_Glow

; ---------------------------------------------------------------------------
; Font_RowPal(rcx = TXMASK * mask, rdx = dst DWORD[mask.h], r8 = keys)
; Builds a vertical colour gradient over the glyph body (the mask minus its
; FONT_PAD margins) and repeats the end colours into the margins, so that the
; result can be used directly as DMASK.rowPal.  keys: see Pal_FromKeys.
; ---------------------------------------------------------------------------
FN_BEGIN Font_RowPal, 0
    mov  r12d, DWORD PTR [rcx+TXMASK.h]
    mov  r13, rdx
    lea  rcx, [rdx+FONT_PAD*4]
    lea  edx, [r12-FONT_PAD*2]
    call Pal_FromKeys
    mov  rdi, r13
    mov  eax, DWORD PTR [rdi+FONT_PAD*4]
    mov  ecx, FONT_PAD
    rep  stosd
    lea  rdi, [r13+r12*4]
    mov  eax, DWORD PTR [rdi-(FONT_PAD+1)*4]
    sub  rdi, FONT_PAD * 4
    mov  ecx, FONT_PAD
    rep  stosd
    FN_RET
FN_END Font_RowPal

END
