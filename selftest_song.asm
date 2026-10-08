; ============================================================================
; selftest_song.asm - built-in checks of the arrangement and of the
;                     transitions between the scenes (part of /selftest).
; ----------------------------------------------------------------------------
; Nobody can listen to the soundtrack in an automated run, so what makes the
; transitions smooth is checked in its parts:
;   * the arpeggio never plays without the sidechain pulse: where the kick
;     rests, a silent "ghost" kick still pumps the music bus with the beat,
;     so the accents of the arpeggio do not flip when the kick drops out or
;     comes back (the flags of the finished render against the bar table; and
;     one real step: the flag is set, nothing sounds on the dry bus, while a
;     bar with a kick does write there),
;   * every scene change is announced by a riser,
;   * a melodic layer dies away before it leaves and grows in after it
;     enters: the exact gains of Sq_FadeAt at chosen bars, for all four
;     layers at every scene change (a layer that goes on keeps its full
;     level), and the velocity of the note that the sequencer really plays
;     in ten chosen steps (the gain has to reach the notes),
;   * the snare roll speeds up in three even stages,
;   * the riser sweeps up smoothly, from silence, on the dry bus only (the
;     kick pump and the echo used to chop it into a stutter that went on
;     over the next scene) and fades out to nothing at its end.
; ============================================================================
INCLUDE common.inc
INCLUDE win.inc
INCLUDE audio.inc

FADE_LAYERS  EQU 4
RISER_START  EQU 0                       ; the test riser plays in the first bar (the notes of the other
                                         ; steps start later; a pad rings for 3.5 s, so not anywhere else)
TAIL_FRAMES  EQU 32                      ; frames looked at at both ends of the riser
GHOST_BAR    EQU 68                      ; arpeggio, pad and lead over a silent pulse
KICK_BAR     EQU 4                       ; the first bar with a (soft) kick
ROLL_BAR     EQU 63                      ; the finale of PRISM: roll and riser
GHOST_FRAME  EQU (GHOST_BAR * 16 * 661500) SHR 7
KICK_FRAME   EQU (KICK_BAR * 16 * 661500) SHR 7
ROLL_F1      EQU ((ROLL_BAR * 16 + 1) * 661500) SHR 7     ; first frames of the steps 1, 8 and 13 of that bar
ROLL_F8      EQU ((ROLL_BAR * 16 + 8) * 661500) SHR 7
ROLL_F13     EQU ((ROLL_BAR * 16 + 13) * 661500) SHR 7

FADEROW STRUCT
    bar     DWORD ?
    step    DWORD ?
    layer   DWORD ?
    gain    REAL4 ?
FADEROW ENDS

VELROW STRUCT
    bar     DWORD ?
    step    DWORD ?
    layers  DWORD ?
    vel     REAL4 ?
VELROW ENDS

.const
ALIGN 16
kSgTol      REAL4 0.0005
kSgOne      REAL4 1.0
kSgLeaveMax REAL4 0.15                   ; a leaving layer is below this at the end of its last bar
kSgEnterMax REAL4 0.25                   ; an entering layer is below this at the start of its first bar
kSgVel      REAL4 0.55
ALIGN 8
kSgSteady   REAL8 1.2                    ; every step has at least this many times the energy of the one before
                                         ; (measured: 1.49 at the least; a pumping riser dips below 1)
kSgGrow     REAL8 1000.0                 ; the riser has at least this many times the energy at step 14 as at step 1
                                         ; (measured: 1.1e5)
kSgFade     REAL8 0.01                   ; the last frames carry at most this much of a step-14 frame
kSgQuiet    REAL8 1.0e-6                 ; ... and the first frames at most this much
kSgTailLo   REAL8 0.8                    ; the last step has 0.8 .. 1.3 times the energy of the one before:
kSgTailHi   REAL8 1.3                    ; a fade over the last 1/32 gives 1.07, 1/16 gives 0.51, 1/64 gives 1.39
kSgHalf     REAL8 0.5                    ; one hit of the roll: the second half of its step has < 0.5 of the first
                                         ; (measured: 0.18 .. 0.21)
kSgTwin     REAL8 0.8                    ; two hits: the second half has >= 0.8 of the first (measured: 1.02 .. 1.24)
kSgSome     REAL8 0.001                  ; ... and the first half is not silent (the energies are in the hundreds)

