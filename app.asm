; ============================================================================
; app.asm - interactive application: loading, main loop, shutdown.
; ============================================================================
INCLUDE common.inc
INCLUDE win.inc

.const
szInitFail BYTE "Demo initialisation failed", 0

.data?
ALIGN 16
fpsFrames  DWORD ?
fpsStart   QWORD ?

.code

; ---------------------------------------------------------------------------
; App_UpdateFps(ecx = current demo time) - refreshes the window caption once
; per second with the measured frame rate and the scene number.
; ---------------------------------------------------------------------------
FN_BEGIN App_UpdateFps, 0
    mov  ebx, ecx
    inc  fpsFrames
    call Sys_NowMs
    mov  rcx, rax
    sub  rcx, fpsStart
    cmp  rcx, 1000
    jb   uf_out
    mov  fpsStart, rax
    mov  eax, fpsFrames
    imul eax, 1000
    xor  edx, edx
    div  ecx
    mov  fpsFrames, 0
    mov  r12d, eax                         ; fps
    mov  eax, ebx
    xor  edx, edx
    mov  ecx, SCENE_MS
    div  ecx
    inc  eax
    mov  r13d, eax                         ; scene number
    call Aud_PosMs
    xor  r8d, r8d
    cmp  eax, -1
    setne r8b                              ; 1 while the soundtrack is audible
    mov  ecx, r12d
    mov  edx, r13d
    call Plat_SetTitleInfo
uf_out:
    FN_RET
FN_END App_UpdateFps

; ---------------------------------------------------------------------------
; App_Dispatch(ecx = CMD_*) - keyboard commands that move the clock.
; ---------------------------------------------------------------------------
FN_BEGIN App_Dispatch, 0
    cmp  ecx, CMD_NEXT
    je   ad_next
    cmp  ecx, CMD_PREV
    je   ad_prev
    cmp  ecx, CMD_PAUSE
    jne  ad_out
    call Clk_TogglePause
    jmp  ad_out
ad_next:
    call Clk_NextScene
    jmp  ad_out
ad_prev:
    call Clk_PrevScene
ad_out:
    FN_RET
FN_END App_Dispatch

; ---------------------------------------------------------------------------
; App_StartAudio - synthesises the soundtrack (the loading bar keeps moving)
; and opens the wave device.  Skipped for /mute; a missing device only means
; that the demo runs silently on the wall clock.
; ---------------------------------------------------------------------------
FN_BEGIN App_StartAudio, 0
    cmp  gMute, 0
    jne  sa_out
    call Aud_Render
    mov  rcx, gPcm
    call Aud_Open
    mov  ecx, 100
    call Tl_Progress
sa_out:
    FN_RET
FN_END App_StartAudio

; ---------------------------------------------------------------------------
; App_Run - never returns; terminates the process when the window closes.
; ---------------------------------------------------------------------------
FN_BEGIN App_Run, 0
    call SetProcessDPIAware
    mov  ecx, 1
    call timeBeginPeriod
    call Plat_CreateWindow
    lea  rax, Plat_DrawLoading
    mov  gProgressCb, rax
    call Demo_Init
    test eax, eax
    jz   ar_ready
    lea  rcx, szInitFail
    call Sys_Fatal
ar_ready:
    call App_StartAudio
    mov  gProgressCb, 0
    call Clk_Start
    call Sys_NowMs
    mov  fpsStart, rax
ar_loop:
    call Plat_Pump
    test eax, eax
    jz   ar_exit
    call Plat_TakeCmd
    test eax, eax
    jz   ar_frame
    mov  ecx, eax
    call App_Dispatch
ar_frame:
    call Clk_Now
    mov  ebx, eax
    mov  ecx, eax
    call Demo_Render
    call Plat_Present
    call Plat_Pace
    mov  ecx, ebx
    call App_UpdateFps
    jmp  ar_loop
ar_exit:
    call Aud_Close
    mov  ecx, 1
    call timeEndPeriod
    xor  ecx, ecx
    call ExitProcess
FN_END App_Run

END
