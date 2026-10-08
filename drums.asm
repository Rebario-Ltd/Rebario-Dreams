; ============================================================================
; drums.asm - percussion and noise effects, rendered offline into the buses.
; ----------------------------------------------------------------------------
; Kick  : sine with a falling pitch, click and soft saturation.
; Snare : high-passed noise plus a short tonal body.
; Clap  : three quick band-passed noise bursts and a tail.
; Hat   : twice high-passed noise (closed / open).
; Riser : resonant band-pass sweep with rising level and a short fade at the
;         very end; dry bus, so neither the kick pump nor the echo chops it.
; Crash : long high-passed stereo noise.
; Every procedure adds to its bus, so overlapping events simply sum.
; ============================================================================
INCLUDE common.inc
INCLUDE audio.inc
INCLUDE dsp.inc

KICK_LEN   EQU 22050
KICK_FADE  EQU 20000                     ; the tail is faded out from this sample on
SNARE_LEN  EQU 11025
CLAP_LEN   EQU 9000
CLAP_BURST EQU 400                       ; samples between the claps
CLAP_BODY  EQU 1200
HAT_LEN    EQU 3528
OHAT_LEN   EQU 17640
CRASH_LEN  EQU 88200

.const
ALIGN 16
kKickFe     REAL4 47.0                   ; final pitch (Hz)
kKickDf     REAL4 123.0                  ; pitch excess at the start
kKickPm     REAL4 0.9994034              ; per-sample factors: pitch, body, click, tail fade
kKickAm     REAL4 0.9998028
kKickCm     REAL4 0.9812810
kKickFd     REAL4 0.9990
kKickClick  REAL4 0.35
kKickDrv    REAL4 0.55
kSnareF     REAL4 0.2557543              ; high-pass at 1.8 kHz
kSnareQ     REAL4 1.1
kSnareEn    REAL4 0.9996977              ; noise decay
kSnareTp    REAL4 0.9992444              ; tone pitch decay
kSnareTa    REAL4 0.9995466              ; tone level decay
kSnareFe    REAL4 150.0
kSnareDf    REAL4 55.0
kSnareNg    REAL4 0.9
kSnareTg    REAL4 0.55
kClapF      REAL4 0.2133073              ; band-pass at 1.5 kHz
kClapQ      REAL4 0.7
kClapBm     REAL4 0.9943471              ; burst decay
kClapTm     REAL4 0.9996512              ; tail decay
kClapT0     REAL4 0.7                    ; tail level
kClapGain   REAL4 1.8
kHatA       REAL4 0.55                   ; one-pole high-pass coefficient
kHatMul     REAL4 0.9983816
kOHatMul    REAL4 0.9997333
kHatGain    REAL4 0.9
kCrashMul   REAL4 0.9999403
kCrashA     REAL4 0.40
kCrashGain  REAL4 0.55
kRiseQ      REAL4 0.5
kRiseF0     REAL4 0.03
kRiseLog    REAL4 4.5443205              ; log2(0.70 / 0.03)
kRiseGain   REAL4 1.2
kRiseTail   REAL4 32.0                   ; the level falls to zero over the last 1/32 of the riser

.data
ALIGN 4
drmRng      DWORD 2463534242

.code

; Common start of every drum: r10d = frames (limited to the buffer), r11 = bus pointer.
; In: ecx = start frame, edx = wanted length, rax = bus base.  eax = 0 when nothing to do.
LEAF_BEGIN Drm_Span
    mov    r10d, AUDIO_FRAMES
    sub    r10d, ecx
    jle    ds_none
    cmp    r10d, edx
    cmova  r10d, edx
    lea    r11, [rax+rcx*8]
    mov    eax, 1
    ret
ds_none:
    xor    eax, eax
    ret
LEAF_END Drm_Span

; ---------------------------------------------------------------------------
; Drm_Kick(ecx = start frame, xmm1 = velocity)
; xmm6 = phase, xmm7 = pitch envelope, xmm8 = body, xmm9 = click, xmm10 = vel.
; ---------------------------------------------------------------------------
FNX_BEGIN Drm_Kick, 0
    movaps xmm10, xmm1
    mov    edx, KICK_LEN
    mov    rax, QWORD PTR synBusDry
    call   Drm_Span
    test   eax, eax
    jz     dk_exit
    lea    r14, gSinTabF
    xorps  xmm6, xmm6
    movss  xmm7, DWORD PTR kOneF
    movss  xmm8, DWORD PTR kOneF
    movss  xmm9, DWORD PTR kOneF
    xor    r8d, r8d
