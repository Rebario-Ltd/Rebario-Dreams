; ============================================================================
; selftest.asm - built-in checks (SiliconDreams.exe /selftest).
; ----------------------------------------------------------------------------
; The exit code is the number of failed checks, every check prints one line:
;   * math library and tables against known values,
;   * the random generator is deterministic,
;   * the bloom post-process (selftest_gfx.asm: calibrated profile, symmetry,
;     edges, gain, every pixel of a block counts),
;   * every scene: the picture has brightness and contrast, and rendering is a
;     pure function of time (12 consecutive frames == one jump to the same time),
;   * the soft image pulse (selftest_pulse.asm: the beat swell, the depth of
;     every scene, the steady tunnel camera, what a beat does to each picture),
;   * the credit line of the first and the last scene (selftest_sig.asm: the
;     heart, the layout of the line, where each scene draws it and when),
;   * the synthesised soundtrack: level, DC offset, fades, every scene audible.
; Nothing here needs a window or an audio device.
; ============================================================================
INCLUDE common.inc

SAMPLES_PER_FRAME EQU 2
STAT_N            EQU 43920              ; sampled pixels: 240 rows x 183 columns
SEQ_FRAMES        EQU 12
FRAME_MS          EQU 33

.const
ALIGN 16
kAbsMask    DWORD 7FFFFFFFh, 7FFFFFFFh, 7FFFFFFFh, 7FFFFFFFh
kHalfF      REAL4 0.5
kZeroF      REAL4 0.0
kOneF       REAL4 1.0
kTwoF       REAL4 2.0
kThreeF     REAL4 3.0
kEightF     REAL4 8.0
kSin05      REAL4 0.47942555
kPi4        REAL4 0.78539816
kEps        REAL4 0.0005
kEpsLoose   REAL4 0.002
kRmsLo      REAL4 3276.7                 ; 0.10 of full scale
kRmsHi      REAL4 10485.0                ; 0.32 of full scale
kFadeMax    REAL4 400.0                  ; RMS allowed in the first / last moments

szPass      BYTE "PASS  ", 0
szFail      BYTE "FAIL  ", 0
szSumA      BYTE "selftest: ", 0
szSumB      BYTE " checks, ", 0
szSumC      BYTE " failed", 0
szGrpG3     BYTE "g3", 0
szGrpPulse  BYTE "pulse", 0
szGrpSig    BYTE "sig", 0
szGrpBad    BYTE "selftest: unknown group (known: g3, pulse, sig)", 0

szSin       BYTE "math: sin(0.5)", 0
szCos       BYTE "math: cos(0)", 0
szExp2      BYTE "math: exp2(3) = 8", 0
szLog2      BYTE "math: log2(8) = 3", 0
szAtan      BYTE "math: atan2(1, 1) = pi/4", 0
szTabPeak   BYTE "tables: sine table peak and zero crossings", 0
szRngRep    BYTE "random: a seed reproduces the sequence", 0
szRngMove   BYTE "random: consecutive values differ", 0
szSfFlat    BYTE "picture has brightness and contrast", 0
szSfSeek    BYTE "same picture after a seek (pure function of time)", 0
szAuPeak    BYTE "audio: loud peak, no overflow", 0
szAuRms     BYTE "audio: RMS level between 0.10 and 0.32 of full scale", 0
szAuDc      BYTE "audio: no DC offset", 0
szAuScenes  BYTE "audio: every scene is audible", 0
szAuFade    BYTE "audio: fades in from and out to silence", 0
szAuStereo  BYTE "audio: stereo image (left differs from right)", 0

.data?
ALIGN 16
stTotal     DWORD ?
stFail      DWORD ?
stName      BYTE 128 DUP (?)
stGroup     BYTE 32 DUP (?)
stSum       QWORD ?                      ; St_Span results
stSumSq     QWORD ?
stPeak      DWORD ?
stDiff      DWORD ?                      ; frames whose channels differ
stTmp       REAL4 ?

.code

; ---------------------------------------------------------------------------
; St_Report(rcx = name, edx = 1 when the check passed) - prints and counts.
; ---------------------------------------------------------------------------
FN_BEGIN St_Report, 0
    mov    ebx, edx
    mov    rsi, rcx
    inc    stTotal
    lea    rcx, szPass
    test   ebx, ebx
    jnz    rp_print
    inc    stFail
    lea    rcx, szFail
