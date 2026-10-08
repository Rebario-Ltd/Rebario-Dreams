; ============================================================================
; selftest_pulse.asm - built-in checks of the soft image pulse (part of
;                      /selftest; "/selftest pulse" runs only these).
; ----------------------------------------------------------------------------
; The beat reaches the picture as one smooth swell (gBeatEnv) that every scene
; shows at its own depth (scenePulse), where the old hard kick jumped from 0 to
; 256 in one frame.  Nobody can watch the demo in an automated run, so the
; checks pin down what makes the picture calm:
;   * the swell: 256 on the beat, 64 a quarter of a beat away, 0 half a beat
;     away; symmetric; falling then rising; no step bigger than a few units,
;   * Tl_Update publishes it and it is continuous in time (1 ms steps, over
;     several beat boundaries),
;   * the depths: none above half of the old punch, the landscape steady,
;     the beat still visible in most scenes; the pulse of a scene is the
;     swell times its depth and cross-fades in a transition; the bloom pump
;     follows it,
;   * the tunnel camera flies steadily (never stops, never jumps) and covers
;     two panels per beat,
;   * the pictures: what a beat does to every scene (the same moment drawn
;     with the swell at 256 and at 0) stays within limits - mean brightness
;     and mean pixel change - and the landscape stays exactly as it is.
; ============================================================================
INCLUDE common.inc

PU_LT        EQU 7000                    ; moment inside a scene's slot: no caption, no transition
PU_STEP      EQU 256                     ; phase step of the swell scan: 256 steps per beat
PU_MAXSTEP   EQU 6                       ; biggest change allowed between two steps (the curve itself: 4.1)
PU_PHASES    EQU 5
PU_SWELLS    EQU 3
PU_BLENDS    EQU 5
PU_SCAN_MS   EQU 1500                    ; 1 ms scan: three beat boundaries
PU_STEP_MAX  EQU 4                       ; ... biggest change per ms (the curve itself: 2.2)
PU_FLY_MS    EQU 1875                    ; four beats
PU_FLY_DT    EQU 16                      ; ms between the camera samples
PU_FLY_MIN   EQU 14                      ; slowest flight allowed, units per PU_FLY_DT (measured 17)
PU_FLY_MAX   EQU 34                      ; fastest (measured 28); the old camera stood still (5), then surged (52)
PU_FLY_SUM   EQU 4 * 512 + (PU_FLY_MS * 5 / 16)     ; four beats, the drift of 5/16 unit per ms
PU_HALF_BEAT EQU 234                     ; half a beat in ms
PU_SURGE_MIN EQU 5                       ; the camera covers at least this many units more in PU_FLY_DT around the beat (measured 8.6)
PU_TRAVEL_MIN EQU 800                    ; a quarter beat of flight changes the tunnel picture by at least this (1/100 level)
PU_MAX_DEPTH EQU 128                     ; no scene shows more than half of the old punch
PU_LAST_DEPTH EQU 200                    ; the depth the last scene gets for a moment
PU_FADE_SWELL EQU 255                    ; swell of the cross-fade check: not 256, see Pu_CrossFade

.const
ALIGN 16
puRgbMask   DWORD 00FFFFFFh, 00FFFFFFh, 00FFFFFFh, 00FFFFFFh

puPhases    DWORD 1000, 5000, 12345, 20000, 30000
.ERRNZ ($ - puPhases) - PU_PHASES * 4
puSwells    DWORD 0, 128, 256
.ERRNZ ($ - puSwells) - PU_SWELLS * 4
puBlends    DWORD 0, 64, 128, 255, 256
.ERRNZ ($ - puBlends) - PU_BLENDS * 4

; per scene: the least and the most that a beat may change the picture (mean
; difference per colour channel, in 1/100 level) and the most it may change
; its mean brightness (per mille), about 0.4 / 1.6 / 1.6 times what the
; depths of scenePulse give (the report lists the measured numbers).  Whoever
; changes a depth changes the limits of that scene with it.
puLimits    DWORD  120,  460,  45          ; 1 TITLE
            DWORD  460, 1820,  20          ; 2 AURORA
            DWORD  100,  410,  45          ; 3 WORMHOLE
            DWORD   50,  190,  30          ; 4 WARP
            DWORD  120,  480,  50          ; 5 MERCURY
            DWORD 1300, 5250,  15          ; 6 MANDALA
            DWORD   50,  200,  37          ; 7 INFERNO
            DWORD  180,  720,  48          ; 8 PRISM
            DWORD    0,    0,   0          ; 9 TERRA: not a bit
