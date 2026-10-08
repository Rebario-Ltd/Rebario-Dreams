; ============================================================================
; fx_plasma.asm - scene 1 "AURORA": domain-warped sine plasma with two ripple
; sources, mapped through a cinematic 1024-entry palette. Pure function of time.
; ============================================================================
INCLUDE common.inc

; wave frequencies in sine-table units (4096 = 2*pi)
PL_FX1   EQU 7             ; horizontal wave, per pixel
PL_FY2   EQU 15            ; vertical wave, per row
PL_K3    EQU 11            ; diagonal wave, per pixel and per row
PL_K4    EQU 10            ; ripple A, per quarter-pixel
PL_K6    EQU 8             ; ripple B, per quarter-pixel
PL_FXW   EQU 5             ; column warp frequency
PL_FYW   EQU 9             ; row warp frequency

; locals
V_P1   EQU LOC + 0
V_P2   EQU LOC + 4
V_P3   EQU LOC + 8
V_P4   EQU LOC + 12
V_P6   EQU LOC + 16
V_PW1  EQU LOC + 20
V_PW2  EQU LOC + 24
V_CYC  EQU LOC + 28
V_FB   EQU LOC + 32

.const
ALIGN 16
k4f      REAL4 4.0
plKeys   DWORD 9
         DWORD 0,     000A0230h
         DWORD 8192,  002B1394h
         DWORD 16384, 007A1CACh
         DWORD 24576, 00D81B8Eh
         DWORD 32768, 00FF5E5Bh
         DWORD 40960, 00FFB347h
         DWORD 49152, 00FFF1B8h
         DWORD 57344, 0038C6F4h
         DWORD 65536, 000A0230h

.data?
ALIGN 16
plPal    DWORD 1024 DUP (?)
plDistA  WORD SCR_PIX DUP (?)
plDistB  WORD SCR_PIX DUP (?)
plWarp   DWORD SCR_W DUP (?)

.code

; Pl_BuildDist(rcx = dst u16[SCR_PIX], edx = cx, r8d = cy) - distance * 4 from a point.
FN_BEGIN Pl_BuildDist, 0
    mov  rdi, rcx
    mov  r12d, edx
    mov  r13d, r8d
    xor  esi, esi
bd_row:
    mov  eax, esi
    sub  eax, r13d
    imul eax, eax
    mov  r14d, eax
    xor  ebx, ebx
bd_px:
    mov  eax, ebx
    sub  eax, r12d
    imul eax, eax
    add  eax, r14d
    cvtsi2ss xmm0, eax
    sqrtss xmm0, xmm0
    mulss xmm0, DWORD PTR k4f
    cvttss2si eax, xmm0
    mov  WORD PTR [rdi], ax
    add  rdi, 2
    inc  ebx
    cmp  ebx, SCR_W
    jb   bd_px
    inc  esi
    cmp  esi, SCR_H
    jb   bd_row
    FN_RET
FN_END Pl_BuildDist

FN_BEGIN Fx_Plasma_Init, 0
    lea  rcx, plPal
    mov  edx, 1024
    lea  r8, plKeys
    call Pal_FromKeys
    lea  rcx, plDistA
    mov  edx, 190
    mov  r8d, 120
    call Pl_BuildDist
    lea  rcx, plDistB
    mov  edx, 450
    mov  r8d, 250
    call Pl_BuildDist
    xor  eax, eax
    FN_RET
FN_END Fx_Plasma_Init