rp_print:
    call   Sys_Print
    mov    rcx, rsi
    call   Sys_PrintLn
    FN_RET
FN_END St_Report

; St_Near(xmm0 = value, xmm1 = expected, xmm2 = tolerance) -> eax = 1 if close
; (NaN counts as a failure).
LEAF_BEGIN St_Near
    subss  xmm0, xmm1
    andps  xmm0, XMMWORD PTR kAbsMask
    comiss xmm0, xmm2
    setbe  al
    setnp  cl
    and    al, cl
    movzx  eax, al
    ret
LEAF_END St_Near

; Calls a one-argument math function and reports whether it returns `expect`.
NEARCHK MACRO fn:REQ, arg:REQ, expect:REQ, tol:REQ, label:REQ
    movss  xmm0, DWORD PTR arg
    call   fn
    movss  xmm1, DWORD PTR expect
    movss  xmm2, DWORD PTR tol
    call   St_Near
    mov    edx, eax
    lea    rcx, label
    call   St_Report
ENDM

; ---------------------------------------------------------------------------
; St_Math - the x87-backed math library and the lookup tables.
; ---------------------------------------------------------------------------
FN_BEGIN St_Math, 0
    NEARCHK Mth_Sinf, kHalfF, kSin05, kEps, szSin
    NEARCHK Mth_Cosf, kZeroF, kOneF, kEps, szCos
    NEARCHK Mth_Exp2f, kThreeF, kEightF, kEpsLoose, szExp2
    NEARCHK Mth_Log2f, kEightF, kThreeF, kEpsLoose, szLog2
    movss  xmm0, DWORD PTR kOneF
    movss  xmm1, DWORD PTR kOneF
    call   Mth_Atan2f
    movss  xmm1, DWORD PTR kPi4
    movss  xmm2, DWORD PTR kEps
    call   St_Near
    mov    edx, eax
    lea    rcx, szAtan
    call   St_Report
    lea    rax, gSinTab
    movsx  ecx, WORD PTR [rax+1024*2]      ; sin(pi/2)
    movsx  edx, WORD PTR [rax+3072*2]      ; sin(3pi/2)
    movsx  esi, WORD PTR [rax]             ; sin(0)
    movsx  edi, WORD PTR [rax+2048*2]      ; sin(pi)
    cmp    ecx, 32767
    sete   bl
    cmp    edx, -32767
    sete   cl
    and    bl, cl
    lea    eax, [rsi+1]
    cmp    eax, 2                          ; sin(0) in -1..1
    setbe  cl
    and    bl, cl
    lea    eax, [rdi+1]
    cmp    eax, 2                          ; sin(pi) in -1..1
    setbe  cl
    and    bl, cl
    movzx  edx, bl
    lea    rcx, szTabPeak
    call   St_Report
    FN_RET
FN_END St_Math

; ---------------------------------------------------------------------------
; St_Rng - xorshift generator: reproducible from a seed and not stuck.
; ---------------------------------------------------------------------------
FN_BEGIN St_Rng, 0
    mov    ecx, 12345
    call   Mth_Seed
    call   Mth_Rand
    mov    ebx, eax
    call   Mth_Rand
    mov    esi, eax
    mov    ecx, 12345
    call   Mth_Seed
    call   Mth_Rand
    cmp    eax, ebx
    sete   dil
    call   Mth_Rand
    cmp    eax, esi
    sete   al
    and    dil, al
    movzx  edx, dil
    lea    rcx, szRngRep
    call   St_Report
    xor    edx, edx
    cmp    ebx, esi
    setne  dl
    lea    rcx, szRngMove
    call   St_Report
    FN_RET
FN_END St_Rng

; ---------------------------------------------------------------------------
; St_Stats -> eax = mean luminance, edx = luminance variance of gFbOut
; (every third row, every seventh pixel).
; ---------------------------------------------------------------------------
FN_BEGIN St_Stats, 0
    mov    rsi, QWORD PTR gFbOut
    xor    r12d, r12d
    xor    r13d, r13d
    mov    r14d, OUT_H / 3
st_row:
    xor    ebx, ebx
