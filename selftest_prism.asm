; ============================================================================
; selftest_prism.asm - built-in checks of the PRISM scene (part of
;                      SiliconDreams.exe /selftest and /selftest g3).
; ----------------------------------------------------------------------------
; The reference numbers come from an independent implementation of the same
; show (the numpy prototype the choreography was designed in):
;   * placement of 20 solids at chosen moments: size, position in view space
;     and the whole orientation matrix (hidden solids included: before their
;     birth, when they are tiny and when the camera is about to run into
;     them; the one that is half faded out by the near fade included too),
;   * the kick swells the solids by exactly 5 %,
;   * before the first solid is born the frame is the bare backdrop (a frame
;     in which nothing is drawn is returned by the resolve unchanged),
;   * the backdrop turns with time and pulses with the kick,
;   * twelve cells of the backdrop (at four moments, with three kick values,
;     on a ray, between two rays and half way) against the formula of the
;     prototype: base, glow, rays, spectrum, turning speeds and the kick,
;   * six frames: the number of pixels that differ from the backdrop (within
;     0.5 %; the real difference is below 0.02 %) and the mean colour (within
;     half a level of 255) agree with the prototype, which uses a different
;     rasteriser and double precision,
;   * rendering all of that never touched the guard bytes around the targets.
; ============================================================================
INCLUDE common.inc
INCLUDE g3.inc
INCLUDE prism.inc

PT_ROWS    EQU 20
PT_FRAMES  EQU 6
PT_BGN     EQU 12
PT_PIX     EQU SCR_PIX

.const
ALIGN 16
kPtAbs      DWORD 7FFFFFFFh, 7FFFFFFFh, 7FFFFFFFh, 7FFFFFFFh
kPtTol4     REAL4 0.001, 0.001, 0.001, 0.001
kPtPix      REAL4 230400.0
kPtMeanTol  REAL4 0.5                       ; levels (0 .. 255)
kPtKickS    REAL4 1.05
kPtEps      REAL4 0.001

; Pairs of offsets (row, XFORM) of the five vectors compared: t, s, c0, c1, c2.
ptPairs     DWORD 16, 48, 32, 64, 48, 0, 64, 16, 80, 32