dk_loop:
    movss  xmm0, DWORD PTR kKickDf
    mulss  xmm0, xmm7
    addss  xmm0, DWORD PTR kKickFe
    mulss  xmm0, DWORD PTR kInvSr
    PHADV  xmm6, xmm0, xmm1
    SINLK  xmm0, xmm6, xmm1, xmm2
    mulss  xmm0, xmm8
    NOISE  xmm1, drmRng
    mulss  xmm1, xmm9
    mulss  xmm1, DWORD PTR kKickClick
    addss  xmm0, xmm1
    movaps xmm1, xmm0                      ; soft saturation
    andps  xmm1, XMMWORD PTR kAbsMask
    mulss  xmm1, DWORD PTR kKickDrv
    addss  xmm1, DWORD PTR kOneF
    divss  xmm0, xmm1
    mulss  xmm0, xmm10
    movaps xmm1, xmm0
    BUSADD r11, xmm0, xmm1
    mulss  xmm7, DWORD PTR kKickPm
    mulss  xmm8, DWORD PTR kKickAm
    mulss  xmm9, DWORD PTR kKickCm
    cmp    r8d, KICK_FADE
    jb     dk_next
    mulss  xmm8, DWORD PTR kKickFd
dk_next:
    inc    r8d
    cmp    r8d, r10d
    jb     dk_loop
dk_exit:
    FNX_RET
FN_END Drm_Kick

; ---------------------------------------------------------------------------
; Drm_Snare(ecx = start frame, xmm1 = velocity)
; xmm6 / xmm7 = filter state, xmm8 = noise level, xmm9 = tone phase,
; xmm10 = tone pitch envelope, xmm11 = tone level, xmm12 = velocity.
; ---------------------------------------------------------------------------
FNX_BEGIN Drm_Snare, 0
    movaps xmm12, xmm1
    mov    edx, SNARE_LEN
    mov    rax, QWORD PTR synBusDry
    call   Drm_Span
    test   eax, eax
    jz     sd_exit
    lea    r14, gSinTabF
    xorps  xmm6, xmm6
    xorps  xmm7, xmm7
    xorps  xmm9, xmm9
    movss  xmm8, DWORD PTR kOneF
    movss  xmm10, DWORD PTR kOneF
    movss  xmm11, DWORD PTR kOneF
    xor    r8d, r8d
sd_loop:
    NOISE  xmm0, drmRng
    movss  xmm1, DWORD PTR kSnareF
    movss  xmm4, DWORD PTR kSnareQ
    SVFSTEP xmm6, xmm7, xmm0, xmm1, xmm4, xmm3, xmm2
    mulss  xmm3, xmm8
    mulss  xmm3, DWORD PTR kSnareNg
    movss  xmm0, DWORD PTR kSnareDf
    mulss  xmm0, xmm10
    addss  xmm0, DWORD PTR kSnareFe
    mulss  xmm0, DWORD PTR kInvSr
    PHADV  xmm9, xmm0, xmm1
    SINLK  xmm0, xmm9, xmm1, xmm2
    mulss  xmm0, xmm11
    mulss  xmm0, DWORD PTR kSnareTg
    addss  xmm0, xmm3
    mulss  xmm0, xmm12
    movaps xmm1, xmm0
    BUSADD r11, xmm0, xmm1
    mulss  xmm8, DWORD PTR kSnareEn
    mulss  xmm10, DWORD PTR kSnareTp
    mulss  xmm11, DWORD PTR kSnareTa
    inc    r8d
    cmp    r8d, r10d
    jb     sd_loop
sd_exit:
    FNX_RET
FN_END Drm_Snare

