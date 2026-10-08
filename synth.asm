; ============================================================================
; synth.asm - generic subtractive voice and the instrument patches.
; ----------------------------------------------------------------------------
; Syn_Note renders one note offline into a float stereo bus: up to three
; PolyBLEP saws (optionally a pulse), a sine sub oscillator, a resonant
; state-variable low-pass with its own decay envelope, an ADSR amplitude
; envelope with exponential decay / release, optional vibrato, soft drive
; and constant-power panning.  Everything is computed per sample in scalar
; SSE; the parameters of an instrument live in a PATCH record.
; ============================================================================
INCLUDE common.inc
INCLUDE audio.inc
INCLUDE dsp.inc

VF_B    EQU 1                            ; flags derived from the patch
VF_C    EQU 2
VF_SUB  EQU 4
VF_DRV  EQU 8
VF_VIB  EQU 16

; Per-note derived constants (single static instance: notes are rendered one at a time).
VSTATE STRUCT
    dtA     REAL4 ?                      ; phase increments per sample
    dtB     REAL4 ?
    dtC     REAL4 ?
    dtS     REAL4 ?
    attInc  REAL4 ?                      ; linear attack step
    decMul  REAL4 ?                      ; per-sample decay / release / cut-off decay factors
    relMul  REAL4 ?
    fenvMul REAL4 ?
    f0      REAL4 ?                      ; filter coefficient at rest
    fE      REAL4 ?                      ; extra coefficient at the start of the note
    gl      REAL4 ?                      ; left / right gain (pan * velocity)
    gr      REAL4 ?
    vibInc  REAL4 ?                      ; vibrato phase step
    vibAmp  REAL4 ?
    attN    DWORD ?                      ; attack length in samples
    vibN    DWORD ?                      ; samples before the vibrato starts
    total   DWORD ?                      ; samples to render (hold + release)
    flags   DWORD ?
VSTATE ENDS

.const
ALIGN 16
kNegLog2e   REAL4 -1.4426950
kPiOverSr   REAL4 7.1237929e-05
kQuarterPi  REAL4 0.78539816
kFMax       REAL4 0.85
kFcMax      REAL4 9000.0
kSr7        REAL4 308700.0               ; 7 time constants of release, in samples per second of tau
kSilence    REAL4 0.00003
kPhaseC     REAL4 0.61

;                  wA    wB     wC    dB      dC      phB   wSub  atk    dec   sus   rel   fcBase fcEnv   fcDec damp  drive vib  vibA    vibD  bus
Pat_Pad       PATCH <0.34, 0.34, 0.34, 1.0065, 0.9935, 0.31, 0.0, 0.5,   3.0,  0.85, 0.9,  700.0, 1700.0, 0.9,  1.4,  0.0,  0.0, 0.0,    0.0,  1>
Pat_Arp       PATCH <0.55, -0.55, 0.0, 1.0,    1.0,    0.35, 0.0, 0.002, 0.09, 0.15, 0.07, 650.0, 5200.0, 0.10, 0.6,  0.25, 0.0, 0.0,    0.0,  1>
Pat_Bass      PATCH <0.65, 0.0,  0.0,  1.0,    1.0,    0.0,  0.7, 0.003, 0.28, 0.6,  0.07, 150.0, 1100.0, 0.16, 0.8,  1.2,  0.0, 0.0,    0.0,  0>
Pat_BassHeavy PATCH <0.6,  0.5,  0.0,  1.007,  1.0,    0.2,  0.6, 0.002, 0.2,  0.55, 0.06, 180.0, 3200.0, 0.12, 0.45, 2.2,  0.0, 0.0,    0.0,  0>
Pat_Lead      PATCH <0.5,  0.45, 0.0,  1.0075, 1.0,    0.4,  0.0, 0.01,  0.5,  0.7,  0.3,  1500.0, 2600.0, 0.3,  0.9,  0.35, 5.3, 0.0035, 0.18, 1>

.data?
ALIGN 16
synBusDry   QWORD ?
synBusMus   QWORD ?
synVs       VSTATE <>

.code

; Sets VF_x in ebx when the REAL4 field of the patch (rdi) is not zero (xmm2 = 0).
FLAGIF MACRO field:REQ, bit:REQ
    LOCAL lSkip
    movss  xmm0, DWORD PTR [rdi+field]
    ucomiss xmm0, xmm2
    jz     lSkip
    or     ebx, bit
