; ============================================================================
; noise.asm - tileable fractal value noise (fBm) into 8-bit square textures
; ----------------------------------------------------------------------------
; Used for the terrain height map, the nebula and texture detail. The result
; wraps seamlessly because the random lattice of every octave is periodic.
; ============================================================================
INCLUDE common.inc

.data?
ALIGN 16
fbmLat         BYTE 262144 DUP (?)     ; lattice of one octave (max 512 x 512)
fbmXI          WORD 512 DUP (?)        ; per-column lattice index
fbmXI1         WORD 512 DUP (?)        ; per-column next lattice index (wrapped)
fbmXF          WORD 512 DUP (?)        ; per-column smoothstep fraction (0..255)

.code

; ---------------------------------------------------------------------------
; Fbm_Octave - adds one octave of tileable value noise to the 8-bit texture.
;   rcx = dst, edx = sizeLog, r8d = cellLog (<= 8), r9d = weight (<= 128)
;   The random lattice (n x n, n = size >> cellLog) must be in fbmLat.
; ---------------------------------------------------------------------------
FN_BEGIN Fbm_Octave, 32
    mov  r15, rcx                         ; dst
    mov  r12d, edx                        ; sizeLog
    mov  r13d, r8d                        ; cellLog
    mov  DWORD PTR [rsp+LOC], r9d         ; weight
    mov  ecx, r12d
    mov  ebx, 1
    shl  ebx, cl                          ; size
    mov  ecx, r13d
    mov  eax, 1
    shl  eax, cl
    dec  eax
    mov  DWORD PTR [rsp+LOC+4], eax       ; cell mask (cell-1)
    mov  eax, r12d
    sub  eax, r13d                        ; n = 1 << (sizeLog - cellLog)
    mov  ecx, eax
    mov  r14d, 1
    shl  r14d, cl                         ; r14d = n
    mov  DWORD PTR [rsp+LOC+8], r14d
    ; --- per-column tables -------------------------------------------------
    lea  rsi, fbmXI
    lea  rdi, fbmXI1
    lea  r8,  fbmXF
    xor  r9d, r9d
oct_col:
    mov  eax, r9d
    mov  ecx, r13d
    shr  eax, cl
    mov  WORD PTR [rsi+r9*2], ax
    inc  eax
    lea  edx, [r14-1]
    and  eax, edx
    mov  WORD PTR [rdi+r9*2], ax
    mov  eax, r9d
    and  eax, DWORD PTR [rsp+LOC+4]
    mov  ecx, 8
    sub  ecx, r13d
    shl  eax, cl                          ; t = 0..255
    mov  edx, eax
    imul eax, eax                         ; t*t
    mov  ecx, 768
    add  edx, edx
    sub  ecx, edx
    imul eax, ecx
    shr  eax, 16                          ; smoothstep * 256
    mov  WORD PTR [r8+r9*2], ax
    inc  r9d
    cmp  r9d, ebx
    jb   oct_col
    ; --- rows ---------------------------------------------------------------
    xor  r10d, r10d                       ; y
oct_row:
    mov  eax, r10d
    mov  ecx, r13d
    shr  eax, cl                          ; iy
    mov  r11d, eax
    inc  eax
    lea  edx, [r14-1]
    and  eax, edx                         ; iy1
    imul r11d, r14d                       ; iy * n
    imul eax, r14d                        ; iy1 * n
    lea  rsi, fbmLat
    lea  rbp, [rsi+rax]                   ; row B
    add  rsi, r11                         ; row A
    mov  eax, r10d
    and  eax, DWORD PTR [rsp+LOC+4]
    mov  ecx, 8
    sub  ecx, r13d
    shl  eax, cl
    mov  edx, eax
    imul eax, eax
    mov  ecx, 768
    add  edx, edx
    sub  ecx, edx
    imul eax, ecx
    shr  eax, 16
    mov  r8d, eax                         ; fy (0..255)
    mov  eax, r10d
    imul eax, ebx
    lea  rdi, [r15+rax]                   ; dst row
    lea  r9,  fbmXI
    lea  r11, fbmXI1
    xor  r14d, r14d                       ; x (n is restored after the row)
