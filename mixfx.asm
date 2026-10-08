; ============================================================================
; mixfx.asm - mix-down of the dry and music buses into 16-bit PCM.
; ----------------------------------------------------------------------------
; One pass over the song, step by step:
;   * sidechain: the music bus is ducked after every kick (table of 0.25 s),
;   * ping-pong delay (3/16 and 2/16 note) fed from the music bus,
;   * Freeverb-style reverb (6 damped combs + 2 all-passes per channel),
;   * sum with the dry bus (drums, bass).
; A second pass normalises the loudness (target RMS), applies a soft knee
; limiter, the 1 s fade-in / 2 s fade-out, and converts to int16.
; ============================================================================
INCLUDE common.inc
INCLUDE audio.inc

DUCK_N    EQU 11025                      ; length of the ducking curve in frames
DLY_BUF   EQU 16384                      ; delay lines (power of two)
DLY_MASK  EQU 16383
DLY_L     EQU 15504                      ; 3 sixteenths
DLY_R     EQU 10336                      ; 2 sixteenths
RV_FLOATS EQU 18432                      ; reverb memory (comb + all-pass lines)

RVSLOT STRUCT
    buf     QWORD ?                      ; delay line start
    len     DWORD ?
    pos     DWORD ?
    lp      REAL4 ?                      ; damping filter state
    pad     DWORD 3 DUP (?)
RVSLOT ENDS

.const
ALIGN 16
kSignMask   DWORD 80000000h, 80000000h, 80000000h, 80000000h
kAbsMask    DWORD 7FFFFFFFh, 7FFFFFFFh, 7FFFFFFFh, 7FFFFFFFh
rvLens      DWORD 1116, 1188, 1277, 1356, 1422, 1491       ; combs, left
            DWORD 1139, 1211, 1300, 1379, 1445, 1514       ; combs, right
            DWORD 556, 441, 579, 464                       ; all-passes L, L, R, R
kOneF       REAL4 1.0
kHalfF      REAL4 0.5
kInvDuckN   REAL4 9.0702948e-05          ; 1 / DUCK_N
kDuckDepth  REAL4 0.62
kDlySend    REAL4 0.55
kDlyFb      REAL4 0.42
kDlyWet     REAL4 0.38
kRvIn       REAL4 0.03
kRvDamp     REAL4 0.35
kRvDamp1    REAL4 0.65
kRvFb       REAL4 0.82
kRvWet      REAL4 0.85
kDcR        REAL4 0.9979                 ; DC blocker pole (corner at about 15 Hz)
kTarget     REAL4 0.20                   ; target RMS before the limiter
kMaxGain    REAL4 8.0
kKnee       REAL4 0.7
kKneeW      REAL4 0.3
kKneeInv    REAL4 3.3333333
kTMax       REAL4 3.0
k9          REAL4 9.0
k27         REAL4 27.0
k32767F     REAL4 32767.0
kFadeIn     REAL4 2.2675737e-05          ; 1 / 44100
kFadeOut    REAL4 1.1337868e-05          ; 1 / 88200

.data?
ALIGN 16
mxDuck      REAL4 DUCK_N DUP (?)
mxDlyL      REAL4 DLY_BUF DUP (?)
mxDlyR      REAL4 DLY_BUF DUP (?)
mxRev       REAL4 RV_FLOATS DUP (?)
rvSlots     RVSLOT 16 DUP (<>)
mxSumSq     REAL8 ?
mxDc        REAL4 4 DUP (?)              ; DC blocker state: xL, yL, xR, yR
mxPcm       QWORD ?

.code

; ---------------------------------------------------------------------------
; Mix_Init - ducking curve, cleared delay / reverb memory, reverb slots.
; ---------------------------------------------------------------------------
FN_BEGIN Mix_Init, 0
    lea    rdi, mxDuck
    xor    ebx, ebx
mi_duck:                                  ; g(a) = 1 - depth * (1 - a)^2
    cvtsi2ss xmm0, ebx
    mulss  xmm0, DWORD PTR kInvDuckN
    movss  xmm1, DWORD PTR kOneF
    subss  xmm1, xmm0
    mulss  xmm1, xmm1
    mulss  xmm1, DWORD PTR kDuckDepth
    movss  xmm0, DWORD PTR kOneF
    subss  xmm0, xmm1
    movss  DWORD PTR [rdi+rbx*4], xmm0
    inc    ebx
    cmp    ebx, DUCK_N
    jb     mi_duck
    lea    rdi, mxDlyL
    mov    ecx, DLY_BUF * 2 + RV_FLOATS
    xor    eax, eax
    rep    stosd                          ; mxDlyL, mxDlyR, mxRev are contiguous
    lea    rcx, mxDc
    mov    QWORD PTR [rcx], 0
    mov    QWORD PTR [rcx+8], 0
    lea    rsi, rvLens
    lea    rdi, rvSlots
    lea    rdx, mxRev
    xor    ebx, ebx
