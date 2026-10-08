; ============================================================================
; vox_terrain.asm - procedural landscape for scene 7 "TERRA".
; ----------------------------------------------------------------------------
; Everything is generated once at start-up from tileable fBm noise:
;   1. heights  : fBm -> contrast curve -> ridges -> detail, then a [1 2 1]^2
;                 blur (height unit 1/256 of a map cell, so 256 = 1.0);
;   2. shadows  : soft cast shadows of the low sun, one sweep per map row;
;   3. colours  : albedo from height / slope / noise (grass, rock, sand, snow,
;                 water depth ramp), lit by sun + sky ambient, shadows baked in;
;                 the alpha byte carries the water coverage;
;   4. packing  : every map cell stores its 2 x 2 neighbourhood (4 heights and
;                 4 colours) so that the renderer needs one 16-byte load for a
;                 bilinear colour sample and one 8-byte load for the height.
; The map wraps in both directions (512 x 512 cells).
; ============================================================================
INCLUDE common.inc

VXN         EQU 512
VXN_PIX     EQU 262144
VX_WATER    EQU 2304                     ; water level: 9.0 cells
VX_HLIM     EQU 32000                    ; keeps heights inside a signed 16-bit lane
VX_DROP     EQU 20036                    ; shadow ray drop per cell: tan(17 deg) * 65536
VX_SEED_A   EQU 7
VX_SEED_B   EQU 107
VX_SEED_C   EQU 55
VX_SEED_D   EQU 77

; Input block of Vxt_Texel.
TXL STRUCT
    hC  DWORD ?
    hL  DWORD ?
    hR  DWORD ?
    hU  DWORD ?
    hD  DWORD ?
    d1  DWORD ?                          ; colour detail 0..255
    d2  DWORD ?                          ; brightness detail 0..255
    sh  DWORD ?                          ; shadow factor 0..255 (255 = lit)
TXL ENDS

.const
ALIGN 16
kSunBGR   REAL4 0.52, 0.86, 1.25, 0.0    ; warm sun light, B G R A
kAmbBGR   REAL4 0.80, 0.52, 0.55, 0.0    ; violet sky light
k255v     REAL4 255.0, 255.0, 255.0, 255.0
kInv252   REAL4 0.003968254
kLo       REAL4 0.34
kInvSpan  REAL4 2.173913
kOne      REAL4 1.0
kZero     REAL4 0.0
kHalf     REAL4 0.5
kThree    REAL4 3.0
kHScale   REAL4 20480.0                  ; 80 cells * 256
k255f     REAL4 255.0
kR0       REAL4 0.82
kR1       REAL4 0.288
k256f     REAL4 256.0
kDetAmp   REAL4 1536.0                   ; 6 cells * 256
kInv512   REAL4 0.001953125              ; 1 / (2 * 256): height difference -> slope
kInv255   REAL4 0.003921569
kCosE     REAL4 0.9563048                ; sun elevation 17 degrees
kSinE     REAL4 0.2923717
kAmbA     REAL4 0.35
kAmbB     REAL4 0.65
kAmbK     REAL4 0.85
kWatA     REAL4 0.55
kWatB     REAL4 0.45
kModA     REAL4 0.75
kModB     REAL4 0.001984127              ; 0.5 / 252
k128f     REAL4 128.0
kA10      REAL4 10.0
kInv5     REAL4 0.2
kA48      REAL4 48.0
kInv16    REAL4 0.0625
kA60      REAL4 60.0
kInv12    REAL4 0.083333333
kS05      REAL4 0.5
kInv05    REAL4 2.0
kS08      REAL4 0.8
kInv07    REAL4 1.4285714
k07       REAL4 0.7
k08       REAL4 0.8

; water: shallow -> deep, indexed by depth
vxWaterKeys DWORD 7
            DWORD 0,     00328C9Ch
            DWORD 3277,  002E8395h
            DWORD 6554,  002C7E91h
            DWORD 16384, 00287489h
            DWORD 32768, 0023687Eh
            DWORD 49152, 001F5F73h
            DWORD 65536, 001C556Fh

