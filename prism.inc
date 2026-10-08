; ============================================================================
; prism.inc - declarations of the PRISM scene (fx_prism.asm) shared with its
;             self test (selftest_prism.asm).  Include after common.inc and g3.inc.
; ============================================================================

PZ_BW      EQU 320                      ; backdrop tables (enlarged 2 x on the screen)
PZ_BH      EQU 180
PZ_BN      EQU PZ_BW * PZ_BH
PZ_OBJS    EQU 8
PZ_MESHES  EQU 5
PZ_MSZ     EQU SIZEOF MESH

PZM_KNOT   EQU 0                        ; mesh numbers
PZM_RING   EQU 1
PZM_SPHERE EQU 2
PZM_CUBE   EQU 3
PZM_ICO    EQU 4

; One solid of the show.  Position = tilt * (r cos a, 0, r sin a) with
; a = orbitW * T + orbitP turns, orientation = start + spin * T (turns).
PZOBJ STRUCT
    mesh   DWORD ?
    tex    DWORD ?                      ; MAT_*
    mode   DWORD ?                      ; G3M_*
    pad    DWORD ?
    birth  REAL4 ?                      ; second at which it starts to grow
    durInv REAL4 ?                      ; 1 / growth time
    scale  REAL4 ?
    orbitR REAL4 ?
    orbitW REAL4 ?
    orbitP REAL4 ?
    tiltX  REAL4 ?                      ; tilt of the orbit plane, turns
    tiltY  REAL4 ?
    a0     REAL4 4 DUP (?)              ; start angles about x, y, z
    spin   REAL4 4 DUP (?)              ; turns per second
PZOBJ ENDS

EXTERNDEF pzObjs:DWORD                  ; PZ_OBJS records of PZOBJ
EXTERNDEF pzHalf:DWORD                  ; PZ_BN cells BGRA: the backdrop before the 2 x enlargement
EXTERNDEF Pz_Frame:PROC                 ; edx = local ms: time, finale, camera and kick of the frame
EXTERNDEF Pz_Place:PROC                 ; rcx = PZOBJ *, rdx = XFORM * -> eax = 1 when visible
EXTERNDEF Pz_Backdrop:PROC              ; rcx = fb, edx = local ms: the spectrum fan alone