.ERRNZ ($ - puLimits) - NUM_SCENES * 12

szPuShape   BYTE "pulse: the swell is 256 on the beat, 64 a quarter of a beat away and 0 half a beat away", 0
szPuSym     BYTE "pulse: the swell is symmetric around the beat", 0
szPuMono    BYTE "pulse: the swell falls to the middle of the beat and rises again", 0
szPuStep    BYTE "pulse: the swell changes by at most 6 between two 1/256 beat steps (no jump)", 0
szPuPub     BYTE "pulse: Tl_Update publishes the beat counter, the phase, the swell and the plain pulse", 0
szPuFrame   BYTE "pulse: Demo_Render publishes the beat state of its time before it draws", 0
szPuCont    BYTE "pulse: the published swell is continuous over beat boundaries (1 ms steps)", 0
szPuTab     BYTE "pulse: no depth above 128, the landscape steady, the beat visible in at least six scenes", 0
szPuMul     BYTE "pulse: the pulse of a scene is the swell times its depth", 0
szPuFade    BYTE "pulse: the depths of two scenes cross-fade in a transition", 0
szPuLast    BYTE "pulse: the last scene has no successor to fade to", 0
szPuBloom   BYTE "pulse: the bloom pump follows the depth of the scene (cross-faded in a transition)", 0
szPuFly     BYTE "pulse: the tunnel camera never stops and never jumps", 0
szPuDist    BYTE "pulse: the tunnel camera covers two panels per beat plus its drift", 0
szPuSurge   BYTE "pulse: the tunnel camera is a little faster on the beat than half a beat later", 0
szPuFollow  BYTE "pulse: the picture of the tunnel follows the camera", 0
szPuPic     BYTE "a beat changes the picture, but only within its limits", 0
szPuInfoA   BYTE "      depth ", 0
szPuInfoB   BYTE ": brightness ", 0
szPuInfoC   BYTE " per mille, mean difference ", 0
szPuInfoD   BYTE " / 100 levels", 0

.data?
ALIGN 16
puDepth     DWORD ?                      ; scenePulse of the last scene, saved while the test changes it

.code

; ---------------------------------------------------------------------------
; Pu_Abs(eax) -> eax = |eax|
; ---------------------------------------------------------------------------
LEAF_BEGIN Pu_Abs
    cdq
    xor    eax, edx
    sub    eax, edx
    ret
LEAF_END Pu_Abs

; ---------------------------------------------------------------------------
; Pu_Shape -> eax = 1 when the swell is 256 on the beat (and just before the
; next one), 64 a quarter of a beat away and 0 half a beat away.
; ---------------------------------------------------------------------------
FN_BEGIN Pu_Shape, 0
    xor    ecx, ecx
    call   Tl_BeatEnv
    cmp    eax, 256
    sete   bl
    mov    ecx, 65535
    call   Tl_BeatEnv
    cmp    eax, 254
    setae  al
    and    bl, al
    mov    ecx, 16384
    call   Tl_BeatEnv
    sub    eax, 63                         ; 63 .. 65
    cmp    eax, 2
    setbe  al
    and    bl, al
    mov    ecx, 49152
    call   Tl_BeatEnv
    sub    eax, 63
    cmp    eax, 2
    setbe  al
    and    bl, al
    mov    ecx, 32768
    call   Tl_BeatEnv
    test   eax, eax
    setz   al
    and    bl, al
    movzx  eax, bl
    FN_RET
FN_END Pu_Shape

; ---------------------------------------------------------------------------
; Pu_Symmetry -> eax = 1 when the swell at phase p and at 1 - p differ by at
; most 1 (the table of the sine rounds a little differently on the two sides).
; ---------------------------------------------------------------------------
FN_BEGIN Pu_Symmetry, 0
    mov    r12d, 1
    xor    esi, esi
