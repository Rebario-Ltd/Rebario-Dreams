; ============================================================================
; common.inc - shared macros, constants, structures and cross-module symbols
; ----------------------------------------------------------------------------
; Calling convention: Microsoft x64. Every non-leaf function uses a uniform
; frame so that unwind data (PROC FRAME) is always correct:
;
;   [rsp+0   .. rsp+111]   outgoing call area (32 shadow + 80 for stack args)
;   [rsp+112 .. ]          locals (offset constant LOC)
;
; FNX_* frames additionally preserve XMM6..XMM15 at [rsp+112 .. rsp+271] and
; the locals start at XLOC.  rsp is 16-byte aligned inside the body, so locals
; may be used with movaps.  All non-volatile GPRs are saved by the prologue,
; so the body may freely use rax,rcx,rdx,rsi,rdi,rbx,rbp,r8-r15.
; Leaf functions (LEAF_*) touch only volatile registers (rax,rcx,rdx,r8-r11,
; xmm0-xmm5) and never use the stack.
; ============================================================================

OPTION CASEMAP:NONE

LOC  EQU 112
XLOC EQU 272

; ---- standard frame (no XMM save) -------------------------------------------
FN_BEGIN MACRO fname:REQ, locals:=<0>
fname PROC FRAME
    push rbp
    .pushreg rbp
    push rbx
    .pushreg rbx
    push rsi
    .pushreg rsi
    push rdi
    .pushreg rdi
    push r12
    .pushreg r12
    push r13
    .pushreg r13
    push r14
    .pushreg r14
    push r15
    .pushreg r15
    __FRM = LOC + (((locals) + 15) AND 0FFFFFFF0h) + 8
    sub rsp, __FRM
    .allocstack __FRM
    .endprolog
ENDM

FN_RET MACRO
    add rsp, __FRM
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret
ENDM

; ---- frame that also preserves XMM6..XMM15 ---------------------------------
FNX_BEGIN MACRO fname:REQ, locals:=<0>
fname PROC FRAME
    push rbp
    .pushreg rbp
    push rbx
    .pushreg rbx
    push rsi
    .pushreg rsi
    push rdi
    .pushreg rdi
    push r12
    .pushreg r12
    push r13
    .pushreg r13
    push r14
    .pushreg r14
    push r15
    .pushreg r15
    __FRM = XLOC + (((locals) + 15) AND 0FFFFFFF0h) + 8
    sub rsp, __FRM
    .allocstack __FRM
    movaps XMMWORD PTR [rsp+112], xmm6
    .savexmm128 xmm6, 112
    movaps XMMWORD PTR [rsp+128], xmm7
    .savexmm128 xmm7, 128
    movaps XMMWORD PTR [rsp+144], xmm8
    .savexmm128 xmm8, 144
    movaps XMMWORD PTR [rsp+160], xmm9
    .savexmm128 xmm9, 160
    movaps XMMWORD PTR [rsp+176], xmm10
    .savexmm128 xmm10, 176
    movaps XMMWORD PTR [rsp+192], xmm11
    .savexmm128 xmm11, 192
    movaps XMMWORD PTR [rsp+208], xmm12
    .savexmm128 xmm12, 208
    movaps XMMWORD PTR [rsp+224], xmm13
    .savexmm128 xmm13, 224
    movaps XMMWORD PTR [rsp+240], xmm14
    .savexmm128 xmm14, 240
    movaps XMMWORD PTR [rsp+256], xmm15
    .savexmm128 xmm15, 256
    .endprolog
ENDM

FNX_RET MACRO
    movaps xmm6,  XMMWORD PTR [rsp+112]
    movaps xmm7,  XMMWORD PTR [rsp+128]
    movaps xmm8,  XMMWORD PTR [rsp+144]
    movaps xmm9,  XMMWORD PTR [rsp+160]
    movaps xmm10, XMMWORD PTR [rsp+176]
    movaps xmm11, XMMWORD PTR [rsp+192]
    movaps xmm12, XMMWORD PTR [rsp+208]
    movaps xmm13, XMMWORD PTR [rsp+224]
    movaps xmm14, XMMWORD PTR [rsp+240]
    movaps xmm15, XMMWORD PTR [rsp+256]
    add rsp, __FRM
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret
ENDM

FN_END MACRO fname:REQ
fname ENDP
ENDM

LEAF_BEGIN MACRO fname:REQ
fname PROC
ENDM

LEAF_END MACRO fname:REQ
fname ENDP
ENDM