.data?
ALIGN 16
vxNoiseA    BYTE VXN_PIX DUP (?)         ; large-scale fBm
ALIGN 16
vxNoiseB    BYTE VXN_PIX DUP (?)         ; height detail
ALIGN 16
vxNoiseC    BYTE VXN_PIX DUP (?)         ; colour detail 1
ALIGN 16
vxNoiseD    BYTE VXN_PIX DUP (?)         ; colour detail 2 (brightness)
ALIGN 16
vxH16       WORD VXN_PIX DUP (?)         ; heights (1/256 cell)
ALIGN 16
vxHTmp      WORD VXN_PIX DUP (?)
ALIGN 16
vxShade     BYTE VXN_PIX DUP (?)         ; 255 = fully lit
ALIGN 16
vxCol       DWORD VXN_PIX DUP (?)        ; baked BGRA, alpha = water
ALIGN 16
vxHCell     WORD VXN_PIX * 4 DUP (?)     ; h00 h10 h01 h11 per cell
ALIGN 16
vxCCell     DWORD VXN_PIX * 4 DUP (?)    ; c00 c10 c01 c11 per cell
ALIGN 16
vxCurveH    WORD 256 DUP (?)
vxCurveN    BYTE 256 DUP (?)
vxRidgeF    WORD 256 DUP (?)
vxDetOff    WORD 256 DUP (?)
vxTRockH    WORD 256 DUP (?)
vxTSandH    WORD 256 DUP (?)
vxTSnowH    WORD 256 DUP (?)
vxTRockS    WORD 256 DUP (?)
vxTSnowS    WORD 256 DUP (?)
vxWaterPal  DWORD 256 DUP (?)

.code

; ---------------------------------------------------------------------------
; Vxt_Ramp - smoothstep(clamp((x - a) * inv)).  xmm0 = x, xmm1 = a, xmm2 = inv
;   -> xmm0.  Clobbers xmm1, xmm3.
; ---------------------------------------------------------------------------
LEAF_BEGIN Vxt_Ramp
    subss xmm0, xmm1
    mulss xmm0, xmm2
    maxss xmm0, DWORD PTR kZero
    minss xmm0, DWORD PTR kOne
    movaps xmm3, xmm0
    mulss xmm3, xmm0                       ; t^2
    addss xmm0, xmm0
    movss xmm1, DWORD PTR kThree
    subss xmm1, xmm0                       ; 3 - 2t
    mulss xmm1, xmm3
    movaps xmm0, xmm1
    ret
LEAF_END Vxt_Ramp

; Stores xmm0 * scale rounded into a WORD table slot: RAMPTAB tab, a, inv, scale
; (xmm4 = x is preserved).
RAMPTAB MACRO tab:REQ, a:REQ, inv:REQ, scale:REQ
    movaps xmm0, xmm4
    movss xmm1, DWORD PTR a
    movss xmm2, DWORD PTR inv
    call Vxt_Ramp
    mulss xmm0, DWORD PTR scale
    cvtss2si eax, xmm0
    lea  rdx, tab
    mov  WORD PTR [rdx+rbx*2], ax
ENDM

; ---------------------------------------------------------------------------
; Vxt_Tables - lookup tables of the height shaping curves.
; ---------------------------------------------------------------------------
FN_BEGIN Vxt_Tables, 0
    xor  ebx, ebx
vt_lp:
    cvtsi2ss xmm0, ebx
    mulss xmm0, DWORD PTR kInv252          ; x = b / 252
    movaps xmm1, xmm0
    subss xmm1, DWORD PTR kLo
    mulss xmm1, DWORD PTR kInvSpan
    maxss xmm1, DWORD PTR kZero
    minss xmm1, DWORD PTR kOne             ; n = contrast curve input
    movaps xmm2, xmm1
    sqrtss xmm2, xmm2
    mulss xmm2, xmm1                       ; n ^ 1.5
    mulss xmm2, DWORD PTR kHScale
    cvtss2si eax, xmm2
    lea  rdx, vxCurveH
    mov  WORD PTR [rdx+rbx*2], ax
    mulss xmm1, DWORD PTR k255f
    cvtss2si eax, xmm1
    lea  rdx, vxCurveN
    mov  BYTE PTR [rdx+rbx], al
    minss xmm0, DWORD PTR kOne
    movaps xmm3, xmm0
    addss xmm3, xmm3
    subss xmm3, DWORD PTR kOne             ; 2x - 1
    xorps xmm5, xmm5
    subss xmm5, xmm3
    maxss xmm3, xmm5                       ; |2x - 1|
    movss xmm4, DWORD PTR kOne
    subss xmm4, xmm3
    mulss xmm4, xmm4                       ; ridge
    mulss xmm4, DWORD PTR kR1
    addss xmm4, DWORD PTR kR0
    mulss xmm4, DWORD PTR k256f
    cvtss2si eax, xmm4
    lea  rdx, vxRidgeF
    mov  WORD PTR [rdx+rbx*2], ax
    subss xmm0, DWORD PTR kHalf
    mulss xmm0, DWORD PTR kDetAmp
    cvtss2si eax, xmm0
    lea  rdx, vxDetOff
    mov  WORD PTR [rdx+rbx*2], ax
    inc  ebx
    cmp  ebx, 256
    jb   vt_lp
    FN_RET
