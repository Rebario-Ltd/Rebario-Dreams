; ============================================================================
; song.asm - the arrangement and the sequencer of the soundtrack.
; ----------------------------------------------------------------------------
; 128 BPM, A minor, 72 bars = 9 scenes x 8 bars (exactly 135 s).  A bar table
; says which layers play (kick, clap, hats, three bass patterns, arpeggio,
; pad, lead, riser, crash, snare roll), which chord is active and which lead
; phrase is used; the sequencer walks the 1152 sixteenth-note steps and
; renders every event offline into the dry / music buses (synth.asm,
; drums.asm); mixfx.asm then mixes them down into the 16-bit PCM buffer.
; Chords: 0 Am, 1 F, 2 C, 3 G, 4 E (turn-around).
;
; Scene changes are smoothed so that the rhythm over the background does not
; break: a silent "ghost" kick keeps the sidechain pumping in the bars where
; the kick rests (L_GHOST), melodic layers die away / grow in over the last /
; first steps of the bars where they stop / start (Sq_FadeAt), every scene
; ends in a riser on the dry bus, and the snare roll of a build-up speeds up
; in three stages (Sq_RollHits).  selftest_song.asm and analyze-wav.py check
; all of it.
; ============================================================================
INCLUDE common.inc
INCLUDE win.inc
INCLUDE audio.inc

; ---- groove blocks ----------------------------------------------------------------
G_FULL1  EQU L_KICK or L_CLAP or L_HAT or L_OPEN or L_BASS1 or L_ARP or L_PAD
G_FULL2  EQU L_KICK or L_CLAP or L_HAT16 or L_OPEN or L_BASS2 or L_ARP or L_ARP2 or L_PAD or L_LEAD
G_FULL4  EQU L_KICK or L_CLAP or L_HAT or L_OPEN or L_BASS3 or L_ARP or L_PAD
G_FULL5  EQU G_FULL2 or L_LEAD2
G_FULL6  EQU L_KICK or L_CLAP or L_SNARE or L_HAT16 or L_OPEN or L_BASS3 or L_PAD or L_LEAD
G_FULL7  EQU L_KICK or L_CLAP or L_SNARE or L_HAT or L_OPEN or L_BASS2 or L_ARP or L_ARP2 or L_PAD
G_TAIL   EQU L_ARP or L_PAD or L_GHOST   ; the arpeggio keeps pumping where the kick rests

BAR MACRO lay:REQ, chord:REQ, phr:REQ
    DWORD lay
    BYTE chord, phr
    WORD 0
ENDM

; ---- timing ------------------------------------------------------------------------
PAD_LEN     EQU 85000                    ; pad notes overlap the next bar a little
ARP_LEN     EQU 4134
LEAD_STEP   EQU 4800
FADE_OUT    EQU 8                        ; steps of diminuendo before a layer drops out
FADE_IN     EQU 4                        ; steps of crescendo after a layer enters
ROLL_16TH   EQU 6                        ; the snare roll doubles its speed here ...
ROLL_32ND   EQU 12                       ; ... and once more here

.const
ALIGN 16
; bar -> layers, chord, phrase, pad
barTab LABEL BYTE
; scene 0: title - pad swell, arpeggio, soft kick, build-up
    BAR L_PAD, 0, 0
    BAR L_PAD, 1, 0
    BAR G_TAIL, 2, 0
    BAR G_TAIL, 3, 0
    BAR G_TAIL or L_KICK or L_SOFT, 0, 1
    BAR G_TAIL or L_KICK or L_SOFT or L_HAT, 1, 1
    BAR G_TAIL or L_KICK or L_SOFT or L_HAT or L_BASS1, 2, 1
    BAR G_TAIL or L_KICK or L_SOFT or L_HAT or L_BASS1 or L_RISER, 4, 1
; scene 1: plasma - first full groove, lead joins halfway
    BAR G_FULL1 or L_CRASH, 0, 0
    BAR G_FULL1, 1, 0
    BAR G_FULL1, 2, 0
    BAR G_FULL1, 3, 0
    BAR G_FULL1 or L_LEAD, 0, 1
    BAR G_FULL1 or L_LEAD, 1, 1
    BAR G_FULL1 or L_LEAD, 2, 1
    BAR G_FULL1 or L_LEAD or L_HAT16 or L_RISER, 4, 1