mi_slot:
    mov    eax, DWORD PTR [rsi+rbx*4]
    mov    QWORD PTR [rdi+RVSLOT.buf], rdx
    mov    DWORD PTR [rdi+RVSLOT.len], eax
    mov    DWORD PTR [rdi+RVSLOT.pos], 0
    mov    DWORD PTR [rdi+RVSLOT.lp], 0
    lea    rdx, [rdx+rax*4]
    add    rdi, SIZEOF RVSLOT
    inc    ebx
    cmp    ebx, 16
    jb     mi_slot
    FN_RET
FN_END Mix_Init

; One damped comb: slot pointer in `slot`, input in `inp`, result y in xmm2.
; Clobbers rax, rcx, xmm1, xmm2, xmm3.
COMBSTEP MACRO slot:REQ, inp:REQ
    LOCAL lWrap
    mov    rax, QWORD PTR [slot+RVSLOT.buf]
    mov    ecx, DWORD PTR [slot+RVSLOT.pos]
    movss  xmm2, DWORD PTR [rax+rcx*4]
    movaps xmm1, xmm2
    mulss  xmm1, DWORD PTR kRvDamp1
    movss  xmm3, DWORD PTR [slot+RVSLOT.lp]
    mulss  xmm3, DWORD PTR kRvDamp
    addss  xmm3, xmm1
    movss  DWORD PTR [slot+RVSLOT.lp], xmm3
    mulss  xmm3, DWORD PTR kRvFb
    addss  xmm3, inp
    movss  DWORD PTR [rax+rcx*4], xmm3
    inc    ecx
    cmp    ecx, DWORD PTR [slot+RVSLOT.len]
    jb     lWrap
    xor    ecx, ecx
lWrap:
    mov    DWORD PTR [slot+RVSLOT.pos], ecx
ENDM

; One all-pass (feedback 0.5) in place on XMM register x.
; Clobbers rax, rcx, xmm2, xmm3.
ALLPASS MACRO slot:REQ, x:REQ
    LOCAL lWrap
    mov    rax, QWORD PTR [slot+RVSLOT.buf]
    mov    ecx, DWORD PTR [slot+RVSLOT.pos]
    movss  xmm2, DWORD PTR [rax+rcx*4]
    movaps xmm3, xmm2
    mulss  xmm3, DWORD PTR kHalfF
    addss  xmm3, x
    movss  DWORD PTR [rax+rcx*4], xmm3
    subss  xmm2, x
    movaps x, xmm2
    inc    ecx
    cmp    ecx, DWORD PTR [slot+RVSLOT.len]
    jb     lWrap
    xor    ecx, ecx
lWrap:
    mov    DWORD PTR [slot+RVSLOT.pos], ecx
ENDM

; ---------------------------------------------------------------------------
; Rv_Process(xmm0 = mono input) -> xmm0 = left, xmm1 = right.
; Uses only volatile registers (rax, rcx, r8, r9, xmm0..xmm5).
; ---------------------------------------------------------------------------
LEAF_BEGIN Rv_Process
    movaps xmm4, xmm0
    xorps  xmm5, xmm5                     ; left comb sum
    xorps  xmm0, xmm0                     ; right comb sum
    lea    r8, rvSlots
    mov    r9d, 6
rp_l:
    COMBSTEP r8, xmm4
    addss  xmm5, xmm2
    add    r8, SIZEOF RVSLOT
    dec    r9d
    jnz    rp_l
    mov    r9d, 6
rp_r:
    COMBSTEP r8, xmm4
    addss  xmm0, xmm2
    add    r8, SIZEOF RVSLOT
    dec    r9d
    jnz    rp_r
    ALLPASS r8, xmm5
    add    r8, SIZEOF RVSLOT
    ALLPASS r8, xmm5
    add    r8, SIZEOF RVSLOT
    ALLPASS r8, xmm0
    add    r8, SIZEOF RVSLOT
    ALLPASS r8, xmm0
    movaps xmm1, xmm0
    movaps xmm0, xmm5
    ret
LEAF_END Rv_Process

; ---------------------------------------------------------------------------
; Mix_Frame - one frame: duck, delay, reverb, sum.  In: rsi = dry frame (read
; and overwritten), rdi = music frame, r14d = ducking age, ebp = delay write
; index.  Adds the frame energy to mxSumSq (double).
; ---------------------------------------------------------------------------
FNX_BEGIN Mix_Frame, 0
    mov    eax, r14d
    cmp    eax, DUCK_N - 1
    jbe    mf_age
    mov    eax, DUCK_N - 1
