; ============================================================================
; win.inc - Win32 imports and constants used by the demo (ANSI entry points)
; ============================================================================

; ---- kernel32 ----------------------------------------------------------------
EXTERN ExitProcess:PROC
EXTERN GetModuleHandleA:PROC
EXTERN GetCommandLineA:PROC
EXTERN GetStdHandle:PROC
EXTERN VirtualAlloc:PROC
EXTERN VirtualFree:PROC
EXTERN QueryPerformanceCounter:PROC
EXTERN QueryPerformanceFrequency:PROC
EXTERN Sleep:PROC
EXTERN CreateFileA:PROC
EXTERN WriteFile:PROC
EXTERN CloseHandle:PROC
EXTERN OutputDebugStringA:PROC

; ---- user32 ------------------------------------------------------------------
EXTERN SetProcessDPIAware:PROC
EXTERN RegisterClassExA:PROC
EXTERN CreateWindowExA:PROC
EXTERN DefWindowProcA:PROC
EXTERN DestroyWindow:PROC
EXTERN ShowWindow:PROC
EXTERN UpdateWindow:PROC
EXTERN PeekMessageA:PROC
EXTERN TranslateMessage:PROC
EXTERN DispatchMessageA:PROC
EXTERN PostQuitMessage:PROC
EXTERN GetDC:PROC
EXTERN ReleaseDC:PROC
EXTERN BeginPaint:PROC
EXTERN EndPaint:PROC
EXTERN FillRect:PROC
EXTERN GetClientRect:PROC
EXTERN GetWindowRect:PROC
EXTERN AdjustWindowRect:PROC
EXTERN SetWindowPos:PROC
EXTERN SetWindowLongPtrA:PROC
EXTERN GetWindowLongPtrA:PROC
EXTERN LoadCursorA:PROC
EXTERN SetCursor:PROC
EXTERN GetSystemMetrics:PROC
EXTERN MonitorFromWindow:PROC
EXTERN GetMonitorInfoA:PROC
EXTERN MessageBoxA:PROC
EXTERN SetWindowTextA:PROC

; ---- gdi32 -------------------------------------------------------------------
EXTERN StretchDIBits:PROC
EXTERN SetStretchBltMode:PROC
EXTERN GetStockObject:PROC
EXTERN PatBlt:PROC
EXTERN CreateFontA:PROC
EXTERN CreateCompatibleDC:PROC
EXTERN CreateDIBSection:PROC
EXTERN SelectObject:PROC
EXTERN DeleteObject:PROC
EXTERN DeleteDC:PROC
EXTERN SetTextColor:PROC
EXTERN SetBkColor:PROC
EXTERN SetBkMode:PROC
EXTERN SetTextCharacterExtra:PROC
EXTERN TextOutA:PROC
EXTERN GetTextExtentPoint32A:PROC
EXTERN GdiFlush:PROC

; ---- winmm / dwmapi ----------------------------------------------------------
EXTERN timeBeginPeriod:PROC
EXTERN timeEndPeriod:PROC
EXTERN waveOutOpen:PROC
EXTERN waveOutClose:PROC
EXTERN waveOutPrepareHeader:PROC
EXTERN waveOutUnprepareHeader:PROC
EXTERN waveOutWrite:PROC
EXTERN waveOutReset:PROC
EXTERN waveOutGetPosition:PROC
EXTERN DwmFlush:PROC

; ---- constants ---------------------------------------------------------------
MEM_COMMIT_RESERVE   EQU 3000h
MEM_RELEASE          EQU 8000h
PAGE_READWRITE       EQU 4

GENERIC_WRITE        EQU 40000000h
CREATE_ALWAYS        EQU 2
FILE_ATTRIBUTE_NORMAL EQU 80h

WS_OVERLAPPEDWINDOW  EQU 00CF0000h
WS_POPUP             EQU 80000000h
WS_VISIBLE           EQU 10000000h
CW_USEDEFAULT        EQU 80000000h
SW_SHOW              EQU 5

WM_DESTROY           EQU 2h
WM_SIZE              EQU 5h
WM_PAINT             EQU 0Fh
WM_CLOSE             EQU 10h
WM_ERASEBKGND        EQU 14h
WM_SETCURSOR         EQU 20h
WM_KEYDOWN           EQU 100h
WM_SYSKEYDOWN        EQU 104h
WM_QUIT              EQU 12h
PM_REMOVE            EQU 1