; Broadcast the low 16 bits of a 32-bit GPR into all eight words of an XMM.
BCAST16 MACRO xr:REQ, gr:REQ
    movd xr, gr
    pshuflw xr, xr, 0
    pshufd xr, xr, 0
ENDM

; ---- scalar colour helpers (32-bit registers, 0x00RRGGBB / BGRA alike) --------
; PIXSCALE c, f, t : c = c * f / 256 per channel (f = 0..256); clobbers t.
PIXSCALE MACRO c:REQ, f:REQ, t:REQ
    mov  t, c
    and  c, 00FF00FFh
    imul c, f
    shr  c, 8
    and  c, 00FF00FFh
    and  t, 0000FF00h
    imul t, f
    shr  t, 8
    and  t, 0000FF00h
    or   c, t
ENDM

; PIXMIX c, d, w, t1, t2 : c = (c * (256 - w) + d * w) / 256 per channel (w = 0..256).
; Clobbers d, t1 and t2.
PIXMIX MACRO c:REQ, d:REQ, w:REQ, t1:REQ, t2:REQ
    mov  t1, 256
    sub  t1, w
    mov  t2, c
    and  c, 00FF00FFh
    imul c, t1
    and  t2, 0000FF00h
    imul t2, t1
    mov  t1, d
    and  d, 00FF00FFh
    imul d, w
    and  t1, 0000FF00h
    imul t1, w
    add  c, d
    add  t2, t1
    shr  c, 8
    shr  t2, 8
    and  c, 00FF00FFh
    and  t2, 0000FF00h
    or   c, t2
ENDM

; PIXADD c, d, x0, x1 : c = saturate(c + d) per channel through SSE.
PIXADD MACRO c:REQ, d:REQ, x0:REQ, x1:REQ
    movd x0, c
    movd x1, d
    paddusb x0, x1
    movd c, x0
ENDM

; ADDPIXW p, c, w, t1, t2 : *(DWORD *)p = saturate(*p + c * w / 256) per channel.
; p = 64-bit register holding the pixel address, c = 0x00RRGGBB (register or
; immediate), w = 0..256 (register or immediate); clobbers t1, t2, xmm0, xmm1.
ADDPIXW MACRO p:REQ, c:REQ, w:REQ, t1:REQ, t2:REQ
    mov  t1, c
    and  t1, 00FF00FFh
    imul t1, w
    shr  t1, 8
    and  t1, 00FF00FFh
    mov  t2, c
    and  t2, 0000FF00h
    imul t2, w
    shr  t2, 8
    and  t2, 0000FF00h
    or   t1, t2
    movd xmm0, t1
    movd xmm1, DWORD PTR [p]
    paddusb xmm0, xmm1
    movd DWORD PTR [p], xmm0
ENDM
; ---- geometry ---------------------------------------------------------------
SCR_W     EQU 640
SCR_H     EQU 360
SCR_PIX   EQU 230400
SCR_BYTES EQU 921600
OUT_W     EQU 1280
OUT_H     EQU 720
OUT_BYTES EQU 3686400

; ---- timeline (all effects are pure functions of time) -----------------------
NUM_SCENES EQU 9
SCENE_MS   EQU 15000          ; 8 bars at 128 BPM
TRANS_MS   EQU 1500           ; cross-transition at the end of a scene
TOTAL_MS   EQU NUM_SCENES * SCENE_MS
BPM        EQU 128

; ---- audio -------------------------------------------------------------------
AUDIO_RATE   EQU 44100
AUDIO_FRAMES EQU TOTAL_MS * AUDIO_RATE / 1000     ; exactly TOTAL_MS of stereo audio
AUDIO_BYTES  EQU AUDIO_FRAMES * 4
STEP_NUM     EQU 661500       ; samples(step) = step * STEP_NUM / 128  (16th note)

; ---- structures --------------------------------------------------------------
; 8-bit coverage mask of rendered text (GDI -> mask).
TXMASK STRUCT
    w   DWORD ?
    h   DWORD ?
    pix QWORD ?
TXMASK ENDS

; Parameter block for Gfx_DrawMask.
DMASK STRUCT
    dst    QWORD ?          ; 640x360 BGRA framebuffer
    tx     QWORD ?          ; TXMASK *
    x      SDWORD ?
    y      SDWORD ?
    color  DWORD ?          ; 0x00RRGGBB solid colour (used when rowPal == 0)
    alpha  DWORD ?          ; 0..256 global opacity
    mode   DWORD ?          ; 0 = alpha blend, 1 = additive
    pad    DWORD ?
    rowPal QWORD ?          ; optional DWORD[mask.h] per-row colours
    rowOff QWORD ?          ; optional SDWORD[mask.h] per-row x offsets
