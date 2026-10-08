; ============================================================================
; diag.asm - headless diagnostics: BMP screenshots of any demo time and the
;            WAV rendering of the soundtrack.
; ============================================================================
INCLUDE common.inc
INCLUDE win.inc

WAV_HDR   EQU 44                         ; bytes of a canonical PCM WAV header

.const
szShotOk BYTE "shot written: ", 0
szShotErr BYTE "cannot write the screenshot file", 0
szWavOk   BYTE "wav written: ", 0
szWavTime BYTE "  (synthesis ", 0
szWavMs   BYTE " ms)", 0
szWavErr  BYTE "cannot write the wav file", 0

.code

; ---------------------------------------------------------------------------
; Diag_WriteBmp(rcx = path, rdx = BGRA pixels (top-down), r8d = w, r9d = h)
;   -> eax = 1 on success. Writes a 32-bit bottom-up BMP.
; ---------------------------------------------------------------------------
FN_BEGIN Diag_WriteBmp, 0
    mov  r12, rcx
    mov  r13, rdx
    mov  r14d, r8d
    mov  r15d, r9d
    mov  eax, r14d
    imul eax, r15d
    shl  eax, 2
    mov  ebx, eax                          ; pixel bytes
    lea  ecx, [rbx+54]
    call Mem_Alloc
    mov  rbp, rax
    mov  rdi, rax
    mov  WORD PTR [rdi], 4D42h             ; "BM"
    lea  eax, [rbx+54]
    mov  DWORD PTR [rdi+2], eax
    mov  DWORD PTR [rdi+6], 0
    mov  DWORD PTR [rdi+10], 54
    mov  DWORD PTR [rdi+14], 40
    mov  DWORD PTR [rdi+18], r14d
    mov  DWORD PTR [rdi+22], r15d
    mov  WORD PTR [rdi+26], 1
    mov  WORD PTR [rdi+28], 32
    mov  DWORD PTR [rdi+30], 0
    mov  DWORD PTR [rdi+34], ebx
    mov  DWORD PTR [rdi+38], 2835
    mov  DWORD PTR [rdi+42], 2835
    mov  DWORD PTR [rdi+46], 0
    mov  DWORD PTR [rdi+50], 0
    lea  rdi, [rbp+54]
    mov  r10d, r15d
bm_row:
    dec  r10d
    mov  eax, r10d
    imul eax, r14d
    shl  rax, 2
    lea  rsi, [r13+rax]
    mov  ecx, r14d
    rep  movsd
    test r10d, r10d
    jnz  bm_row
    mov  rcx, r12
    mov  rdx, rbp
    lea  r8d, [rbx+54]
    call Sys_WriteFile
    mov  esi, eax
    mov  rcx, rbp
    xor  edx, edx
    mov  r8d, MEM_RELEASE
    call VirtualFree
    mov  eax, esi
    FN_RET
FN_END Diag_WriteBmp

; ---------------------------------------------------------------------------
; Diag_RunShot(rcx = demo time ms, rdx = output path) -> eax = exit code.
; Renders one complete presentation frame (1280x720) without a window.
; ---------------------------------------------------------------------------
FN_BEGIN Diag_RunShot, 0
    mov  ebx, ecx
    mov  rsi, rdx
    call Demo_Init
    mov  ecx, ebx
    call Demo_Render
    mov  rcx, rsi
    mov  rdx, gFbOut
    mov  r8d, OUT_W
    mov  r9d, OUT_H
    call Diag_WriteBmp
    test eax, eax
    jz   shot_fail
    lea  rcx, szShotOk
    call Sys_Print
    mov  rcx, rsi
    call Sys_PrintLn
    xor  eax, eax
    jmp  shot_out
shot_fail:
    lea  rcx, szShotErr
    call Sys_PrintLn
    mov  eax, 1
shot_out:
    FN_RET
FN_END Diag_RunShot

; ---------------------------------------------------------------------------
; Diag_WavHeader(rcx = destination, 44 bytes) - canonical PCM header for the
; soundtrack (44.1 kHz, 16-bit, stereo, AUDIO_BYTES of data).
; ---------------------------------------------------------------------------
LEAF_BEGIN Diag_WavHeader
    mov  DWORD PTR [rcx], 46464952h        ; "RIFF"
    mov  DWORD PTR [rcx+4], AUDIO_BYTES + 36
    mov  DWORD PTR [rcx+8], 45564157h      ; "WAVE"
    mov  DWORD PTR [rcx+12], 20746D66h     ; "fmt "
    mov  DWORD PTR [rcx+16], 16
    mov  DWORD PTR [rcx+20], 00020001h     ; PCM, 2 channels
    mov  DWORD PTR [rcx+24], AUDIO_RATE
    mov  DWORD PTR [rcx+28], AUDIO_RATE * 4
    mov  DWORD PTR [rcx+32], 00100004h     ; block align 4, 16 bits
    mov  DWORD PTR [rcx+36], 61746164h     ; "data"
    mov  DWORD PTR [rcx+40], AUDIO_BYTES
    ret
LEAF_END Diag_WavHeader

; ---------------------------------------------------------------------------
; Diag_RunWav(rcx = output path) -> eax = exit code.
; Synthesises the soundtrack and stores it as a WAV file; the header is built
; in the room that Aud_Render leaves in front of gPcm.
; ---------------------------------------------------------------------------
FN_BEGIN Diag_RunWav, 0
    mov  rsi, rcx
    call Sys_NowMs
    mov  rbx, rax
    call Mth_Init
    call Aud_Render
    call Sys_NowMs
    sub  rax, rbx
    mov  ebx, eax                          ; synthesis time in ms
    mov  rdi, gPcm
    sub  rdi, WAV_HDR
    mov  rcx, rdi
    call Diag_WavHeader
    mov  rcx, rsi
    mov  rdx, rdi
    mov  r8d, AUDIO_BYTES + WAV_HDR
    call Sys_WriteFile
    test eax, eax
    jz   wav_fail
    lea  rcx, szWavOk
    call Sys_Print
    mov  rcx, rsi
    call Sys_Print
    lea  rcx, szWavTime
    call Sys_Print
    mov  ecx, ebx
    call Sys_PrintInt
    lea  rcx, szWavMs
    call Sys_PrintLn
    xor  eax, eax
    jmp  wav_out
wav_fail:
    lea  rcx, szWavErr
    call Sys_PrintLn
    mov  eax, 1
wav_out:
    FN_RET
FN_END Diag_RunWav

END
