; ============================================================================
; sys.asm - memory, timing, console/file output, command-line helpers
; ============================================================================
INCLUDE common.inc
INCLUDE win.inc

.const
szFatalTitle BYTE "Rebario Dreams - fatal error", 0
szOutOfMem   BYTE "Out of memory (VirtualAlloc failed)", 0
szCrLf       BYTE 13, 10, 0

.data
ALIGN 16
gStdOut      QWORD 0

.data?
ALIGN 16
gQpcFreq     QWORD ?
gQpcStart    QWORD ?

.code

; ---------------------------------------------------------------------------
; Sys_Init - high resolution timer base and the (optional) inherited stdout.
; ---------------------------------------------------------------------------
FN_BEGIN Sys_Init, 0
    lea  rcx, gQpcFreq
    call QueryPerformanceFrequency
    lea  rcx, gQpcStart
    call QueryPerformanceCounter
    mov  ecx, -11                        ; STD_OUTPUT_HANDLE
    call GetStdHandle
    mov  gStdOut, rax
    FN_RET
FN_END Sys_Init

; ---------------------------------------------------------------------------
; Sys_NowMs -> rax = milliseconds since Sys_Init (monotonic).
; ---------------------------------------------------------------------------
FN_BEGIN Sys_NowMs, 16
    lea  rcx, [rsp+LOC]
    call QueryPerformanceCounter
    mov  rax, QWORD PTR [rsp+LOC]
    sub  rax, gQpcStart
    imul rax, rax, 1000
    xor  edx, edx
    div  QWORD PTR gQpcFreq
    FN_RET
FN_END Sys_NowMs

; ---------------------------------------------------------------------------
; Mem_Alloc(rcx = bytes) -> rax = zeroed, page-aligned block. Never fails.
; ---------------------------------------------------------------------------
FN_BEGIN Mem_Alloc, 0
    mov  rdx, rcx
    xor  ecx, ecx
    mov  r8d, MEM_COMMIT_RESERVE
    mov  r9d, PAGE_READWRITE
    call VirtualAlloc
    test rax, rax
    jnz  ma_ok
    lea  rcx, szOutOfMem
    call Sys_Fatal
ma_ok:
    FN_RET
FN_END Mem_Alloc

; ---------------------------------------------------------------------------
; Sys_Print(rcx = ASCIIZ) - debugger output plus inherited stdout, if any.
; ---------------------------------------------------------------------------
FN_BEGIN Sys_Print, 16
    mov  rsi, rcx
    xor  ebx, ebx
sp_len:
    cmp  BYTE PTR [rsi+rbx], 0
    je   sp_len_done
    inc  ebx
    jmp  sp_len
sp_len_done:
    mov  rcx, rsi
    call OutputDebugStringA
    mov  rcx, gStdOut
    cmp  rcx, -1
    je   sp_done
    test rcx, rcx
    jz   sp_done
    mov  rdx, rsi
    mov  r8d, ebx
    lea  r9, [rsp+LOC]
    mov  QWORD PTR [rsp+32], 0
    call WriteFile
sp_done:
    FN_RET
FN_END Sys_Print

; Sys_PrintLn(rcx = ASCIIZ) - text followed by CR LF.
FN_BEGIN Sys_PrintLn, 0
    call Sys_Print
    lea  rcx, szCrLf
    call Sys_Print
    FN_RET
FN_END Sys_PrintLn

; ---------------------------------------------------------------------------
; Sys_Fatal(rcx = message) - reports the error and terminates with exit code 1.
; ---------------------------------------------------------------------------
FN_BEGIN Sys_Fatal, 0
    mov  rsi, rcx
    cmp  gHeadless, 0
    jne  fatal_print
    xor  ecx, ecx
    mov  rdx, rsi
    lea  r8, szFatalTitle
    mov  r9d, MB_OK OR MB_ICONERROR
    call MessageBoxA
    jmp  fatal_exit
fatal_print:
    mov  rcx, rsi
    call Sys_PrintLn
fatal_exit:
    mov  ecx, 1
    call ExitProcess
FN_END Sys_Fatal

; ---------------------------------------------------------------------------
; Sys_WriteFile(rcx = path, rdx = data, r8 = size) -> eax = 1 on success.
; ---------------------------------------------------------------------------
FN_BEGIN Sys_WriteFile, 16
    mov  r12, rdx
    mov  r13, r8
    mov  edx, GENERIC_WRITE
    xor  r8d, r8d
    xor  r9d, r9d
    mov  QWORD PTR [rsp+32], CREATE_ALWAYS
    mov  QWORD PTR [rsp+40], FILE_ATTRIBUTE_NORMAL
    mov  QWORD PTR [rsp+48], 0
    call CreateFileA
    cmp  rax, -1
    je   wf_fail
    mov  rbx, rax
    mov  rcx, rbx
    mov  rdx, r12
    mov  r8d, r13d
    lea  r9, [rsp+LOC]
    mov  QWORD PTR [rsp+32], 0
    call WriteFile
    mov  esi, eax
    mov  rcx, rbx
    call CloseHandle
    mov  eax, esi
    jmp  wf_out