sy_lp:
    lea    rax, puPhases
    mov    ebx, DWORD PTR [rax+rsi*4]
    mov    ecx, ebx
    call   Tl_BeatEnv
    mov    edi, eax
    mov    ecx, 65536
    sub    ecx, ebx
    call   Tl_BeatEnv
    sub    eax, edi
    call   Pu_Abs
    cmp    eax, 1
    setbe  al
    movzx  eax, al
    and    r12d, eax
    inc    esi
    cmp    esi, PU_PHASES
    jb     sy_lp
    mov    eax, r12d
    FN_RET
FN_END Pu_Symmetry

; ---------------------------------------------------------------------------
; Pu_ScanSwell -> eax = 1 when the swell never rises on the first half of the
; beat and never falls on the second, edx = the biggest change between two
; samples that are 1/256 beat apart.
; ---------------------------------------------------------------------------
FN_BEGIN Pu_ScanSwell, 0
    xor    ecx, ecx
    call   Tl_BeatEnv
    mov    ebx, eax                        ; the previous sample
    xor    esi, esi                        ; phase
    mov    r12d, 1                         ; shape ok
    xor    r13d, r13d                      ; biggest change
sw_lp:
    add    esi, PU_STEP
    mov    ecx, esi
    cmp    ecx, 65535
    jbe    sw_at
    mov    ecx, 65535
sw_at:
    call   Tl_BeatEnv
    mov    edi, eax
    sub    edi, ebx                        ; change since the previous sample
    mov    ebx, eax
    cmp    esi, 32768
    ja     sw_rise
    test   edi, edi                        ; first half: must not rise
    jle    sw_mag
    xor    r12d, r12d
    jmp    sw_mag
sw_rise:
    test   edi, edi                        ; second half: must not fall
    jns    sw_mag
    xor    r12d, r12d
sw_mag:
    mov    eax, edi
    call   Pu_Abs
    cmp    eax, r13d
    cmova  r13d, eax
    cmp    esi, 65536
    jb     sw_lp
    mov    eax, r12d
    mov    edx, r13d
    FN_RET
FN_END Pu_ScanSwell

; ---------------------------------------------------------------------------
; Pu_Published -> eax = 1 when Tl_Update publishes the beat counter, the
; phase and the swell right: 128 beats are exactly 60 s, beat 1 begins at
; 469 ms, half a beat later the swell is gone.
; ---------------------------------------------------------------------------
FN_BEGIN Pu_Published, 0
    mov    ecx, 60000
    call   Tl_Update
    cmp    DWORD PTR gBeatNo, 128
    sete   bl
    cmp    DWORD PTR gBeat16, 0
    sete   al
    and    bl, al
    cmp    DWORD PTR gBeatEnv, 256
    sete   al
    and    bl, al
    cmp    DWORD PTR gKick, 256            ; a scene that is drawn directly sees the plain swell
    sete   al
    and    bl, al
    mov    ecx, 468
    call   Tl_Update
    cmp    DWORD PTR gBeatNo, 0
    sete   al
    and    bl, al
    mov    ecx, 469
    call   Tl_Update
    cmp    DWORD PTR gBeatNo, 1
    sete   al
    and    bl, al
    mov    ecx, 234
    call   Tl_Update
    cmp    DWORD PTR gBeatEnv, 2
    setbe  al
    and    bl, al
    movzx  eax, bl
    FN_RET
FN_END Pu_Published

; ---------------------------------------------------------------------------
; Pu_Frame -> eax = 1 when Demo_Render itself publishes the beat state of its
; time (time, beat counter, phase, swell) before it draws.
; ---------------------------------------------------------------------------
FN_BEGIN Pu_Frame, 0
    mov    DWORD PTR gTimeMs, 0
    mov    DWORD PTR gBeatNo, 0
    mov    DWORD PTR gBeat16, 5
    mov    DWORD PTR gBeatEnv, 0
    mov    ecx, PU_FLY_MS                  ; four beats: on the beat
    call   Demo_Render
    cmp    DWORD PTR gTimeMs, PU_FLY_MS
    sete   bl
    cmp    DWORD PTR gBeatNo, 4
    sete   al
    and    bl, al
    cmp    DWORD PTR gBeat16, 0
    sete   al
    and    bl, al
    cmp    DWORD PTR gBeatEnv, 256
    sete   al
    and    bl, al
    movzx  eax, bl
    FN_RET
FN_END Pu_Frame

