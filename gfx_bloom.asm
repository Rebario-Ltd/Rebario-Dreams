; ============================================================================
; gfx_bloom.asm - bloom post-process on the 640x360 composite.
; ----------------------------------------------------------------------------
; Every frame, before the vignette / fade:
;   1. bright-pass (per-channel saturated subtraction of a threshold) combined
;      with a 4x4 box down-sample and a gain  -> level 1 (160 x 90),
;   2. 5-tap binomial blur (1 2 3 2 1) horizontally and vertically,
;   3. 2x2 down-sample -> level 2 (80 x 45) and the same blur,
;   4. level 2 is enlarged (bilinear), added to level 1, enlarged twice more
;      to 640 x 360 and added to the picture with saturation.
; Two levels give a tight core and a wide, soft halo.  The cost is about one
; millisecond per frame.  Threshold and gain come from the timeline (per scene,
; cross-faded during transitions, pumped by the kick).
; ============================================================================
INCLUDE common.inc

L1_W     EQU 160
L1_H     EQU 90
L2_W     EQU 80
L2_H     EQU 45
L1_BYTES EQU L1_W * L1_H * 4             ; 57600
L2_BYTES EQU L2_W * L2_H * 4             ; 14400
U2_BYTES EQU 320 * 180 * 4               ; 230400
G_BYTES  EQU SCR_W * SCR_H * 4           ; 921600
BLOOM_BYTES EQU L1_BYTES * 3 + L2_BYTES + U2_BYTES + G_BYTES

.const
ALIGN 16
kDiv9    WORD 8 DUP (7282)               ; 65536 / 9 (weights 1 2 3 2 1 sum to 9)

.data?
ALIGN 16
blL1     QWORD ?                         ; 160 x 90 glow
blTmp    QWORD ?                         ; blur scratch (level 1 sized)
blL2     QWORD ?                         ; 80 x 45 glow
blU1     QWORD ?                         ; 160 x 90 combined
blU2     QWORD ?                         ; 320 x 180
blG      QWORD ?                         ; 640 x 360 final glow

.code

; ---------------------------------------------------------------------------
; Bloom_Init - one allocation for every buffer (64-byte multiples).
; ---------------------------------------------------------------------------
FN_BEGIN Bloom_Init, 0
    mov    ecx, BLOOM_BYTES
    call   Mem_Alloc
    mov    QWORD PTR blL1, rax
    add    rax, L1_BYTES
    mov    QWORD PTR blTmp, rax
    add    rax, L1_BYTES
    mov    QWORD PTR blL2, rax
    add    rax, L2_BYTES
    mov    QWORD PTR blU1, rax
    add    rax, L1_BYTES
    mov    QWORD PTR blU2, rax
    add    rax, U2_BYTES
    mov    QWORD PTR blG, rax
    FN_RET
FN_END Bloom_Init

; One 16-byte row of a 4x4 block: threshold it and add it to the word sums
; xmm0 (pixels 0, 1) and xmm1 (pixels 2, 3).
BRIGHTROW MACRO rowOff:REQ
    movdqa xmm2, XMMWORD PTR [rbx+rowOff]
    psubusb xmm2, xmm7
    movdqa xmm3, xmm2
    punpcklbw xmm2, xmm9
    punpckhbw xmm3, xmm9
    paddw  xmm0, xmm2
    paddw  xmm1, xmm3
ENDM

; ---------------------------------------------------------------------------
; Bl_BrightDown(rcx = framebuffer, edx = threshold 0..255, r8d = gain, 8.8) -> level 1.
; avg = sum(16 thresholded pixels) / 16; out = avg * gain / 256 (saturated).
; ---------------------------------------------------------------------------
FNX_BEGIN Bl_BrightDown, 0
    movd   xmm7, edx
    punpcklbw xmm7, xmm7
    punpcklwd xmm7, xmm7
    pshufd xmm7, xmm7, 0                   ; threshold in every byte
    shl    r8d, 4                          ; sum * (gain * 16) >> 16 = avg * gain / 256
    BCAST16 xmm8, r8d
    pxor   xmm9, xmm9
    mov    rsi, rcx
    mov    rdi, QWORD PTR blL1
    xor    r12d, r12d                      ; destination row