FN_END Vxt_Tables

; ---------------------------------------------------------------------------
; Vxt_ColorTables - blend weights of the albedo (height in cells * 2, slope * 128).
; ---------------------------------------------------------------------------
FN_BEGIN Vxt_ColorTables, 0
    xor  ebx, ebx
ct_lp:
    cvtsi2ss xmm4, ebx
    mulss xmm4, DWORD PTR kHalf            ; height in cells
    RAMPTAB vxTRockH, kA48, kInv16, kRockMax
    RAMPTAB vxTSnowH, kA60, kInv12, k256f
    movaps xmm0, xmm4
    movss xmm1, DWORD PTR kA10
    movss xmm2, DWORD PTR kInv5
    call Vxt_Ramp
    movss xmm1, DWORD PTR kOne
    subss xmm1, xmm0
    mulss xmm1, DWORD PTR k256f            ; sand = 256 * (1 - ramp(h, 10, 15))
    cvtss2si eax, xmm1
    lea  rdx, vxTSandH
    mov  WORD PTR [rdx+rbx*2], ax
    cvtsi2ss xmm4, ebx
    mulss xmm4, DWORD PTR kInv128          ; slope
    RAMPTAB vxTRockS, kS05, kInv05, k256f
    RAMPTAB vxTSnowS, kS08, kInv07, kSnowMax
    inc  ebx
    cmp  ebx, 256
    jb   ct_lp
    FN_RET
FN_END Vxt_ColorTables

.const
ALIGN 4
kRockMax  REAL4 179.2                    ; 256 * 0.7
kSnowMax  REAL4 204.8                    ; 256 * 0.8
kInv128   REAL4 0.0078125

.code

; ---------------------------------------------------------------------------
; Vxt_Heights - fBm -> height map (vxH16), then the smoothing blur.
; ---------------------------------------------------------------------------
FN_BEGIN Vxt_Heights, 0
    lea  rcx, vxNoiseA
    mov  edx, 9
    mov  r8d, 7
    mov  r9d, 6 + (VX_SEED_A SHL 8)
    call Mth_Fbm
    lea  rcx, vxNoiseB
    mov  edx, 9
    mov  r8d, 5
    mov  r9d, 4 + (VX_SEED_B SHL 8)
    call Mth_Fbm
    lea  rsi, vxNoiseA
    lea  rdi, vxNoiseB
    lea  r8, vxH16
    lea  r9, vxCurveH
    lea  r12, vxRidgeF
    lea  r13, vxCurveN
    lea  r14, vxDetOff
    xor  ecx, ecx
hg_lp:
    movzx eax, BYTE PTR [rsi+rcx]          ; base fBm
    movzx edx, BYTE PTR [rdi+rcx]          ; detail fBm
    movzx r10d, WORD PTR [r9+rax*2]        ; contrast curve
    movzx r11d, WORD PTR [r12+rdx*2]       ; ridge factor
    imul r10d, r11d
    shr  r10d, 8
    movzx eax, BYTE PTR [r13+rax]          ; n
    lea  eax, [rax+rax*2]
    mov  r11d, 255
    cmp  eax, r11d
    cmova eax, r11d                        ; min(255, 3n)
    movsx edx, WORD PTR [r14+rdx*2]        ; detail offset
    imul edx, eax
    sar  edx, 8
    add  r10d, edx
    xor  eax, eax
    test r10d, r10d
    cmovs r10d, eax
    mov  eax, VX_HLIM
    cmp  r10d, eax
    cmova r10d, eax
    mov  WORD PTR [r8+rcx*2], r10w
    inc  ecx
    cmp  ecx, VXN_PIX
    jb   hg_lp
    FN_RET
FN_END Vxt_Heights