oct_px:
    movzx eax, WORD PTR [r9+r14*2]        ; ix
    movzx edx, WORD PTR [r11+r14*2]       ; ix1
    movzx ecx, BYTE PTR [rsi+rax]         ; l00
    movzx eax, BYTE PTR [rsi+rdx]         ; l10
    sub  eax, ecx
    lea  rdx, fbmXF
    movzx edx, WORD PTR [rdx+r14*2]       ; fx
    imul eax, edx
    sar  eax, 8
    add  ecx, eax                         ; a
    movzx eax, WORD PTR [r9+r14*2]
    movzx edx, WORD PTR [r11+r14*2]
    movzx r12d, BYTE PTR [rbp+rax]        ; l01
    movzx eax, BYTE PTR [rbp+rdx]         ; l11
    sub  eax, r12d
    lea  rdx, fbmXF
    movzx edx, WORD PTR [rdx+r14*2]
    imul eax, edx
    sar  eax, 8
    add  r12d, eax                        ; b
    sub  r12d, ecx
    imul r12d, r8d
    sar  r12d, 8
    add  ecx, r12d                        ; v = 0..255
    imul ecx, DWORD PTR [rsp+LOC]
    shr  ecx, 8
    movzx eax, BYTE PTR [rdi+r14]
    add  eax, ecx
    mov  BYTE PTR [rdi+r14], al
    inc  r14d
    cmp  r14d, ebx
    jb   oct_px
    mov  r14d, DWORD PTR [rsp+LOC+8]      ; restore n
    inc  r10d
    cmp  r10d, ebx
    jb   oct_row
    FN_RET
FN_END Fbm_Octave

; ---------------------------------------------------------------------------
; Mth_Fbm - tileable fractal noise into an 8-bit square texture.
;   rcx = dst (size*size bytes), edx = log2(size) (<= 9),
;   r8d = log2 of the largest cell (<= 8), r9d = octaves (low 8 bits) | seed << 8
;   Octave k uses cells of (largest >> k) pixels and weight 128 >> k.
; ---------------------------------------------------------------------------
FN_BEGIN Mth_Fbm, 48
    mov  QWORD PTR [rsp+LOC], rcx         ; dst
    mov  DWORD PTR [rsp+LOC+8], edx       ; sizeLog
    mov  DWORD PTR [rsp+LOC+12], r8d      ; cell log of octave 0
    movzx eax, r9b
    mov  DWORD PTR [rsp+LOC+16], eax      ; octaves
    shr  r9d, 8
    mov  ecx, r9d
    mov  edx, 9E3779B1h
    imul ecx, edx
    or   ecx, 1
    call Mth_Seed
    mov  ecx, DWORD PTR [rsp+LOC+8]       ; clear dst
    mov  eax, 1
    shl  eax, cl
    imul eax, eax
    shr  eax, 2
    mov  ecx, eax
    mov  rdi, QWORD PTR [rsp+LOC]
    xor  eax, eax
    rep  stosd
    xor  r12d, r12d                       ; octave index
    mov  r13d, 128                        ; weight
fbm_oct:
    mov  r14d, DWORD PTR [rsp+LOC+12]
    sub  r14d, r12d                       ; cell log
    js   fbm_done
    mov  ecx, DWORD PTR [rsp+LOC+8]
    sub  ecx, r14d
    mov  ebx, 1
    shl  ebx, cl
    imul ebx, ebx                         ; lattice cells
    lea  rdi, fbmLat
    xor  esi, esi
fbm_fill:
    call Mth_Rand
    shr  eax, 24
    mov  BYTE PTR [rdi+rsi], al
    inc  esi
    cmp  esi, ebx
    jb   fbm_fill
    mov  rcx, QWORD PTR [rsp+LOC]
    mov  edx, DWORD PTR [rsp+LOC+8]
    mov  r8d, r14d
    mov  r9d, r13d
    call Fbm_Octave
    shr  r13d, 1
    inc  r12d
    cmp  r12d, DWORD PTR [rsp+LOC+16]
    jb   fbm_oct
fbm_done:
    FN_RET
FN_END Mth_Fbm

END
