; ============================================================================
; platform.asm - Win32 window, message pump, presentation and pacing.
; ----------------------------------------------------------------------------
; The 1280x720 BGRA frame in gFbOut is stretched into the client area with a
; letter-box that keeps 16:9.  F11 / F / Alt+Enter toggle borderless
; fullscreen.  Keyboard commands are queued in pendCmd and consumed by the
; main loop through Plat_TakeCmd.
; ============================================================================
INCLUDE common.inc
INCLUDE win.inc

EXTERN CreateSolidBrush:PROC

.const
szClass   BYTE "SiliconDreamsWnd", 0
szTitle   BYTE "REBARIO DREAMS  -  x64 MASM demo", 0
szErrWnd  BYTE "Cannot create the demo window", 0
szLoading BYTE "LOADING", 0
szTtlA    BYTE "REBARIO DREAMS  |  ", 0
szTtlB    BYTE " fps  |  scene ", 0
.ERRNZ NUM_SCENES - 9              ; the title below shows the number of scenes
szTtlC    BYTE " / 9", 0
szTtlSound  BYTE "  |  sound", 0
szTtlSilent BYTE "  |  silent", 0

BAR_W     EQU 400                 ; loading bar width in pixels
BAR_H     EQU 6
TRACK_CLR EQU 00301820h           ; COLORREF (BGR)
FILL_CLR  EQU 00882EFFh           ; neon pink
TEXT_CLR  EQU 00E0D0C0h

.data
ALIGN 16
bmiOut    BITMAPINFOHEADER <40, OUT_W, -OUT_H, 1, 32, 0, 0, 0, 0, 0, 0>

.data?
ALIGN 16
hWnd       QWORD ?
hDc        QWORD ?
savedStyle QWORD ?
savedRc    RECT <>
cliW       DWORD ?
cliH       DWORD ?
fullscr    DWORD ?
pendCmd    DWORD ?
lastFrame  QWORD ?

.code

; ---------------------------------------------------------------------------
; Plat_WndProc(hwnd, msg, wParam, lParam)
; ---------------------------------------------------------------------------
FN_BEGIN Plat_WndProc, 96
    mov  rbx, rcx
    mov  esi, edx
    mov  rdi, r8
    mov  r12, r9
    cmp  esi, WM_PAINT
    je   wp_paint
    cmp  esi, WM_KEYDOWN
    je   wp_key
    cmp  esi, WM_SYSKEYDOWN
    je   wp_syskey
    cmp  esi, WM_SIZE
    je   wp_size
    cmp  esi, WM_SETCURSOR
    je   wp_cursor
    cmp  esi, WM_CLOSE
    je   wp_close
    cmp  esi, WM_DESTROY
    je   wp_destroy
wp_def:
    mov  rcx, rbx
    mov  edx, esi
    mov  r8, rdi
    mov  r9, r12
    call DefWindowProcA
    jmp  wp_out
wp_paint:
    mov  rcx, rbx
    lea  rdx, [rsp+LOC]
    call BeginPaint
    mov  rcx, rax
    call Plat_PresentDC
    mov  rcx, rbx
    lea  rdx, [rsp+LOC]
    call EndPaint
    jmp  wp_zero
wp_key:
    cmp  edi, VK_ESCAPE
    je   wp_close
    bt   r12d, 30                          ; ignore auto-repeat
    jc   wp_zero
    cmp  edi, VK_F11
    je   wp_fs
    cmp  edi, VK_F
    je   wp_fs
    cmp  edi, VK_SPACE
    je   wp_pause
    cmp  edi, VK_P
    je   wp_pause
    cmp  edi, VK_RIGHT
    je   wp_next
    cmp  edi, VK_LEFT
    je   wp_prev
    jmp  wp_def
wp_syskey:
    cmp  edi, VK_RETURN
    jne  wp_def
wp_fs:
    call Plat_ToggleFullscreen
    jmp  wp_zero
wp_pause:
    mov  pendCmd, CMD_PAUSE
    jmp  wp_zero
wp_next:
    mov  pendCmd, CMD_NEXT
    jmp  wp_zero
wp_prev:
    mov  pendCmd, CMD_PREV
    jmp  wp_zero