; object, ms, visible, 0 | t | s in every lane | c0 | c1 | c2     (96 bytes)
ALIGN 16
ptRows      DWORD 0, 0, 0, 0              ; knot at 0.0 s: not visible
            REAL4 20 DUP (0.0)
            DWORD 0, 1000, 1, 0              ; knot at 1.0 s
            REAL4 0.000000, 0.000000, 12.500000, 0.0
            REAL4 1.067832, 1.067832, 1.067832, 1.067832
            REAL4 0.912464, 0.070874, -0.402973, 0.0, 0.222706, 0.740178, 0.634460, 0.0, 0.343238, -0.668666, 0.659601, 0.0
            DWORD 0, 6000, 1, 0              ; knot at 6.0 s
            REAL4 0.000000, 0.000000, 12.500000, 0.0
            REAL4 1.000000, 1.000000, 1.000000, 1.000000
            REAL4 -0.555556, -0.210582, -0.804371, 0.0, 0.637100, 0.513814, -0.574542, 0.0, 0.534285, -0.831655, -0.151291, 0.0
            DWORD 1, 2000, 0, 0              ; gold1 at 2.0 s: not visible
            REAL4 20 DUP (0.0)
            DWORD 1, 5500, 1, 0              ; gold1 at 5.5 s
            REAL4 -0.519856, -1.465511, 16.829206, 0.0
            REAL4 0.620000, 0.620000, 0.620000, 0.620000
            REAL4 0.986389, 0.000000, -0.164430, 0.0, 0.000000, 1.000000, 0.000000, 0.0, 0.164430, 0.000000, 0.986389, 0.0
            DWORD 2, 3900, 1, 0              ; teal1 at 3.9 s
            REAL4 -1.004107, 3.155978, 16.111311, 0.0
            REAL4 0.453566, 0.453566, 0.453566, 0.453566
            REAL4 0.982465, 0.000000, -0.186446, 0.0, 0.000000, 1.000000, 0.000000, 0.0, 0.186446, 0.000000, 0.982465, 0.0
            DWORD 3, 7000, 1, 0              ; ring at 7.0 s
            REAL4 0.000000, 0.000000, 12.500000, 0.0
            REAL4 3.400000, 3.400000, 3.400000, 3.400000
            REAL4 -0.173796, -0.166958, -0.970526, 0.0, 0.193029, 0.960630, -0.199822, 0.0, 0.965678, -0.222068, -0.134726, 0.0
            DWORD 4, 10000, 1, 0              ; cubeA at 10.0 s
            REAL4 -6.061866, -0.592047, 13.658990, 0.0
            REAL4 0.565965, 0.565965, 0.565965, 0.565965
            REAL4 -0.200063, 0.293893, 0.934667, 0.0, 0.945225, 0.309017, 0.105157, 0.0, -0.257923, 0.904508, -0.339617, 0.0
            DWORD 5, 12000, 1, 0              ; cubeB at 12.0 s
            REAL4 5.031829, 1.371667, 9.147505, 0.0
            REAL4 0.550000, 0.550000, 0.550000, 0.550000
            REAL4 -0.652629, 0.746306, 0.130776, 0.0, -0.212628, -0.014734, -0.977022, 0.0, -0.727231, -0.665440, 0.168302, 0.0
            DWORD 6, 14000, 1, 0              ; cubeC at 14.0 s
            REAL4 -3.305118, -2.264183, 18.186937, 0.0
            REAL4 0.633179, 0.633179, 0.633179, 0.633179
            REAL4 -0.406869, 0.162249, -0.898962, 0.0, -0.835717, -0.463453, 0.294598, 0.0, -0.368828, 0.871141, 0.324159, 0.0
            DWORD 7, 9000, 1, 0              ; glass at 9.0 s
            REAL4 0.000000, 0.000000, 12.500000, 0.0
            REAL4 4.303576, 4.303576, 4.303576, 4.303576
            REAL4 -0.935531, 0.000000, -0.353244, 0.0, 0.350458, -0.125333, -0.928154, 0.0, -0.044273, -0.992115, 0.117253, 0.0
            DWORD 7, 15500, 1, 0              ; glass at 15.5 s
            REAL4 0.000000, 0.000000, 10.246806, 0.0
            REAL4 5.622299, 5.622299, 5.622299, 5.622299
            REAL4 0.048628, 0.992332, -0.113632, 0.0, 0.328103, -0.123324, -0.936557, 0.0, -0.943389, 0.008260, -0.331584, 0.0
            DWORD 3, 16000, 1, 0              ; ring at 16.0 s
            REAL4 0.000000, 0.000000, 10.022291, 0.0
            REAL4 4.916358, 4.916358, 4.916358, 4.916358
            REAL4 -0.330723, -0.862093, 0.383951, 0.0, -0.829848, 0.071914, -0.553336, 0.0, 0.449416, -0.501622, -0.739189, 0.0
            DWORD 4, 16200, 0, 0              ; cubeA at 16.2 s: not visible
            REAL4 20 DUP (0.0)
            DWORD 1, 14500, 1, 0              ; gold1 at 14.5 s
            REAL4 5.816634, -0.287619, 8.629843, 0.0
            REAL4 0.771113, 0.771113, 0.771113, 0.771113
            REAL4 0.789268, 0.446940, -0.421070, 0.0, -0.271422, 0.869031, 0.413661, 0.0, 0.550805, -0.212202, 0.807208, 0.0
            DWORD 0, 100, 1, 0              ; knot at 0.1 s: tiny, but visible
            REAL4 0.000000, 0.000000, 12.500000, 0.0
            REAL4 0.200732, 0.200732, 0.200732, 0.200732
            REAL4 0.999104, 0.007535, -0.041650, 0.0, 0.018882, 0.801324, 0.597932, 0.0, 0.037880, -0.598183, 0.800464, 0.0
            DWORD 1, 3150, 1, 0              ; gold1 at 3.15 s: half grown
            REAL4 3.439511, -2.178108, 14.641403, 0.0
            REAL4 0.353576, 0.353576, 0.353576, 0.353576
            REAL4 0.984758, 0.000000, -0.173930, 0.0, 0.000000, 1.000000, 0.000000, 0.0, 0.173930, 0.000000, 0.984758, 0.0
            DWORD 2, 3650, 1, 0              ; teal1 at 3.65 s: tiny
            REAL4 -1.383423, 3.057103, 16.070751, 0.0
            REAL4 0.109704, 0.109704, 0.109704, 0.109704
            REAL4 0.982949, 0.000000, -0.183879, 0.0, 0.000000, 1.000000, 0.000000, 0.0, 0.183879, 0.000000, 0.982949, 0.0
            DWORD 4, 15000, 1, 0              ; cubeA at 15.0 s: 2.25 from the camera, inside the near fade
            REAL4 -3.365905, 2.592239, 2.246379, 0.0
            REAL4 0.499433, 0.499433, 0.499433, 0.499433
            REAL4 0.575822, 0.434897, -0.692310, 0.0, 0.813142, -0.392705, 0.429632, 0.0, -0.085028, -0.810338, -0.579761, 0.0
            DWORD 4, 15400, 1, 0              ; cubeA at 15.4 s: 1.15 from the camera, size 0.0116 (the limit is 0.01)
            REAL4 -2.719452, 2.891867, 1.145574, 0.0
            REAL4 0.011588, 0.011588, 0.011588, 0.011588
            REAL4 0.370799, 0.904437, -0.210956, 0.0, 0.928711, -0.360594, 0.086420, 0.0, 0.002092, -0.227962, -0.973668, 0.0

