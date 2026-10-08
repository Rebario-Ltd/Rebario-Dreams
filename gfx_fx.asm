; ============================================================================
; gfx_fx.asm - scalar full-frame effects: iris (circular wipe) transition
; ============================================================================
INCLUDE common.inc

.data?
ALIGN 16
gDist16    WORD SCR_PIX DUP (?)    ; distance from the screen centre, pixels

.code

; ---------------------------------------------------------------------------
; Gfx_FxInit - builds the centre-distance table.
; ---------------------------------------------------------------------------
.const
ALIGN 16
kCx   REAL4 319.5
kCy   REAL4 179.5

.code
FN_BEGIN Gfx_FxInit, 0
    lea  rdi, gDist16
    xor  r12d, r12d
di_row:
    cvtsi2ss xmm1, r12d
    subss xmm1, DWORD PTR kCy
    mulss xmm1, xmm1
    xor  r13d, r13d
di_px:
    cvtsi2ss xmm0, r13d
    subss xmm0, DWORD PTR kCx
    mulss xmm0, xmm0
    addss xmm0, xmm1
    sqrtss xmm0, xmm0
    cvttss2si eax, xmm0
    mov  WORD PTR [rdi], ax
    add  rdi, 2
    inc  r13d
    cmp  r13d, SCR_W
    jb   di_px
    inc  r12d
    cmp  r12d, SCR_H
    jb   di_row
    FN_RET
FN_END Gfx_FxInit

; ---------------------------------------------------------------------------
; Gfx_Iris(rcx = dst, rdx = a, r8 = b, r9d = radius)
; Inside the circle the frame shows b, outside a; the soft edge is ~43 px wide.
; ---------------------------------------------------------------------------
IRIS_GAIN EQU 6

FN_BEGIN Gfx_Iris, 0
    lea  rsi, gDist16
    mov  r10d, r9d
    xor  r11d, r11d                        ; pixel index
ir_px:
    movzx eax, WORD PTR [rsi+r11*2]
    mov  ebx, r10d
    sub  ebx, eax                          ; radius - d
    imul ebx, ebx, IRIS_GAIN               ; ramp width = 256 / IRIS_GAIN pixels
    add  ebx, 128
    jns  ir_hi
    xor  ebx, ebx
ir_hi:
    cmp  ebx, 256
    jbe  ir_blend
    mov  ebx, 256
ir_blend:
    mov  eax, 256
    sub  eax, ebx                          ; weight of a
    mov  edi, DWORD PTR [rdx+r11*4]        ; a
    mov  r12d, DWORD PTR [r8+r11*4]        ; b
    mov  r13d, edi
    and  r13d, 00FF00FFh
    imul r13d, eax
    mov  r14d, r12d
    and  r14d, 00FF00FFh
    imul r14d, ebx
    add  r13d, r14d
    shr  r13d, 8
    and  r13d, 00FF00FFh
    and  edi, 0000FF00h
    imul edi, eax
    and  r12d, 0000FF00h
    imul r12d, ebx
    add  edi, r12d
    shr  edi, 8
    and  edi, 0000FF00h
    or   edi, r13d
    mov  DWORD PTR [rcx+r11*4], edi
    inc  r11d
    cmp  r11d, SCR_PIX
    jb   ir_px
    FN_RET
FN_END Gfx_Iris

END