; scene 2: tunnel - driving sixteenths
    BAR G_FULL2 or L_CRASH, 0, 0
    BAR G_FULL2, 1, 0
    BAR G_FULL2, 2, 0
    BAR G_FULL2, 3, 0
    BAR G_FULL2, 0, 1
    BAR G_FULL2, 1, 1
    BAR G_FULL2, 2, 1
    BAR G_FULL2 or L_RISER, 4, 1
; scene 3: warp - breakdown that builds
    BAR G_TAIL, 0, 0
    BAR G_TAIL, 1, 0
    BAR G_TAIL or L_HAT, 2, 0
    BAR G_TAIL or L_HAT or L_RISER, 3, 0
    BAR G_TAIL or L_KICK or L_HAT or L_BASS1 or L_CRASH, 0, 1
    BAR G_TAIL or L_KICK or L_CLAP or L_HAT or L_BASS1, 1, 1
    BAR G_TAIL or L_KICK or L_CLAP or L_HAT16 or L_BASS2 or L_LEAD, 2, 1
    BAR G_TAIL or L_KICK or L_CLAP or L_HAT16 or L_BASS2 or L_LEAD or L_ROLL or L_RISER, 4, 1
; scene 4: mercury - bouncy
    BAR G_FULL4 or L_CRASH, 0, 0
    BAR G_FULL4, 1, 0
    BAR G_FULL4, 2, 0
    BAR G_FULL4, 3, 0
    BAR G_FULL4 or L_ARP2 or L_HAT16 or L_LEAD, 0, 1
    BAR G_FULL4 or L_ARP2 or L_HAT16 or L_LEAD, 1, 1
    BAR G_FULL4 or L_ARP2 or L_HAT16 or L_LEAD, 2, 1
    BAR G_FULL4 or L_ARP2 or L_HAT16 or L_LEAD or L_RISER, 4, 1
; scene 5: mandala - everything
    BAR G_FULL5 or L_CRASH, 0, 0
    BAR G_FULL5, 1, 0
    BAR G_FULL5, 2, 0
    BAR G_FULL5, 3, 0
    BAR G_FULL5, 0, 1
    BAR G_FULL5, 1, 1
    BAR G_FULL5, 2, 1
    BAR G_FULL5 or L_ROLL or L_RISER, 4, 1
; scene 6: inferno - heavy bass, snare on the clap, arpeggio returns for the second half
    BAR G_FULL6 or L_CRASH, 0, 0
    BAR G_FULL6, 1, 0
    BAR G_FULL6, 2, 0
    BAR G_FULL6, 3, 0
    BAR G_FULL6 or L_ARP, 0, 1
    BAR G_FULL6 or L_ARP, 1, 1
    BAR G_FULL6 or L_ARP or L_LEAD2, 2, 1
    BAR G_FULL6 or L_ARP or L_LEAD2 or L_ROLL or L_RISER, 4, 1
; scene 7: prism - the glittering climax: rolling bass, arpeggio with echo, snare;
; the lead (phrases 3 and 4) joins as the ring appears and doubles when the glass
; and the cubes arrive; the finale is a riser into a snare roll
    BAR G_FULL7 or L_CRASH, 0, 3
    BAR G_FULL7, 1, 3
    BAR G_FULL7 or L_LEAD, 2, 3
    BAR G_FULL7 or L_LEAD, 3, 3
    BAR G_FULL7 or L_LEAD or L_LEAD2 or L_CRASH, 0, 4
    BAR G_FULL7 or L_LEAD or L_LEAD2, 1, 4
    BAR G_FULL7 or L_LEAD or L_LEAD2 or L_RISER, 2, 4
    BAR G_FULL7 or L_LEAD or L_LEAD2 or L_ROLL or L_RISER, 4, 4
; scene 8: terra - the groove thins out, the pad and lead ring out
    BAR G_FULL1 or L_LEAD or L_CRASH, 0, 0
    BAR G_FULL1 or L_LEAD, 1, 0
    BAR L_KICK or L_HAT or L_BASS1 or L_ARP or L_PAD or L_LEAD, 2, 0
    BAR L_KICK or L_HAT or L_ARP or L_PAD or L_LEAD, 3, 0
    BAR L_ARP or L_PAD or L_LEAD or L_GHOST, 0, 1
    BAR L_ARP or L_PAD or L_LEAD or L_GHOST, 1, 1
    BAR L_PAD or L_LEAD, 0, 2
    BAR L_PAD or L_LEAD, 0, 2