; ---------------------------------------------------------------------------
; Pu_Continuity -> eax = 1 when the published swell moves by at most
; PU_STEP_MAX per millisecond over PU_SCAN_MS and reaches both ends.
; ---------------------------------------------------------------------------
FN_BEGIN Pu_Continuity, 0
    xor    ecx, ecx
    call   Tl_Update
    mov    ebx, DWORD PTR gBeatEnv         ; the previous sample
    mov    r12d, ebx                       ; highest
    mov    r13d, ebx                       ; lowest
    xor    r14d, r14d                      ; biggest change
    mov    esi, 1
ct_lp:
    mov    ecx, esi
    call   Tl_Update
    mov    edi, DWORD PTR gBeatEnv
    mov    eax, edi
    sub    eax, ebx
    mov    ebx, edi
    call   Pu_Abs
    cmp    eax, r14d
    cmova  r14d, eax
    cmp    edi, r12d
    cmova  r12d, edi
    cmp    edi, r13d
    cmovb  r13d, edi
    inc    esi
    cmp    esi, PU_SCAN_MS
    jbe    ct_lp
    cmp    r14d, PU_STEP_MAX
    setbe  al
    cmp    r12d, 250
    setae  cl
    and    al, cl
    cmp    r13d, 5
    setbe  cl
    and    al, cl
    movzx  eax, al
    FN_RET
FN_END Pu_Continuity

; ---------------------------------------------------------------------------
; Pu_Table -> eax = 1 when no depth is above PU_MAX_DEPTH, the last scene (the
; landscape) is steady and at least six scenes pulse.
; ---------------------------------------------------------------------------
FN_BEGIN Pu_Table, 0
    lea    rsi, scenePulse
    mov    r12d, 1
    xor    r13d, r13d                      ; scenes that pulse
    xor    ebx, ebx
tt_lp:
    mov    eax, DWORD PTR [rsi+rbx*4]
    cmp    eax, PU_MAX_DEPTH
    seta   cl
    movzx  ecx, cl
    xor    ecx, 1
    and    r12d, ecx
    test   eax, eax
    setnz  cl
    movzx  ecx, cl
    add    r13d, ecx
    inc    ebx
    cmp    ebx, NUM_SCENES
    jb     tt_lp
    xor    eax, eax
    cmp    DWORD PTR [rsi+(NUM_SCENES - 1) * 4], 0
    sete   al
    and    eax, r12d
    cmp    r13d, 6
    setae  cl
    movzx  ecx, cl
    and    eax, ecx
    FN_RET
FN_END Pu_Table

; ---------------------------------------------------------------------------
; Pu_Product -> eax = 1 when Tl_ScenePulse(scene, 0) is depth * swell / 256
; for every scene and three swells.
; ---------------------------------------------------------------------------
FN_BEGIN Pu_Product, 0
    mov    r12d, 1
    xor    esi, esi                        ; index of the swell
pm_sw:
    lea    rax, puSwells
    mov    edi, DWORD PTR [rax+rsi*4]
    mov    DWORD PTR gBeatEnv, edi
    xor    ebx, ebx                        ; scene
pm_sc:
    mov    ecx, ebx
    xor    edx, edx
    call   Tl_ScenePulse
    lea    rcx, scenePulse
    mov    edx, DWORD PTR [rcx+rbx*4]
    imul   edx, edi
    shr    edx, 8
    cmp    eax, edx
    sete   al
    movzx  eax, al
    and    r12d, eax
    inc    ebx
    cmp    ebx, NUM_SCENES
    jb     pm_sc
    inc    esi
    cmp    esi, PU_SWELLS
    jb     pm_sw
    mov    eax, r12d
    FN_RET
FN_END Pu_Product

; ---------------------------------------------------------------------------
; Pu_CrossFade -> eax = 1 when Tl_ScenePulse(scene, blend) is the depth of the
; scene plus blend / 256 of the way to the depth of the next one (times the
; swell), for the scenes 0..7 and five blends.  The swell is pinned at 255
; and not at 256 on purpose: with 256 the wrap of a 32-bit product hides a
; logical shift of a falling depth (2^24 * 256 = 2^32), as it did in the
; "cross-fade rounds up" mutant.
; ---------------------------------------------------------------------------
FN_BEGIN Pu_CrossFade, 0
    mov    r12d, 1
    mov    DWORD PTR gBeatEnv, PU_FADE_SWELL
    lea    rsi, scenePulse
    xor    ebx, ebx                        ; scene