lSkip:
ENDM

; ---------------------------------------------------------------------------
; Vn_ExpMul: xmm0 = time constant in seconds -> xmm0 = per-sample decay factor.
; ---------------------------------------------------------------------------
FN_BEGIN Vn_ExpMul, 0
    mulss  xmm0, DWORD PTR kSr
    maxss  xmm0, DWORD PTR kOneF
    movss  xmm1, DWORD PTR kOneF
    divss  xmm1, xmm0
    mulss  xmm1, DWORD PTR kNegLog2e
    movaps xmm0, xmm1
    call   Mth_Exp2f
    FN_RET
FN_END Vn_ExpMul

; Vn_FcToF: xmm0 = cut-off in Hz -> xmm0 = SVF coefficient 2 sin(pi fc / sr), limited.
FN_BEGIN Vn_FcToF, 0
    mulss  xmm0, DWORD PTR kPiOverSr
    call   Mth_Sinf
    addss  xmm0, xmm0
    minss  xmm0, DWORD PTR kFMax
    FN_RET
FN_END Vn_FcToF

; ---------------------------------------------------------------------------
; Vn_PrepOsc: flags and oscillator phase increments.
;   rsi = NOTE *, rdi = PATCH *, r12 = VSTATE *
; ---------------------------------------------------------------------------
FN_BEGIN Vn_PrepOsc, 0
    xorps  xmm2, xmm2
    xor    ebx, ebx
    FLAGIF PATCH.wB, VF_B
    FLAGIF PATCH.wC, VF_C
    FLAGIF PATCH.wSub, VF_SUB
    FLAGIF PATCH.drive, VF_DRV
    FLAGIF PATCH.vibAmt, VF_VIB
    mov    DWORD PTR [r12+VSTATE.flags], ebx
    movss  xmm0, DWORD PTR [rsi+NOTE.freq]
    mulss  xmm0, DWORD PTR kInvSr
    movss  DWORD PTR [r12+VSTATE.dtA], xmm0
    movaps xmm1, xmm0
    mulss  xmm1, DWORD PTR [rdi+PATCH.ratB]
    movss  DWORD PTR [r12+VSTATE.dtB], xmm1
    movaps xmm1, xmm0
    mulss  xmm1, DWORD PTR [rdi+PATCH.ratC]
    movss  DWORD PTR [r12+VSTATE.dtC], xmm1
    mulss  xmm0, DWORD PTR kHalfF
    movss  DWORD PTR [r12+VSTATE.dtS], xmm0
    FN_RET
FN_END Vn_PrepOsc

; ---------------------------------------------------------------------------
; Vn_PrepEnv: attack, decay / release factors and the filter coefficients.
; ---------------------------------------------------------------------------
FN_BEGIN Vn_PrepEnv, 16
    movss  xmm0, DWORD PTR [rdi+PATCH.attack]
    mulss  xmm0, DWORD PTR kSr
    maxss  xmm0, DWORD PTR kOneF
    cvttss2si eax, xmm0
    mov    DWORD PTR [r12+VSTATE.attN], eax
    cvtsi2ss xmm0, eax
    movss  xmm1, DWORD PTR kOneF
    divss  xmm1, xmm0
    movss  DWORD PTR [r12+VSTATE.attInc], xmm1
    movss  xmm0, DWORD PTR [rdi+PATCH.decay]
    call   Vn_ExpMul
    movss  DWORD PTR [r12+VSTATE.decMul], xmm0
    movss  xmm0, DWORD PTR [rdi+PATCH.release]
    call   Vn_ExpMul
    movss  DWORD PTR [r12+VSTATE.relMul], xmm0
    movss  xmm0, DWORD PTR [rdi+PATCH.fcDec]
    call   Vn_ExpMul
    movss  DWORD PTR [r12+VSTATE.fenvMul], xmm0
    movss  xmm0, DWORD PTR [rdi+PATCH.fcBase]
    call   Vn_FcToF
    movss  DWORD PTR [r12+VSTATE.f0], xmm0
    movss  DWORD PTR [rsp+LOC], xmm0
    movss  xmm0, DWORD PTR [rdi+PATCH.fcBase]
    addss  xmm0, DWORD PTR [rdi+PATCH.fcEnv]
    minss  xmm0, DWORD PTR kFcMax
    call   Vn_FcToF
    subss  xmm0, DWORD PTR [rsp+LOC]
    xorps  xmm1, xmm1
    maxss  xmm0, xmm1
    movss  DWORD PTR [r12+VSTATE.fE], xmm0
    FN_RET