st_col:
    mov    eax, DWORD PTR [rsi+rbx*4]
    movzx  ecx, al                         ; B
    movzx  edx, ah                         ; G
    shr    eax, 16
    movzx  eax, al                         ; R
    add    ecx, eax
    lea    ecx, [rcx+rdx*2]
    shr    ecx, 2                          ; (R + 2G + B) / 4
    add    r12, rcx
    imul   ecx, ecx
    add    r13, rcx
    add    ebx, 7
    cmp    ebx, OUT_W
    jb     st_col
    add    rsi, OUT_W * 4 * 3
    dec    r14d
    jnz    st_row
    mov    rax, r12
    xor    edx, edx
    mov    ecx, STAT_N
    div    rcx
    mov    r15, rax                        ; mean
    mov    rax, r13
    xor    edx, edx
    div    rcx
    mov    rdx, r15
    imul   rdx, rdx
    sub    rax, rdx                        ; variance = E[x^2] - mean^2
    mov    edx, eax
    mov    eax, r15d
    FN_RET
FN_END St_Stats

; St_Hash -> eax = FNV-1a of the presentation frame (gFbOut).
LEAF_BEGIN St_Hash
    mov    r8, QWORD PTR gFbOut
    mov    eax, 811C9DC5h
    mov    ecx, OUT_W * OUT_H
sh_lp:
    xor    eax, DWORD PTR [r8]
    imul   eax, eax, 16777619
    add    r8, 4
    dec    ecx
    jnz    sh_lp
    ret
LEAF_END St_Hash

; ---------------------------------------------------------------------------
; St_Seq(ecx = end time ms) -> eax = hash of the frame at that time after
; playing SEQ_FRAMES consecutive frames (the incremental path of the scenes).
; ---------------------------------------------------------------------------
FN_BEGIN St_Seq, 0
    mov    ebx, ecx
    sub    ebx, (SEQ_FRAMES - 1) * FRAME_MS
    xor    esi, esi
sq_lp:
    mov    ecx, ebx
    call   Demo_Render
    add    ebx, FRAME_MS
    inc    esi
    cmp    esi, SEQ_FRAMES
    jb     sq_lp
    call   St_Hash
    FN_RET
FN_END St_Seq

; St_NameScene(ecx = scene index 0..8, rdx = text) -> rax = "scene N: text" (N = 1..9).
LEAF_BEGIN St_NameScene
    lea    r8, stName
    mov    DWORD PTR [r8], 6E656373h       ; "scen"
    mov    WORD PTR [r8+4], 2065h          ; "e "
    add    cl, '1'
    mov    BYTE PTR [r8+6], cl
    mov    WORD PTR [r8+7], 203Ah          ; ": "
    lea    r9, [r8+9]
ns_cp:
    mov    al, BYTE PTR [rdx]
    mov    BYTE PTR [r9], al
    inc    rdx
    inc    r9
    test   al, al
    jnz    ns_cp
    mov    rax, r8
    ret
LEAF_END St_NameScene

; ---------------------------------------------------------------------------
; St_Scene(ecx = scene index) - contrast and determinism of one scene.
; ---------------------------------------------------------------------------
FN_BEGIN St_Scene, 0
    mov    r12d, ecx
    imul   ebx, ecx, SCENE_MS
    add    ebx, 6000
    mov    ecx, ebx
    call   St_Seq
    mov    r13d, eax                       ; hash of the incremental run
    call   St_Stats
    xor    ecx, ecx
    cmp    eax, 8
    setae  cl
    xor    esi, esi
    cmp    edx, 50
    setae  sil
    and    esi, ecx
    mov    ecx, r12d
    lea    rdx, szSfFlat
    call   St_NameScene
    mov    rcx, rax
    mov    edx, esi
    call   St_Report
    lea    ecx, [rbx-4000]
    call   Demo_Render                     ; a seek back inside the scene ...
    mov    ecx, ebx
    call   Demo_Render                     ; ... and forward again by a jump
    call   St_Hash
    xor    esi, esi
    cmp    eax, r13d
    sete   sil
    mov    ecx, r12d
    lea    rdx, szSfSeek
    call   St_NameScene
    mov    rcx, rax
    mov    edx, esi
    call   St_Report
    FN_RET
FN_END St_Scene