szSgArp     BYTE "song: the arpeggio always pumps (every bar with it has a kick or a ghost kick)", 0
szSgFlags   BYTE "song: sidechain flags sit on the beats of the bars with a kick or a ghost kick", 0
szSgGhost   BYTE "song: a ghost kick sets the flag and stays silent; a real kick sounds on the dry bus", 0
szSgRisers  BYTE "song: every scene change is announced by a riser", 0
szSgFade    BYTE "song: fade gains of the melodic layers at chosen bars", 0
szSgChange  BYTE "song: layers fade out before they leave, grow in after they enter, keep their level while they go on", 0
szSgVel     BYTE "song: the fade gain reaches the notes of the arpeggio, its echo, the lead and its double", 0
szSgRoll    BYTE "song: the snare roll speeds up in three stages (8ths, 16ths, 32nds)", 0
szSgRollR   BYTE "song: the roll plays no hit, one hit and two hits in its steps 1, 8 and 13", 0
szSgBus     BYTE "song: the riser is on the dry bus only (no pumping, no echo)", 0
szSgRise    BYTE "song: the riser sweeps up smoothly from silence", 0
szSgTail    BYTE "song: the riser fades out to silence over its last 1/32", 0

; bar, step, layer, expected gain
ALIGN 4
fadeRows    FADEROW <47, 15, L_ARP,  0.11111111>      ; the arpeggio leaves after bar 47 ...
            FADEROW <47, 8,  L_ARP,  0.88888889>      ; ... fading over the last eight steps
            FADEROW <47, 7,  L_ARP,  1.0>
            FADEROW <52, 0,  L_ARP,  0.2>             ; it returns in bar 52 ...
            FADEROW <52, 3,  L_ARP,  0.8>             ; ... growing in over four steps
            FADEROW <52, 4,  L_ARP,  1.0>
            FADEROW <23, 15, L_ARP2, 0.11111111>      ; the octave echo leaves before the breakdown
            FADEROW <47, 15, L_LEAD, 1.0>             ; the lead plays on into scene 6
            FADEROW <0,  0,  L_PAD,  1.0>             ; the first bar has no predecessor
            FADEROW <71, 15, L_ARP,  1.0>             ; the last bar has no successor (what follows the table
                                                      ; has no arpeggio bit: reading it would fade the layer)
FADE_ROWS   EQU ($ - fadeRows) / SIZEOF FADEROW
fadeLayers  DWORD L_ARP, L_ARP2, L_LEAD, L_LEAD2

; bar, step, layers that play (the rest is masked), velocity of the last note of the step
; (the velocity of the layer times its fade gain)
velRows     VELROW <47, 15, L_ARP,              0.06888889>   ; 0.62 / 9: the last note before the arpeggio leaves
            VELROW <47, 9,  L_ARP,              0.48222222>   ; 0.62 * 7/9
            VELROW <46, 15, L_ARP,              0.62>         ; the same step, one bar earlier: no fade
            VELROW <52, 0,  L_ARP,              0.19>         ; 0.95 / 5: the arpeggio returns
            VELROW <52, 3,  L_ARP,              0.496>        ; 0.62 * 4/5
            VELROW <23, 15, L_ARP or L_ARP2,    0.04222222>   ; the echo: 0.38 / 9
            VELROW <12, 0,  L_LEAD,             0.17>         ; 0.85 / 5: the lead joins
            VELROW <55, 14, L_LEAD,             0.18888889>   ; 0.85 * 2/9: it leaves before the PRISM
            VELROW <54, 0,  L_LEAD or L_LEAD2,  0.064>        ; 0.32 / 5: the double joins
            VELROW <55, 14, L_LEAD or L_LEAD2,  0.07111111>   ; 0.32 * 2/9
VEL_ROWS    EQU ($ - velRows) / SIZEOF VELROW

; snare hits per step of the roll
rollExpect  BYTE 1, 0, 1, 0, 1, 0,  1, 1, 1, 1, 1, 1,  2, 2, 2, 2

.data?
ALIGN 16
sgEnergy    REAL8 16 DUP (?)             ; energy of every step of the test riser
sgGain      REAL4 2 DUP (?)              ; gain at the end of the last bar / the start of the first
sgFirst     REAL8 ?                      ; mean energy per frame of the first / last frames
sgLast      REAL8 ?
sgHalf      REAL8 ?                      ; energy of the first half of a step