; ---------------------------------------------------------------------------
; Vxt_Blur - [1 2 1] x [1 2 1] smoothing with wrap-around (vxH16 in place).
; ---------------------------------------------------------------------------
FN_BEGIN Vxt_Blur, 0
    lea  rsi, vxH16
    lea  rdi, vxHTmp
    xor  r15d, r15d                        ; y
bl_hrow:
    mov  eax, r15d
    shl  eax, 10
    lea  r8, [rsi+rax]
    lea  r9, [rdi+rax]
    xor  ecx, ecx
bl_hpx:
    lea  eax, [rcx-1]
    and  eax, 511
    movzx edx, WORD PTR [r8+rax*2]
    movzx r10d, WORD PTR [r8+rcx*2]
    lea  edx, [rdx+r10*2]
    lea  eax, [rcx+1]
    and  eax, 511
    movzx r10d, WORD PTR [r8+rax*2]
    add  edx, r10d
    shr  edx, 1
    mov  WORD PTR [r9+rcx*2], dx
    inc  ecx
    cmp  ecx, VXN
    jb   bl_hpx
    inc  r15d
    cmp  r15d, VXN
    jb   bl_hrow
    xor  r15d, r15d
bl_vrow:
    lea  eax, [r15-1]
    and  eax, 511
    shl  eax, 10
    lea  r8, [rdi+rax]                     ; row above
    mov  eax, r15d
    shl  eax, 10
    lea  r9, [rdi+rax]                     ; row
    lea  r12, [rsi+rax]                    ; destination
    lea  eax, [r15+1]
    and  eax, 511
    shl  eax, 10
    lea  r10, [rdi+rax]                    ; row below
    xor  ecx, ecx
bl_vpx:
    movzx eax, WORD PTR [r8+rcx*2]
    movzx edx, WORD PTR [r9+rcx*2]
    lea  eax, [rax+rdx*2]
    movzx edx, WORD PTR [r10+rcx*2]
    add  eax, edx
    shr  eax, 3
    mov  WORD PTR [r12+rcx*2], ax
    inc  ecx
    cmp  ecx, VXN
    jb   bl_vpx
    inc  r15d
    cmp  r15d, VXN
    jb   bl_vrow
    FN_RET
FN_END Vxt_Blur

; ---------------------------------------------------------------------------
; Vxt_Shadow - soft cast shadows of a sun that shines along +x.  A ray that
; starts far to the left descends VX_DROP per cell; a cell is lit when its
; height reaches the ray (smooth 0..255 across a few cells of penumbra).
; ---------------------------------------------------------------------------
FN_BEGIN Vxt_Shadow, 0
    lea  rsi, vxH16
    lea  rdi, vxShade
    xor  r15d, r15d                        ; y
sh_row:
    mov  eax, r15d
    shl  eax, 10
    lea  r8, [rsi+rax]
    mov  eax, r15d
    shl  eax, 9
    lea  r9, [rdi+rax]
    xor  r10d, r10d                        ; ray height (1/65536 cell)
    xor  ecx, ecx
sh_prime:                                  ; first lap only primes the ray
    sub  r10d, VX_DROP
    movzx edx, WORD PTR [r8+rcx*2]
    shl  edx, 8
    cmp  r10d, edx
    cmovl r10d, edx
    inc  ecx
    cmp  ecx, VXN
    jb   sh_prime
    xor  ecx, ecx
sh_lap:
    sub  r10d, VX_DROP
    movzx edx, WORD PTR [r8+rcx*2]
    shl  edx, 8
    mov  eax, edx
    sub  eax, r10d                         ; > 0: the cell pokes out of the shadow
    imul eax, 51
    sar  eax, 16
    add  eax, 128
    xor  r11d, r11d
    test eax, eax
    cmovs eax, r11d
    mov  r11d, 255
    cmp  eax, r11d
    cmova eax, r11d
    mov  BYTE PTR [r9+rcx], al
    cmp  r10d, edx
    cmovl r10d, edx
    inc  ecx
    cmp  ecx, VXN
    jb   sh_lap
    inc  r15d
    cmp  r15d, VXN
    jb   sh_row
    FN_RET
FN_END Vxt_Shadow