mf_age:
    lea    rcx, mxDuck
    movss  xmm7, DWORD PTR [rcx+rax*4]
    movss  xmm8, DWORD PTR [rdi]
    mulss  xmm8, xmm7                     ; music left, ducked
    movss  xmm9, DWORD PTR [rdi+4]
    mulss  xmm9, xmm7
    mov    eax, ebp                       ; delayed taps
    sub    eax, DLY_L
    and    eax, DLY_MASK
    lea    rcx, mxDlyL
    movss  xmm10, DWORD PTR [rcx+rax*4]
    mov    eax, ebp
    sub    eax, DLY_R
    and    eax, DLY_MASK
    lea    rcx, mxDlyR
    movss  xmm11, DWORD PTR [rcx+rax*4]
    movaps xmm0, xmm8                      ; ping-pong write
    mulss  xmm0, DWORD PTR kDlySend
    movaps xmm1, xmm11
    mulss  xmm1, DWORD PTR kDlyFb
    addss  xmm0, xmm1
    lea    rcx, mxDlyL
    movss  DWORD PTR [rcx+rbp*4], xmm0
    movaps xmm0, xmm9
    mulss  xmm0, DWORD PTR kDlySend
    movaps xmm1, xmm10
    mulss  xmm1, DWORD PTR kDlyFb
    addss  xmm0, xmm1
    lea    rcx, mxDlyR
    movss  DWORD PTR [rcx+rbp*4], xmm0
    movaps xmm0, xmm8                      ; reverb input: music + a little delay
    addss  xmm0, xmm9
    movaps xmm1, xmm10
    addss  xmm1, xmm11
    mulss  xmm1, DWORD PTR kHalfF
    addss  xmm0, xmm1
    mulss  xmm0, DWORD PTR kRvIn
    call   Rv_Process
    mulss  xmm0, DWORD PTR kRvWet
    mulss  xmm1, DWORD PTR kRvWet
    mulss  xmm10, DWORD PTR kDlyWet
    mulss  xmm11, DWORD PTR kDlyWet
    addss  xmm0, xmm10
    addss  xmm1, xmm11
    addss  xmm0, xmm8
    addss  xmm1, xmm9
    addss  xmm0, DWORD PTR [rsi]
    addss  xmm1, DWORD PTR [rsi+4]
    lea    rcx, mxDc                       ; DC blocker, y = x - x1 + R * y1
    movaps xmm2, xmm0                      ; (the kick sine starts at phase 0 and
    subss  xmm0, DWORD PTR [rcx]           ; leaves a small positive offset)
    movss  DWORD PTR [rcx], xmm2
    movss  xmm3, DWORD PTR [rcx+4]
    mulss  xmm3, DWORD PTR kDcR
    addss  xmm0, xmm3
    movss  DWORD PTR [rcx+4], xmm0
    movaps xmm2, xmm1
    subss  xmm1, DWORD PTR [rcx+8]
    movss  DWORD PTR [rcx+8], xmm2
    movss  xmm3, DWORD PTR [rcx+12]
    mulss  xmm3, DWORD PTR kDcR
    addss  xmm1, xmm3
    movss  DWORD PTR [rcx+12], xmm1
    movss  DWORD PTR [rsi], xmm0
    movss  DWORD PTR [rsi+4], xmm1
    cvtss2sd xmm2, xmm0                    ; energy goes to memory: the XMM
    mulsd  xmm2, xmm2                      ; registers are restored on return
    cvtss2sd xmm3, xmm1
    mulsd  xmm3, xmm3
    addsd  xmm2, xmm3
    addsd  xmm2, QWORD PTR mxSumSq
    movsd  QWORD PTR mxSumSq, xmm2
    FNX_RET
FN_END Mix_Frame

; ---------------------------------------------------------------------------
; Mix_Frames - walks the steps; rsi = dry bus, rdi = music bus, r12 = kick flags.
; Result: mxSumSq.
; ---------------------------------------------------------------------------
FN_BEGIN Mix_Frames, 0
    mov    r13d, 0                         ; step
    mov    r14d, DUCK_N                    ; frames since the last kick
    xor    ebp, ebp                        ; delay write index
    mov    QWORD PTR mxSumSq, 0
mfs_step:
    lea    eax, [r13+1]
    imul   rax, rax, 661500                ; STEP_NUM
    shr    rax, 7
    mov    r15d, eax                       ; end frame of this step
    cmp    BYTE PTR [r12+r13], 0
    je     mfs_go
    xor    r14d, r14d                      ; kick: restart the ducking curve