cf_sc:
    xor    edi, edi                        ; index of the blend
cf_bl:
    lea    rax, puBlends
    mov    r13d, DWORD PTR [rax+rdi*4]
    mov    ecx, ebx
    mov    edx, r13d
    call   Tl_ScenePulse
    mov    r8d, DWORD PTR [rsi+rbx*4+4]    ; the next depth
    sub    r8d, DWORD PTR [rsi+rbx*4]
    imul   r8d, r13d
    sar    r8d, 8
    add    r8d, DWORD PTR [rsi+rbx*4]      ; the cross-faded depth
    imul   r8d, PU_FADE_SWELL
    shr    r8d, 8                          ; expected
    cmp    eax, r8d
    sete   al
    movzx  eax, al
    and    r12d, eax
    inc    edi
    cmp    edi, PU_BLENDS
    jb     cf_bl
    inc    ebx
    cmp    ebx, NUM_SCENES - 1
    jb     cf_sc
    mov    eax, r12d
    FN_RET
FN_END Pu_CrossFade

; ---------------------------------------------------------------------------
; Pu_LastScene -> eax = 1 when the last scene keeps its own depth at every
; blend.  The table is given a depth of PU_LAST_DEPTH for the check (the real
; one is 0, which the memory behind the table might happen to be, too).
; ---------------------------------------------------------------------------
FN_BEGIN Pu_LastScene, 0
    lea    rsi, scenePulse
    mov    eax, DWORD PTR [rsi+(NUM_SCENES - 1) * 4]
    mov    DWORD PTR puDepth, eax
    mov    DWORD PTR [rsi+(NUM_SCENES - 1) * 4], PU_LAST_DEPTH
    mov    DWORD PTR gBeatEnv, 256
    mov    r12d, 1
    xor    edi, edi
ls_bl:
    lea    rax, puBlends
    mov    edx, DWORD PTR [rax+rdi*4]
    mov    ecx, NUM_SCENES - 1
    call   Tl_ScenePulse
    cmp    eax, PU_LAST_DEPTH
    sete   al
    movzx  eax, al
    and    r12d, eax
    inc    edi
    cmp    edi, PU_BLENDS
    jb     ls_bl
    lea    rsi, scenePulse
    mov    eax, DWORD PTR puDepth
    mov    DWORD PTR [rsi+(NUM_SCENES - 1) * 4], eax
    mov    eax, r12d
    FN_RET
FN_END Pu_LastScene

; ---------------------------------------------------------------------------
; Pu_BloomPump -> eax = 1 when, after Tl_Compose, gKick (what the bloom of the
; frame pumped with) is the pulse of the scene on the screen: its own depth in
; a plain frame of WARP and of the landscape, the cross-faded depth halfway
; through the transition from WARP into MERCURY.
; ---------------------------------------------------------------------------
FN_BEGIN Pu_BloomPump, 0
    mov    r12d, 1
    mov    ebx, 3 * SCENE_MS + PU_LT       ; WARP
    xor    esi, esi                        ; its blend
    mov    edi, 3
    call   Pu_Pump
    and    r12d, eax
    mov    ebx, (NUM_SCENES - 1) * SCENE_MS + PU_LT
    xor    esi, esi
    mov    edi, NUM_SCENES - 1
    call   Pu_Pump
    and    r12d, eax
    mov    ebx, 3 * SCENE_MS + (SCENE_MS - TRANS_MS) + TRANS_MS / 2
    mov    esi, 128
    mov    edi, 3
    call   Pu_Pump
    and    r12d, eax
    mov    eax, r12d
    FN_RET
FN_END Pu_BloomPump

; Pu_Pump(ebx = demo time, esi = blend there, edi = scene on the screen) -> eax = 1
; when gKick after the composition is the pulse of (scene, blend) at the swell 256.
FN_BEGIN Pu_Pump, 0
    mov    ecx, ebx
    call   Tl_Update
    mov    DWORD PTR gBeatEnv, 256
    mov    ecx, ebx
    call   Tl_Compose
    mov    ecx, edi
    mov    edx, esi
    call   Tl_ScenePulse
    cmp    eax, DWORD PTR gKick
    sete   al
    movzx  eax, al
    FN_RET