; ---------------------------------------------------------------------------
; Vxt_Albedo(rcx = TXL *, edx = slope index) -> eax = 0x00RRGGBB (land colour)
; ---------------------------------------------------------------------------
FN_BEGIN Vxt_Albedo, 0
    mov  r12, rcx
    mov  r13d, edx                         ; slope index
    mov  eax, DWORD PTR [r12+TXL.hC]
    shr  eax, 7
    mov  edx, 255
    cmp  eax, edx
    cmova eax, edx
    mov  r14d, eax                         ; height index
    mov  esi, DWORD PTR [r12+TXL.d1]
    mov  eax, 0048702Ch                    ; grass (dark -> light by detail)
    mov  edx, 0080963Eh
    PIXMIX eax, edx, esi, ecx, edi
    mov  r8d, 005C504Ch                    ; rock
    mov  edx, 00806C5Ch
    PIXMIX r8d, edx, esi, ecx, edi
    lea  rcx, vxTRockS
    movzx edx, WORD PTR [rcx+r13*2]
    lea  rcx, vxTRockH
    movzx r9d, WORD PTR [rcx+r14*2]
    cmp  edx, r9d
    cmovb edx, r9d                         ; rock weight
    PIXMIX eax, r8d, edx, ecx, edi
    lea  rcx, vxTSandH
    movzx edx, WORD PTR [rcx+r14*2]
    mov  r8d, 00D8C08Ch                    ; sand
    PIXMIX eax, r8d, edx, ecx, edi
    lea  rcx, vxTSnowH
    movzx edx, WORD PTR [rcx+r14*2]
    lea  rcx, vxTSnowS
    movzx r9d, WORD PTR [rcx+r13*2]
    mov  ecx, 256
    sub  ecx, r9d
    imul edx, ecx
    shr  edx, 8                            ; snow weight
    mov  r8d, 00F8F0F4h                    ; snow
    PIXMIX eax, r8d, edx, ecx, edi
    FN_RET
FN_END Vxt_Albedo

; ---------------------------------------------------------------------------
; Vxt_Texel(rcx = TXL *) -> eax = lit BGRA colour (alpha 255 on water).
; Float stage: slope, diffuse = n.l * shadow, ambient from the normal's z.
; ---------------------------------------------------------------------------
FN_BEGIN Vxt_Texel, 16
    mov  rbx, rcx
    mov  eax, DWORD PTR [rbx+TXL.hR]
    sub  eax, DWORD PTR [rbx+TXL.hL]
    cvtsi2ss xmm0, eax
    mulss xmm0, DWORD PTR kInv512          ; gx
    mov  eax, DWORD PTR [rbx+TXL.hD]
    sub  eax, DWORD PTR [rbx+TXL.hU]
    cvtsi2ss xmm1, eax
    mulss xmm1, DWORD PTR kInv512          ; gy
    mulss xmm1, xmm1
    movaps xmm2, xmm0
    mulss xmm2, xmm0
    addss xmm2, xmm1                       ; gx^2 + gy^2
    sqrtss xmm3, xmm2                      ; slope
    mulss xmm3, DWORD PTR k128f
    cvttss2si r12d, xmm3
    mov  eax, 255
    cmp  r12d, eax
    cmova r12d, eax                        ; slope index
    addss xmm2, DWORD PTR kOne
    sqrtss xmm2, xmm2
    movss xmm4, DWORD PTR kOne
    divss xmm4, xmm2                       ; nz
    mulss xmm0, DWORD PTR kCosE
    addss xmm0, DWORD PTR kSinE
    mulss xmm0, xmm4
    maxss xmm0, DWORD PTR kZero
    minss xmm0, DWORD PTR kOne             ; n.l
    cvtsi2ss xmm5, DWORD PTR [rbx+TXL.sh]
    mulss xmm5, DWORD PTR kInv255
    mulss xmm0, xmm5                       ; lit = n.l * shadow
    mulss xmm4, DWORD PTR kAmbB
    addss xmm4, DWORD PTR kAmbA
    mulss xmm4, DWORD PTR kAmbK            ; ambient
    movss DWORD PTR [rsp+LOC], xmm0
    movss DWORD PTR [rsp+LOC+4], xmm4
    mov  eax, DWORD PTR [rbx+TXL.hC]
    cmp  eax, VX_WATER
    jbe  tx_water
    mov  rcx, rbx
    mov  edx, r12d
    call Vxt_Albedo
    movss xmm0, DWORD PTR [rsp+LOC]
    movss xmm4, DWORD PTR [rsp+LOC+4]
    movd xmm1, eax
    pxor xmm2, xmm2
    punpcklbw xmm1, xmm2
    punpcklwd xmm1, xmm2
    cvtdq2ps xmm1, xmm1                    ; albedo
    shufps xmm0, xmm0, 0
    shufps xmm4, xmm4, 0
    mulps xmm0, XMMWORD PTR kSunBGR
    mulps xmm4, XMMWORD PTR kAmbBGR
    addps xmm0, xmm4                       ; light colour
    mulps xmm0, xmm1
    cvtsi2ss xmm3, DWORD PTR [rbx+TXL.d2]
    mulss xmm3, DWORD PTR kModB
    addss xmm3, DWORD PTR kModA            ; 0.75 .. 1.25 brightness modulation
    shufps xmm3, xmm3, 0
    mulps xmm0, xmm3
    xor  r13d, r13d                        ; alpha: no water
    jmp  tx_pack