FN_END Vn_PrepEnv

; ---------------------------------------------------------------------------
; Vn_PrepOut: pan gains, vibrato and the number of samples to render.
; ---------------------------------------------------------------------------
FN_BEGIN Vn_PrepOut, 16
    movss  xmm0, DWORD PTR [rsi+NOTE.pan]
    addss  xmm0, DWORD PTR kOneF
    mulss  xmm0, DWORD PTR kQuarterPi
    movss  DWORD PTR [rsp+LOC], xmm0
    call   Mth_Cosf
    mulss  xmm0, DWORD PTR [rsi+NOTE.vel]
    movss  DWORD PTR [r12+VSTATE.gl], xmm0
    movss  xmm0, DWORD PTR [rsp+LOC]
    call   Mth_Sinf
    mulss  xmm0, DWORD PTR [rsi+NOTE.vel]
    movss  DWORD PTR [r12+VSTATE.gr], xmm0
    movss  xmm0, DWORD PTR [rdi+PATCH.vibHz]
    mulss  xmm0, DWORD PTR kInvSr
    movss  DWORD PTR [r12+VSTATE.vibInc], xmm0
    movss  xmm0, DWORD PTR [rdi+PATCH.vibAmt]
    movss  DWORD PTR [r12+VSTATE.vibAmp], xmm0
    movss  xmm0, DWORD PTR [rdi+PATCH.vibDly]
    mulss  xmm0, DWORD PTR kSr
    cvttss2si eax, xmm0
    mov    DWORD PTR [r12+VSTATE.vibN], eax
    movss  xmm0, DWORD PTR [rdi+PATCH.release]
    mulss  xmm0, DWORD PTR kSr7
    cvttss2si eax, xmm0
    add    eax, DWORD PTR [rsi+NOTE.len]
    mov    ecx, AUDIO_FRAMES
    sub    ecx, DWORD PTR [rsi+NOTE.start]
    jg     po_room
    xor    eax, eax
    jmp    po_store
po_room:
    cmp    eax, ecx
    cmova  eax, ecx
po_store:
    mov    DWORD PTR [r12+VSTATE.total], eax
    FN_RET
FN_END Vn_PrepOut

; ---------------------------------------------------------------------------
; Syn_Note(rcx = NOTE *) - renders the note into its bus (adds to the bus).
; Loop registers: r8d = sample, r9d = held samples, r10d = total, r11 = bus
; pointer, ebx = attack samples, r13d = flags, r14 = sine table, rdi = patch,
; r12 = derived constants.  xmm6..9 = oscillator phases A, B, C, sub;
; xmm10 = amplitude envelope, xmm11 = cut-off envelope, xmm12 / xmm13 =
; filter low / band, xmm14 = vibrato phase.
; ---------------------------------------------------------------------------
FNX_BEGIN Syn_Note, 0
    mov    rsi, rcx
    mov    rdi, QWORD PTR [rsi+NOTE.patch]
    lea    r12, synVs
    call   Vn_PrepOsc
    call   Vn_PrepEnv
    call   Vn_PrepOut
    mov    r10d, DWORD PTR [r12+VSTATE.total]
    test   r10d, r10d
    jz     sn_exit
    mov    rax, QWORD PTR synBusDry
    cmp    DWORD PTR [rdi+PATCH.bus], 0
    je     sn_bus
    mov    rax, QWORD PTR synBusMus
sn_bus:
    mov    ecx, DWORD PTR [rsi+NOTE.start]
    lea    r11, [rax+rcx*8]
    mov    r9d, DWORD PTR [rsi+NOTE.len]
    mov    ebx, DWORD PTR [r12+VSTATE.attN]
    mov    r13d, DWORD PTR [r12+VSTATE.flags]
    lea    r14, gSinTabF
    xorps  xmm6, xmm6
    movss  xmm7, DWORD PTR [rdi+PATCH.phB]
    movss  xmm8, DWORD PTR kPhaseC
    xorps  xmm9, xmm9
    xorps  xmm10, xmm10
    movss  xmm11, DWORD PTR kOneF
    xorps  xmm12, xmm12
    xorps  xmm13, xmm13
    xorps  xmm14, xmm14
    xor    r8d, r8d