.code

; ---------------------------------------------------------------------------
; Sg_Silent(rsi = first dword, ecx = count) -> eax = 1 when every dword is 0
; (every bit; -0.0 counts as a sound).
; ---------------------------------------------------------------------------
LEAF_BEGIN Sg_Silent
    mov    r11, rsi
    xor    eax, eax
sgq_lp:
    or     eax, DWORD PTR [r11]
    add    r11, 4
    dec    ecx
    jnz    sgq_lp
    xor    ecx, ecx
    test   eax, eax
    setz   cl
    mov    eax, ecx
    ret
LEAF_END Sg_Silent

; ---------------------------------------------------------------------------
; Sg_Below(xmm0 = value, xmm1 = limit) -> eax = 1 when value < limit.
; ---------------------------------------------------------------------------
LEAF_BEGIN Sg_Below
    xor    eax, eax
    comiss xmm0, xmm1
    setb   al
    setnp  cl
    movzx  ecx, cl
    and    eax, ecx
    ret
LEAF_END Sg_Below

; ---------------------------------------------------------------------------
; St_SongPump - the sidechain flags of the last render (sqKick) against the
; bar table.
; ---------------------------------------------------------------------------
FN_BEGIN St_SongPump, 0
    mov    r12d, 1                         ; every bar with the arpeggio pulses
    mov    r13d, 1                         ; the flags are exactly the beats of pulsing bars
    xor    esi, esi
sgp_bar:
    lea    rax, barTab
    mov    edx, DWORD PTR [rax+rsi*8]      ; layers of the bar
    xor    ecx, ecx
    test   edx, L_KICK or L_GHOST
    setnz  cl                              ; ecx = 1 when the bar has a (ghost) kick
    test   edx, L_ARP
    jz     sgp_flags
    and    r12d, ecx
sgp_flags:
    mov    eax, esi
    shl    eax, 4
    lea    rdi, sqKick
    add    rdi, rax
    xor    ebx, ebx
sgp_step:
    mov    eax, ecx                        ; wanted flag: the bar pulses and this is a beat
    test   ebx, 3
    jz     sgp_cmp
    xor    eax, eax
sgp_cmp:
    movzx  edx, BYTE PTR [rdi+rbx]
    cmp    edx, eax
    je     sgp_next
    xor    r13d, r13d
sgp_next:
    inc    ebx
    cmp    ebx, 16
    jb     sgp_step
    inc    esi
    cmp    esi, SONG_BARS
    jb     sgp_bar
    mov    edx, r12d
    lea    rcx, szSgArp
    call   St_Report
    mov    edx, r13d
    lea    rcx, szSgFlags
    call   St_Report
    FN_RET
FN_END St_SongPump