wf_fail:
    xor  eax, eax
wf_out:
    FN_RET
FN_END Sys_WriteFile

; ---------------------------------------------------------------------------
; Sys_FmtInt(rcx = dst (>= 12 bytes), edx = int32) -> eax = length, NUL-terminated.
; ---------------------------------------------------------------------------
LEAF_BEGIN Sys_FmtInt
    mov  r8, rcx
    mov  eax, edx
    test eax, eax
    jns  fi_pos
    mov  BYTE PTR [rcx], '-'
    inc  rcx
    neg  eax
fi_pos:
    mov  r9, rcx
    mov  r10d, 10
fi_dg:
    xor  edx, edx
    div  r10d
    add  dl, '0'
    mov  BYTE PTR [rcx], dl
    inc  rcx
    test eax, eax
    jnz  fi_dg
    mov  BYTE PTR [rcx], 0
    mov  r11, rcx
    dec  rcx
fi_rev:
    cmp  r9, rcx
    jae  fi_done
    mov  al, BYTE PTR [r9]
    mov  dl, BYTE PTR [rcx]
    mov  BYTE PTR [r9], dl
    mov  BYTE PTR [rcx], al
    inc  r9
    dec  rcx
    jmp  fi_rev
fi_done:
    mov  rax, r11
    sub  rax, r8
    ret
LEAF_END Sys_FmtInt

; Sys_PrintInt(ecx = value) - decimal number without newline.
FN_BEGIN Sys_PrintInt, 32
    mov  edx, ecx
    lea  rcx, [rsp+LOC]
    call Sys_FmtInt
    lea  rcx, [rsp+LOC]
    call Sys_Print
    FN_RET
FN_END Sys_PrintInt

; ---------------------------------------------------------------------------
; Cmd_Next(rcx = position, rdx = outBuf, r8d = outSize) -> rax = new position,
; or 0 when no more tokens. Handles "quoted tokens". Leaf function.
; ---------------------------------------------------------------------------
LEAF_BEGIN Cmd_Next
cn_skip:
    mov  al, BYTE PTR [rcx]
    cmp  al, ' '
    jne  cn_chk
    inc  rcx
    jmp  cn_skip
cn_chk:
    test al, al
    jnz  cn_start
    xor  eax, eax
    ret
cn_start:
    mov  r9b, ' '
    cmp  al, '"'
    jne  cn_init
    mov  r9b, '"'
    inc  rcx
cn_init:
    dec  r8d
    xor  r10d, r10d
cn_copy:
    mov  al, BYTE PTR [rcx]
    test al, al
    jz   cn_end
    cmp  al, r9b
    je   cn_close
    cmp  r10d, r8d
    jae  cn_next
    mov  BYTE PTR [rdx+r10], al
    inc  r10d
cn_next:
    inc  rcx
    jmp  cn_copy
cn_close:
    inc  rcx
cn_end:
    mov  BYTE PTR [rdx+r10], 0
    mov  rax, rcx
    ret
LEAF_END Cmd_Next

; Sys_ParseInt(rcx = ASCIIZ) -> eax. Optional leading '-'. Leaf function.
LEAF_BEGIN Sys_ParseInt
    xor  eax, eax
    xor  r8d, r8d
    cmp  BYTE PTR [rcx], '-'
    jne  pi_lp
    mov  r8d, 1
    inc  rcx
pi_lp:
    movzx edx, BYTE PTR [rcx]
    sub  edx, '0'
    cmp  edx, 9
    ja   pi_done
    imul eax, eax, 10
    add  eax, edx
    inc  rcx
    jmp  pi_lp
pi_done:
    test r8d, r8d
    jz   pi_ret
    neg  eax
pi_ret:
    ret
LEAF_END Sys_ParseInt

; Sys_StrEqI(rcx = a, rdx = b) -> eax = 1 if equal, ASCII case-insensitive.
LEAF_BEGIN Sys_StrEqI
se_lp:
    movzx eax, BYTE PTR [rcx]
    movzx r8d, BYTE PTR [rdx]
    lea  r9d, [rax-'A']
    cmp  r9d, 25
    ja   se_a
    or   eax, 20h
se_a:
    lea  r9d, [r8-'A']
    cmp  r9d, 25
    ja   se_b
    or   r8d, 20h
se_b:
    cmp  eax, r8d
    jne  se_ne
    test eax, eax
    jz   se_eq
    inc  rcx
    inc  rdx
    jmp  se_lp
se_ne:
    xor  eax, eax
    ret
se_eq:
    mov  eax, 1
    ret
LEAF_END Sys_StrEqI

END