; ---------------------------------------------------------------------------
; Drm_Clap(ecx = start frame, xmm1 = velocity)
; xmm6 / xmm7 = filter state, xmm8 = envelope, xmm12 = velocity, r9d = burst timer.
; ---------------------------------------------------------------------------
FNX_BEGIN Drm_Clap, 0
    movaps xmm12, xmm1
    mov    edx, CLAP_LEN
    mov    rax, QWORD PTR synBusDry
    call   Drm_Span
    test   eax, eax
    jz     cp_exit
    xorps  xmm6, xmm6
    xorps  xmm7, xmm7
    xorps  xmm8, xmm8
    xor    r9d, r9d
    xor    r8d, r8d
cp_loop:
    NOISE  xmm0, drmRng
    movss  xmm1, DWORD PTR kClapF
    movss  xmm4, DWORD PTR kClapQ
    SVFSTEP xmm6, xmm7, xmm0, xmm1, xmm4, xmm3, xmm2
    cmp    r8d, CLAP_BODY
    jb     cp_burst
    ja     cp_tail
    movss  xmm8, DWORD PTR kClapT0
    jmp    cp_out
cp_tail:
    mulss  xmm8, DWORD PTR kClapTm
    jmp    cp_out
cp_burst:
    test   r9d, r9d
    jnz    cp_decay
    movss  xmm8, DWORD PTR kOneF
    mov    r9d, CLAP_BURST
cp_decay:
    dec    r9d
    mulss  xmm8, DWORD PTR kClapBm
cp_out:
    movaps xmm0, xmm7
    mulss  xmm0, xmm8
    mulss  xmm0, xmm12
    mulss  xmm0, DWORD PTR kClapGain
    movaps xmm1, xmm0
    BUSADD r11, xmm0, xmm1
    inc    r8d
    cmp    r8d, r10d
    jb     cp_loop
cp_exit:
    FNX_RET
FN_END Drm_Clap

; ---------------------------------------------------------------------------
; Drm_Hat(ecx = start frame, edx = 1 for open, xmm2 = velocity)
; xmm6 / xmm7 = one-pole low-pass states, xmm8 = level, xmm9 = decay factor.
; ---------------------------------------------------------------------------
FNX_BEGIN Drm_Hat, 0
    movaps xmm12, xmm2
    movss  xmm9, DWORD PTR kHatMul
    mov    r9d, HAT_LEN
    test   edx, edx
    jz     ht_set
    movss  xmm9, DWORD PTR kOHatMul
    mov    r9d, OHAT_LEN
ht_set:
    mov    edx, r9d
    mov    rax, QWORD PTR synBusDry
    call   Drm_Span
    test   eax, eax
    jz     ht_exit
    xorps  xmm6, xmm6
    xorps  xmm7, xmm7
    movss  xmm8, DWORD PTR kOneF
    xor    r8d, r8d
ht_loop:
    NOISE  xmm0, drmRng
    movaps xmm1, xmm0                      ; first high-pass: x - lp
    subss  xmm1, xmm6
    mulss  xmm1, DWORD PTR kHatA
    addss  xmm6, xmm1
    subss  xmm0, xmm6
    movaps xmm1, xmm0                      ; second high-pass
    subss  xmm1, xmm7
    mulss  xmm1, DWORD PTR kHatA
    addss  xmm7, xmm1
    subss  xmm0, xmm7
    mulss  xmm0, xmm8
    mulss  xmm0, xmm12
    mulss  xmm0, DWORD PTR kHatGain
    movaps xmm1, xmm0
    BUSADD r11, xmm0, xmm1
    mulss  xmm8, xmm9
    inc    r8d
    cmp    r8d, r10d
    jb     ht_loop
ht_exit:
    FNX_RET
FN_END Drm_Hat