mfs_go:
    mov    eax, r13d
    imul   rax, rax, 661500
    shr    rax, 7
    mov    ebx, eax                        ; first frame of this step
mfs_frame:
    call   Mix_Frame
    add    rsi, 8
    add    rdi, 8
    inc    r14d
    inc    ebp
    and    ebp, DLY_MASK
    inc    ebx
    cmp    ebx, r15d
    jb     mfs_frame
    inc    r13d
    cmp    r13d, SONG_STEPS
    jb     mfs_step
    FN_RET
FN_END Mix_Frames

; Soft knee: |x| <= 0.7 passes, above it a tanh-like curve towards 1.0.
; x = XMM value (in / out); a, t, u = scratch XMM registers.
SOFTCLIP MACRO x:REQ, a:REQ, t:REQ, u:REQ
    LOCAL lDone
    movaps a, x
    andps  a, XMMWORD PTR kAbsMask
    comiss a, DWORD PTR kKnee
    jbe    lDone
    subss  a, DWORD PTR kKnee
    mulss  a, DWORD PTR kKneeInv
    minss  a, DWORD PTR kTMax
    movaps t, a
    mulss  t, a
    movaps u, t
    mulss  u, DWORD PTR k9
    addss  u, DWORD PTR k27
    addss  t, DWORD PTR k27
    mulss  t, a
    divss  t, u
    mulss  t, DWORD PTR kKneeW
    addss  t, DWORD PTR kKnee
    movaps a, x
    andps  a, XMMWORD PTR kSignMask
    orps   t, a
    movaps x, t
lDone:
ENDM

; ---------------------------------------------------------------------------
; Mix_Finish - loudness, limiter, fades, int16.  rsi = mixed float frames,
; rdi = pcm out.
; ---------------------------------------------------------------------------
FNX_BEGIN Mix_Finish, 0
    movsd  xmm0, QWORD PTR mxSumSq
    mov    eax, AUDIO_FRAMES * 2           ; samples of both channels
    cvtsi2sd xmm1, eax
    divsd  xmm0, xmm1                      ; mean square
    sqrtsd xmm0, xmm0
    cvtsd2ss xmm0, xmm0
    movss  xmm5, DWORD PTR kMaxGain
    movss  xmm1, DWORD PTR kTarget
    ucomiss xmm0, xmm1
    jbe    fin_g1                          ; very quiet: keep the cap
    divss  xmm1, xmm0
    movaps xmm5, xmm1
    jmp    fin_go
fin_g1:
    divss  xmm1, xmm0
    minss  xmm1, xmm5
    movaps xmm5, xmm1
fin_go:
    xor    ebx, ebx
fin_lp:
    cvtsi2ss xmm2, ebx                     ; fade = min(1, i / 44100, (N - i) / 88200)
    mulss  xmm2, DWORD PTR kFadeIn
    mov    eax, AUDIO_FRAMES
    sub    eax, ebx
    cvtsi2ss xmm3, eax
    mulss  xmm3, DWORD PTR kFadeOut
    minss  xmm2, xmm3
    minss  xmm2, DWORD PTR kOneF
    mulss  xmm2, xmm5                      ; total gain
    movss  xmm0, DWORD PTR [rsi]
    mulss  xmm0, xmm2
    SOFTCLIP xmm0, xmm6, xmm7, xmm8
    mulss  xmm0, DWORD PTR k32767F
    cvtss2si eax, xmm0
    mov    WORD PTR [rdi], ax
    movss  xmm1, DWORD PTR [rsi+4]
    mulss  xmm1, xmm2
    SOFTCLIP xmm1, xmm6, xmm7, xmm8
    mulss  xmm1, DWORD PTR k32767F
    cvtss2si eax, xmm1
    mov    WORD PTR [rdi+2], ax
    add    rsi, 8
    add    rdi, 4
    inc    ebx
    cmp    ebx, AUDIO_FRAMES
    jb     fin_lp
    FNX_RET
FN_END Mix_Finish

; ---------------------------------------------------------------------------
; Mix_Down(rcx = kick flags BYTE[SONG_STEPS], rdx = pcm out)
; Mixes synBusDry / synBusMus into the PCM buffer.
; ---------------------------------------------------------------------------
FN_BEGIN Mix_Down, 0
    mov    r12, rcx
    mov    QWORD PTR mxPcm, rdx
    call   Mix_Init
    mov    rsi, QWORD PTR synBusDry
    mov    rdi, QWORD PTR synBusMus
    call   Mix_Frames
    mov    rsi, QWORD PTR synBusDry
    mov    rdi, QWORD PTR mxPcm
    call   Mix_Finish
    xor    eax, eax
    FN_RET
FN_END Mix_Down

END