; chord -> three pad / arpeggio notes and the bass root (MIDI)
chordTab BYTE 57, 60, 64, 33             ; Am
         BYTE 57, 60, 65, 29             ; F
         BYTE 55, 60, 64, 36             ; C
         BYTE 55, 59, 62, 31             ; G
         BYTE 56, 59, 64, 28             ; E

; arpeggio patterns: index into { n0, n1, n2, n0+12, n1+12, n2+12 }
arpPat   BYTE 0, 1, 2, 3,  2, 1, 2, 4,  0, 1, 2, 3,  5, 4, 3, 2
         BYTE 0, 2, 1, 3,  2, 4, 3, 5,  4, 3, 2, 4,  1, 3, 0, 2

; bass patterns: 0 = rest, else semitone offset + 1 (1 root, 8 fifth, 13 octave)
bassPat1 BYTE 0, 0, 1, 0,  0, 0, 1, 0,  0, 0, 1, 0,  0, 0, 1, 0
bassPat2 BYTE 0, 1, 1, 1,  0, 1, 1, 13, 0, 1, 1, 1,  0, 1, 1, 13
bassPat3 BYTE 1, 0, 0, 1,  0, 0, 1, 0,  1, 0, 0, 8,  0, 0, 13, 0

; sixteenth hat velocities (percent)
hatVel   BYTE 40, 24, 66, 26,  40, 24, 66, 26,  40, 24, 66, 26,  40, 24, 66, 34

; lead phrases (MIDI note per sixteenth, 0 = continue the previous note); four bars each
leadTab  LABEL BYTE
         BYTE 76, 0, 0, 0,  74, 0, 72, 0,  69, 0, 0, 0,  72, 0, 0, 0    ; phrase 0 (and 1): Am
         BYTE 72, 0, 0, 0,  69, 0, 72, 0,  77, 0, 0, 0,  76, 0, 72, 0    ;                    F
         BYTE 76, 0, 0, 0,  79, 0, 76, 0,  74, 0, 0, 0,  72, 0, 0, 0    ;                    C
         BYTE 71, 0, 0, 0,  74, 0, 0, 0,  79, 0, 0, 0,  74, 0, 71, 0    ;                    G
         BYTE 76, 0, 0, 0,  74, 0, 72, 0,  69, 0, 0, 0,  72, 0, 0, 0    ; phrase 1: same, then E7
         BYTE 72, 0, 0, 0,  69, 0, 72, 0,  77, 0, 0, 0,  76, 0, 72, 0
         BYTE 76, 0, 0, 0,  79, 0, 76, 0,  74, 0, 0, 0,  72, 0, 0, 0
         BYTE 68, 0, 0, 0,  71, 0, 0, 0,  76, 0, 0, 0,  74, 0, 71, 0
         BYTE 32 DUP (0)                                                 ; phrase 2: two empty bars,
         BYTE 76, 15 DUP (0)                                             ; E5 held for the third bar,
         BYTE 69, 15 DUP (0)                                             ; A4 for the last one
         BYTE 81, 0, 0, 76,  0, 0, 79, 0,  76, 0, 72, 0,  76, 0, 0, 0    ; phrase 3 (PRISM, bars 1 - 4): Am
         BYTE 77, 0, 0, 72,  0, 0, 76, 0,  72, 0, 69, 0,  72, 0, 0, 0    ;                    F
         BYTE 79, 0, 0, 76,  0, 0, 84, 0,  79, 0, 76, 0,  79, 0, 0, 0    ;                    C
         BYTE 83, 0, 0, 79,  0, 0, 74, 0,  79, 0, 83, 0,  86, 0, 0, 0    ;                    G, climbing
         BYTE 81, 0, 0, 76,  0, 0, 79, 0,  76, 0, 72, 0,  76, 0, 0, 0    ; phrase 4 (PRISM, bars 5 - 8): Am again
         BYTE 77, 0, 0, 72,  0, 0, 76, 0,  72, 0, 69, 0,  72, 0, 0, 0    ;                    F
         BYTE 84, 0, 79, 0,  76, 0, 79, 0,  84, 0, 79, 0,  76, 0, 79, 0  ;                    C: running eighths
         BYTE 83, 0, 80, 0,  76, 0, 80, 0,  83, 0, 80, 0,  88, 0, 0, 0   ;                    E: the finale