wp_size:
    movzx eax, r12w
    mov  cliW, eax
    shr  r12, 16
    movzx eax, r12w
    mov  cliH, eax
    jmp  wp_zero
wp_cursor:
    cmp  fullscr, 0
    je   wp_def
    xor  ecx, ecx
    call SetCursor
    mov  eax, 1
    jmp  wp_out
wp_close:
    mov  rcx, rbx
    call DestroyWindow
    jmp  wp_zero
wp_destroy:
    xor  ecx, ecx
    call PostQuitMessage
wp_zero:
    xor  eax, eax
wp_out:
    FN_RET
FN_END Plat_WndProc

; ---------------------------------------------------------------------------
; Plat_CreateWindow - registers the class and shows a window whose client
; area is exactly 1280x720, centred on the primary monitor.
; ---------------------------------------------------------------------------
FN_BEGIN Plat_CreateWindow, 128
    xor  ecx, ecx
    call GetModuleHandleA
    mov  rsi, rax                          ; hInstance
    lea  rdi, [rsp+LOC]                    ; WNDCLASSEXA (80 bytes)
    xor  eax, eax
    mov  ecx, 10
    push rdi
    rep  stosq
    pop  rdi
    mov  DWORD PTR [rdi+WNDCLASSEXA.cbSize], 80
    mov  DWORD PTR [rdi+WNDCLASSEXA.style], 20h          ; CS_OWNDC
    lea  rax, Plat_WndProc
    mov  QWORD PTR [rdi+WNDCLASSEXA.lpfnWndProc], rax
    mov  QWORD PTR [rdi+WNDCLASSEXA.hInstance], rsi
    xor  ecx, ecx
    mov  edx, IDC_ARROW
    call LoadCursorA
    mov  QWORD PTR [rdi+WNDCLASSEXA.hCursor], rax
    mov  ecx, BLACK_BRUSH
    call GetStockObject
    mov  QWORD PTR [rdi+WNDCLASSEXA.hbrBackground], rax
    lea  rax, szClass
    mov  QWORD PTR [rdi+WNDCLASSEXA.lpszClassName], rax
    mov  rcx, rdi
    call RegisterClassExA
    lea  rbx, [rsp+LOC+80]                 ; RECT for AdjustWindowRect
    mov  DWORD PTR [rbx+RECT.left], 0
    mov  DWORD PTR [rbx+RECT.top], 0
    mov  DWORD PTR [rbx+RECT.right], OUT_W
    mov  DWORD PTR [rbx+RECT.bottom], OUT_H
    mov  rcx, rbx
    mov  edx, WS_OVERLAPPEDWINDOW
    xor  r8d, r8d
    call AdjustWindowRect
    mov  r12d, DWORD PTR [rbx+RECT.right]
    sub  r12d, DWORD PTR [rbx+RECT.left]   ; outer width
    mov  r13d, DWORD PTR [rbx+RECT.bottom]
    sub  r13d, DWORD PTR [rbx+RECT.top]    ; outer height
    mov  ecx, SM_CXSCREEN
    call GetSystemMetrics
    sub  eax, r12d
    sar  eax, 1
    mov  r14d, eax                         ; x
    mov  ecx, SM_CYSCREEN
    call GetSystemMetrics
    sub  eax, r13d
    sar  eax, 1
    mov  r15d, eax                         ; y
    xor  ecx, ecx
    lea  rdx, szClass
    lea  r8, szTitle
    mov  r9d, WS_OVERLAPPEDWINDOW
    mov  QWORD PTR [rsp+32], r14           ; x (low 32 bits are what counts)
    mov  QWORD PTR [rsp+40], r15           ; y
    mov  QWORD PTR [rsp+48], r12           ; width
    mov  QWORD PTR [rsp+56], r13           ; height
    mov  QWORD PTR [rsp+64], 0             ; parent
    mov  QWORD PTR [rsp+72], 0             ; menu
    mov  QWORD PTR [rsp+80], rsi           ; instance
    mov  QWORD PTR [rsp+88], 0             ; param
    call CreateWindowExA
    mov  hWnd, rax
    test rax, rax
    jnz  cw_ok
    lea  rcx, szErrWnd
    call Sys_Fatal
