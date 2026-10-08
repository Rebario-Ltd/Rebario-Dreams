; ============================================================================
; data.asm - storage for the process-wide shared state declared in common.inc
; ============================================================================
INCLUDE common.inc

.data
ALIGN 16
gRng        DWORD 2463534242          ; xorshift32 state, never zero
gFade       DWORD 256

.data?
ALIGN 16
gFbA        QWORD ?
gFbB        QWORD ?
gFbC        QWORD ?
gFbOut      QWORD ?
gPcm        QWORD ?
gProgressCb QWORD ?

gTimeMs     DWORD ?
gBeat16     DWORD ?
gBeatNo     DWORD ?
gBeatEnv    DWORD ?
gKick       DWORD ?
gFlash      DWORD ?
gProgress   DWORD ?
gHeadless   DWORD ?
gMute       DWORD ?

ALIGN 16
gSinTab     WORD 4096 DUP (?)
ALIGN 16
gSinTabF    REAL4 4100 DUP (?)

END