padPan   REAL4 -0.55, 0.0, 0.55
kInv12   REAL4 0.083333336
k440     REAL4 440.0
k001     REAL4 0.01
kVelKick REAL4 0.95
kVelSoft REAL4 0.5
kVelClap REAL4 0.9
kVelSnr  REAL4 0.7
kVelHat  REAL4 0.6
kVelOpen REAL4 0.5
kVelPad  REAL4 0.2
kVelB1   REAL4 0.9
kVelB3   REAL4 1.0
kVelA0   REAL4 0.62
kVelA1   REAL4 0.8
kVelA2   REAL4 0.95
kVelEcho REAL4 0.38
kVelLead REAL4 0.85
kVelLd2  REAL4 0.32
kVelCrash REAL4 0.8
kVelRiser REAL4 0.55
kRollBase REAL4 0.25                     ; the roll grows from 0.25 to 0.55 (0.56 for the second hit of a step),
kRollRamp REAL4 0.02                     ; below the snare of the groove (0.7): the build-up does not end
kRollHalf REAL4 0.01                     ; louder than the downbeat that follows it
kPanL    REAL4 -0.3
kPanR    REAL4 0.3
kZeroF   REAL4 0.0
kOneF    REAL4 1.0
kFadeOutInv REAL4 0.11111111             ; 1 / (FADE_OUT + 1)
kFadeInInv  REAL4 0.2                    ; 1 / (FADE_IN + 1)
.ERRNZ FADE_OUT - 8
.ERRNZ FADE_IN - 4

.data?
ALIGN 16
sqKick   BYTE SONG_STEPS DUP (?)         ; 1 where a kick plays (sidechain trigger)
sqNote   NOTE <>
sqChord  QWORD ?                         ; current chord row
sqLayers DWORD ?
sqBar    DWORD ?
sqStep   DWORD ?
sqFrame  DWORD ?
sqPhrase DWORD ?
sqPcmRaw QWORD ?                         ; allocation holding the WAV header room and the PCM

.code

; Sq_Hz(ecx = MIDI note) -> xmm0 = frequency.
FN_BEGIN Sq_Hz, 0
    sub    ecx, 69
    cvtsi2ss xmm0, ecx
    mulss  xmm0, DWORD PTR kInv12
    call   Mth_Exp2f
    mulss  xmm0, DWORD PTR k440
    FN_RET
FN_END Sq_Hz

; ---------------------------------------------------------------------------
; Sq_Play(rcx = PATCH *, edx = MIDI note, r8d = held frames, xmm3 = velocity,
;         xmm4 = pan) - renders a note at the start of the current step.
; ---------------------------------------------------------------------------
FN_BEGIN Sq_Play, 0
    mov    r12, rcx
    mov    r13d, r8d
    mov    ecx, edx
    call   Sq_Hz
    lea    rax, sqNote
    mov    QWORD PTR [rax+NOTE.patch], r12
    mov    ecx, DWORD PTR sqFrame
    mov    DWORD PTR [rax+NOTE.start], ecx
    mov    DWORD PTR [rax+NOTE.len], r13d
    movss  DWORD PTR [rax+NOTE.freq], xmm0
    movss  DWORD PTR [rax+NOTE.vel], xmm3
    movss  DWORD PTR [rax+NOTE.pan], xmm4
    mov    rcx, rax
    call   Syn_Note
    FN_RET
FN_END Sq_Play

; Sq_Pad: three chord notes at the first step of a bar.
FN_BEGIN Sq_Pad, 0
    cmp    DWORD PTR sqStep, 0
    jne    pd_exit
    test   DWORD PTR sqLayers, L_PAD
    jz     pd_exit
    mov    rsi, QWORD PTR sqChord
    xor    ebx, ebx
pd_lp:
    lea    rcx, Pat_Pad
    movzx  edx, BYTE PTR [rsi+rbx]
    mov    r8d, PAD_LEN
    movss  xmm3, DWORD PTR kVelPad
    lea    rax, padPan
    movss  xmm4, DWORD PTR [rax+rbx*4]
    call   Sq_Play
    inc    ebx
    cmp    ebx, 3
    jb     pd_lp