DMASK ENDS

; Request block for Font_Render.
FONTREQ STRUCT
    dst    QWORD ?          ; TXMASK * receiving the mask
    text   QWORD ?          ; ASCIIZ string
    height DWORD ?          ; em height in pixels
    weight DWORD ?          ; 100..900
    face   DWORD ?          ; 0 Segoe UI Black, 1 Bahnschrift, 2 Consolas, 3 Impact, 4 Segoe UI Light
    italic DWORD ?          ; 0 / 1
    track  DWORD ?          ; extra pixels between characters
    pad    DWORD ?
FONTREQ ENDS

; Every mask made by Font_Render has this many empty pixels on each of its sides
; (room for the glyph overhang and for the blur of Font_Glow).
FONT_PAD EQU 16

; The credit line "created with <heart> by Paul Deecalov (c) 2026" (signature.asm).
SIG_HEART EQU 14                ; the heart is drawn in a box of this many pixels
SIG_GAP   EQU 6                 ; clear pixels between a text and the heart
SIG_RED   EQU 00FF3355h         ; colour of the heart, 0x00RRGGBB

; One entry per scene in the timeline table.
SCENE STRUCT
    renderFn QWORD ?        ; void render(uint32 *fb, int32 localMs)
    initFn   QWORD ?        ; int init(void)  -> 0 on success
    caption  QWORD ?        ; ASCII caption text
    trans    DWORD ?        ; transition style into the next scene
    bloom    DWORD ?        ; BLOOMPACK(threshold, gain)
SCENE ENDS
EXTERNDEF sceneTab:SCENE        ; NUM_SCENES rows (timeline.asm), read by the self test
EXTERNDEF scenePulse:DWORD      ; NUM_SCENES pulse depths 0..256 (timeline.asm), read by the self test

; Bloom parameters of a scene: bright-pass threshold 0..255 in bits 0..7, glow
; gain in 8.8 fixed point (256 = x1.0) from bit 8 up.
BLOOMPACK MACRO thr:REQ, gain:REQ
    EXITM <(((gain) SHL 8) OR (thr))>
ENDM

; ---- shared state (storage lives in data.asm) --------------------------------
EXTERNDEF gFbA:QWORD            ; scene A render target (640x360 BGRA)
EXTERNDEF gFbB:QWORD            ; scene B render target
EXTERNDEF gFbC:QWORD            ; composite / post-processing buffer
EXTERNDEF gFbOut:QWORD          ; 1280x720 BGRA presentation buffer
EXTERNDEF gPcm:QWORD            ; int16 stereo music buffer

EXTERNDEF gTimeMs:DWORD         ; demo time of the current frame
EXTERNDEF gBeat16:DWORD         ; phase inside the beat, 0..65535
EXTERNDEF gBeatNo:DWORD         ; absolute beat counter
EXTERNDEF gBeatEnv:DWORD        ; soft swell of the beat 0..256: peak on the beat, 0 half a beat later
EXTERNDEF gKick:DWORD           ; beat pulse the scene under construction draws with, 0..256:
                                ; gBeatEnv scaled by that scene's depth (scenePulse)
EXTERNDEF gFlash:DWORD          ; additive white flash 0..255
EXTERNDEF gFade:DWORD           ; global brightness 0..256

EXTERNDEF gSinTab:WORD          ; 4096 x int16, sin * 32767
EXTERNDEF gSinTabF:REAL4        ; 4097 x float, sin
EXTERNDEF gRng:DWORD            ; xorshift32 state

EXTERNDEF gProgress:DWORD       ; loading progress 0..100
EXTERNDEF gProgressCb:QWORD     ; optional void cb(void) called on progress
EXTERNDEF gHeadless:DWORD       ; 1 = no window / no message boxes
EXTERNDEF gMute:DWORD           ; 1 = /mute: no soundtrack is synthesised or played