; ms, pixels that differ from the backdrop | mean R, G, B (prototype, kick = 0)
ptFrames    DWORD 2000, 27292, 0, 0
            REAL4 20.72, 21.56, 44.80, 0.0
            DWORD 6000, 32743, 0, 0
            REAL4 25.46, 22.63, 40.27, 0.0
            DWORD 9500, 74998, 0, 0
            REAL4 49.64, 43.95, 63.86, 0.0
            DWORD 13000, 94572, 0, 0
            REAL4 53.18, 49.89, 65.06, 0.0
            DWORD 15000, 159831, 0, 0
            REAL4 79.65, 68.86, 90.54, 0.0
            DWORD 15500, 179129, 0, 0
            REAL4 92.40, 78.93, 98.67, 0.0

; ms, kick (0 .. 256), cell (y * 320 + x) of the half-size backdrop, 0x00RRGGBB of the prototype's
; backdrop at the centre of that cell with the rays scaled by 1 + kick / 512 (within 4 levels):
; a cell on a ray, one half way up its side and one between two rays (only the dark base and the glow)
ptBgRows    DWORD     0,   0, 24522, 0533242h      ; cell (202,  76)
            DWORD     0,   0, 28197, 00B233Ch      ; cell ( 37,  88)
            DWORD     0,   0, 24390, 00F0C2Eh      ; cell ( 70,  76)
            DWORD  4000,   0, 36939, 0173579h      ; cell (139, 115)
            DWORD  4000,   0, 38037, 022093Dh      ; cell (277, 118)
            DWORD  4000,   0, 14784, 00B0A24h      ; cell ( 64,  46)
            DWORD  9500, 256, 35073, 01C419Dh      ; cell (193, 109)
            DWORD  9500, 256, 32070, 0293C31h      ; cell ( 70, 100)
            DWORD  9500, 256, 17796, 0120E36h      ; cell (196,  55)
            DWORD 13000, 128, 19689, 052107Dh      ; cell (169,  61)
            DWORD 13000, 128, 15750, 0361531h      ; cell ( 70,  49)
            DWORD 13000, 128, 43686, 0100D31h      ; cell (166, 136)

