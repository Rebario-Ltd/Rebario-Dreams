; ============================================================================
; audio.inc - declarations shared by the soundtrack modules
;             synth.asm (DSP voices), drums.asm (percussion), song.asm
;             (sequencer), mixfx.asm (mix-down) and audio.asm (playback).
; ============================================================================

; Instrument description for the generic subtractive voice (Syn_Note).
; Oscillators are PolyBLEP saws; osc B with wB < 0 and ratB = 1 makes a pulse
; whose width is phB.  Times are seconds, frequencies Hz.
PATCH STRUCT
    wA      REAL4 ?              ; level of the main saw
    wB      REAL4 ?              ; level of the second saw (negative: pulse mode)
    wC      REAL4 ?              ; level of the third saw
    ratB    REAL4 ?              ; frequency ratio of saw B (detune)
    ratC    REAL4 ?              ; frequency ratio of saw C
    phB     REAL4 ?              ; start phase of saw B (pulse width)
    wSub    REAL4 ?              ; sine one octave below
    attack  REAL4 ?              ; attack time
    decay   REAL4 ?              ; decay time constant
    sustain REAL4 ?              ; sustain level
    release REAL4 ?              ; release time constant
    fcBase  REAL4 ?              ; low-pass cut-off at rest
    fcEnv   REAL4 ?              ; extra cut-off at the start of the note
    fcDec   REAL4 ?              ; time constant of the cut-off envelope
    damp    REAL4 ?              ; filter damping: 2 flat .. 0.4 resonant
    drive   REAL4 ?              ; soft saturation amount (0 = clean)
    vibHz   REAL4 ?              ; vibrato rate
    vibAmt  REAL4 ?              ; vibrato depth (relative frequency)
    vibDly  REAL4 ?              ; delay before the vibrato starts
    bus     DWORD ?              ; 0 = dry bus, 1 = music bus (ducked, reverb)
PATCH ENDS

; One note event for Syn_Note.
NOTE STRUCT
    patch   QWORD ?              ; PATCH *
    start   DWORD ?              ; first frame
    len     DWORD ?              ; frames the key is held
    freq    REAL4 ?              ; Hz
    vel     REAL4 ?              ; linear gain
    pan     REAL4 ?              ; -1 .. 1
    pad     DWORD ?
NOTE ENDS

SONG_BARS    EQU NUM_SCENES * 8  ; every scene lasts eight bars (include common.inc first)
SONG_STEPS   EQU SONG_BARS * 16  ; 16th notes in the demo
STEP_FR      EQU 5168            ; frames per sixteenth (rounded)
BAR_FR       EQU 82688           ; frames per bar

; ---- layers of the arrangement (song.asm: one DWORD of the bar table per bar) --------
L_KICK   EQU 00000001h
L_CLAP   EQU 00000002h
L_HAT    EQU 00000004h                  ; off-beat eighth hats
L_HAT16  EQU 00000008h                  ; sixteenth hats
L_OPEN   EQU 00000010h                  ; open hat on the last two off-beats
L_BASS1  EQU 00000020h                  ; off-beat bass
L_BASS2  EQU 00000040h                  ; rolling sixteenth bass
L_BASS3  EQU 00000080h                  ; heavy syncopated bass
L_ARP    EQU 00000100h
L_ARP2   EQU 00000200h                  ; octave echo of the arpeggio
L_PAD    EQU 00000400h
L_LEAD   EQU 00000800h
L_LEAD2  EQU 00001000h                  ; lead doubled an octave higher
L_RISER  EQU 00002000h
L_CRASH  EQU 00004000h
L_ROLL   EQU 00008000h                  ; snare roll
L_SOFT   EQU 00010000h                  ; kick is soft and short of weight
L_SNARE  EQU 00020000h                  ; snare layered on the clap
L_GHOST  EQU 00040000h                  ; silent kick: it only triggers the sidechain pump

; ---- bus storage (float, interleaved stereo, AUDIO_FRAMES frames each) --------
EXTERNDEF synBusDry:QWORD
EXTERNDEF synBusMus:QWORD

; ---- synth.asm ------------------------------------------------------------------
EXTERNDEF Syn_Note:PROC         ; rcx = NOTE *
EXTERNDEF Pat_Pad:PATCH
EXTERNDEF Pat_Arp:PATCH
EXTERNDEF Pat_Bass:PATCH
EXTERNDEF Pat_BassHeavy:PATCH
EXTERNDEF Pat_Lead:PATCH

; ---- drums.asm ------------------------------------------------------------------
EXTERNDEF Drm_Kick:PROC         ; ecx = start frame, xmm1 = velocity
EXTERNDEF Drm_Snare:PROC        ; ecx = start frame, xmm1 = velocity
EXTERNDEF Drm_Clap:PROC         ; ecx = start frame, xmm1 = velocity
EXTERNDEF Drm_Hat:PROC          ; ecx = start frame, edx = 1 open, xmm2 = velocity
EXTERNDEF Drm_Riser:PROC        ; ecx = start frame, edx = frames, xmm2 = velocity
EXTERNDEF Drm_Crash:PROC        ; ecx = start frame, xmm1 = velocity

; ---- mixfx.asm ------------------------------------------------------------------
EXTERNDEF Mix_Down:PROC         ; rcx = kick flags BYTE[SONG_STEPS], rdx = pcm out

; ---- song.asm -------------------------------------------------------------------
EXTERNDEF barTab:BYTE           ; per bar: DWORD layers, BYTE chord, BYTE phrase, WORD 0
EXTERNDEF sqKick:BYTE           ; sidechain flags of the last render, BYTE[SONG_STEPS]
EXTERNDEF sqLayers:DWORD        ; layers of the current bar (a test may mask them)
EXTERNDEF sqNote:NOTE           ; the note the sequencer rendered last
EXTERNDEF Sq_LoadBar:PROC       ; ecx = bar: layers, chord and phrase of the bar become current
EXTERNDEF Sq_Step:PROC          ; ecx = step 0..15 of the current bar: every instrument plays
EXTERNDEF Sq_FadeAt:PROC        ; ecx = bar, edx = step, r8d = layer -> xmm0 = gain 0..1
EXTERNDEF Sq_RollHits:PROC      ; ecx = step -> eax = snare hits of the roll in that step