pd_exit:
    FN_RET
FN_END Sq_Pad

; ---------------------------------------------------------------------------
; Sq_Kick: kick on the beats; flags the step for the sidechain.  A bar with
; L_GHOST and no kick only sets the flag: the music bus keeps pumping with the
; beat, so the arpeggio does not change its accents when the kick drops out
; of the arrangement or comes back.
; ---------------------------------------------------------------------------
FN_BEGIN Sq_Kick, 0
    test   DWORD PTR sqStep, 3
    jnz    kk_exit
    test   DWORD PTR sqLayers, L_KICK
    jnz    kk_play
    test   DWORD PTR sqLayers, L_GHOST
    jz     kk_exit
    jmp    kk_flag
kk_play:
    movss  xmm1, DWORD PTR kVelKick
    test   DWORD PTR sqLayers, L_SOFT
    jz     kk_go
    movss  xmm1, DWORD PTR kVelSoft
kk_go:
    mov    ecx, DWORD PTR sqFrame
    call   Drm_Kick
kk_flag:
    mov    eax, DWORD PTR sqBar
    shl    eax, 4
    add    eax, DWORD PTR sqStep
    lea    rdx, sqKick
    mov    BYTE PTR [rdx+rax], 1
kk_exit:
    FN_RET
FN_END Sq_Kick

; ---------------------------------------------------------------------------
; Sq_Hats: open hats, sixteenth hats or off-beat eighths (one hit per step).
; ---------------------------------------------------------------------------
FN_BEGIN Sq_Hats, 0
    mov    esi, DWORD PTR sqLayers
    mov    ebx, DWORD PTR sqStep
    xor    edx, edx
    test   esi, L_OPEN
    jz     ht_16
    cmp    ebx, 6
    je     ht_open
    cmp    ebx, 14
    jne    ht_16
ht_open:
    mov    edx, 1
    movss  xmm2, DWORD PTR kVelOpen
    jmp    ht_go
ht_16:
    test   esi, L_HAT16
    jz     ht_8
    lea    rax, hatVel
    movzx  eax, BYTE PTR [rax+rbx]
    cvtsi2ss xmm2, eax
    mulss  xmm2, DWORD PTR k001
    jmp    ht_go
ht_8:
    test   esi, L_HAT
    jz     ht_exit
    mov    eax, ebx
    and    eax, 3
    cmp    eax, 2
    jne    ht_exit
    movss  xmm2, DWORD PTR kVelHat
ht_go:
    mov    ecx, DWORD PTR sqFrame
    call   Drm_Hat
ht_exit:
    FN_RET
FN_END Sq_Hats

; ---------------------------------------------------------------------------
; Sq_RollHits(ecx = step) -> eax = snare hits of the roll in that step: eighths
; (steps 0, 2, 4), sixteenths (6 .. 11), thirty-seconds (12 .. 15), so the roll
; speeds up in three even stages instead of one jump.  Clobbers nothing else.
; ---------------------------------------------------------------------------
LEAF_BEGIN Sq_RollHits
    mov    eax, 2
    cmp    ecx, ROLL_32ND
    jae    rh_out
    mov    eax, 1
    cmp    ecx, ROLL_16TH
    jae    rh_out
    mov    eax, ecx
    and    eax, 1
    xor    eax, 1                          ; eighths: the even steps only
rh_out:
    ret
LEAF_END Sq_RollHits

; ---------------------------------------------------------------------------
; Sq_Snares: clap (and snare) on the backbeat, snare roll build-ups.
; ---------------------------------------------------------------------------
FN_BEGIN Sq_Snares, 0
    mov    esi, DWORD PTR sqLayers
    mov    ebx, DWORD PTR sqStep
    test   esi, L_CLAP
    jz     sn_roll
    cmp    ebx, 4
    je     sn_clap
    cmp    ebx, 12
    jne    sn_roll
sn_clap:
    movss  xmm1, DWORD PTR kVelClap
    mov    ecx, DWORD PTR sqFrame
    call   Drm_Clap
    test   esi, L_SNARE
    jz     sn_roll
    movss  xmm1, DWORD PTR kVelSnr
    mov    ecx, DWORD PTR sqFrame
    call   Drm_Snare