FN_END Pu_Pump

; ---------------------------------------------------------------------------
; Pu_Fly -> eax = the shortest, edx = the longest distance the tunnel camera
; covers in PU_FLY_DT ms, over four beats.
; ---------------------------------------------------------------------------
FN_BEGIN Pu_Fly, 0
    xor    esi, esi                        ; time
    mov    ebx, -1                         ; previous position (none yet)
    mov    r12d, 7FFFFFFFh                 ; shortest
    xor    r13d, r13d                      ; longest
fl_lp:
    mov    ecx, esi
    call   Tl_Update
    mov    ecx, esi
    call   Tun_Travel
    cmp    ebx, -1
    je     fl_first
    mov    edx, eax
    sub    edx, ebx
    cmp    edx, r12d
    cmovl  r12d, edx
    cmp    edx, r13d
    cmovg  r13d, edx
fl_first:
    mov    ebx, eax
    add    esi, PU_FLY_DT
    cmp    esi, PU_FLY_MS
    jb     fl_lp
    mov    eax, r12d
    mov    edx, r13d
    FN_RET
FN_END Pu_Fly

; ---------------------------------------------------------------------------
; Pu_Distance -> eax = the distance the tunnel camera covers from t = 0 to
; four beats later (both on the beat, where the speed swell is zero).
; ---------------------------------------------------------------------------
FN_BEGIN Pu_Distance, 0
    xor    ecx, ecx
    call   Tl_Update
    xor    ecx, ecx
    call   Tun_Travel
    mov    ebx, eax
    mov    ecx, PU_FLY_MS
    call   Tl_Update
    mov    ecx, PU_FLY_MS
    call   Tun_Travel
    sub    eax, ebx
    FN_RET
FN_END Pu_Distance

; ---------------------------------------------------------------------------
; Pu_Run(ecx = t) -> eax = the distance the tunnel camera covers from t to
; t + PU_FLY_DT ms.
; ---------------------------------------------------------------------------
FN_BEGIN Pu_Run, 0
    mov    ebx, ecx
    call   Tl_Update
    mov    ecx, ebx
    call   Tun_Travel
    mov    esi, eax
    lea    ecx, [rbx+PU_FLY_DT]
    call   Tl_Update
    lea    ecx, [rbx+PU_FLY_DT]
    call   Tun_Travel
    sub    eax, esi
    FN_RET
FN_END Pu_Run

; ---------------------------------------------------------------------------
; Pu_Surge -> eax = 1 when the camera covers at least PU_SURGE_MIN units more
; around the fourth beat than around the middle of the beat after it.
; ---------------------------------------------------------------------------
FN_BEGIN Pu_Surge, 0
    mov    ecx, PU_FLY_MS - PU_FLY_DT / 2
    call   Pu_Run
    mov    ebx, eax                        ; around the beat
    mov    ecx, PU_FLY_MS + PU_HALF_BEAT - PU_FLY_DT / 2
    call   Pu_Run
    sub    ebx, eax
    xor    eax, eax
    cmp    ebx, PU_SURGE_MIN
    setge  al
    FN_RET
FN_END Pu_Surge

; ---------------------------------------------------------------------------
; Pu_SumRgb(rcx = frame) -> rax = sum of the blue, green and red bytes of a
; 640x360 frame (the fourth byte of a pixel is not counted).
; ---------------------------------------------------------------------------
LEAF_BEGIN Pu_SumRgb
    movdqa xmm3, XMMWORD PTR puRgbMask
    pxor   xmm1, xmm1
    pxor   xmm2, xmm2
    mov    eax, SCR_BYTES / 16
sr_lp:
    movdqa xmm0, XMMWORD PTR [rcx]
    pand   xmm0, xmm3
    psadbw xmm0, xmm1
    paddq  xmm2, xmm0
    add    rcx, 16
    dec    eax
    jnz    sr_lp
    movhlps xmm0, xmm2
    paddq  xmm2, xmm0
    movq   rax, xmm2
    ret
LEAF_END Pu_SumRgb