cw_ok:
    mov  rcx, rax
    call GetDC
    mov  hDc, rax
    mov  cliW, OUT_W
    mov  cliH, OUT_H
    mov  rcx, hWnd
    mov  edx, SW_SHOW
    call ShowWindow
    mov  rcx, hWnd
    call UpdateWindow
    FN_RET
FN_END Plat_CreateWindow

; ---------------------------------------------------------------------------
; Plat_Pump -> eax = 1 while running, 0 after WM_QUIT.
; ---------------------------------------------------------------------------
FN_BEGIN Plat_Pump, 64
pump_lp:
    lea  rcx, [rsp+LOC]
    xor  edx, edx
    xor  r8d, r8d
    xor  r9d, r9d
    mov  QWORD PTR [rsp+32], PM_REMOVE
    call PeekMessageA
    test eax, eax
    jz   pump_idle
    cmp  DWORD PTR [rsp+LOC+MSGSTRUCT.message], WM_QUIT
    je   pump_quit
    lea  rcx, [rsp+LOC]
    call TranslateMessage
    lea  rcx, [rsp+LOC]
    call DispatchMessageA
    jmp  pump_lp
pump_idle:
    mov  eax, 1
    jmp  pump_out
pump_quit:
    xor  eax, eax
pump_out:
    FN_RET
FN_END Plat_Pump

; ---------------------------------------------------------------------------
; Plat_TakeCmd -> eax = pending CMD_* (and clears it).
; ---------------------------------------------------------------------------
LEAF_BEGIN Plat_TakeCmd
    xor  eax, eax
    xchg eax, pendCmd
    ret
LEAF_END Plat_TakeCmd

; ---------------------------------------------------------------------------
; Plat_PresentDC(rcx = hdc) - letter-boxed StretchDIBits of gFbOut.
; ---------------------------------------------------------------------------
FN_BEGIN Plat_PresentDC, 0
    mov  rbx, rcx
    cmp  gFbOut, 0
    je   pr_out
    mov  esi, cliW
    mov  edi, cliH
    test esi, esi
    jz   pr_out
    test edi, edi
    jz   pr_out
    mov  r12d, esi                         ; dest width
    mov  eax, esi
    imul eax, 9
    shr  eax, 4
    mov  r13d, eax                         ; dest height = width * 9 / 16
    cmp  r13d, edi
    jbe  pr_fit
    mov  r13d, edi                         ; too tall: fit to height
    mov  eax, edi
    shl  eax, 4
    xor  edx, edx
    mov  ecx, 9
    div  ecx
    mov  r12d, eax
pr_fit:
    mov  r14d, esi
    sub  r14d, r12d
    shr  r14d, 1                           ; x offset
    mov  r15d, edi
    sub  r15d, r13d
    shr  r15d, 1                           ; y offset
    mov  edx, COLORONCOLOR
    cmp  r12d, OUT_W
    je   pr_set
    mov  edx, HALFTONE
pr_set:
    mov  rcx, rbx
    call SetStretchBltMode
    mov  rcx, rbx
    mov  edx, r14d
    mov  r8d, r15d
    mov  r9d, r12d
    mov  QWORD PTR [rsp+32], r13           ; dest height
    mov  QWORD PTR [rsp+40], 0             ; xSrc
    mov  QWORD PTR [rsp+48], 0             ; ySrc
    mov  QWORD PTR [rsp+56], OUT_W
    mov  QWORD PTR [rsp+64], OUT_H
    mov  rax, gFbOut
    mov  QWORD PTR [rsp+72], rax
    lea  rax, bmiOut
    mov  QWORD PTR [rsp+80], rax
    mov  QWORD PTR [rsp+88], DIB_RGB_COLORS
    mov  QWORD PTR [rsp+96], SRCCOPY
    call StretchDIBits
pr_out:
    FN_RET
FN_END Plat_PresentDC

FN_BEGIN Plat_Present, 0
    mov  rcx, hDc
    call Plat_PresentDC
    FN_RET
FN_END Plat_Present

