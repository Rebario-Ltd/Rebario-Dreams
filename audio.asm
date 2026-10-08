; ============================================================================
; audio.asm - waveOut playback of the pre-rendered soundtrack (gPcm).
; ----------------------------------------------------------------------------
; The whole soundtrack (135 s, 44.1 kHz, 16-bit stereo) is one WAVEHDR; to play
; from the middle (scene jumps) the header simply points into the buffer.  The
; position counter of the device is the master clock of the demo (clock.asm).
;
; Interface used by the clock / application:
;   Aud_Open(rcx = pcm)  -> eax = 1 when an output device is available
;   Aud_Play(ecx = ms)      start (or restart) playback at a demo time
;   Aud_Stop                stop playback (used for pause and before a restart)
;   Aud_PosMs            -> eax = audible demo time in ms, or -1 when silent
;   Aud_Close               release the device
; Every call is a no-op when no device could be opened: the demo then simply
; runs on the wall clock.
; ============================================================================
INCLUDE common.inc
INCLUDE win.inc

HDR_SIZE EQU 48                          ; sizeof(WAVEHDR)
MMT_SIZE EQU 12                          ; sizeof(MMTIME), packed

.const
ALIGN 8
audFmt  WAVEFORMATEX <WAVE_FORMAT_PCM, 2, AUDIO_RATE, AUDIO_RATE * 4, 4, 16, 0>

.data?
ALIGN 16
audHwo   QWORD ?
audPcm   QWORD ?
audHdr   WAVEHDR <>
audMmt   DWORD 4 DUP (?)                 ; MMTIME { wType, union { sample | cb | ... } }
audStart DWORD ?                         ; demo time (ms) at which the playback began
audState DWORD ?                         ; 0 = no device, 1 = idle, 2 = playing

.code

; ---------------------------------------------------------------------------
; Aud_Open(rcx = pcm) -> eax = 1 if the default wave device accepted 44.1k/16/2.
; ---------------------------------------------------------------------------
FN_BEGIN Aud_Open, 0
    mov    audPcm, rcx
    mov    audState, 0
    lea    rcx, audHwo
    mov    edx, WAVE_MAPPER
    lea    r8, audFmt
    xor    r9d, r9d
    mov    QWORD PTR [rsp+32], 0         ; dwInstance
    mov    QWORD PTR [rsp+40], 0         ; CALLBACK_NULL
    call   waveOutOpen
    test   eax, eax
    jnz    ao_none
    mov    audState, 1
    mov    eax, 1
    jmp    ao_out
ao_none:
    xor    eax, eax
ao_out:
    FN_RET
FN_END Aud_Open

; ---------------------------------------------------------------------------
; Aud_Stop - halts the playback; the position counter restarts from zero.
; ---------------------------------------------------------------------------
FN_BEGIN Aud_Stop, 0
    cmp    audState, 2
    jne    as_out
    mov    rcx, audHwo
    call   waveOutReset
    mov    rcx, audHwo
    lea    rdx, audHdr
    mov    r8d, HDR_SIZE
    call   waveOutUnprepareHeader
    mov    audState, 1
as_out:
    FN_RET
FN_END Aud_Stop

; ---------------------------------------------------------------------------
; Aud_Play(ecx = demo ms) - (re)starts the soundtrack at that time.
; ---------------------------------------------------------------------------
FN_BEGIN Aud_Play, 0
    cmp    audState, 0
    je     ap_out
    mov    ebx, ecx
    call   Aud_Stop
    cmp    ebx, TOTAL_MS
    jae    ap_out
    mov    eax, ebx
    imul   rax, rax, 441                 ; frames = ms * 44100 / 1000
    xor    edx, edx
    mov    ecx, 10
    div    rcx
    shl    eax, 2                        ; byte offset of that frame
    mov    r12d, eax
    lea    rdx, audHdr
    mov    rcx, audPcm
    add    rcx, rax
    mov    QWORD PTR [rdx+WAVEHDR.lpData], rcx
    mov    eax, AUDIO_BYTES
    sub    eax, r12d
    mov    DWORD PTR [rdx+WAVEHDR.dwBufferLength], eax
    mov    DWORD PTR [rdx+WAVEHDR.dwFlags], 0
    mov    DWORD PTR [rdx+WAVEHDR.dwLoops], 0
    mov    rcx, audHwo
    mov    r8d, HDR_SIZE
    call   waveOutPrepareHeader
    test   eax, eax
    jnz    ap_out
    mov    rcx, audHwo
    lea    rdx, audHdr
    mov    r8d, HDR_SIZE
    call   waveOutWrite
    test   eax, eax
    jnz    ap_undo
    mov    audStart, ebx
    mov    audState, 2
    jmp    ap_out
ap_undo:
    mov    rcx, audHwo
    lea    rdx, audHdr
    mov    r8d, HDR_SIZE
    call   waveOutUnprepareHeader
ap_out:
    FN_RET
FN_END Aud_Play

; ---------------------------------------------------------------------------
; Aud_PosMs -> eax = demo time (ms) that is audible right now, -1 when silent
; (no device, stopped, or the whole buffer has been played).
; ---------------------------------------------------------------------------
FN_BEGIN Aud_PosMs, 0
    cmp    audState, 2
    jne    pm_silent
    lea    rax, audHdr
    test   DWORD PTR [rax+WAVEHDR.dwFlags], WHDR_DONE
    jnz    pm_silent
    lea    rdx, audMmt
    mov    DWORD PTR [rdx], TIME_SAMPLES
    mov    rcx, audHwo
    mov    r8d, MMT_SIZE
    call   waveOutGetPosition
    test   eax, eax
    jnz    pm_silent
    lea    rdx, audMmt
    mov    eax, DWORD PTR [rdx]
    mov    ecx, DWORD PTR [rdx+4]
    cmp    eax, TIME_SAMPLES
    je     pm_calc
    cmp    eax, TIME_BYTES
    jne    pm_silent
    shr    ecx, 2                        ; bytes -> sample frames
pm_calc:
    mov    eax, ecx
    imul   rax, rax, 1000
    xor    edx, edx
    mov    ecx, AUDIO_RATE
    div    rcx
    add    eax, audStart
    jmp    pm_out
pm_silent:
    mov    eax, -1
pm_out:
    FN_RET
FN_END Aud_PosMs

; ---------------------------------------------------------------------------
; Aud_Close - stops and releases the device.
; ---------------------------------------------------------------------------
FN_BEGIN Aud_Close, 0
    cmp    audState, 0
    je     ac_out
    call   Aud_Stop
    mov    rcx, audHwo
    call   waveOutClose
    mov    audState, 0
ac_out:
    FN_RET
FN_END Aud_Close

END