; ---------------------------------------------------------------------------
; St_Span(ecx = first frame, edx = frame count) - sum, sum of squares, peak
; and the number of frames whose channels differ, of the soundtrack.
; ---------------------------------------------------------------------------
FN_BEGIN St_Span, 0
    mov    rsi, QWORD PTR gPcm
    lea    rsi, [rsi+rcx*4]
    mov    ebx, edx
    xor    r12d, r12d                      ; sum
    xor    r13d, r13d                      ; sum of squares
    xor    r14d, r14d                      ; peak
    xor    r15d, r15d                      ; frames with L != R
sp_lp:
    movsx  rax, WORD PTR [rsi]
    movsx  rcx, WORD PTR [rsi+2]
    cmp    eax, ecx
    setne  dl
    movzx  edx, dl
    add    r15d, edx
    add    r12, rax
    add    r12, rcx
    mov    edx, eax
    imul   edx, edx
    add    r13, rdx
    mov    edx, ecx
    imul   edx, edx
    add    r13, rdx
    mov    edx, eax
    sar    edx, 31
    xor    eax, edx
    sub    eax, edx                        ; |L|
    cmp    eax, r14d
    cmova  r14d, eax
    mov    edx, ecx
    sar    edx, 31
    xor    ecx, edx
    sub    ecx, edx                        ; |R|
    cmp    ecx, r14d
    cmova  r14d, ecx
    add    rsi, 4
    dec    ebx
    jnz    sp_lp
    mov    QWORD PTR stSum, r12
    mov    QWORD PTR stSumSq, r13
    mov    DWORD PTR stPeak, r14d
    mov    DWORD PTR stDiff, r15d
    FN_RET
FN_END St_Span

; ---------------------------------------------------------------------------
; St_Rms(ecx = first frame, edx = frame count) -> xmm0 = RMS in 16-bit units.
; ---------------------------------------------------------------------------
FN_BEGIN St_Rms, 0
    mov    ebx, edx
    call   St_Span
    cvtsi2sd xmm0, QWORD PTR stSumSq
    lea    eax, [rbx+rbx]
    cvtsi2sd xmm1, rax
    divsd  xmm0, xmm1
    sqrtsd xmm0, xmm0
    cvtsd2ss xmm0, xmm0
    FN_RET
FN_END St_Rms

; ---------------------------------------------------------------------------
; St_Scenes -> eax = 1 when every 15 s scene of the soundtrack has an RMS
; above 0.03 of full scale.
; ---------------------------------------------------------------------------
FN_BEGIN St_Scenes, 0
    mov    r12d, 1
    xor    esi, esi
ss_lp:
    imul   ecx, esi, AUDIO_FRAMES / NUM_SCENES
    mov    edx, AUDIO_FRAMES / NUM_SCENES
    call   St_Rms
    mov    eax, 983                        ; 0.03 * 32767
    cvtsi2ss xmm1, eax
    comiss xmm0, xmm1
    setae  al
    movzx  eax, al
    and    r12d, eax
    inc    esi
    cmp    esi, NUM_SCENES
    jb     ss_lp
    mov    eax, r12d
    FN_RET
FN_END St_Scenes

; St_Between(xmm0 = value, xmm1 = low, xmm2 = high) -> eax = 1 if low <= value <= high.
LEAF_BEGIN St_Between
    xor    eax, eax
    comiss xmm0, xmm1
    setae  al
    comiss xmm2, xmm0
    setae  cl
    movzx  ecx, cl
    and    eax, ecx
    ret
LEAF_END St_Between

; ---------------------------------------------------------------------------
; St_AudioLevels - whole-song peak, RMS, DC offset and stereo width.
; ---------------------------------------------------------------------------
FN_BEGIN St_AudioLevels, 0
    xor    ecx, ecx
    mov    edx, AUDIO_FRAMES
    call   St_Span
    xor    edx, edx
    cmp    DWORD PTR stPeak, 16384
    setae  dl
    cmp    DWORD PTR stPeak, 32767
    setbe  al
    and    dl, al
    movzx  edx, dl
    lea    rcx, szAuPeak
    call   St_Report
    mov    rax, QWORD PTR stSum
    cqo
    xor    rax, rdx
    sub    rax, rdx                        ; |sum|
    xor    edx, edx
    cmp    rax, AUDIO_FRAMES * SAMPLES_PER_FRAME * 164
    setbe  dl                              ; |mean| <= 164 (0.5% of full scale)
    lea    rcx, szAuDc
    call   St_Report
    mov    eax, DWORD PTR stDiff
    xor    edx, edx
    cmp    eax, AUDIO_FRAMES / 2
    seta   dl
    lea    rcx, szAuStereo
    call   St_Report
    FN_RET