; ---------------------------------------------------------------------------
; Pu_Sad(rcx = frame a, rdx = frame b) -> rax = sum of the absolute differences
; of all their bytes.
; ---------------------------------------------------------------------------
LEAF_BEGIN Pu_Sad
    pxor   xmm2, xmm2
    mov    eax, SCR_BYTES / 16
sd_lp:
    movdqa xmm0, XMMWORD PTR [rcx]
    psadbw xmm0, XMMWORD PTR [rdx]
    paddq  xmm2, xmm0
    add    rcx, 16
    add    rdx, 16
    dec    eax
    jnz    sd_lp
    movhlps xmm0, xmm2
    paddq  xmm2, xmm0
    movq   rax, xmm2
    ret
LEAF_END Pu_Sad

; ---------------------------------------------------------------------------
; Pu_Mad(rcx = frame a, rdx = frame b) -> eax = mean absolute difference per
; colour channel, in 1/100 level.
; ---------------------------------------------------------------------------
FN_BEGIN Pu_Mad, 0
    call   Pu_Sad
    imul   rax, rax, 100
    xor    edx, edx
    mov    ecx, SCR_PIX * 3
    div    rcx
    FN_RET
FN_END Pu_Mad

; ---------------------------------------------------------------------------
; Pu_Shot(ecx = scene, edx = swell, r8d = phase or -1) - the scene at PU_LT,
; drawn by the real frame code with the swell pinned (and the phase inside the
; beat, unless it is -1): the 640x360 picture ends up in gFbC.
; ---------------------------------------------------------------------------
FN_BEGIN Pu_Shot, 0
    mov    ebx, edx
    mov    r13d, r8d
    imul   r12d, ecx, SCENE_MS
    add    r12d, PU_LT
    mov    ecx, r12d
    call   Tl_Update
    mov    DWORD PTR gBeatEnv, ebx
    cmp    r13d, -1
    je     ps_draw
    mov    DWORD PTR gBeat16, r13d
ps_draw:
    mov    ecx, r12d
    call   Demo_Frame
    FN_RET
FN_END Pu_Shot

; ---------------------------------------------------------------------------
; Pu_Scene(ecx = scene) -> eax = change of the mean brightness in per mille,
; edx = mean absolute difference per colour channel in 1/100 level between the
; picture on the beat (swell 256) and half a beat away (swell 0).
; ---------------------------------------------------------------------------
FN_BEGIN Pu_Scene, 0
    mov    r12d, ecx
    xor    edx, edx
    mov    r8d, -1
    call   Pu_Shot
    mov    rcx, QWORD PTR gFbC
    call   Pu_SumRgb
    mov    r13, rax                        ; brightness at rest
    mov    rcx, QWORD PTR gFbA
    mov    rdx, QWORD PTR gFbC
    call   Gfx_Copy                        ; keep that picture
    mov    ecx, r12d
    mov    edx, 256
    mov    r8d, -1
    call   Pu_Shot
    mov    rcx, QWORD PTR gFbC
    call   Pu_SumRgb
    sub    rax, r13
    cqo
    xor    rax, rdx
    sub    rax, rdx                        ; |change of the sum|
    imul   rax, rax, 1000
    xor    edx, edx
    div    r13
    mov    r14d, eax                       ; per mille of the brightness at rest
    mov    rcx, QWORD PTR gFbA
    mov    rdx, QWORD PTR gFbC
    call   Pu_Mad
    mov    edx, eax
    mov    eax, r14d
    FN_RET
FN_END Pu_Scene

; ---------------------------------------------------------------------------
; Pu_TunnelFollows -> eax = 1 when the picture of the tunnel changes by at
; least PU_TRAVEL_MIN between the beat and a quarter of a beat later (the
; swell pinned to 0): the renderer really flies where Tun_Travel says.
; ---------------------------------------------------------------------------
FN_BEGIN Pu_TunnelFollows, 0
    mov    ecx, 2
    xor    edx, edx
    xor    r8d, r8d
    call   Pu_Shot
    mov    rcx, QWORD PTR gFbA
    mov    rdx, QWORD PTR gFbC
    call   Gfx_Copy
    mov    ecx, 2
    xor    edx, edx
    mov    r8d, 16384
    call   Pu_Shot
    mov    rcx, QWORD PTR gFbA
    mov    rdx, QWORD PTR gFbC
    call   Pu_Mad
    xor    edx, edx
    cmp    eax, PU_TRAVEL_MIN
    setae  dl
    mov    eax, edx
    FN_RET