; Pl_Phases(edx = ms) - fills the per-frame phase locals of the caller frame
; (the caller's [rsp+LOC..] area is addressed relative to its own rsp).
; Implemented inline in Fx_Plasma_Render for simplicity.

; ---------------------------------------------------------------------------
; Fx_Plasma_Render(rcx = fb, edx = local ms)
; ---------------------------------------------------------------------------
FN_BEGIN Fx_Plasma_Render, 48
    mov  QWORD PTR [rsp+V_FB], rcx
    mov  r15d, edx                         ; t
    imul eax, r15d, 601
    shr  eax, 10
    mov  DWORD PTR [rsp+V_P1], eax
    imul eax, r15d, 461
    shr  eax, 10
    neg  eax
    mov  DWORD PTR [rsp+V_P2], eax
    imul eax, r15d, 717
    shr  eax, 10
    mov  DWORD PTR [rsp+V_P3], eax
    imul eax, r15d, 1331
    shr  eax, 10
    neg  eax
    mov  ecx, gKick
    shl  ecx, 1
    sub  eax, ecx                          ; kick pushes the rings outward
    mov  DWORD PTR [rsp+V_P4], eax
    imul eax, r15d, 1126
    shr  eax, 10
    mov  DWORD PTR [rsp+V_P6], eax
    imul eax, r15d, 350
    shr  eax, 10
    mov  DWORD PTR [rsp+V_PW1], eax
    imul eax, r15d, 290
    shr  eax, 10
    mov  DWORD PTR [rsp+V_PW2], eax
    imul eax, r15d, 26
    shr  eax, 10
    mov  ecx, gKick
    imul ecx, ecx, 40
    shr  ecx, 8
    add  eax, ecx
    mov  DWORD PTR [rsp+V_CYC], eax
    lea  rsi, gSinTab
    lea  r12, plWarp
    xor  ecx, ecx                          ; column warp pre-pass
pl_warp:
    imul eax, ecx, PL_FXW
    add  eax, DWORD PTR [rsp+V_PW1]
    and  eax, 4095
    movsx eax, WORD PTR [rsi+rax*2]
    sar  eax, 6
    mov  DWORD PTR [r12+rcx*4], eax
    inc  ecx
    cmp  ecx, SCR_W
    jb   pl_warp
    mov  rdi, QWORD PTR [rsp+V_FB]
    lea  rbp, plPal
    mov  r14d, DWORD PTR [rsp+V_CYC]
    xor  r15d, r15d                        ; y
pl_row:
    imul eax, r15d, PL_FYW                 ; row warp for the horizontal wave
    add  eax, DWORD PTR [rsp+V_PW2]
    and  eax, 4095
    movsx eax, WORD PTR [rsi+rax*2]
    sar  eax, 6
    add  eax, DWORD PTR [rsp+V_P1]
    mov  r10d, eax                         ; i1 at x = 0
    imul eax, r15d, PL_FY2
    add  eax, DWORD PTR [rsp+V_P2]
    mov  r13d, eax                         ; base of the vertical wave
    imul eax, r15d, PL_K3
    add  eax, DWORD PTR [rsp+V_P3]
    mov  r11d, eax                         ; i3 at x = 0
    mov  eax, r15d
    imul eax, eax, SCR_W * 2
    lea  r8, plDistA
    add  r8, rax
    lea  r9, plDistB
    add  r9, rax
    xor  ecx, ecx
pl_px:
    mov  eax, r10d
    add  r10d, PL_FX1
    and  eax, 4095
    movsx ebx, WORD PTR [rsi+rax*2]        ; horizontal wave
    mov  eax, DWORD PTR [r12+rcx*4]
    add  eax, r13d
    and  eax, 4095
    movsx edx, WORD PTR [rsi+rax*2]
    add  ebx, edx                          ; vertical wave
    mov  eax, r11d
    add  r11d, PL_K3
    and  eax, 4095
    movsx edx, WORD PTR [rsi+rax*2]
    add  ebx, edx                          ; diagonal wave
    movzx eax, WORD PTR [r8+rcx*2]
    imul eax, eax, PL_K4
    add  eax, DWORD PTR [rsp+V_P4]
    and  eax, 4095
    movsx edx, WORD PTR [rsi+rax*2]
    add  ebx, edx                          ; ripple A
    movzx eax, WORD PTR [r9+rcx*2]
    imul eax, eax, PL_K6
    add  eax, DWORD PTR [rsp+V_P6]
    and  eax, 4095
    movsx edx, WORD PTR [rsi+rax*2]
    sar  edx, 1
    add  ebx, edx                          ; ripple B (half weight)
    sar  ebx, 7
    add  ebx, r14d
    and  ebx, 1023
    mov  eax, DWORD PTR [rbp+rbx*4]
    mov  DWORD PTR [rdi], eax
    add  rdi, 4
    inc  ecx
    cmp  ecx, SCR_W
    jb   pl_px
    inc  r15d
    cmp  r15d, SCR_H
    jb   pl_row
    FN_RET
FN_END Fx_Plasma_Render

END