bd_row:
    imul   ebx, r12d, SCR_W * 4 * 4        ; first byte of the 4 source rows
    add    rbx, rsi
    xor    r13d, r13d                      ; destination column
bd_px:
    pxor   xmm0, xmm0
    pxor   xmm1, xmm1
    BRIGHTROW 0
    BRIGHTROW SCR_W * 4
    BRIGHTROW SCR_W * 8
    BRIGHTROW SCR_W * 12
    paddw  xmm0, xmm1                      ; pixels 0+2, 1+3
    pshufd xmm1, xmm0, 4Eh
    paddw  xmm0, xmm1                      ; all 16 pixels per channel
    pmulhuw xmm0, xmm8
    packuswb xmm0, xmm0
    movd   DWORD PTR [rdi], xmm0
    add    rdi, 4
    add    rbx, 16
    inc    r13d
    cmp    r13d, L1_W
    jb     bd_px
    inc    r12d
    cmp    r12d, L1_H
    jb     bd_row
    FNX_RET
FN_END Bl_BrightDown

; One tap of the blur: the pixel at index (i + off) of the current line, index
; clamped to 0..last (r10d), unpacked to four words in xr.  xmm4 must be zero.
BLURTAP MACRO off:REQ, xr:REQ
    lea    eax, [rbp+off]
    xor    edx, edx
    test   eax, eax
    cmovs  eax, edx
    cmp    eax, r10d
    cmova  eax, r10d
    imul   rax, rbx
    movd   xr, DWORD PTR [r8+rax]
    punpcklbw xr, xmm4
ENDM

; ---------------------------------------------------------------------------
; Bl_Core - one 1-2-3-2-1 blur pass over `lines` lines of `len` pixels.
; In: r12 = source, r13 = destination, r14d = pixels per line, r15d = lines,
; rbx = byte step between neighbours, rsi = byte step between lines.
; ---------------------------------------------------------------------------
FN_BEGIN Bl_Core, 0
    pxor   xmm4, xmm4
    lea    r10d, [r14-1]                   ; last index
    mov    r8, r12
    mov    r9, r13
    mov    edi, r15d
bc_line:
    xor    ebp, ebp
bc_px:
    BLURTAP -2, xmm0
    BLURTAP -1, xmm1
    BLURTAP 1, xmm3
    paddw  xmm1, xmm3                      ; t-1 + t+1
    paddw  xmm1, xmm1                      ; x 2
    BLURTAP 2, xmm3
    paddw  xmm0, xmm3                      ; t-2 + t+2
    paddw  xmm0, xmm1
    BLURTAP 0, xmm2
    paddw  xmm0, xmm2
    paddw  xmm2, xmm2
    paddw  xmm0, xmm2                      ; + 3 * t0
    pmulhuw xmm0, XMMWORD PTR kDiv9
    packuswb xmm0, xmm0
    mov    eax, ebp
    imul   rax, rbx
    movd   DWORD PTR [r9+rax], xmm0
    inc    ebp
    cmp    ebp, r14d
    jb     bc_px
    add    r8, rsi
    add    r9, rsi
    dec    edi
    jnz    bc_line
    FN_RET
FN_END Bl_Core