sn_roll:
    test   esi, L_ROLL
    jz     sn_exit
    mov    ecx, ebx
    call   Sq_RollHits
    mov    edi, eax                        ; hits in this step (0 .. 2)
    test   edi, edi
    jz     sn_exit
    cvtsi2ss xmm1, ebx
    mulss  xmm1, DWORD PTR kRollRamp
    addss  xmm1, DWORD PTR kRollBase
    mov    ecx, DWORD PTR sqFrame
    call   Drm_Snare
    cmp    edi, 2
    jb     sn_exit
    cvtsi2ss xmm1, ebx                     ; the second hit sits on the half step, a little louder
    mulss  xmm1, DWORD PTR kRollRamp
    addss  xmm1, DWORD PTR kRollBase
    addss  xmm1, DWORD PTR kRollHalf
    mov    ecx, DWORD PTR sqFrame
    add    ecx, STEP_FR / 2
    call   Drm_Snare
sn_exit:
    FN_RET
FN_END Sq_Snares

; ---------------------------------------------------------------------------
; Sq_Bass: one of three patterns on the chord root.
; ---------------------------------------------------------------------------
FN_BEGIN Sq_Bass, 0
    mov    esi, DWORD PTR sqLayers
    lea    rdi, bassPat1
    lea    r12, Pat_Bass
    movss  xmm3, DWORD PTR kVelB1
    mov    r13d, STEP_FR * 8 / 5
    test   esi, L_BASS1
    jnz    bs_pick
    lea    rdi, bassPat2
    mov    r13d, STEP_FR * 9 / 10
    test   esi, L_BASS2
    jnz    bs_pick
    test   esi, L_BASS3
    jz     bs_exit
    lea    rdi, bassPat3
    lea    r12, Pat_BassHeavy
    movss  xmm3, DWORD PTR kVelB3
    mov    r13d, STEP_FR * 2
bs_pick:
    mov    ebx, DWORD PTR sqStep
    movzx  eax, BYTE PTR [rdi+rbx]
    test   eax, eax
    jz     bs_exit
    dec    eax
    mov    rdx, QWORD PTR sqChord
    movzx  edx, BYTE PTR [rdx+3]
    add    edx, eax
    mov    rcx, r12
    mov    r8d, r13d
    movss  xmm4, DWORD PTR kZeroF
    call   Sq_Play
bs_exit:
    FN_RET
FN_END Sq_Bass

; ---------------------------------------------------------------------------
; Sq_FadeAt(ecx = bar, edx = step, r8d = layer bit) -> xmm0 = gain 0..1.
; A layer that the next bar no longer has dies away over the last FADE_OUT
; steps of its final bar, one that the previous bar did not have grows in
; over the first FADE_IN steps of its first bar, so a melodic layer never
; stops or starts dead on a downbeat.  The first bar has no predecessor and
; the last one no successor.  Clobbers eax, r9d, xmm1.
; ---------------------------------------------------------------------------
LEAF_BEGIN Sq_FadeAt
    movss  xmm0, DWORD PTR kOneF
    lea    r9, barTab
    cmp    edx, 16 - FADE_OUT
    jb     fd_in
    lea    eax, [rcx+1]
    cmp    eax, SONG_BARS
    jae    fd_in
    test   DWORD PTR [r9+rax*8], r8d
    jnz    fd_in                           ; the layer goes on
    mov    eax, 16
    sub    eax, edx
    cvtsi2ss xmm0, eax
    mulss  xmm0, DWORD PTR kFadeOutInv     ; (16 - step) / (FADE_OUT + 1)
fd_in:
    cmp    edx, FADE_IN
    jae    fd_exit
    test   ecx, ecx
    jz     fd_exit
    lea    eax, [rcx-1]
    test   DWORD PTR [r9+rax*8], r8d
    jnz    fd_exit                         ; the layer was already playing
    lea    eax, [rdx+1]
    cvtsi2ss xmm1, eax
    mulss  xmm1, DWORD PTR kFadeInInv      ; (step + 1) / (FADE_IN + 1)
    minss  xmm0, xmm1
fd_exit:
    ret
LEAF_END Sq_FadeAt