FN_END Pu_TunnelFollows

; ---------------------------------------------------------------------------
; Pu_Pictures - one check per scene: the mean difference lies between the
; scene's least and most, and the brightness changes by at most its per mille.
; ---------------------------------------------------------------------------
FN_BEGIN Pu_Pictures, 0
    xor    ebx, ebx
pp_lp:
    mov    ecx, ebx
    call   Pu_Scene
    mov    esi, eax                        ; brightness change, per mille
    mov    edi, edx                        ; mean difference, 1/100 level
    lea    rax, puLimits
    lea    ecx, [rbx+rbx*2]
    lea    r12, [rax+rcx*4]                ; the row of this scene
    xor    r13d, r13d
    cmp    edi, DWORD PTR [r12]            ; at least the least ...
    setae  r13b
    cmp    edi, DWORD PTR [r12+4]          ; ... at most the most ...
    setbe  al
    and    r13b, al
    cmp    esi, DWORD PTR [r12+8]          ; ... and the brightness within its limit
    setbe  al
    and    r13b, al
    mov    ecx, ebx
    lea    rdx, szPuPic
    call   St_NameScene
    mov    rcx, rax
    movzx  edx, r13b
    call   St_Report
    lea    rcx, szPuInfoA                  ; what was measured (for tuning scenePulse)
    call   Sys_Print
    lea    rax, scenePulse
    mov    ecx, DWORD PTR [rax+rbx*4]
    call   Sys_PrintInt
    lea    rcx, szPuInfoB
    call   Sys_Print
    mov    ecx, esi
    call   Sys_PrintInt
    lea    rcx, szPuInfoC
    call   Sys_Print
    mov    ecx, edi
    call   Sys_PrintInt
    lea    rcx, szPuInfoD
    call   Sys_PrintLn
    inc    ebx
    cmp    ebx, NUM_SCENES
    jb     pp_lp
    FN_RET
FN_END Pu_Pictures

; Reports the result of a check function (eax = 1 when it passed).
PUCHECK MACRO fn:REQ, label:REQ
    call   fn
    mov    edx, eax
    lea    rcx, label
    call   St_Report
ENDM

; ---------------------------------------------------------------------------
; St_Pulse - all checks of the soft image pulse.
; ---------------------------------------------------------------------------
FN_BEGIN St_Pulse, 0
    PUCHECK Pu_Shape, szPuShape
    PUCHECK Pu_Symmetry, szPuSym
    call   Pu_ScanSwell
    mov    esi, edx
    mov    edx, eax
    lea    rcx, szPuMono
    call   St_Report
    xor    edx, edx
    cmp    esi, PU_MAXSTEP
    setbe  dl
    lea    rcx, szPuStep
    call   St_Report
    PUCHECK Pu_Published, szPuPub
    PUCHECK Pu_Continuity, szPuCont
    PUCHECK Pu_Table, szPuTab
    PUCHECK Pu_Product, szPuMul
    PUCHECK Pu_CrossFade, szPuFade
    PUCHECK Pu_LastScene, szPuLast
    ; From here on frames are drawn.  A pulse beyond 256 sends the scenes off their tables and crashes the
    ; exe, so the checks that only count come first: such a mistake is reported as a FAIL, not as a crash.
    PUCHECK Pu_Frame, szPuFrame
    PUCHECK Pu_BloomPump, szPuBloom
    call   Pu_Fly
    mov    esi, edx
    xor    edx, edx
    cmp    eax, PU_FLY_MIN
    setge  dl
    xor    ecx, ecx
    cmp    esi, PU_FLY_MAX
    setle  cl
    and    edx, ecx
    lea    rcx, szPuFly
    call   St_Report
    call   Pu_Distance
    sub    eax, PU_FLY_SUM
    call   Pu_Abs
    xor    edx, edx
    cmp    eax, 2
    setbe  dl
    lea    rcx, szPuDist
    call   St_Report
    PUCHECK Pu_Surge, szPuSurge
    PUCHECK Pu_TunnelFollows, szPuFollow
    call   Pu_Pictures
    FN_RET
FN_END St_Pulse

END