; ---- mathlib.asm -------------------------------------------------------------
EXTERNDEF Mth_Init:PROC         ; build sine tables
EXTERNDEF Mth_Sinf:PROC         ; xmm0 = sin(xmm0)
EXTERNDEF Mth_Cosf:PROC         ; xmm0 = cos(xmm0)
EXTERNDEF Mth_Atan2f:PROC       ; xmm0 = atan2(y = xmm0, x = xmm1)
EXTERNDEF Mth_Exp2f:PROC        ; xmm0 = 2^xmm0
EXTERNDEF Mth_Log2f:PROC        ; xmm0 = log2(xmm0)
EXTERNDEF Mth_Seed:PROC         ; ecx = seed
EXTERNDEF Mth_Rand:PROC         ; -> eax (32-bit xorshift)
EXTERNDEF Mth_Hash2:PROC        ; ecx = x, edx = y, r8d = seed -> eax

; ---- sys.asm -------------------------------------------------------------------
EXTERNDEF Sys_Init:PROC         ; timer base, inherited stdout
EXTERNDEF Sys_NowMs:PROC        ; -> rax = ms since Sys_Init
EXTERNDEF Mem_Alloc:PROC        ; rcx = bytes -> rax zeroed page-aligned block
EXTERNDEF Sys_Print:PROC        ; rcx = ASCIIZ
EXTERNDEF Sys_PrintLn:PROC      ; rcx = ASCIIZ (+ CR LF)
EXTERNDEF Sys_PrintInt:PROC     ; ecx = int32 (decimal)
EXTERNDEF Sys_FmtInt:PROC       ; rcx = dst, edx = int32 -> eax = length
EXTERNDEF Sys_Fatal:PROC        ; rcx = message, never returns
EXTERNDEF Sys_WriteFile:PROC    ; rcx = path, rdx = data, r8 = size -> eax = ok
EXTERNDEF Cmd_Next:PROC         ; rcx = pos, rdx = buf, r8d = size -> rax = new pos | 0
EXTERNDEF Sys_ParseInt:PROC     ; rcx = ASCIIZ -> eax
EXTERNDEF Sys_StrEqI:PROC       ; rcx, rdx = ASCIIZ -> eax = 1 if equal (ignore case)

; ---- gfx.asm -------------------------------------------------------------------
EXTERNDEF Gfx_Init:PROC         ; build the vignette table
EXTERNDEF Gfx_Fill:PROC         ; rcx = fb, edx = BGRA
EXTERNDEF Gfx_Copy:PROC         ; rcx = dst, rdx = src
EXTERNDEF Gfx_Mix:PROC          ; rcx = dst, rdx = a, r8 = b, r9d = alpha 0..256
EXTERNDEF Gfx_AddSat:PROC       ; rcx = dst, rdx = src
EXTERNDEF Gfx_Scale:PROC        ; rcx = fb, edx = 0..256
EXTERNDEF Gfx_Post:PROC         ; rcx = fb (vignette * gFade + gFlash)
EXTERNDEF Gfx_Upscale2x:PROC    ; rcx = dst 1280x720, rdx = src 640x360
EXTERNDEF Gfx_Up2:PROC          ; rcx = dst (2w x 2h), rdx = src (w x h), r8d = w (mult. of 4), r9d = h

; ---- gfx_bloom.asm -------------------------------------------------------------
EXTERNDEF Bloom_Init:PROC       ; allocate the glow buffers
EXTERNDEF Bloom_Apply:PROC      ; rcx = 640x360 fb, edx = threshold 0..255, r8d = gain (8.8)

; ---- timeline.asm ----------------------------------------------------------------
EXTERNDEF Demo_Init:PROC        ; allocate, build tables, init every scene -> eax = 0
EXTERNDEF Demo_Render:PROC      ; ecx = demo time ms -> frame in gFbOut (1280x720)
EXTERNDEF Demo_Frame:PROC       ; ecx = demo time ms: Demo_Render without Tl_Update (the beat state stays as set)
EXTERNDEF Tl_Progress:PROC      ; ecx = percent (0..100), pings gProgressCb
EXTERNDEF Tl_Update:PROC        ; ecx = demo time ms: gTimeMs, gBeat16, gBeatNo, gBeatEnv, gKick
EXTERNDEF Tl_BeatEnv:PROC       ; ecx = phase inside the beat 0..65535 -> eax = swell 0..256
EXTERNDEF Tl_ScenePulse:PROC    ; ecx = scene, edx = blend 0..256 -> eax = gBeatEnv * the (cross-faded) depth of the scene
EXTERNDEF Tl_Compose:PROC       ; ecx = demo time ms: scene(s) + bloom into gFbC
EXTERNDEF Tl_RenderScene:PROC   ; ecx = scene, rdx = fb, r8d = demo time ms (scene + caption, no bloom)
EXTERNDEF Tl_BloomParams:PROC   ; ecx = scene, edx = blend 0..256 -> eax = threshold, edx = gain 8.8