tx_water:
    mov  ecx, VX_WATER
    sub  ecx, eax                          ; depth
    imul ecx, 113
    shr  ecx, 10
    mov  edx, 255
    cmp  ecx, edx
    cmova ecx, edx
    lea  rdx, vxWaterPal
    movd xmm1, DWORD PTR [rdx+rcx*4]
    pxor xmm2, xmm2
    punpcklbw xmm1, xmm2
    punpcklwd xmm1, xmm2
    cvtdq2ps xmm1, xmm1
    movss xmm0, DWORD PTR [rsp+LOC]
    mulss xmm0, DWORD PTR kWatB
    addss xmm0, DWORD PTR kWatA            ; water brightness 0.55 .. 1.0
    shufps xmm0, xmm0, 0
    mulps xmm0, xmm1
    mov  r13d, 0FF000000h
tx_pack:
    minps xmm0, XMMWORD PTR k255v
    cvtps2dq xmm0, xmm0
    packssdw xmm0, xmm0
    packuswb xmm0, xmm0
    movd eax, xmm0
    and  eax, 00FFFFFFh
    or   eax, r13d
    FN_RET
FN_END Vxt_Texel

; ---------------------------------------------------------------------------
; Vxt_Light - bakes the colour map (vxCol).  Locals: TXL block at +0.
; ---------------------------------------------------------------------------
FN_BEGIN Vxt_Light, 32
    xor  r15d, r15d                        ; y
vl_row:
    lea  rax, vxH16
    mov  ecx, r15d
    shl  ecx, 10
    lea  r12, [rax+rcx]                    ; row
    lea  ecx, [r15-1]
    and  ecx, 511
    shl  ecx, 10
    lea  r13, [rax+rcx]                    ; row above
    lea  ecx, [r15+1]
    and  ecx, 511
    shl  ecx, 10
    lea  r14, [rax+rcx]                    ; row below
    xor  ebx, ebx                          ; x
vl_px:
    mov  ebp, r15d
    shl  ebp, 9
    add  ebp, ebx                          ; texel index
    lea  esi, [rbx-1]
    and  esi, 511
    movzx eax, WORD PTR [r12+rsi*2]
    mov  DWORD PTR [rsp+LOC+TXL.hL], eax
    lea  esi, [rbx+1]
    and  esi, 511
    movzx eax, WORD PTR [r12+rsi*2]
    mov  DWORD PTR [rsp+LOC+TXL.hR], eax
    movzx eax, WORD PTR [r12+rbx*2]
    mov  DWORD PTR [rsp+LOC+TXL.hC], eax
    movzx eax, WORD PTR [r13+rbx*2]
    mov  DWORD PTR [rsp+LOC+TXL.hU], eax
    movzx eax, WORD PTR [r14+rbx*2]
    mov  DWORD PTR [rsp+LOC+TXL.hD], eax
    lea  rdx, vxNoiseC
    movzx eax, BYTE PTR [rdx+rbp]
    mov  DWORD PTR [rsp+LOC+TXL.d1], eax
    lea  rdx, vxNoiseD
    movzx eax, BYTE PTR [rdx+rbp]
    mov  DWORD PTR [rsp+LOC+TXL.d2], eax
    lea  rdx, vxShade
    movzx eax, BYTE PTR [rdx+rbp]
    mov  DWORD PTR [rsp+LOC+TXL.sh], eax
    lea  rcx, [rsp+LOC]
    call Vxt_Texel
    lea  rdx, vxCol
    mov  DWORD PTR [rdx+rbp*4], eax
    inc  ebx
    cmp  ebx, VXN
    jb   vl_px
    inc  r15d
    cmp  r15d, VXN
    jb   vl_row
    FN_RET
