; ============================================================================
; vox.inc - declarations shared by the voxel scene modules
;           (fx_voxel.asm: camera / credits, vox_render.asm: ray casting)
; ============================================================================

VX_F      EQU 320                 ; focal length in pixels (90 degree field of view)
VX_ZNEAR  EQU 2                   ; first sampled distance (cells)
VX_ZFAR   EQU 620                 ; last sampled distance
VX_WATER  EQU 2304                ; water level (1/256 cell), same as in vox_terrain.asm
VX_SUN_AZ EQU 32768               ; sun azimuth: 180 degrees, 1/16 table units
VX_SUN_UP EQU 98                  ; sun height above the horizon: F * tan(17 degrees)

; Per-frame and per-step state of the ray caster (instance: vxp).
VXP STRUCT
    camX    SDWORD ?              ; camera position, 16.16 map units
    camY    SDWORD ?
    fwdX    SDWORD ?              ; heading unit vector, +-32767
    fwdY    SDWORD ?
    camH    SDWORD ?              ; camera height, 1/256 cell
    hor     SDWORD ?              ; horizon row
    sunX    SDWORD ?              ; sun disc centre on the screen
    sunY    SDWORD ?
    tb      DWORD ?               ; glitter time bucket (pre-multiplied)
    step    DWORD ?               ; ray step number
    baseX   SDWORD ?              ; map position under column 0 for the current step
    baseY   SDWORD ?
    colDX      SDWORD ?              ; map position change per column
    colDY      SDWORD ?
    kk      QWORD ?               ; screen scale for the current step, 16.16
    fogW    DWORD ?               ; fog weight 0..128
    fresW   DWORD ?               ; water reflection weight 0..128
    rw      DWORD ?               ; glitter reciprocal width, 16.16
    gfade   DWORD ?               ; glitter distance fade 0..128
    fb      QWORD ?               ; target framebuffer
VXP ENDS

EXTERNDEF vxp:BYTE                ; VXP instance
EXTERNDEF Vox_InitTables:PROC     ; sky palette, sun glow, reciprocal tables
EXTERNDEF Vox_Frame:PROC          ; rcx = fb; renders sky, sun and terrain from vxp
