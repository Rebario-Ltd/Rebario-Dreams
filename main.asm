; ============================================================================
; main.asm - process entry point and command-line dispatch.
;
;   SiliconDreams.exe [/mute]              play the demo (window + music)
;   SiliconDreams.exe /shot <ms> <file>    render one frame to a BMP, no window
;   SiliconDreams.exe /wav <file>          render the soundtrack to a WAV
;   SiliconDreams.exe /selftest [group]    built-in checks (g3: only the 3D renderer
;                                          and the PRISM scene; pulse: only the soft
;                                          pulse of the picture; sig: only the credit
;                                          line), exit code = failures
;   SiliconDreams.exe /bench [frames]      milliseconds per frame of every scene
;
; /mute may precede any other option; it skips the soundtrack synthesis and
; the wave device (used by the automated window tests).  Diagnostic options
; run headless and return their result as the process exit code.
; ============================================================================
INCLUDE common.inc
INCLUDE win.inc

; One row of the option table: spelling and handler (rcx = command-line
; position after the option -> eax = exit code).
OPTENT STRUCT
    optName QWORD ?
    optFn   QWORD ?
OPTENT ENDS

.const
szOptShot  BYTE "/shot", 0
szOptWav   BYTE "/wav", 0
szOptMute  BYTE "/mute", 0
szOptTest  BYTE "/selftest", 0
szOptBench BYTE "/bench", 0
szUsage    BYTE "usage: SiliconDreams [/mute]", 13, 10
           BYTE "       SiliconDreams [/mute] /shot <ms> <file.bmp>", 13, 10
           BYTE "       SiliconDreams /wav <file.wav>", 13, 10
           BYTE "       SiliconDreams /selftest [g3|pulse|sig]", 13, 10
           BYTE "       SiliconDreams /bench [frames]", 0

ALIGN 8
optTab     OPTENT <szOptShot, Opt_Shot>
           OPTENT <szOptWav, Opt_Wav>
           OPTENT <szOptTest, Diag_SelfTest>
           OPTENT <szOptBench, Diag_Bench>
           OPTENT <0, 0>

.data?
ALIGN 16
tokOpt     BYTE 64 DUP (?)
tokNum     BYTE 64 DUP (?)
tokPath    BYTE 520 DUP (?)

.code

; ---------------------------------------------------------------------------
; Opt_Usage -> eax = 2 after printing the usage text.
; ---------------------------------------------------------------------------
FN_BEGIN Opt_Usage, 0
    lea  rcx, szUsage
    call Sys_PrintLn
    mov  eax, 2
    FN_RET
FN_END Opt_Usage

; ---------------------------------------------------------------------------
; Opt_Shot(rcx = command line position after "/shot") -> eax = exit code.
; ---------------------------------------------------------------------------
FN_BEGIN Opt_Shot, 0
    lea  rdx, tokNum
    mov  r8d, 64
    call Cmd_Next
    test rax, rax
    jz   os_usage
    mov  rcx, rax
    lea  rdx, tokPath
    mov  r8d, 520
    call Cmd_Next
    test rax, rax
    jz   os_usage
    lea  rcx, tokNum
    call Sys_ParseInt
    mov  ecx, eax
    lea  rdx, tokPath
    call Diag_RunShot
    jmp  os_out
os_usage:
    call Opt_Usage
os_out:
    FN_RET
FN_END Opt_Shot

; ---------------------------------------------------------------------------
; Opt_Wav(rcx = command line position after "/wav") -> eax = exit code.
; ---------------------------------------------------------------------------
FN_BEGIN Opt_Wav, 0
    lea  rdx, tokPath
    mov  r8d, 520
    call Cmd_Next
    test rax, rax
    jz   ow_usage
    lea  rcx, tokPath
    call Diag_RunWav
    jmp  ow_out
ow_usage:
    call Opt_Usage
ow_out:
    FN_RET
FN_END Opt_Wav

; ---------------------------------------------------------------------------
; Opt_Dispatch(rcx = option token, rdx = command line position after it)
;   -> eax = exit code of the handler, 2 for an unknown option.
; ---------------------------------------------------------------------------
FN_BEGIN Opt_Dispatch, 0
    mov  rsi, rcx
    mov  rdi, rdx
    lea  rbx, optTab
od_next:
    mov  rdx, QWORD PTR [rbx+OPTENT.optName]
    test rdx, rdx
    jz   od_unknown
    mov  rcx, rsi
    call Sys_StrEqI
    test eax, eax
    jnz  od_found
    add  rbx, SIZEOF OPTENT
    jmp  od_next
od_found:
    mov  gHeadless, 1
    mov  rcx, rdi
    call QWORD PTR [rbx+OPTENT.optFn]
    jmp  od_out
od_unknown:
    mov  gHeadless, 1
    call Opt_Usage
od_out:
    FN_RET
FN_END Opt_Dispatch

; ---------------------------------------------------------------------------
; Start - image entry point.
; ---------------------------------------------------------------------------
PUBLIC Start
FN_BEGIN Start, 16
    stmxcsr DWORD PTR [rsp+LOC]            ; flush denormals: no slow-downs in filters
    or   DWORD PTR [rsp+LOC], 8040h
    ldmxcsr DWORD PTR [rsp+LOC]
    call Sys_Init
    call GetCommandLineA
    mov  rcx, rax
    lea  rdx, tokOpt
    mov  r8d, 64
    call Cmd_Next                          ; program name
    mov  rsi, rax
st_opt:
    test rsi, rsi
    jz   st_play
    mov  rcx, rsi
    lea  rdx, tokOpt
    mov  r8d, 64
    call Cmd_Next                          ; next option, if any
    test rax, rax
    jz   st_play
    mov  rsi, rax
    lea  rcx, tokOpt
    lea  rdx, szOptMute
    call Sys_StrEqI
    test eax, eax
    jz   st_dispatch
    mov  gMute, 1
    jmp  st_opt
st_dispatch:
    lea  rcx, tokOpt
    mov  rdx, rsi
    call Opt_Dispatch
    mov  ecx, eax
    call ExitProcess
st_play:
    call App_Run
    xor  ecx, ecx
    call ExitProcess
FN_END Start

END
