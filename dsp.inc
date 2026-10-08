; ============================================================================
; dsp.inc - float DSP macros and constants shared by synth.asm and drums.asm.
; Conventions: r14 holds &gSinTabF where SINLK is used; eax and edx are
; scratch registers of NOISE / SINLK; XMM arguments are caller-chosen.
; ============================================================================

.const
ALIGN 16
kOneV       REAL4 1.0, 0.0, 0.0, 0.0
kAbsMask    DWORD 7FFFFFFFh, 7FFFFFFFh, 7FFFFFFFh, 7FFFFFFFh
kOneF       REAL4 1.0
kHalfF      REAL4 0.5
k4096F      REAL4 4096.0
kSr         REAL4 44100.0
kInvSr      REAL4 2.2675737e-05
kNoiseScale REAL4 4.6566129e-10          ; 1 / 2^31

; ---- phase accumulators ([0, 1)) ----------------------------------------------
; t = t + dph, wrapped; s is a scratch register.
PHADV MACRO t:REQ, dph:REQ, s:REQ
    addss t, dph
    movaps s, t
    cmpnltss s, DWORD PTR kOneF
    andps s, XMMWORD PTR kOneV
    subss t, s
ENDM

; t wrapped into [0, 1) after it grew by less than one period.
WRAP1 MACRO t:REQ, s:REQ
    movaps s, t
    cmpnltss s, DWORD PTR kOneF
    andps s, XMMWORD PTR kOneV
    subss t, s
ENDM

; ---- band-limited saw -----------------------------------------------------------
; o = saw(t) in [-1, 1] with a PolyBLEP correction around the wrap-around;
; dph is the phase increment per sample.  s1, s2 are scratch registers.
BLEPSAW MACRO o:REQ, t:REQ, dph:REQ, s1:REQ, s2:REQ
    LOCAL lHi, lEnd
    movaps o, t
    addss  o, o
    subss  o, DWORD PTR kOneF
    comiss t, dph
    jae    lHi
    movaps s1, t                          ; just after the wrap: x = t / dph
    divss  s1, dph
    movaps s2, s1
    mulss  s2, s2
    addss  s1, s1
    subss  s1, s2
    subss  s1, DWORD PTR kOneF            ; 2x - x^2 - 1
    subss  o, s1
    jmp    lEnd
lHi:
    movss  s2, DWORD PTR kOneF
    subss  s2, dph
    comiss t, s2
    jbe    lEnd
    movaps s1, t                          ; just before the wrap: x = (t - 1) / dph
    subss  s1, DWORD PTR kOneF
    divss  s1, dph
    movaps s2, s1
    mulss  s2, s2
    addss  s2, s1
    addss  s2, s1
    addss  s2, DWORD PTR kOneF            ; x^2 + 2x + 1
    subss  o, s2
lEnd:
ENDM

; ---- sine from the shared float table (4097 entries) -------------------------------
; o = sin(2 pi t) for t in [0, 1); needs r14 = &gSinTabF; clobbers eax.
SINLK MACRO o:REQ, t:REQ, s1:REQ, s2:REQ
    movaps o, t
    mulss  o, DWORD PTR k4096F
    cvttss2si eax, o
    cvtsi2ss s1, eax
    subss  o, s1
    movss  s1, DWORD PTR [r14+rax*4]
    movss  s2, DWORD PTR [r14+rax*4+4]
    subss  s2, s1
    mulss  s2, o
    addss  s1, s2
    movaps o, s1
ENDM

; ---- white noise ------------------------------------------------------------------
; o = noise in [-1, 1) from the xorshift32 state in memory operand rng.
; Clobbers eax and edx.
NOISE MACRO o:REQ, rng:REQ
    mov  eax, DWORD PTR rng
    mov  edx, eax
    shl  edx, 13
    xor  eax, edx
    mov  edx, eax
    shr  edx, 17
    xor  eax, edx
    mov  edx, eax
    shl  edx, 5
    xor  eax, edx
    mov  DWORD PTR rng, eax
    cvtsi2ss o, eax
    mulss  o, DWORD PTR kNoiseScale
ENDM

; ---- state-variable filter (Chamberlin) -------------------------------------------
; One step: sLp/sBp are the state registers, x the input, f and q the
; coefficients, h the scratch register that receives the high-pass output.
SVFSTEP MACRO sLp:REQ, sBp:REQ, x:REQ, f:REQ, q:REQ, h:REQ, s:REQ
    movaps s, f
    mulss  s, sBp
    addss  sLp, s                          ; low += f * band
    movaps h, x
    subss  h, sLp
    movaps s, q
    mulss  s, sBp
    subss  h, s                            ; high = x - low - q * band
    movaps s, h
    mulss  s, f
    addss  sBp, s                          ; band += f * high
ENDM

; ---- adds a stereo sample to a bus -------------------------------------------------
; p = pointer register to the frame, l/r = XMM left/right values.  Advances p.
BUSADD MACRO p:REQ, l:REQ, r:REQ
    addss  l, DWORD PTR [p]
    addss  r, DWORD PTR [p+4]
    movss  DWORD PTR [p], l
    movss  DWORD PTR [p+4], r
    add    p, 8
ENDM