; v *= the fade gain of `layer` at the current step (clobbers eax, ecx, edx, r8d, r9d, xmm0, xmm1).
LAYERGAIN MACRO layer:REQ, v:REQ
    mov    ecx, DWORD PTR sqBar
    mov    edx, DWORD PTR sqStep
    mov    r8d, layer
    call   Sq_FadeAt
    mulss  v, xmm0
ENDM

; ---------------------------------------------------------------------------
; Sq_Arp: sixteenth-note arpeggio (two alternating patterns), optional echo.
; ---------------------------------------------------------------------------
FN_BEGIN Sq_Arp, 0
    mov    esi, DWORD PTR sqLayers
    test   esi, L_ARP
    jz     ar_exit
    mov    ebx, DWORD PTR sqStep
    lea    rdi, arpPat
    test   DWORD PTR sqBar, 1
    jz     ar_pat
    add    rdi, 16
ar_pat:
    movzx  eax, BYTE PTR [rdi+rbx]
    xor    r13d, r13d
    cmp    eax, 3
    jb     ar_note
    sub    eax, 3
    mov    r13d, 12
ar_note:
    mov    rdx, QWORD PTR sqChord
    movzx  r12d, BYTE PTR [rdx+rax]
    add    r12d, r13d
    movss  xmm3, DWORD PTR kVelA0
    test   ebx, 1
    jnz    ar_pan
    movss  xmm3, DWORD PTR kVelA1
    test   ebx, 3
    jnz    ar_pan
    movss  xmm3, DWORD PTR kVelA2
ar_pan:
    movss  xmm4, DWORD PTR kPanL
    test   ebx, 1
    jz     ar_play
    movss  xmm4, DWORD PTR kPanR
ar_play:
    LAYERGAIN L_ARP, xmm3
    lea    rcx, Pat_Arp
    mov    edx, r12d
    mov    r8d, ARP_LEN
    call   Sq_Play
    test   esi, L_ARP2
    jz     ar_exit
    test   ebx, 1
    jz     ar_exit
    movss  xmm3, DWORD PTR kVelEcho
    LAYERGAIN L_ARP2, xmm3
    movss  xmm4, DWORD PTR kPanL
    lea    rcx, Pat_Arp
    lea    edx, [r12+12]
    mov    r8d, ARP_LEN * 3 / 4
    call   Sq_Play
ar_exit:
    FN_RET
FN_END Sq_Arp

; ---------------------------------------------------------------------------
; Sq_Lead: the phrase table lists note starts; a note lasts until the next one.
; ---------------------------------------------------------------------------
FN_BEGIN Sq_Lead, 0
    mov    esi, DWORD PTR sqLayers
    test   esi, L_LEAD
    jz     ld_exit
    mov    eax, DWORD PTR sqBar
    and    eax, 3
    shl    eax, 4
    add    eax, DWORD PTR sqStep
    mov    ebx, eax                        ; position in the 4-bar phrase
    mov    ecx, DWORD PTR sqPhrase
    shl    ecx, 6
    lea    rdi, leadTab
    add    rdi, rcx
    movzx  r12d, BYTE PTR [rdi+rbx]
    test   r12d, r12d
    jz     ld_exit
    mov    r13d, 1                         ; steps until the next note (<= 16)
ld_len:
    lea    eax, [rbx+r13]
    cmp    eax, 64
    jae    ld_play
    cmp    BYTE PTR [rdi+rax], 0
    jne    ld_play
    inc    r13d
    cmp    r13d, 16
    jb     ld_len
ld_play:
    movss  xmm3, DWORD PTR kVelLead
    LAYERGAIN L_LEAD, xmm3
    movss  xmm4, DWORD PTR kZeroF
    lea    rcx, Pat_Lead
    mov    edx, r12d
    imul   r8d, r13d, LEAD_STEP
    call   Sq_Play
    test   esi, L_LEAD2
    jz     ld_exit
    movss  xmm3, DWORD PTR kVelLd2
    LAYERGAIN L_LEAD2, xmm3
    movss  xmm4, DWORD PTR kPanR
    lea    rcx, Pat_Lead
    lea    edx, [r12+12]
    imul   r8d, r13d, LEAD_STEP
    call   Sq_Play
ld_exit:
    FN_RET
FN_END Sq_Lead