; ---- scenes (fx_*.asm): Init() -> eax = 0, Render(rcx = fb, edx = local ms) -------
EXTERNDEF Fx_Title_Init:PROC
EXTERNDEF Fx_Title_Render:PROC
EXTERNDEF Fx_Plasma_Init:PROC
EXTERNDEF Fx_Plasma_Render:PROC
EXTERNDEF Fx_Tunnel_Init:PROC
EXTERNDEF Fx_Tunnel_Render:PROC
EXTERNDEF Tun_Travel:PROC       ; ecx = local ms -> eax = camera depth (256 per panel) at the beat state of gBeatNo / gBeat16
EXTERNDEF Fx_Stars_Init:PROC
EXTERNDEF Fx_Stars_Render:PROC
EXTERNDEF Fx_Blobs_Init:PROC
EXTERNDEF Fx_Blobs_Render:PROC
EXTERNDEF Fx_Roto_Init:PROC
EXTERNDEF Fx_Roto_Render:PROC
EXTERNDEF Fx_Fire_Init:PROC
EXTERNDEF Fx_Fire_Render:PROC
EXTERNDEF Fx_Prism_Init:PROC
EXTERNDEF Fx_Prism_Render:PROC
EXTERNDEF Fx_Voxel_Init:PROC
EXTERNDEF Fx_Voxel_Render:PROC

; ---- diag.asm ----------------------------------------------------------------------
EXTERNDEF Diag_WriteBmp:PROC    ; rcx = path, rdx = BGRA, r8d = w, r9d = h -> eax = ok
EXTERNDEF Diag_RunShot:PROC     ; rcx = demo ms, rdx = path -> eax = exit code
EXTERNDEF Diag_RunWav:PROC      ; rcx = path -> eax = exit code (synthesises and writes a WAV)
EXTERNDEF Diag_SelfTest:PROC    ; -> eax = number of failed checks (selftest.asm)
EXTERNDEF Diag_Bench:PROC       ; rcx = command line position after /bench -> eax = 0 (bench.asm)

; ---- selftest.asm / selftest_gfx.asm ------------------------------------------------
EXTERNDEF St_Report:PROC        ; rcx = check name, edx = 1 when it passed (prints, counts)
EXTERNDEF St_Near:PROC          ; xmm0 = value, xmm1 = expected, xmm2 = tolerance -> eax = 1 when close
EXTERNDEF St_NameScene:PROC     ; ecx = scene index 0..8, rdx = text -> rax = "scene N: text" (N = 1..9)
EXTERNDEF St_Gfx:PROC           ; the graphics checks (bloom, scene table)
EXTERNDEF St_G3:PROC            ; the 3D renderer checks (selftest_g3.asm, selftest_g3r.asm)
EXTERNDEF St_G3Raster:PROC      ; ... its rasteriser and render target part
EXTERNDEF St_G3Mat:PROC         ; ... its matcaps (selftest_g3m.asm)
EXTERNDEF St_Prism:PROC         ; the PRISM scene checks (selftest_prism.asm)
EXTERNDEF St_Song:PROC          ; the arrangement and scene-transition checks (selftest_song.asm)
EXTERNDEF St_Pulse:PROC         ; the soft image-pulse checks (selftest_pulse.asm)
EXTERNDEF St_Sig:PROC           ; the credit line checks (selftest_sig.asm)

; ---- gfx_fx.asm -------------------------------------------------------------------
EXTERNDEF Gfx_FxInit:PROC       ; centre-distance table
EXTERNDEF Gfx_Iris:PROC         ; rcx = dst, rdx = a, r8 = b, r9d = radius

; ---- gfx_text.asm / font.asm ----------------------------------------------------
EXTERNDEF Gfx_DrawMask:PROC     ; rcx = DMASK *
EXTERNDEF Msk_BoxBlur:PROC      ; rcx = pix, edx = w, r8d = h, r9d = radius
EXTERNDEF Font_Render:PROC      ; rcx = FONTREQ *
EXTERNDEF Font_Glow:PROC        ; rcx = TXMASK * src, rdx = TXMASK * out, r8d = radius
EXTERNDEF Font_RowPal:PROC      ; rcx = TXMASK *, rdx = dst DWORD[mask.h], r8 = gradient keys
EXTERNDEF Msk_Radial:PROC       ; rcx = TXMASK * out, edx = size, r8d = power (1 | 2 | 3 = disc)

