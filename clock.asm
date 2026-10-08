; ============================================================================
; clock.asm - demo clock: wall time (QPC) disciplined by the audio position.
; ----------------------------------------------------------------------------
; t = baseDemo + (now - baseWall) + corr
; corr is a low-pass of (audioPos - wallTime) so the picture stays locked to
; what is actually audible, without inheriting the jitter of the position
; counter.  Large jumps (start-up, seeks) snap instead of gliding.
; ============================================================================
INCLUDE common.inc

SNAP_MS    EQU 120            ; |error| above this resets the correction
SMOOTH_SHF EQU 4              ; 1/16 of the error is absorbed per frame
RESTART_MS EQU 2500           ; "previous scene" restarts the current one first

.data?
ALIGN 16
clkBaseWall QWORD ?
clkBaseDemo DWORD ?
clkFrozen   DWORD ?
clkPaused   DWORD ?
clkCorr     SDWORD ?

.code

; ---------------------------------------------------------------------------
; Clk_Seek(ecx = ms) - jump to a demo time (restarts the audio when running).
; ---------------------------------------------------------------------------
FN_BEGIN Clk_Seek, 0
    cmp  ecx, TOTAL_MS
    jb   sk_ok
    xor  ecx, ecx
sk_ok:
    mov  ebx, ecx
    mov  clkBaseDemo, ecx
    mov  clkFrozen, ecx
    mov  clkCorr, 0
    call Sys_NowMs
    mov  clkBaseWall, rax
    cmp  clkPaused, 0
    jne  sk_out
    mov  ecx, ebx
    call Aud_Play
sk_out:
    FN_RET
FN_END Clk_Seek

; ---------------------------------------------------------------------------
; Clk_Start - time 0, running.
; ---------------------------------------------------------------------------
FN_BEGIN Clk_Start, 0
    mov  clkPaused, 0
    xor  ecx, ecx
    call Clk_Seek
    FN_RET
FN_END Clk_Start

; ---------------------------------------------------------------------------
; Clk_Now -> eax = demo time in [0, TOTAL_MS); loops the demo at the end.
; ---------------------------------------------------------------------------
FN_BEGIN Clk_Now, 0
    cmp  clkPaused, 0
    jne  now_frozen
    call Sys_NowMs
    sub  rax, clkBaseWall
    add  eax, clkBaseDemo
    mov  ebx, eax                          ; wall-clock time
    call Aud_PosMs
    cmp  eax, -1
    je   now_range
    sub  eax, ebx                          ; raw error (audio - wall)
    mov  edx, eax
    sub  edx, clkCorr                      ; how far the correction lags
    cmp  edx, SNAP_MS
    jg   now_snap
    cmp  edx, -SNAP_MS
    jl   now_snap
    sar  edx, SMOOTH_SHF
    add  clkCorr, edx
    jmp  now_apply
now_snap:
    mov  clkCorr, eax
now_apply:
    add  ebx, clkCorr
now_range:
    test ebx, ebx
    jns  now_hi
    xor  ebx, ebx
now_hi:
    cmp  ebx, TOTAL_MS
    jb   now_ret
    xor  ecx, ecx
    call Clk_Seek                          ; demo loops from the beginning
    xor  ebx, ebx
now_ret:
    mov  eax, ebx
    jmp  now_out
now_frozen:
    mov  eax, clkFrozen
now_out:
    FN_RET
FN_END Clk_Now

; ---------------------------------------------------------------------------
; Clk_TogglePause - freeze / resume picture and sound.
; ---------------------------------------------------------------------------
FN_BEGIN Clk_TogglePause, 0
    cmp  clkPaused, 0
    jne  tp_resume
    call Clk_Now
    mov  clkFrozen, eax
    mov  clkPaused, 1
    call Aud_Stop
    jmp  tp_out
tp_resume:
    mov  clkPaused, 0
    mov  ecx, clkFrozen
    call Clk_Seek
tp_out:
    FN_RET
FN_END Clk_TogglePause

; ---------------------------------------------------------------------------
; Clk_NextScene - jump to the start of the following scene (wraps around).
; ---------------------------------------------------------------------------
FN_BEGIN Clk_NextScene, 0
    call Clk_Now
    xor  edx, edx
    mov  ecx, SCENE_MS
    div  ecx
    inc  eax
    cmp  eax, NUM_SCENES
    jb   ns_ok
    xor  eax, eax
ns_ok:
    imul ecx, eax, SCENE_MS
    call Clk_Seek
    FN_RET
FN_END Clk_NextScene

; ---------------------------------------------------------------------------
; Clk_PrevScene - restart the current scene, or go one scene back when it has
; only just begun.
; ---------------------------------------------------------------------------
FN_BEGIN Clk_PrevScene, 0
    call Clk_Now
    xor  edx, edx
    mov  ecx, SCENE_MS
    div  ecx                               ; eax = scene, edx = ms inside it
    cmp  edx, RESTART_MS
    jae  ps_seek
    dec  eax
    jns  ps_seek
    mov  eax, NUM_SCENES - 1
ps_seek:
    imul ecx, eax, SCENE_MS
    call Clk_Seek
    FN_RET
FN_END Clk_PrevScene

END