szPtPlace   BYTE "prism: placement of 20 solids matches the prototype (size, position, orientation)", 0
szPtKick    BYTE "prism: the kick swells the solids by 5 %", 0
szPtBlank   BYTE "prism: before the first solid is born the frame is the bare backdrop", 0
szPtBack    BYTE "prism: the backdrop turns with time and pulses with the kick", 0
szPtCells   BYTE "prism: 12 backdrop cells (base, glow, rays, spectrum, kick) match the prototype", 0
szPtArea    BYTE "prism: covered area of 6 frames agrees with the prototype", 0
szPtMean    BYTE "prism: mean colour of 6 frames agrees with the prototype", 0
szPtGuard   BYTE "prism: nothing is drawn outside the render targets", 0

.data?
ALIGN 16
ptXf        XFORM <>
ptFbA       DWORD PT_PIX DUP (?)
ptFbB       DWORD PT_PIX DUP (?)
ptCount     DWORD ?                       ; Pt_Stat results
ptSumB      DWORD ?
ptSumG      DWORD ?
ptSumR      DWORD ?

.code

; Pt_Cmp4(rcx = a, rdx = b) -> eax = 1 when all four floats differ by at most 0.001.
LEAF_BEGIN Pt_Cmp4
    movaps    xmm0, XMMWORD PTR [rcx]
    subps     xmm0, XMMWORD PTR [rdx]
    andps     xmm0, XMMWORD PTR kPtAbs
    cmpleps   xmm0, XMMWORD PTR kPtTol4     ; NaN compares false
    movmskps  eax, xmm0
    cmp       eax, 15
    sete      al
    movzx     eax, al
    ret
LEAF_END Pt_Cmp4

; Pt_Vectors(rsi = row) -> eax = 1 when t, s and the three columns of ptXf match the row.
FN_BEGIN Pt_Vectors, 0
    lea       rdi, ptPairs
    mov       ebx, 1
    mov       r12d, 5
pv_lp:
    mov       eax, DWORD PTR [rdi]
    lea       rcx, [rsi+rax]
    mov       eax, DWORD PTR [rdi+4]
    lea       rdx, ptXf
    add       rdx, rax
    call      Pt_Cmp4
    and       ebx, eax
    add       rdi, 8
    dec       r12d
    jnz       pv_lp
    mov       eax, ebx
    FN_RET
FN_END Pt_Vectors

; Pt_Row(rsi = row) -> eax = 1 when the solid is placed (or hidden) as the row says.
FN_BEGIN Pt_Row, 0
    mov       DWORD PTR gKick, 0
    mov       edx, DWORD PTR [rsi+4]
    call      Pz_Frame
    mov       eax, DWORD PTR [rsi]
    imul      eax, eax, SIZEOF PZOBJ
    lea       rcx, pzObjs
    add       rcx, rax
    lea       rdx, ptXf
    call      Pz_Place
    mov       ebx, eax
    cmp       eax, DWORD PTR [rsi+8]
    jne       pr_bad
    test      ebx, ebx
    jz        pr_ok                          ; hidden as expected
    call      Pt_Vectors
    FN_RET
pr_ok:
    mov       eax, 1
    FN_RET
pr_bad:
    xor       eax, eax
    FN_RET
FN_END Pt_Row

FN_BEGIN Pt_Place, 0
    lea       rsi, ptRows
    mov       edi, PT_ROWS
    mov       r12d, 1
pl_lp:
    call      Pt_Row
    and       r12d, eax
    add       rsi, 96
    dec       edi
    jnz       pl_lp
    mov       edx, r12d
    lea       rcx, szPtPlace
    call      St_Report
    FN_RET
FN_END Pt_Place