; ---- signature.asm (credit line of the first and the last scene) ---------------
EXTERNDEF Msk_Heart:PROC        ; rcx = TXMASK * out, edx = size: a size x size mask with a heart on it
EXTERNDEF Sig_Init:PROC         ; builds sigText and sigHeart once (any scene that shows the line calls it)
EXTERNDEF sigText:BYTE          ; TXMASK: "created with" and "by Paul Deecalov (c) 2026", a hole between them
EXTERNDEF sigHeart:BYTE         ; TXMASK: the heart that fills the hole, same size as sigText
EXTERNDEF szSigLeft:BYTE        ; "created with"
EXTERNDEF szSigRight:BYTE       ; "by Paul Deecalov (c) 2026"
EXTERNDEF titHeartGlow:BYTE     ; TXMASK: blurred heart behind the line in the title (fx_title.asm; the self test wipes it)
EXTERNDEF vxHLine:BYTE          ; TXMASK: dark halo of the text of the line in the last scene (fx_voxel.asm)
EXTERNDEF vxHHeart:BYTE         ; TXMASK: dark red halo of its heart

; ---- noise.asm / palette.asm ---------------------------------------------------
EXTERNDEF Mth_Fbm:PROC          ; rcx = dst, edx = sizeLog, r8d = cellLog, r9d = octaves | seed << 8
EXTERNDEF Pal_FromKeys:PROC     ; rcx = dst, edx = count, r8 = keys
EXTERNDEF Pal_Cosine:PROC       ; rcx = dst, edx = count, r8 = float[12]

; ---- vox_terrain.asm (scene 9 landscape) ----------------------------------------
EXTERNDEF Vox_BuildTerrain:PROC ; generate heights, shadows and the baked colour map
EXTERNDEF Vox_HeightAt:PROC     ; ecx = x, edx = y (16.16 map position) -> eax = height (1/256 cell)
EXTERNDEF vxHCell:WORD          ; 512 x 512 x { h00, h10, h01, h11 }
EXTERNDEF vxCCell:DWORD         ; 512 x 512 x { c00, c10, c01, c11 } BGRA, alpha = water
EXTERNDEF vxCol:DWORD           ; 512 x 512 baked colours (top-down map)
; ---- keyboard commands produced by the window procedure -------------------------
CMD_NONE  EQU 0
CMD_NEXT  EQU 1
CMD_PREV  EQU 2
CMD_PAUSE EQU 3

; ---- platform.asm -------------------------------------------------------------------
EXTERNDEF Plat_CreateWindow:PROC    ; 1280x720 client window
EXTERNDEF Plat_Pump:PROC            ; -> eax = 1 while running, 0 after WM_QUIT
EXTERNDEF Plat_TakeCmd:PROC         ; -> eax = pending CMD_* (cleared)
EXTERNDEF Plat_Present:PROC         ; letter-boxed blit of gFbOut
EXTERNDEF Plat_Pace:PROC            ; DwmFlush or a 16 ms limiter
EXTERNDEF Plat_DrawLoading:PROC     ; progress callback (pumps messages, draws the bar)
EXTERNDEF Plat_SetTitleInfo:PROC    ; ecx = fps, edx = scene number, r8d = 1 when sound is audible

; ---- clock.asm ------------------------------------------------------------------------
EXTERNDEF Clk_Start:PROC            ; time 0, running
EXTERNDEF Clk_Now:PROC              ; -> eax = demo time (loops)
EXTERNDEF Clk_Seek:PROC             ; ecx = ms
EXTERNDEF Clk_TogglePause:PROC
EXTERNDEF Clk_NextScene:PROC
EXTERNDEF Clk_PrevScene:PROC

; ---- song.asm / audio.asm -----------------------------------------------------------------
EXTERNDEF Aud_Render:PROC           ; synthesise the soundtrack into gPcm (progress 75..99)
EXTERNDEF Aud_Open:PROC             ; rcx = pcm -> eax = 1 if a device is available
EXTERNDEF Aud_Play:PROC             ; ecx = demo ms
EXTERNDEF Aud_Stop:PROC
EXTERNDEF Aud_PosMs:PROC            ; -> eax = audible demo ms, -1 when silent
EXTERNDEF Aud_Close:PROC

; ---- app.asm ----------------------------------------------------------------------------
EXTERNDEF App_Run:PROC              ; interactive demo, never returns