FN_END Vxt_Light

; ---------------------------------------------------------------------------
; Vxt_Pack - 2 x 2 neighbourhood per cell (water-clamped heights).
; ---------------------------------------------------------------------------
FN_BEGIN Vxt_Pack, 0
    lea  rsi, vxH16
    lea  rdi, vxCol
    lea  r8, vxHCell
    lea  r9, vxCCell
    xor  r15d, r15d                        ; y
pk_row:
    mov  eax, r15d
    shl  eax, 9
    mov  r10d, eax                         ; row index
    lea  eax, [r15+1]
    and  eax, 511
    shl  eax, 9
    mov  r11d, eax                         ; next row index
    xor  ebx, ebx                          ; x
pk_px:
    lea  r12d, [rbx+1]
    and  r12d, 511                         ; x + 1
    lea  eax, [r10+rbx]                    ; index 00
    lea  edx, [r10+r12]                    ; index 10
    lea  ecx, [r11+rbx]                    ; index 01
    lea  r13d, [r11+r12]                   ; index 11
    mov  ebp, eax
    shl  ebp, 4
    mov  r14d, VX_WATER
    movzx r12d, WORD PTR [rsi+rax*2]
    cmp  r12d, r14d
    cmovb r12d, r14d
    mov  WORD PTR [r8+rax*8], r12w
    movzx r12d, WORD PTR [rsi+rdx*2]
    cmp  r12d, r14d
    cmovb r12d, r14d
    mov  WORD PTR [r8+rax*8+2], r12w
    movzx r12d, WORD PTR [rsi+rcx*2]
    cmp  r12d, r14d
    cmovb r12d, r14d
    mov  WORD PTR [r8+rax*8+4], r12w
    movzx r12d, WORD PTR [rsi+r13*2]
    cmp  r12d, r14d
    cmovb r12d, r14d
    mov  WORD PTR [r8+rax*8+6], r12w
    mov  r12d, DWORD PTR [rdi+rax*4]
    mov  DWORD PTR [r9+rbp], r12d
    mov  r12d, DWORD PTR [rdi+rdx*4]
    mov  DWORD PTR [r9+rbp+4], r12d
    mov  r12d, DWORD PTR [rdi+rcx*4]
    mov  DWORD PTR [r9+rbp+8], r12d
    mov  r12d, DWORD PTR [rdi+r13*4]
    mov  DWORD PTR [r9+rbp+12], r12d
    inc  ebx
    cmp  ebx, VXN
    jb   pk_px
    inc  r15d
    cmp  r15d, VXN
    jb   pk_row
    FN_RET
FN_END Vxt_Pack

; ---------------------------------------------------------------------------
; Vox_BuildTerrain - the whole generation pipeline.
; ---------------------------------------------------------------------------
FN_BEGIN Vox_BuildTerrain, 0
    lea  rcx, vxWaterPal
    mov  edx, 256
    lea  r8, vxWaterKeys
    call Pal_FromKeys
    call Vxt_Tables
    call Vxt_ColorTables
    call Vxt_Heights
    call Vxt_Blur
    lea  rcx, vxNoiseC
    mov  edx, 9
    mov  r8d, 4
    mov  r9d, 4 + (VX_SEED_C SHL 8)
    call Mth_Fbm
    lea  rcx, vxNoiseD
    mov  edx, 9
    mov  r8d, 6
    mov  r9d, 5 + (VX_SEED_D SHL 8)
    call Mth_Fbm
    call Vxt_Shadow
    call Vxt_Light
    call Vxt_Pack
    xor  eax, eax
    FN_RET
FN_END Vox_BuildTerrain

; ---------------------------------------------------------------------------
; Vox_HeightAt(ecx = x, edx = y; 16.16 map position) -> eax = height (1/256 cell),
; clamped to the water level (nearest cell; used for the camera clearance).
; ---------------------------------------------------------------------------
LEAF_BEGIN Vox_HeightAt
    shr  ecx, 16
    and  ecx, 511
    shr  edx, 16
    and  edx, 511
    shl  edx, 9
    or   edx, ecx
    lea  rax, vxH16
    movzx eax, WORD PTR [rax+rdx*2]
    mov  ecx, VX_WATER
    cmp  eax, ecx
    cmovb eax, ecx
    ret
LEAF_END Vox_HeightAt

END