; ---------------------------------------------------------------------------
; St_SongGhost - the first step of a ghost bar and of a bar with a kick, both
; rendered for real into the (fresh) buses.
; ---------------------------------------------------------------------------
FN_BEGIN St_SongGhost, 0
    lea    rax, sqKick
    mov    BYTE PTR [rax+GHOST_BAR*16], 0  ; (the render of the soundtrack has set it)
    mov    ecx, GHOST_BAR
    call   Sq_LoadBar
    xor    ecx, ecx
    call   Sq_Step
    lea    rax, sqKick
    movzx  ebx, BYTE PTR [rax+GHOST_BAR*16] ; 1: the pulse is there ...
    mov    rsi, QWORD PTR synBusDry
    add    rsi, GHOST_FRAME * 8
    mov    ecx, BAR_FR * 2
    call   Sg_Silent                       ; ... and the dry bus (the kick's) is silent
    and    ebx, eax
    mov    ecx, KICK_BAR
    call   Sq_LoadBar
    xor    ecx, ecx
    call   Sq_Step
    mov    rsi, QWORD PTR synBusDry
    add    rsi, KICK_FRAME * 8
    mov    ecx, BAR_FR * 2
    call   Sg_Silent                       ; control: a real kick is heard there
    xor    eax, 1
    and    ebx, eax
    mov    edx, ebx
    lea    rcx, szSgGhost
    call   St_Report
    FN_RET
FN_END St_SongGhost

; ---------------------------------------------------------------------------
; St_SongRisers - the last bar of every scene has a riser.
; ---------------------------------------------------------------------------
FN_BEGIN St_SongRisers, 0
    mov    r12d, 1
    mov    ebx, 1                          ; scene 1 .. NUM_SCENES - 1 starts after bar 8 * scene - 1
sgr_lp:
    lea    eax, [rbx*8-1]
    lea    rcx, barTab
    xor    edx, edx
    test   DWORD PTR [rcx+rax*8], L_RISER
    setnz  dl
    and    r12d, edx
    inc    ebx
    cmp    ebx, NUM_SCENES
    jb     sgr_lp
    mov    edx, r12d
    lea    rcx, szSgRisers
    call   St_Report
    FN_RET
FN_END St_SongRisers

; ---------------------------------------------------------------------------
; St_SongFadeRows - Sq_FadeAt against the exact gains in fadeRows.
; ---------------------------------------------------------------------------
FN_BEGIN St_SongFadeRows, 0
    mov    r12d, 1
    xor    ebx, ebx
    lea    rsi, fadeRows
sgf_lp:
    mov    ecx, DWORD PTR [rsi+FADEROW.bar]
    mov    edx, DWORD PTR [rsi+FADEROW.step]
    mov    r8d, DWORD PTR [rsi+FADEROW.layer]
    call   Sq_FadeAt
    movss  xmm1, DWORD PTR [rsi+FADEROW.gain]
    movss  xmm2, DWORD PTR kSgTol
    call   St_Near
    and    r12d, eax
    add    rsi, SIZEOF FADEROW
    inc    ebx
    cmp    ebx, FADE_ROWS
    jb     sgf_lp
    mov    edx, r12d
    lea    rcx, szSgFade
    call   St_Report
    FN_RET
FN_END St_SongFadeRows

; ---------------------------------------------------------------------------
; St_SongFadeChange - at every scene change and for each of the four melodic
; layers: gone after the change -> quiet at the end of the last bar; new after
; the change -> quiet at the start of the first bar; on both sides -> full
; level at both ends (a layer that goes on must not be touched).
; ---------------------------------------------------------------------------
FN_BEGIN St_SongFadeChange, 0
    mov    r12d, 1
    mov    r13d, 1                         ; scene 1 .. NUM_SCENES - 1
sgc_scene:
    lea    r14d, [r13*8-1]                 ; the last bar before the change
    xor    ebx, ebx
sgc_layer:
    lea    rax, fadeLayers
    mov    r15d, DWORD PTR [rax+rbx*4]     ; layer bit
    lea    rax, barTab
    xor    esi, esi
    test   DWORD PTR [rax+r14*8], r15d
    setnz  sil                             ; the layer plays before the change
    xor    edi, edi
    test   DWORD PTR [rax+r14*8+8], r15d
    setnz  dil                             ; ... and after it
    mov    eax, esi
    or     eax, edi
    jz     sgc_next
    mov    ecx, r14d                       ; gain in the last step of the last bar
    mov    edx, 15
    mov    r8d, r15d
    call   Sq_FadeAt
    movss  DWORD PTR sgGain, xmm0
    lea    ecx, [r14+1]                    ; gain in the first step of the first bar after
    xor    edx, edx
    mov    r8d, r15d
    call   Sq_FadeAt
    movss  DWORD PTR sgGain+4, xmm0
    test   esi, esi
    jz     sgc_enter
    test   edi, edi
    jz     sgc_leave
    movss  xmm0, DWORD PTR sgGain          ; goes on: both gains are 1
    movss  xmm1, DWORD PTR kSgOne
    movss  xmm2, DWORD PTR kSgTol
    call   St_Near
    and    r12d, eax
    movss  xmm0, DWORD PTR sgGain+4
    movss  xmm1, DWORD PTR kSgOne
    movss  xmm2, DWORD PTR kSgTol
    call   St_Near
    and    r12d, eax
    jmp    sgc_next
sgc_leave:
    movss  xmm0, DWORD PTR sgGain
    movss  xmm1, DWORD PTR kSgLeaveMax
    call   Sg_Below
    and    r12d, eax
    jmp    sgc_next
sgc_enter:
    movss  xmm0, DWORD PTR sgGain+4
    movss  xmm1, DWORD PTR kSgEnterMax
    call   Sg_Below
    and    r12d, eax
sgc_next:
    inc    ebx
    cmp    ebx, FADE_LAYERS
    jb     sgc_layer
    inc    r13d
    cmp    r13d, NUM_SCENES
    jb     sgc_scene
    mov    edx, r12d
    lea    rcx, szSgChange
    call   St_Report
    FN_RET
FN_END St_SongFadeChange

; ---------------------------------------------------------------------------
; St_SongVel - the velocity of the last note of a step that the sequencer
; really plays (only the layers of the row sound) against velRows.
; ---------------------------------------------------------------------------
FN_BEGIN St_SongVel, 0
    mov    r12d, 1
    xor    ebx, ebx
    lea    rsi, velRows
sgv_lp:
    mov    ecx, DWORD PTR [rsi+VELROW.bar]
    call   Sq_LoadBar
    mov    eax, DWORD PTR [rsi+VELROW.layers]
    mov    DWORD PTR sqLayers, eax
    mov    ecx, DWORD PTR [rsi+VELROW.step]
    call   Sq_Step
    lea    rax, sqNote
    movss  xmm0, DWORD PTR [rax+NOTE.vel]
    movss  xmm1, DWORD PTR [rsi+VELROW.vel]
    movss  xmm2, DWORD PTR kSgTol
    call   St_Near
    and    r12d, eax
    add    rsi, SIZEOF VELROW
    inc    ebx
    cmp    ebx, VEL_ROWS
    jb     sgv_lp
    mov    edx, r12d
    lea    rcx, szSgVel
    call   St_Report
    FN_RET
FN_END St_SongVel

; ---------------------------------------------------------------------------
; St_SongRoll - Sq_RollHits for the sixteen steps of a bar.
; ---------------------------------------------------------------------------
FN_BEGIN St_SongRoll, 0
    mov    r12d, 1
    xor    ebx, ebx
sgl_lp:
    mov    ecx, ebx
    call   Sq_RollHits
    lea    rdx, rollExpect
    movzx  edx, BYTE PTR [rdx+rbx]
    cmp    eax, edx
    je     sgl_ok
    xor    r12d, r12d
sgl_ok:
    inc    ebx
    cmp    ebx, 16
    jb     sgl_lp
    mov    edx, r12d
    lea    rcx, szSgRoll
    call   St_Report
    FN_RET
FN_END St_SongRoll

; ---------------------------------------------------------------------------
; Sg_SumSq(rsi = first frame of a bus, ecx = frames) -> xmm0 = the energy (the
; sum of squares of both channels) of those frames.
; ---------------------------------------------------------------------------
LEAF_BEGIN Sg_SumSq
    mov    r11, rsi
    xorpd  xmm2, xmm2
sgs_frame:
    cvtss2sd xmm0, DWORD PTR [r11]
    mulsd  xmm0, xmm0
    addsd  xmm2, xmm0
    cvtss2sd xmm1, DWORD PTR [r11+4]
    mulsd  xmm1, xmm1
    addsd  xmm2, xmm1
    add    r11, 8
    dec    ecx
    jnz    sgs_frame
    movapd xmm0, xmm2
    ret
LEAF_END Sg_SumSq

; ---------------------------------------------------------------------------
; Sg_Energy(rsi = first frame of the riser bar on the dry bus) - the energy
; of its sixteen steps into sgEnergy.
; ---------------------------------------------------------------------------
FN_BEGIN Sg_Energy, 0
    mov    r12, rsi
    lea    rdi, sgEnergy
    xor    ebx, ebx
sge_lp:
    mov    rsi, r12
    mov    ecx, STEP_FR
    call   Sg_SumSq
    movsd  QWORD PTR [rdi+rbx*8], xmm0
    add    r12, STEP_FR * 8
    inc    ebx
    cmp    ebx, 16
    jb     sge_lp
    FN_RET
FN_END Sg_Energy

; ---------------------------------------------------------------------------
; Sg_Halves(rsi = first frame of a step on the dry bus) -> xmm0 = the energy of
; the first half of the step, xmm1 = that of the second half (where the second
; hit of a roll step lands).
; ---------------------------------------------------------------------------
FN_BEGIN Sg_Halves, 0
    mov    r12, rsi
    mov    ecx, STEP_FR / 2
    call   Sg_SumSq
    movsd  QWORD PTR sgHalf, xmm0
    lea    rsi, [r12 + (STEP_FR / 2) * 8]
    mov    ecx, STEP_FR / 2
    call   Sg_SumSq
    movapd xmm1, xmm0
    movsd  xmm0, QWORD PTR sgHalf
    FN_RET
FN_END Sg_Halves

; ---------------------------------------------------------------------------
; St_SongRollSteps - three steps of the roll bar rendered for real (only the
; roll sounds): an odd step of the eighth-note stage has no hit at all, an
; even one has a hit whose tail is far quieter in the second half, a step of
; the thirty-second stage has a second hit in the second half.
; ---------------------------------------------------------------------------
FN_BEGIN St_SongRollSteps, 0
    mov    ecx, ROLL_BAR
    call   Sq_LoadBar
    mov    DWORD PTR sqLayers, L_ROLL
    mov    ecx, 1
    call   Sq_Step
    mov    ecx, 8
    call   Sq_Step
    mov    ecx, 13
    call   Sq_Step
    mov    rsi, QWORD PTR synBusDry
    add    rsi, ROLL_F1 * 8
    mov    ecx, STEP_FR * 2
    call   Sg_Silent
    mov    ebx, eax                        ; step 1: silence
    mov    rsi, QWORD PTR synBusDry
    add    rsi, ROLL_F8 * 8
    call   Sg_Halves
    movapd xmm2, xmm0
    mulsd  xmm2, QWORD PTR kSgHalf
    xor    eax, eax
    comisd xmm2, xmm1
    seta   al                              ; step 8: one hit - the second half has less than half
    and    ebx, eax
    xor    eax, eax
    comisd xmm0, QWORD PTR kSgSome
    seta   al
    and    ebx, eax
    mov    rsi, QWORD PTR synBusDry
    add    rsi, ROLL_F13 * 8
    call   Sg_Halves
    movapd xmm2, xmm0
    mulsd  xmm2, QWORD PTR kSgTwin
    xor    eax, eax
    comisd xmm1, xmm2
    setae  al                              ; step 13: two hits - the second half is as loud as the first
    and    ebx, eax
    xor    eax, eax
    comisd xmm0, QWORD PTR kSgSome
    seta   al
    and    ebx, eax
    mov    edx, ebx
    lea    rcx, szSgRollR
    call   St_Report
    FN_RET
FN_END St_SongRollSteps

; ---------------------------------------------------------------------------
; Sg_EdgeEnergy(rsi = first frame of the riser bar on the dry bus) - mean
; energy per frame of the first and of the last TAIL_FRAMES frames into
; sgFirst and sgLast.
; ---------------------------------------------------------------------------
LEAF_BEGIN Sg_EdgeEnergy
    xorpd  xmm2, xmm2
    xorpd  xmm3, xmm3
    xor    r8d, r8d
sgx_lp:
    mov    r9d, r8d
    cvtss2sd xmm0, DWORD PTR [rsi+r9*8]
    mulsd  xmm0, xmm0
    cvtss2sd xmm1, DWORD PTR [rsi+r9*8+4]
    mulsd  xmm1, xmm1
    addsd  xmm0, xmm1
    addsd  xmm2, xmm0                      ; first frames
    mov    r9d, BAR_FR - TAIL_FRAMES
    add    r9d, r8d
    cvtss2sd xmm0, DWORD PTR [rsi+r9*8]
    mulsd  xmm0, xmm0
    cvtss2sd xmm1, DWORD PTR [rsi+r9*8+4]
    mulsd  xmm1, xmm1
    addsd  xmm0, xmm1
    addsd  xmm3, xmm0                      ; last frames
    inc    r8d
    cmp    r8d, TAIL_FRAMES
    jb     sgx_lp
    mov    eax, TAIL_FRAMES
    cvtsi2sd xmm0, eax
    divsd  xmm2, xmm0
    divsd  xmm3, xmm0
    movsd  QWORD PTR sgFirst, xmm2
    movsd  QWORD PTR sgLast, xmm3
    ret
LEAF_END Sg_EdgeEnergy

; ---------------------------------------------------------------------------
; St_SongRiser - renders one riser into the (fresh) buses and looks at both of
; them: the music bus has to stay untouched, the dry bus rises steadily from
; silence and ends in silence.
; ---------------------------------------------------------------------------
FN_BEGIN St_SongRiser, 0
    mov    ecx, RISER_START
    mov    edx, BAR_FR
    movss  xmm2, DWORD PTR kSgVel
    call   Drm_Riser
    mov    rsi, QWORD PTR synBusMus
    add    rsi, RISER_START * 8
    mov    ecx, BAR_FR * 2
    call   Sg_Silent
    mov    edx, eax
    lea    rcx, szSgBus
    call   St_Report
    mov    rsi, QWORD PTR synBusDry
    add    rsi, RISER_START * 8
    call   Sg_Energy
    call   Sg_EdgeEnergy
    mov    r12d, 1                         ; rises steadily: each step has >= 1.2 times the energy of the previous
    mov    ebx, 1
    lea    rsi, sgEnergy
sgb_rise:
    movsd  xmm0, QWORD PTR [rsi+rbx*8]
    movsd  xmm1, QWORD PTR [rsi+rbx*8-8]
    mulsd  xmm1, QWORD PTR kSgSteady
    xor    eax, eax
    comisd xmm0, xmm1
    setae  al
    and    r12d, eax
    inc    ebx
    cmp    ebx, 15
    jb     sgb_rise
    movsd  xmm0, QWORD PTR [rsi+14*8]      ; ... and is far louder at step 14 than at step 1
    movsd  xmm1, QWORD PTR [rsi+8]
    mulsd  xmm1, QWORD PTR kSgGrow
    xor    eax, eax
    comisd xmm0, xmm1
    setae  al
    and    r12d, eax
    movsd  xmm0, QWORD PTR [rsi+14*8]      ; mean energy per frame of step 14
    mov    eax, STEP_FR
    cvtsi2sd xmm1, eax
    divsd  xmm0, xmm1
    mulsd  xmm0, QWORD PTR kSgQuiet        ; starts from silence
    xor    eax, eax
    comisd xmm0, QWORD PTR sgFirst
    seta   al
    and    r12d, eax
    mov    edx, r12d
    lea    rcx, szSgRise
    call   St_Report
    movsd  xmm0, QWORD PTR [rsi+14*8]      ; ... and ends in silence (St_Report clobbered xmm0)
    mov    eax, STEP_FR
    cvtsi2sd xmm1, eax
    divsd  xmm0, xmm1
    mulsd  xmm0, QWORD PTR kSgFade
    xor    ebx, ebx
    comisd xmm0, QWORD PTR sgLast
    seta   bl
    movsd  xmm0, QWORD PTR [rsi+15*8]      ; the fade is short: the last step is about as loud as the one before
    movsd  xmm1, QWORD PTR [rsi+14*8]
    mulsd  xmm1, QWORD PTR kSgTailLo
    xor    eax, eax
    comisd xmm0, xmm1
    setae  al
    and    ebx, eax
    movsd  xmm1, QWORD PTR [rsi+14*8]
    mulsd  xmm1, QWORD PTR kSgTailHi
    xor    eax, eax
    comisd xmm1, xmm0
    setae  al
    and    ebx, eax
    mov    edx, ebx
    lea    rcx, szSgTail
    call   St_Report
    FN_RET
FN_END St_SongRiser

; ---------------------------------------------------------------------------
; St_Song - all the arrangement and transition checks.  Needs sqKick to hold
; the flags of a finished Aud_Render; the buses of the render have been
; released, so it allocates two of its own for the steps it plays.
; ---------------------------------------------------------------------------
FN_BEGIN St_Song, 0
    call   St_SongPump
    call   St_SongRisers
    call   St_SongFadeRows
    call   St_SongFadeChange
    call   St_SongRoll
    mov    ecx, AUDIO_FRAMES * 8
    call   Mem_Alloc
    mov    QWORD PTR synBusDry, rax
    mov    ecx, AUDIO_FRAMES * 8
    call   Mem_Alloc
    mov    QWORD PTR synBusMus, rax
    call   St_SongVel
    call   St_SongGhost
    call   St_SongRollSteps
    call   St_SongRiser
    mov    rcx, QWORD PTR synBusDry
    xor    edx, edx
    mov    r8d, MEM_RELEASE
    call   VirtualFree
    mov    rcx, QWORD PTR synBusMus
    xor    edx, edx
    mov    r8d, MEM_RELEASE
    call   VirtualFree
    FN_RET
FN_END St_Song

END