VK_RETURN            EQU 0Dh
VK_ESCAPE            EQU 1Bh
VK_SPACE             EQU 20h
VK_LEFT              EQU 25h
VK_RIGHT             EQU 27h
VK_F11               EQU 7Ah
VK_P                 EQU 50h
VK_M                 EQU 4Dh
VK_F                 EQU 46h

GWL_STYLE            EQU -16
SWP_NOSIZE           EQU 1h
SWP_NOMOVE           EQU 2h
SWP_NOZORDER         EQU 4h
SWP_NOACTIVATE       EQU 10h
SWP_FRAMECHANGED     EQU 20h
SWP_SHOWWINDOW       EQU 40h
HWND_TOP             EQU 0
IDC_ARROW            EQU 7F00h
BLACK_BRUSH          EQU 4
BLACKNESS            EQU 42h
COLORONCOLOR         EQU 3
HALFTONE             EQU 4
DIB_RGB_COLORS       EQU 0
SRCCOPY              EQU 00CC0020h
TRANSPARENT          EQU 1
OPAQUE_BK            EQU 2
MONITOR_DEFAULTTONEAREST EQU 2
SM_CXSCREEN          EQU 0
SM_CYSCREEN          EQU 1
MB_OK                EQU 0
MB_ICONERROR         EQU 10h

WAVE_MAPPER          EQU 0FFFFFFFFh
WAVE_FORMAT_PCM      EQU 1
WHDR_DONE            EQU 1
WHDR_BEGINLOOP       EQU 4
WHDR_ENDLOOP         EQU 8
TIME_SAMPLES         EQU 2
TIME_BYTES           EQU 4
MMSYSERR_NOERROR     EQU 0

; ---- structures --------------------------------------------------------------
WNDCLASSEXA STRUCT
    cbSize        DWORD ?
    style         DWORD ?
    lpfnWndProc   QWORD ?
    cbClsExtra    DWORD ?
    cbWndExtra    DWORD ?
    hInstance     QWORD ?
    hIcon         QWORD ?
    hCursor       QWORD ?
    hbrBackground QWORD ?
    lpszMenuName  QWORD ?
    lpszClassName QWORD ?
    hIconSm       QWORD ?
WNDCLASSEXA ENDS

MSGSTRUCT STRUCT
    hwnd     QWORD ?
    message  DWORD ?
    pad0     DWORD ?
    wParam   QWORD ?
    lParam   QWORD ?
    time     DWORD ?
    ptx      SDWORD ?
    pty      SDWORD ?
    pad1     DWORD ?
MSGSTRUCT ENDS

RECT STRUCT
    left   SDWORD ?
    top    SDWORD ?
    right  SDWORD ?
    bottom SDWORD ?
RECT ENDS

MONITORINFO STRUCT
    cbSize    DWORD ?
    rcMonitor RECT <>
    rcWork    RECT <>
    dwFlags   DWORD ?
MONITORINFO ENDS

PAINTSTRUCT STRUCT
    hdc         QWORD ?
    fErase      DWORD ?
    rcPaint     RECT <>
    fRestore    DWORD ?
    fIncUpdate  DWORD ?
    rgbReserved BYTE 32 DUP (?)
    pad         DWORD ?
PAINTSTRUCT ENDS

BITMAPINFOHEADER STRUCT
    biSize          DWORD ?
    biWidth         SDWORD ?
    biHeight        SDWORD ?
    biPlanes        WORD ?
    biBitCount      WORD ?
    biCompression   DWORD ?
    biSizeImage     DWORD ?
    biXPelsPerMeter SDWORD ?
    biYPelsPerMeter SDWORD ?
    biClrUsed       DWORD ?
    biClrImportant  DWORD ?
BITMAPINFOHEADER ENDS

SIZEL STRUCT
    cx_ SDWORD ?
    cy_ SDWORD ?
SIZEL ENDS

WAVEFORMATEX STRUCT 2
    wFormatTag      WORD ?
    nChannels       WORD ?
    nSamplesPerSec  DWORD ?
    nAvgBytesPerSec DWORD ?
    nBlockAlign     WORD ?
    wBitsPerSample  WORD ?
    cbSize          WORD ?
WAVEFORMATEX ENDS

WAVEHDR STRUCT
    lpData          QWORD ?
    dwBufferLength  DWORD ?
    dwBytesRecorded DWORD ?
    dwUser          QWORD ?
    dwFlags         DWORD ?
    dwLoops         DWORD ?
    lpNext          QWORD ?
    reserved        QWORD ?
WAVEHDR ENDS