; ---------------------------------------------------------------------------
; Plat_Pace - one frame of pacing: DwmFlush when the compositor is running,
; otherwise a ~16 ms limiter built from Sleep(1) + QPC.
; ---------------------------------------------------------------------------
FN_BEGIN Plat_Pace, 0
    call DwmFlush
    test eax, eax
    jns  pace_done
pace_wait:
    call Sys_NowMs
    mov  rdx, rax
    sub  rdx, lastFrame
    cmp  rdx, 16
    jae  pace_done
    mov  ecx, 1
    call Sleep
    jmp  pace_wait
pace_done:
    call Sys_NowMs
    mov  lastFrame, rax
    FN_RET
FN_END Plat_Pace

; ---------------------------------------------------------------------------
; Plat_ToggleFullscreen - borderless window covering the current monitor.
; ---------------------------------------------------------------------------
FN_BEGIN Plat_ToggleFullscreen, 64
    cmp  fullscr, 0
    jne  fs_leave
    mov  rcx, hWnd
    lea  rdx, savedRc
    call GetWindowRect
    mov  rcx, hWnd
    mov  edx, GWL_STYLE
    call GetWindowLongPtrA
    mov  savedStyle, rax
    mov  rcx, hWnd
    mov  edx, MONITOR_DEFAULTTONEAREST
    call MonitorFromWindow
    lea  rbx, [rsp+LOC]                    ; MONITORINFO
    mov  DWORD PTR [rbx+MONITORINFO.cbSize], 40
    mov  rcx, rax
    mov  rdx, rbx
    call GetMonitorInfoA
    mov  rcx, hWnd
    mov  edx, GWL_STYLE
    mov  r8d, WS_POPUP OR WS_VISIBLE
    call SetWindowLongPtrA
    mov  eax, DWORD PTR [rbx+MONITORINFO.rcMonitor+RECT.right]
    sub  eax, DWORD PTR [rbx+MONITORINFO.rcMonitor+RECT.left]
    mov  QWORD PTR [rsp+32], rax           ; cx
    mov  eax, DWORD PTR [rbx+MONITORINFO.rcMonitor+RECT.bottom]
    sub  eax, DWORD PTR [rbx+MONITORINFO.rcMonitor+RECT.top]
    mov  QWORD PTR [rsp+40], rax           ; cy
    mov  QWORD PTR [rsp+48], SWP_FRAMECHANGED OR SWP_SHOWWINDOW
    mov  rcx, hWnd
    mov  edx, HWND_TOP
    mov  r8d, DWORD PTR [rbx+MONITORINFO.rcMonitor+RECT.left]
    mov  r9d, DWORD PTR [rbx+MONITORINFO.rcMonitor+RECT.top]
    call SetWindowPos
    mov  fullscr, 1
    jmp  fs_out
fs_leave:
    mov  rcx, hWnd
    mov  edx, GWL_STYLE
    mov  r8, savedStyle
    call SetWindowLongPtrA
    mov  eax, savedRc.right
    sub  eax, savedRc.left
    mov  QWORD PTR [rsp+32], rax           ; cx
    mov  eax, savedRc.bottom
    sub  eax, savedRc.top
    mov  QWORD PTR [rsp+40], rax           ; cy
    mov  QWORD PTR [rsp+48], SWP_FRAMECHANGED OR SWP_NOZORDER OR SWP_SHOWWINDOW
    mov  rcx, hWnd
    xor  edx, edx
    mov  r8d, savedRc.left
    mov  r9d, savedRc.top
    call SetWindowPos
    mov  fullscr, 0
fs_out:
    FN_RET
FN_END Plat_ToggleFullscreen