; Pt_Kick - the knot at 6 s with the kick at its maximum is 5 % larger.
FN_BEGIN Pt_Kick, 0
    mov       DWORD PTR gKick, 256
    mov       edx, 6000
    call      Pz_Frame
    lea       rcx, pzObjs
    lea       rdx, ptXf
    call      Pz_Place
    mov       ebx, eax
    movss     xmm0, DWORD PTR ptXf.s
    movss     xmm1, DWORD PTR kPtKickS
    movss     xmm2, DWORD PTR kPtEps
    call      St_Near
    and       eax, ebx
    mov       edx, eax
    mov       DWORD PTR gKick, 0
    lea       rcx, szPtKick
    call      St_Report
    FN_RET
FN_END Pt_Kick

; Pt_Render(ecx = ms) - backdrop into ptFbA and the whole scene into ptFbB (kick 0).
FN_BEGIN Pt_Render, 0
    mov       ebx, ecx
    mov       DWORD PTR gKick, 0
    lea       rcx, ptFbA
    mov       edx, ebx
    call      Pz_Backdrop
    lea       rcx, ptFbB
    mov       edx, ebx
    call      Fx_Prism_Render
    FN_RET
FN_END Pt_Render

FN_BEGIN Pt_Blank, 0
    xor       ecx, ecx
    call      Pt_Render
    lea       rcx, ptFbA
    lea       rdx, ptFbB
    call      Rq_SameFrames
    mov       edx, eax
    lea       rcx, szPtBlank
    call      St_Report
    FN_RET
FN_END Pt_Blank

; Pt_Back - the backdrop at 4 s differs from the one at 0, and the kick changes it too.
FN_BEGIN Pt_Back, 0
    lea       rcx, ptFbA
    xor       edx, edx
    mov       DWORD PTR gKick, 0
    call      Pz_Backdrop
    lea       rcx, ptFbB
    mov       edx, 4000
    call      Pz_Backdrop
    lea       rcx, ptFbA
    lea       rdx, ptFbB
    call      Rq_SameFrames
    mov       ebx, eax                       ; 1 = identical = bad
    lea       rcx, ptFbA
    mov       edx, 4000
    call      Pz_Backdrop
    mov       DWORD PTR gKick, 256
    lea       rcx, ptFbB
    mov       edx, 4000
    call      Pz_Backdrop
    mov       DWORD PTR gKick, 0
    lea       rcx, ptFbA
    lea       rdx, ptFbB
    call      Rq_SameFrames
    or        ebx, eax
    xor       edx, edx
    test      ebx, ebx
    setz      dl
    lea       rcx, szPtBack
    call      St_Report
    FN_RET
FN_END Pt_Back

; Pt_BackCells - every row of ptBgRows: draw the backdrop at that time with that kick and compare
; the cell of the half-size picture (pzHalf) with the prototype's colour (every channel within 4).
FN_BEGIN Pt_BackCells, 0
    lea       rsi, ptBgRows
    mov       edi, PT_BGN
    mov       r12d, 1
bc_lp:
    mov       eax, DWORD PTR [rsi+4]
    mov       DWORD PTR gKick, eax
    lea       rcx, ptFbA
    mov       edx, DWORD PTR [rsi]
    call      Pz_Backdrop
    mov       eax, DWORD PTR [rsi+8]
    lea       rdx, pzHalf
    mov       ecx, DWORD PTR [rdx+rax*4]
    mov       edx, DWORD PTR [rsi+12]
    call      Mt_Close
    and       r12d, eax
    add       rsi, 16
    dec       edi
    jnz       bc_lp
    mov       DWORD PTR gKick, 0
    mov       edx, r12d
    lea       rcx, szPtCells
    call      St_Report
    FN_RET
FN_END Pt_BackCells

; Pt_Stat -> eax = pixels of ptFbB that differ from ptFbA; the sums of the channels
; of ptFbB go to ptSumB / ptSumG / ptSumR.
FN_BEGIN Pt_Stat, 0
    lea       rcx, ptFbA
    lea       rdx, ptFbB
    xor       r12d, r12d
    xor       r13d, r13d
    xor       r14d, r14d
    xor       r15d, r15d
    mov       esi, PT_PIX