FN_END St_AudioLevels

; ---------------------------------------------------------------------------
; St_Audio - synthesises the soundtrack and checks it.
; ---------------------------------------------------------------------------
FN_BEGIN St_Audio, 0
    call   Aud_Render
    call   St_AudioLevels
    xor    ecx, ecx
    mov    edx, AUDIO_FRAMES
    call   St_Rms
    movss  xmm1, DWORD PTR kRmsLo
    movss  xmm2, DWORD PTR kRmsHi
    call   St_Between
    mov    edx, eax
    lea    rcx, szAuRms
    call   St_Report
    call   St_Scenes
    mov    edx, eax
    lea    rcx, szAuScenes
    call   St_Report
    xor    ecx, ecx
    mov    edx, 2205                       ; the first 50 ms
    call   St_Rms
    movss  DWORD PTR stTmp, xmm0
    mov    ecx, AUDIO_FRAMES - 4410        ; the last 100 ms
    mov    edx, 4410
    call   St_Rms
    maxss  xmm0, DWORD PTR stTmp
    movss  xmm1, DWORD PTR kFadeMax
    xor    edx, edx
    comiss xmm1, xmm0
    seta   dl
    lea    rcx, szAuFade
    call   St_Report
    call   St_Song                         ; (the buses are free again: it renders a riser of its own)
    FN_RET
FN_END St_Audio

; ---------------------------------------------------------------------------
; St_Everything - every group of checks, in the order of the report.
; ---------------------------------------------------------------------------
FN_BEGIN St_Everything, 0
    call   St_Math
    call   St_Rng
    call   St_Gfx
    call   St_G3
    xor    ebx, ebx
se_scene:
    mov    ecx, ebx
    call   St_Scene
    inc    ebx
    cmp    ebx, NUM_SCENES
    jb     se_scene
    call   St_Pulse
    call   St_Sig
    call   St_Audio
    FN_RET
FN_END St_Everything

; ---------------------------------------------------------------------------
; Diag_SelfTest(rcx = command line position after "/selftest") -> eax = number
; of failed checks.  An optional group name ("g3": the 3D renderer, "pulse":
; the soft image pulse, "sig": the credit line) runs only that group, which
; takes a fraction of the time of the whole report.
; ---------------------------------------------------------------------------
FN_BEGIN Diag_SelfTest, 0
    mov    rsi, rcx
    mov    stTotal, 0
    mov    stFail, 0
    call   Demo_Init
    mov    rcx, rsi
    lea    rdx, stGroup
    mov    r8d, 32
    call   Cmd_Next
    test   rax, rax
    jnz    dt_group
    call   St_Everything
    jmp    dt_sum
dt_group:
    lea    rcx, stGroup
    lea    rdx, szGrpG3
    call   Sys_StrEqI
    test   eax, eax
    jz     dt_pulse
    call   St_G3
    jmp    dt_sum
dt_pulse:
    lea    rcx, stGroup
    lea    rdx, szGrpPulse
    call   Sys_StrEqI
    test   eax, eax
    jz     dt_sig
    call   St_Pulse
    jmp    dt_sum
dt_sig:
    lea    rcx, stGroup
    lea    rdx, szGrpSig
    call   Sys_StrEqI
    test   eax, eax
    jz     dt_unknown
    call   St_Sig
    jmp    dt_sum
dt_unknown:
    lea    rcx, szGrpBad
    call   Sys_PrintLn
    inc    stFail
dt_sum:
    lea    rcx, szSumA
    call   Sys_Print
    mov    ecx, stTotal
    call   Sys_PrintInt
    lea    rcx, szSumB
    call   Sys_Print
    mov    ecx, stFail
    call   Sys_PrintInt
    lea    rcx, szSumC
    call   Sys_PrintLn
    mov    eax, stFail
    FN_RET
FN_END Diag_SelfTest

END