; ---------------------------------------------------------------------------
; Plat_FillBox(rcx = hdc, edx = left, r8d = top, r9d = width, height, COLORREF)
; Solid rectangle through a temporary brush.  Arguments 5 and 6 are passed in
; the standard Win64 way (caller's [rsp+32] / [rsp+40] before the call).
; ---------------------------------------------------------------------------
FN_BEGIN Plat_FillBox, 32
    mov  rbx, rcx
    lea  rax, [rsp+LOC]
    mov  DWORD PTR [rax+RECT.left], edx
    mov  DWORD PTR [rax+RECT.top], r8d
    add  edx, r9d
    mov  DWORD PTR [rax+RECT.right], edx
    mov  ecx, DWORD PTR [rsp+__FRM+8*8+40]     ; height (above the pushed regs)
    add  r8d, ecx
    mov  DWORD PTR [rax+RECT.bottom], r8d
    mov  ecx, DWORD PTR [rsp+__FRM+8*8+48]     ; colour
    call CreateSolidBrush
    mov  rsi, rax
    mov  rcx, rbx
    lea  rdx, [rsp+LOC]
    mov  r8, rsi
    call FillRect
    mov  rcx, rsi
    call DeleteObject
    FN_RET
FN_END Plat_FillBox

; ---------------------------------------------------------------------------
; Plat_DrawLoading - progress callback: pumps messages and draws a neon bar.
; ---------------------------------------------------------------------------
FN_BEGIN Plat_DrawLoading, 0
    call Plat_Pump
    test eax, eax
    jnz  dl_run
    xor  ecx, ecx
    call ExitProcess                       ; window closed while loading
dl_run:
    mov  esi, cliW
    shr  esi, 1
    sub  esi, BAR_W / 2                    ; left
    mov  edi, cliH
    shr  edi, 1
    sub  edi, BAR_H / 2                    ; top
    mov  rcx, hDc
    lea  edx, [rsi-3]
    lea  r8d, [rdi-3]
    mov  r9d, BAR_W + 6
    mov  QWORD PTR [rsp+32], BAR_H + 6
    mov  QWORD PTR [rsp+40], TRACK_CLR
    call Plat_FillBox
    mov  eax, gProgress
    cmp  eax, 100
    jbe  dl_pct
    mov  eax, 100
dl_pct:
    imul eax, BAR_W
    xor  edx, edx
    mov  ecx, 100
    div  ecx
    mov  r9d, eax                          ; filled width
    mov  rcx, hDc
    mov  edx, esi
    mov  r8d, edi
    mov  QWORD PTR [rsp+32], BAR_H
    mov  QWORD PTR [rsp+40], FILL_CLR
    call Plat_FillBox
    mov  rcx, hDc
    mov  edx, TRANSPARENT
    call SetBkMode
    mov  rcx, hDc
    mov  edx, TEXT_CLR
    call SetTextColor
    mov  rcx, hDc
    mov  edx, esi
    lea  r8d, [rdi-28]
    lea  r9, szLoading
    mov  QWORD PTR [rsp+32], 7
    call TextOutA
    FN_RET
FN_END Plat_DrawLoading

; ---------------------------------------------------------------------------
; Plat_SetTitleInfo(ecx = fps, edx = scene number 1..8, r8d = 1 when the
; soundtrack is audible) - window caption.
; ---------------------------------------------------------------------------
FN_BEGIN Plat_SetTitleInfo, 96
    mov  r12d, ecx
    mov  r13d, edx
    mov  r14d, r8d
    lea  rdi, [rsp+LOC]
    lea  rsi, szTtlA
    call tt_copy
    lea  rcx, [rsp+LOC+80]
    mov  edx, r12d
    call Sys_FmtInt
    lea  rsi, [rsp+LOC+80]
    call tt_copy
    lea  rsi, szTtlB
    call tt_copy
    lea  rcx, [rsp+LOC+80]
    mov  edx, r13d
    call Sys_FmtInt
    lea  rsi, [rsp+LOC+80]
    call tt_copy
    lea  rsi, szTtlC
    call tt_copy
    lea  rsi, szTtlSound
    test r14d, r14d
    jnz  ti_audio
    lea  rsi, szTtlSilent
ti_audio:
    call tt_copy
    mov  rcx, hWnd
    lea  rdx, [rsp+LOC]
    call SetWindowTextA
    FN_RET
tt_copy:                                   ; append ASCIIZ rsi at rdi, keep rdi on the NUL
    mov  al, BYTE PTR [rsi]
    mov  BYTE PTR [rdi], al
    test al, al
    jz   tt_done
    inc  rsi
    inc  rdi
    jmp  tt_copy
tt_done:
    ret
FN_END Plat_SetTitleInfo

END