sn_loop:
    movss  xmm5, DWORD PTR kOneF           ; frequency factor (vibrato)
    test   r13d, VF_VIB
    jz     sn_novib
    cmp    r8d, DWORD PTR [r12+VSTATE.vibN]
    jb     sn_novib
    SINLK  xmm0, xmm14, xmm1, xmm2
    mulss  xmm0, DWORD PTR [r12+VSTATE.vibAmp]
    addss  xmm5, xmm0
    PHADV  xmm14, DWORD PTR [r12+VSTATE.vibInc], xmm1
sn_novib:
    movss  xmm2, DWORD PTR [r12+VSTATE.dtA]
    mulss  xmm2, xmm5
    movss  xmm3, DWORD PTR [r12+VSTATE.dtB]
    mulss  xmm3, xmm5
    movss  xmm4, DWORD PTR [r12+VSTATE.dtC]
    mulss  xmm4, xmm5
    BLEPSAW xmm0, xmm6, xmm2, xmm15, xmm5
    mulss  xmm0, DWORD PTR [rdi+PATCH.wA]
    PHADV  xmm6, xmm2, xmm15
    test   r13d, VF_B
    jz     sn_noB
    BLEPSAW xmm1, xmm7, xmm3, xmm15, xmm5
    mulss  xmm1, DWORD PTR [rdi+PATCH.wB]
    addss  xmm0, xmm1
    PHADV  xmm7, xmm3, xmm15
sn_noB:
    test   r13d, VF_C
    jz     sn_noC
    BLEPSAW xmm1, xmm8, xmm4, xmm15, xmm5
    mulss  xmm1, DWORD PTR [rdi+PATCH.wC]
    addss  xmm0, xmm1
    PHADV  xmm8, xmm4, xmm15
sn_noC:
    test   r13d, VF_SUB
    jz     sn_noS
    SINLK  xmm1, xmm9, xmm15, xmm5
    mulss  xmm1, DWORD PTR [rdi+PATCH.wSub]
    addss  xmm0, xmm1
    PHADV  xmm9, DWORD PTR [r12+VSTATE.dtS], xmm15
sn_noS:
    movss  xmm1, DWORD PTR [r12+VSTATE.fE]         ; filter coefficient
    mulss  xmm1, xmm11
    addss  xmm1, DWORD PTR [r12+VSTATE.f0]
    minss  xmm1, DWORD PTR kFMax
    movss  xmm4, DWORD PTR [rdi+PATCH.damp]
    SVFSTEP xmm12, xmm13, xmm0, xmm1, xmm4, xmm3, xmm2
    mulss  xmm11, DWORD PTR [r12+VSTATE.fenvMul]
    cmp    r8d, r9d                               ; amplitude envelope
    jae    sn_rel
    cmp    r8d, ebx
    jb     sn_att
    movss  xmm1, DWORD PTR [rdi+PATCH.sustain]
    subss  xmm10, xmm1
    mulss  xmm10, DWORD PTR [r12+VSTATE.decMul]
    addss  xmm10, xmm1
    jmp    sn_env
sn_att:
    addss  xmm10, DWORD PTR [r12+VSTATE.attInc]
    minss  xmm10, DWORD PTR kOneF
    jmp    sn_env
sn_rel:
    mulss  xmm10, DWORD PTR [r12+VSTATE.relMul]
    comiss xmm10, DWORD PTR kSilence
    jb     sn_exit
sn_env:
    movaps xmm0, xmm12
    mulss  xmm0, xmm10
    test   r13d, VF_DRV
    jz     sn_pan
    movaps xmm1, xmm0                             ; soft saturation x / (1 + d |x|)
    andps  xmm1, XMMWORD PTR kAbsMask
    mulss  xmm1, DWORD PTR [rdi+PATCH.drive]
    addss  xmm1, DWORD PTR kOneF
    divss  xmm0, xmm1
sn_pan:
    movaps xmm1, xmm0
    mulss  xmm0, DWORD PTR [r12+VSTATE.gl]
    mulss  xmm1, DWORD PTR [r12+VSTATE.gr]
    BUSADD r11, xmm0, xmm1
    inc    r8d
    cmp    r8d, r10d
    jb     sn_loop
sn_exit:
    FNX_RET
FN_END Syn_Note

END