; ---------------------------------------------------------------------------
; Bl_Blur(rcx = image, edx = width, r8d = height) - separable blur in place.
; ---------------------------------------------------------------------------
FN_BEGIN Bl_Blur, 16
    mov    QWORD PTR [rsp+LOC], rcx
    mov    DWORD PTR [rsp+LOC+8], edx
    mov    DWORD PTR [rsp+LOC+12], r8d
    mov    r12, rcx                        ; horizontal: image -> scratch
    mov    r13, QWORD PTR blTmp
    mov    r14d, edx
    mov    r15d, r8d
    mov    ebx, 4
    lea    esi, [rdx*4]
    call   Bl_Core
    mov    r12, QWORD PTR blTmp            ; vertical: scratch -> image
    mov    r13, QWORD PTR [rsp+LOC]
    mov    r14d, DWORD PTR [rsp+LOC+12]
    mov    r15d, DWORD PTR [rsp+LOC+8]
    mov    ebx, DWORD PTR [rsp+LOC+8]
    shl    ebx, 2
    mov    esi, 4
    call   Bl_Core
    FN_RET
FN_END Bl_Blur

; ---------------------------------------------------------------------------
; Bl_Down2(rcx = source, rdx = destination, r8d = source width, r9d = source
; height) - 2x2 average.
; ---------------------------------------------------------------------------
LEAF_BEGIN Bl_Down2
    mov    r10d, r8d
    shl    r10d, 2                         ; source row bytes
    shr    r9d, 1                          ; destination rows
d2_row:
    lea    r11, [rcx+r10]                  ; second source row
    xor    eax, eax
d2_px:
    movq   xmm0, QWORD PTR [rcx+rax]
    movq   xmm1, QWORD PTR [r11+rax]
    pavgb  xmm0, xmm1
    pshufd xmm1, xmm0, 1
    pavgb  xmm0, xmm1
    movd   DWORD PTR [rdx], xmm0
    add    rdx, 4
    add    eax, 8
    cmp    eax, r10d
    jb     d2_px
    lea    rcx, [rcx+r10*2]
    dec    r9d
    jnz    d2_row
    ret
LEAF_END Bl_Down2

; Bl_AddBytes(rcx = dst, rdx = src, r8d = byte count, multiple of 16): saturated add.
LEAF_BEGIN Bl_AddBytes
    xor    eax, eax
ab_lp:
    movdqa xmm0, XMMWORD PTR [rcx+rax]
    paddusb xmm0, XMMWORD PTR [rdx+rax]
    movdqa XMMWORD PTR [rcx+rax], xmm0
    add    eax, 16
    cmp    eax, r8d
    jb     ab_lp
    ret
LEAF_END Bl_AddBytes

; ---------------------------------------------------------------------------
; Bloom_Apply(rcx = 640x360 framebuffer, edx = threshold 0..255, r8d = gain 8.8).
; ---------------------------------------------------------------------------
FN_BEGIN Bloom_Apply, 0
    mov    r12, rcx
    call   Bl_BrightDown
    mov    rcx, QWORD PTR blL1
    mov    edx, L1_W
    mov    r8d, L1_H
    call   Bl_Blur
    mov    rcx, QWORD PTR blL1
    mov    rdx, QWORD PTR blL2
    mov    r8d, L1_W
    mov    r9d, L1_H
    call   Bl_Down2
    mov    rcx, QWORD PTR blL2
    mov    edx, L2_W
    mov    r8d, L2_H
    call   Bl_Blur
    mov    rcx, QWORD PTR blU1
    mov    rdx, QWORD PTR blL2
    mov    r8d, L2_W
    mov    r9d, L2_H
    call   Gfx_Up2
    mov    rcx, QWORD PTR blU1
    mov    rdx, QWORD PTR blL1
    mov    r8d, L1_BYTES
    call   Bl_AddBytes
    mov    rcx, QWORD PTR blU2
    mov    rdx, QWORD PTR blU1
    mov    r8d, L1_W
    mov    r9d, L1_H
    call   Gfx_Up2
    mov    rcx, QWORD PTR blG
    mov    rdx, QWORD PTR blU2
    mov    r8d, 320
    mov    r9d, 180
    call   Gfx_Up2
    mov    rcx, r12
    mov    rdx, QWORD PTR blG
    call   Gfx_AddSat
    FN_RET
FN_END Bloom_Apply

END