st_lp:
    mov       eax, DWORD PTR [rdx]
    cmp       eax, DWORD PTR [rcx]
    setne     bl
    movzx     ebx, bl
    add       r12d, ebx
    movzx     ebx, al
    add       r13d, ebx
    movzx     ebx, ah
    add       r14d, ebx
    shr       eax, 16
    movzx     ebx, al
    add       r15d, ebx
    add       rcx, 4
    add       rdx, 4
    dec       esi
    jnz       st_lp
    mov       DWORD PTR ptCount, r12d
    mov       DWORD PTR ptSumB, r13d
    mov       DWORD PTR ptSumG, r14d
    mov       DWORD PTR ptSumR, r15d
    mov       eax, r12d
    FN_RET
FN_END Pt_Stat

; Pt_MeanOk(ecx = channel sum, xmm1 = expected mean) -> eax = 1 when within half a level.
FN_BEGIN Pt_MeanOk, 0
    cvtsi2ss  xmm0, ecx
    divss     xmm0, DWORD PTR kPtPix
    movss     xmm2, DWORD PTR kPtMeanTol
    call      St_Near
    FN_RET
FN_END Pt_MeanOk

; Pt_FrameOk(rsi = row of ptFrames) -> eax bit 0 = area close (0.5 %), bit 1 = colour close.
FN_BEGIN Pt_FrameOk, 0
    mov       ecx, DWORD PTR [rsi]
    call      Pt_Render
    call      Pt_Stat
    mov       ecx, DWORD PTR [rsi+4]          ; expected count
    sub       eax, ecx
    cdq
    xor       eax, edx
    sub       eax, edx                        ; |difference|
    imul      eax, eax, 200
    xor       ebx, ebx
    cmp       eax, ecx
    setbe     bl                              ; |d| * 200 <= count: within 0.5 %
    mov       ecx, DWORD PTR ptSumR
    movss     xmm1, DWORD PTR [rsi+16]
    call      Pt_MeanOk
    mov       edi, eax
    mov       ecx, DWORD PTR ptSumG
    movss     xmm1, DWORD PTR [rsi+20]
    call      Pt_MeanOk
    and       edi, eax
    mov       ecx, DWORD PTR ptSumB
    movss     xmm1, DWORD PTR [rsi+24]
    call      Pt_MeanOk
    and       edi, eax
    lea       eax, [rbx+rdi*2]
    FN_RET
FN_END Pt_FrameOk

FN_BEGIN Pt_Frames, 0
    lea       rsi, ptFrames
    mov       r12d, PT_FRAMES
    mov       r13d, 1                         ; area
    mov       r14d, 1                         ; colour
pf_lp:
    call      Pt_FrameOk
    mov       ecx, eax
    and       ecx, 1
    and       r13d, ecx
    shr       eax, 1
    and       r14d, eax
    add       rsi, 32
    dec       r12d
    jnz       pf_lp
    mov       edx, r13d
    lea       rcx, szPtArea
    call      St_Report
    mov       edx, r14d
    lea       rcx, szPtMean
    call      St_Report
    FN_RET
FN_END Pt_Frames

FN_BEGIN Pt_Guard, 0
    mov       rcx, QWORD PTR g3Color
    call      Rq_Guard
    mov       ebx, eax
    mov       rcx, QWORD PTR g3Z
    call      Rq_Guard
    and       ebx, eax
    mov       edx, ebx
    lea       rcx, szPtGuard
    call      St_Report
    FN_RET
FN_END Pt_Guard

; ---------------------------------------------------------------------------
; St_Prism - all checks of the PRISM scene.
; ---------------------------------------------------------------------------
FN_BEGIN St_Prism, 0
    call      Pt_Place
    call      Pt_Kick
    call      Pt_Blank
    call      Pt_Back
    call      Pt_BackCells
    call      Pt_Frames
    call      Pt_Guard
    FN_RET
FN_END St_Prism

END