; ---------------------------------------------------------------------------
; Drm_Riser(ecx = start frame, edx = frames, xmm2 = velocity)
; Dry bus (a pumping, echoing riser stutters over the next section instead of
; sweeping smoothly into it).  xmm6/7 and xmm8/9 = band-pass states (L / R),
; xmm10 = filter coefficient, xmm11 = progress 0..1, xmm12 = progress step,
; xmm13 = velocity, xmm14 = coefficient growth per sample.
; ---------------------------------------------------------------------------
FNX_BEGIN Drm_Riser, 16
    movaps xmm13, xmm2
    mov    rax, QWORD PTR synBusDry
    call   Drm_Span
    test   eax, eax
    jz     rs_exit
    cvtsi2ss xmm0, r10d
    movss  xmm1, DWORD PTR kOneF
    divss  xmm1, xmm0
    movaps xmm12, xmm1                     ; 1 / frames
    movss  xmm0, DWORD PTR kRiseLog
    mulss  xmm0, xmm12
    call   Mth_Exp2f
    movaps xmm14, xmm0
    movss  xmm10, DWORD PTR kRiseF0
    xorps  xmm6, xmm6
    xorps  xmm7, xmm7
    xorps  xmm8, xmm8
    xorps  xmm9, xmm9
    xorps  xmm11, xmm11
    movss  xmm4, DWORD PTR kRiseQ
    xor    r8d, r8d
rs_loop:
    NOISE  xmm0, drmRng
    SVFSTEP xmm6, xmm7, xmm0, xmm10, xmm4, xmm3, xmm2
    NOISE  xmm0, drmRng
    SVFSTEP xmm8, xmm9, xmm0, xmm10, xmm4, xmm3, xmm2
    movaps xmm5, xmm11                     ; level = progress^2 * velocity
    mulss  xmm5, xmm11
    mulss  xmm5, xmm13
    mulss  xmm5, DWORD PTR kRiseGain
    movss  xmm2, DWORD PTR kOneF           ; fade out over the last 1/32: min(1, (1 - progress) * 32)
    subss  xmm2, xmm11
    mulss  xmm2, DWORD PTR kRiseTail
    minss  xmm2, DWORD PTR kOneF
    mulss  xmm5, xmm2
    movaps xmm0, xmm7
    mulss  xmm0, xmm5
    movaps xmm1, xmm9
    mulss  xmm1, xmm5
    BUSADD r11, xmm0, xmm1
    mulss  xmm10, xmm14
    addss  xmm11, xmm12
    inc    r8d
    cmp    r8d, r10d
    jb     rs_loop
rs_exit:
    FNX_RET
FN_END Drm_Riser

; ---------------------------------------------------------------------------
; Drm_Crash(ecx = start frame, xmm1 = velocity)
; xmm6/7 = left high-pass states, xmm8/9 = right, xmm10 = level, xmm12 = velocity.
; ---------------------------------------------------------------------------
FNX_BEGIN Drm_Crash, 0
    movaps xmm12, xmm1
    mov    edx, CRASH_LEN
    mov    rax, QWORD PTR synBusDry
    call   Drm_Span
    test   eax, eax
    jz     cr_exit
    xorps  xmm6, xmm6
    xorps  xmm7, xmm7
    xorps  xmm8, xmm8
    xorps  xmm9, xmm9
    movss  xmm10, DWORD PTR kOneF
    xor    r8d, r8d
cr_loop:
    NOISE  xmm0, drmRng
    movaps xmm2, xmm0
    subss  xmm2, xmm6                      ; left: two cascaded high-passes
    mulss  xmm2, DWORD PTR kCrashA
    addss  xmm6, xmm2
    subss  xmm0, xmm6
    movaps xmm2, xmm0
    subss  xmm2, xmm7
    mulss  xmm2, DWORD PTR kCrashA
    addss  xmm7, xmm2
    subss  xmm0, xmm7
    NOISE  xmm1, drmRng
    movaps xmm2, xmm1
    subss  xmm2, xmm8                      ; right
    mulss  xmm2, DWORD PTR kCrashA
    addss  xmm8, xmm2
    subss  xmm1, xmm8
    movaps xmm2, xmm1
    subss  xmm2, xmm9
    mulss  xmm2, DWORD PTR kCrashA
    addss  xmm9, xmm2
    subss  xmm1, xmm9
    movaps xmm3, xmm10
    mulss  xmm3, xmm12
    mulss  xmm3, DWORD PTR kCrashGain
    mulss  xmm0, xmm3
    mulss  xmm1, xmm3
    BUSADD r11, xmm0, xmm1
    mulss  xmm10, DWORD PTR kCrashMul
    inc    r8d
    cmp    r8d, r10d
    jb     cr_loop
cr_exit:
    FNX_RET
FN_END Drm_Crash

END
