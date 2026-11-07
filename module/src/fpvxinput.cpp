#include "fpvxinput.h"

#if defined(FPVXINPUT_STUB)
typedef unsigned int DWORD;
typedef unsigned short WORD;
typedef unsigned char BYTE;
typedef short SHORT;
typedef DWORD (*XGetStateFn)(DWORD, void*);
extern XGetStateFn g_stubGetState;
static XGetStateFn resolve() { return g_stubGetState; }
#else
#ifdef FPVJOY_FREESTANDING
extern "C" {
typedef unsigned long DWORD;
typedef unsigned short WORD;
typedef unsigned char BYTE;
typedef short SHORT;
typedef wchar_t WCHAR;
typedef void* HMODULE;
typedef long long (__stdcall* FARPROC)();
__declspec(dllimport) HMODULE __stdcall LoadLibraryW(const WCHAR* name);
__declspec(dllimport) FARPROC __stdcall GetProcAddress(HMODULE m, const char* name);
}
#else
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif
typedef DWORD (__stdcall* XGetStateFn)(DWORD, void*);
static XGetStateFn resolve()
{
    static bool tried = false;
    static XGetStateFn fn = 0;
    if (tried) return fn;
    tried = true;
    const WCHAR* libs[] = { L"xinput1_4.dll", L"xinput1_3.dll", L"xinput9_1_0.dll" };
    for (int i = 0; i < 3 && !fn; i++) {
        HMODULE m = LoadLibraryW(libs[i]);
        if (m) fn = (XGetStateFn)(void*)GetProcAddress(m, "XInputGetState");
    }
    return fn;
}
#endif

namespace {

struct XGamepad {
    WORD wButtons;
    BYTE bLeftTrigger;
    BYTE bRightTrigger;
    SHORT sThumbLX;
    SHORT sThumbLY;
    SHORT sThumbRX;
    SHORT sThumbRY;
};

struct XState {
    DWORD dwPacketNumber;
    XGamepad Gamepad;
};

static_assert(sizeof(XState) == 16, "XINPUT_STATE layout");

double thumb(SHORT v)
{
    double t = v < 0 ? (double)v / 32768.0 : (double)v / 32767.0;
    if (t < -1.0) t = -1.0;
    if (t > 1.0) t = 1.0;
    return t;
}

const WORD XMAP[10] = { 0x1000, 0x2000, 0x4000, 0x8000, 0x0100, 0x0200, 0x0020, 0x0010, 0x0040, 0x0080 };

}

bool FpvXInput_Available()
{
    return resolve() != 0;
}

bool FpvXInput_Read(int slot, double* axes, int nAxes, unsigned int* buttons, unsigned long* packet)
{
    XGetStateFn fn = resolve();
    if (!fn || slot < 0 || slot > 3) return false;
    XState s;
    unsigned char* p = (unsigned char*)&s;
    for (unsigned i = 0; i < sizeof(s); i++) p[i] = 0;
    if (fn((DWORD)slot, &s) != 0) return false;
    const XGamepad& g = s.Gamepad;
    double lt = g.bLeftTrigger / 255.0, rt = g.bRightTrigger / 255.0;
    double v[8] = { thumb(g.sThumbLX), -thumb(g.sThumbLY), lt - rt, thumb(g.sThumbRX), -thumb(g.sThumbRY),
        lt * 2.0 - 1.0, rt * 2.0 - 1.0, 0.0 };
    for (int i = 0; i < nAxes; i++) axes[i] = i < 8 ? v[i] : 0.0;
    unsigned int b = 0;
    for (int i = 0; i < 10; i++) if (g.wButtons & XMAP[i]) b |= 1u << i;
    if (g.wButtons & 0x0001) b |= 1u << 10;
    if (g.wButtons & 0x0002) b |= 1u << 11;
    if (g.wButtons & 0x0004) b |= 1u << 12;
    if (g.wButtons & 0x0008) b |= 1u << 13;
    *buttons = b;
    *packet = (unsigned long)s.dwPacketNumber;
    return true;
}
