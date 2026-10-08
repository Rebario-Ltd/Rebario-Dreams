; ============================================================================
; bench.asm - rendering speed (SiliconDreams.exe /bench [frames]).
; ----------------------------------------------------------------------------
; Renders `frames` complete 1280x720 presentation frames (default 60) of every
; scene, one after the other, and prints milliseconds per frame and the frame
; rate; the soundtrack synthesis is timed as well.  Headless, no window.
; ============================================================================
INCLUDE common.inc

BENCH_DEFAULT EQU 60
BENCH_MAX     EQU 3000
BENCH_STEP_MS EQU 33

.const
szBnScene   BYTE "scene ", 0
szBnMs      BYTE " ms/frame  (", 0
szBnFps     BYTE " fps)", 0
szBnSynth   BYTE "soundtrack synthesis: ", 0
szBnRealA   BYTE " ms  (", 0
szBnRealB   BYTE "x faster than real time)", 0
szBnSpace   BYTE "  ", 0
szBnDot     BYTE ".", 0
szBnZero    BYTE "0", 0

.data?
ALIGN 16
benNum      BYTE 32 DUP (?)

.code

; ---------------------------------------------------------------------------
; Bn_Print100(ecx = value * 100) - prints "whole.frac" with two decimals.
; ---------------------------------------------------------------------------
FN_BEGIN Bn_Print100, 0
    mov    eax, ecx
    xor    edx, edx
    mov    ecx, 100
    div    ecx
    mov    ebx, edx                        ; fraction
    mov    ecx, eax
    call   Sys_PrintInt
    lea    rcx, szBnDot
    call   Sys_Print
    cmp    ebx, 10
    jae    pr_frac
    lea    rcx, szBnZero
    call   Sys_Print
pr_frac:
    mov    ecx, ebx
    call   Sys_PrintInt
    FN_RET
FN_END Bn_Print100

; ---------------------------------------------------------------------------
; Bn_Line(ecx = scene index, edx = elapsed ms, r8d = frames) - one result row.
; ---------------------------------------------------------------------------
FN_BEGIN Bn_Line, 0
    mov    ebx, ecx
    mov    esi, edx
    mov    edi, r8d
    test   esi, esi
    jnz    bl_ok
    mov    esi, 1                          ; never divide by zero
bl_ok:
    lea    rcx, szBnScene
    call   Sys_Print
    lea    ecx, [rbx+1]
    call   Sys_PrintInt
    lea    rcx, szBnSpace
    call   Sys_Print
    mov    eax, esi
    imul   rax, rax, 100
    xor    edx, edx
    div    rdi                             ; ms per frame x 100
    mov    ecx, eax
    call   Bn_Print100
    lea    rcx, szBnMs
    call   Sys_Print
    mov    eax, edi
    imul   rax, rax, 1000
    xor    edx, edx
    div    rsi                             ; frames per second
    mov    ecx, eax
    call   Sys_PrintInt
    lea    rcx, szBnFps
    call   Sys_PrintLn
    FN_RET
FN_END Bn_Line

; ---------------------------------------------------------------------------
; Bn_Scene(ecx = scene index, edx = frames) - times one scene.
; ---------------------------------------------------------------------------
FN_BEGIN Bn_Scene, 0
    mov    r12d, ecx
    mov    r13d, edx
    imul   ebx, ecx, SCENE_MS
    add    ebx, 3000                       ; inside the scene, away from the transitions
    call   Sys_NowMs
    mov    r14, rax
    xor    esi, esi
bs_lp:
    mov    ecx, ebx
    call   Demo_Render
    add    ebx, BENCH_STEP_MS
    inc    esi
    cmp    esi, r13d
    jb     bs_lp
    call   Sys_NowMs
    sub    rax, r14
    mov    ecx, r12d
    mov    edx, eax
    mov    r8d, r13d
    call   Bn_Line
    FN_RET
FN_END Bn_Scene

; ---------------------------------------------------------------------------
; Bn_Synth - times the soundtrack synthesis.
; ---------------------------------------------------------------------------
FN_BEGIN Bn_Synth, 0
    call   Sys_NowMs
    mov    rbx, rax
    call   Aud_Render
    call   Sys_NowMs
    sub    rax, rbx
    mov    ebx, eax
    lea    rcx, szBnSynth
    call   Sys_Print
    mov    ecx, ebx
    call   Sys_PrintInt
    lea    rcx, szBnRealA
    call   Sys_Print
    mov    eax, TOTAL_MS
    xor    edx, edx
    test   ebx, ebx
    jz     sy_done
    div    ebx
sy_done:
    mov    ecx, eax
    call   Sys_PrintInt
    lea    rcx, szBnRealB
    call   Sys_PrintLn
    FN_RET
FN_END Bn_Synth

; ---------------------------------------------------------------------------
; Diag_Bench(rcx = command line position after "/bench") -> eax = 0.
; ---------------------------------------------------------------------------
FN_BEGIN Diag_Bench, 0
    mov    r12d, BENCH_DEFAULT
    lea    rdx, benNum
    mov    r8d, 32
    call   Cmd_Next
    test   rax, rax
    jz     db_go
    lea    rcx, benNum
    call   Sys_ParseInt
    test   eax, eax
    jle    db_go
    cmp    eax, BENCH_MAX
    cmova  eax, r12d
    mov    r12d, eax
db_go:
    call   Demo_Init
    xor    ebx, ebx
db_scene:
    mov    ecx, ebx
    mov    edx, r12d
    call   Bn_Scene
    inc    ebx
    cmp    ebx, NUM_SCENES
    jb     db_scene
    call   Bn_Synth
    xor    eax, eax
    FN_RET
FN_END Diag_Bench

END