; Sq_Fx: crash and riser at the start of a bar.
FN_BEGIN Sq_Fx, 0
    cmp    DWORD PTR sqStep, 0
    jne    fx_exit
    mov    esi, DWORD PTR sqLayers
    test   esi, L_CRASH
    jz     fx_riser
    mov    ecx, DWORD PTR sqFrame
    movss  xmm1, DWORD PTR kVelCrash
    call   Drm_Crash
fx_riser:
    test   esi, L_RISER
    jz     fx_exit
    mov    ecx, DWORD PTR sqFrame
    mov    edx, BAR_FR
    movss  xmm2, DWORD PTR kVelRiser
    call   Drm_Riser
fx_exit:
    FN_RET
FN_END Sq_Fx

; ---------------------------------------------------------------------------
; Sq_Step(ecx = song step) - every instrument for one sixteenth.
; ---------------------------------------------------------------------------
FN_BEGIN Sq_Step, 0
    mov    DWORD PTR sqStep, ecx
    mov    eax, DWORD PTR sqBar
    shl    eax, 4
    add    eax, ecx
    imul   rax, rax, 661500                ; STEP_NUM
    shr    rax, 7
    mov    DWORD PTR sqFrame, eax
    call   Sq_Pad
    call   Sq_Kick
    call   Sq_Snares
    call   Sq_Hats
    call   Sq_Bass
    call   Sq_Arp
    call   Sq_Lead
    call   Sq_Fx
    FN_RET
FN_END Sq_Step

; Sq_LoadBar(ecx = bar) - makes the bar current: its layers, chord and phrase.
LEAF_BEGIN Sq_LoadBar
    mov    DWORD PTR sqBar, ecx
    lea    r8, barTab
    mov    eax, DWORD PTR [r8+rcx*8]
    mov    DWORD PTR sqLayers, eax
    movzx  eax, BYTE PTR [r8+rcx*8+4]
    lea    rdx, chordTab
    lea    rdx, [rdx+rax*4]
    mov    QWORD PTR sqChord, rdx
    movzx  eax, BYTE PTR [r8+rcx*8+5]
    mov    DWORD PTR sqPhrase, eax
    ret
LEAF_END Sq_LoadBar

; Sq_Bar(ecx = bar) - loads the bar row, runs its 16 steps.
FN_BEGIN Sq_Bar, 0
    call   Sq_LoadBar
    xor    esi, esi
sb_step:
    mov    ecx, esi
    call   Sq_Step
    inc    esi
    cmp    esi, 16
    jb     sb_step
    FN_RET
FN_END Sq_Bar

; ---------------------------------------------------------------------------
; Aud_Render - renders the soundtrack into gPcm (44.1 kHz, 16-bit, stereo).
; Reports progress 75..99 (the scenes use 0..75).  The allocation has room for
; a 44-byte WAV header right in front of gPcm (see Diag_RunWav).
; ---------------------------------------------------------------------------
FN_BEGIN Aud_Render, 0
    mov    ecx, AUDIO_BYTES + 64
    call   Mem_Alloc
    mov    QWORD PTR sqPcmRaw, rax
    add    rax, 64
    mov    gPcm, rax
    mov    ecx, AUDIO_FRAMES * 8
    call   Mem_Alloc
    mov    QWORD PTR synBusDry, rax
    mov    ecx, AUDIO_FRAMES * 8
    call   Mem_Alloc
    mov    QWORD PTR synBusMus, rax
    lea    rdi, sqKick
    mov    ecx, SONG_STEPS
    xor    eax, eax
    rep    stosb
    xor    ebx, ebx
ar_bar:
    imul   ecx, ebx, (20 SHL 16) / SONG_BARS
    shr    ecx, 16
    add    ecx, 75
    call   Tl_Progress
    mov    ecx, ebx
    call   Sq_Bar
    inc    ebx
    cmp    ebx, SONG_BARS
    jb     ar_bar
    mov    ecx, 96
    call   Tl_Progress
    lea    rcx, sqKick
    mov    rdx, gPcm
    call   Mix_Down
    mov    rcx, QWORD PTR synBusDry
    xor    edx, edx
    mov    r8d, MEM_RELEASE
    call   VirtualFree
    mov    rcx, QWORD PTR synBusMus
    xor    edx, edx
    mov    r8d, MEM_RELEASE
    call   VirtualFree
    mov    ecx, 99
    call   Tl_Progress
    xor    eax, eax
    FN_RET
FN_END Aud_Render

END
