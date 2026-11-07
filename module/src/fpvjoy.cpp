#include "GarrysMod/Lua/Interface.h"
#include "fpvhid.h"
#include "fpvmusic.h"
#include "fpvxinput.h"

#ifdef FPVJOY_FREESTANDING
extern "C" {
typedef unsigned int UINT;
typedef unsigned long DWORD;
typedef unsigned short WORD;
typedef unsigned long long UINT_PTR;
typedef UINT MMRESULT;
typedef int BOOL;
typedef wchar_t WCHAR;

#define MAXPNAMELEN 32
#define MAX_JOYSTICKOEMVXDNAME 260
#define JOY_RETURNX 0x00000001ul
#define JOY_RETURNY 0x00000002ul
#define JOY_RETURNZ 0x00000004ul
#define JOY_RETURNR 0x00000008ul
#define JOY_RETURNU 0x00000010ul
#define JOY_RETURNV 0x00000020ul
#define JOY_RETURNPOV 0x00000040ul
#define JOY_RETURNBUTTONS 0x00000080ul
#define JOY_RETURNALL (JOY_RETURNX | JOY_RETURNY | JOY_RETURNZ | JOY_RETURNR | JOY_RETURNU | JOY_RETURNV | JOY_RETURNPOV | JOY_RETURNBUTTONS)
#define JOYCAPS_HASZ 0x0001
#define JOYCAPS_HASR 0x0002
#define JOYCAPS_HASU 0x0004
#define JOYCAPS_HASV 0x0008
#define JOYERR_NOERROR 0
#define CP_UTF8 65001

typedef struct tagJOYCAPSW {
    WORD wMid;
    WORD wPid;
    WCHAR szPname[MAXPNAMELEN];
    UINT wXmin;
    UINT wXmax;
    UINT wYmin;
    UINT wYmax;
    UINT wZmin;
    UINT wZmax;
    UINT wNumButtons;
    UINT wPeriodMin;
    UINT wPeriodMax;
    UINT wRmin;
    UINT wRmax;
    UINT wUmin;
    UINT wUmax;
    UINT wVmin;
    UINT wVmax;
    UINT wCaps;
    UINT wMaxAxes;
    UINT wNumAxes;
    UINT wMaxButtons;
    WCHAR szRegKey[MAXPNAMELEN];
    WCHAR szOEMVxD[MAX_JOYSTICKOEMVXDNAME];
} JOYCAPSW;

typedef struct joyinfoex_tag {
    DWORD dwSize;
    DWORD dwFlags;
    DWORD dwXpos;
    DWORD dwYpos;
    DWORD dwZpos;
    DWORD dwRpos;
    DWORD dwUpos;
    DWORD dwVpos;
    DWORD dwButtons;
    DWORD dwButtonNumber;
    DWORD dwPOV;
    DWORD dwReserved1;
    DWORD dwReserved2;
} JOYINFOEX;

static_assert(sizeof(JOYCAPSW) == 728, "JOYCAPSW layout");
static_assert(sizeof(JOYINFOEX) == 52, "JOYINFOEX layout");

__declspec(dllimport) UINT __stdcall joyGetNumDevs(void);
__declspec(dllimport) MMRESULT __stdcall joyGetDevCapsW(UINT_PTR uJoyID, JOYCAPSW* pjc, UINT cbjc);
__declspec(dllimport) MMRESULT __stdcall joyGetPosEx(UINT uJoyID, JOYINFOEX* pji);
__declspec(dllimport) MMRESULT __stdcall joyConfigChanged(DWORD dwFlags);
__declspec(dllimport) int __stdcall WideCharToMultiByte(UINT CodePage, DWORD dwFlags, const WCHAR* lpWideCharStr,
    int cchWideChar, char* lpMultiByteStr, int cbMultiByte, const char* lpDefaultChar, BOOL* lpUsedDefaultChar);

int _fltused = 0;
void* memset(void* dst, int c, size_t n)
{
    volatile unsigned char* d = (volatile unsigned char*)dst;
    while (n--) *d++ = (unsigned char)c;
    return dst;
}
void* memcpy(void* dst, const void* src, size_t n)
{
    volatile unsigned char* d = (volatile unsigned char*)dst;
    const volatile unsigned char* s = (const volatile unsigned char*)src;
    while (n--) *d++ = *s++;
    return dst;
}
}
#else
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#pragma comment(lib, "winmm.lib")
#endif

using namespace GarrysMod::Lua;

static const int MAX_JOY = 16;
static JOYCAPSW g_caps[MAX_JOY];
static bool g_capsValid[MAX_JOY];

static bool LoadCaps(int id)
{
    if (id < 0 || id >= MAX_JOY) return false;
    MMRESULT r = joyGetDevCapsW((UINT_PTR)id, &g_caps[id], (UINT)sizeof(JOYCAPSW));
    g_capsValid[id] = (r == JOYERR_NOERROR);
    return g_capsValid[id];
}

static double Norm(DWORD v, UINT mn, UINT mx)
{
    if (mx <= mn) return 0.0;
    double t = ((double)v - (double)mn) / ((double)mx - (double)mn);
    if (t < 0.0) t = 0.0;
    if (t > 1.0) t = 1.0;
    return t * 2.0 - 1.0;
}

static bool ReadPos(int id, JOYINFOEX* ji, MMRESULT* err)
{
    ji->dwSize = sizeof(JOYINFOEX);
    ji->dwFlags = JOY_RETURNALL;
    MMRESULT r = joyGetPosEx((UINT)id, ji);
    if (err) *err = r;
    return r == JOYERR_NOERROR;
}

LUA_FUNCTION(fj_Version)
{
    LUA->PushString("2.2.0 hid+winmm+xinput+music");
    return 1;
}

LUA_FUNCTION(fj_HidScan)
{
    LUA->PushNumber((double)FpvHid_Scan());
    return 1;
}

LUA_FUNCTION(fj_HidInfo)
{
    int i = (int)LUA->CheckNumber(1);
    const char* name = 0;
    int vid = 0, pid = 0, axes = 0, buttons = 0, usage = 0;
    if (!FpvHid_Info(i, &name, &vid, &pid, &axes, &buttons, &usage)) {
        LUA->PushBool(false);
        return 1;
    }
    LUA->PushBool(true);
    LUA->PushString(name);
    LUA->PushNumber((double)vid);
    LUA->PushNumber((double)pid);
    LUA->PushNumber((double)axes);
    LUA->PushNumber((double)buttons);
    LUA->PushNumber((double)usage);
    return 7;
}

LUA_FUNCTION(fj_HidRead)
{
    int i = (int)LUA->CheckNumber(1);
    double axes[8];
    unsigned int lo = 0, hi = 0;
    unsigned long reports = 0;
    if (!FpvHid_Read(i, axes, 8, &lo, &hi, &reports)) {
        LUA->PushBool(false);
        return 1;
    }
    LUA->PushBool(true);
    LUA->PushNumber((double)lo);
    LUA->PushNumber((double)hi);
    LUA->PushNumber((double)reports);
    for (int a = 0; a < 8; a++) LUA->PushNumber(axes[a]);
    return 12;
}

LUA_FUNCTION(fj_XInputRead)
{
    int slot = (int)LUA->CheckNumber(1);
    double axes[8];
    unsigned int buttons = 0;
    unsigned long packet = 0;
    if (!FpvXInput_Read(slot, axes, 8, &buttons, &packet)) {
        LUA->PushBool(false);
        return 1;
    }
    LUA->PushBool(true);
    LUA->PushNumber((double)buttons);
    LUA->PushNumber(0.0);
    LUA->PushNumber((double)packet);
    for (int a = 0; a < 8; a++) LUA->PushNumber(axes[a]);
    return 12;
}

LUA_FUNCTION(fj_Refresh)
{
    joyConfigChanged(0);
    for (int i = 0; i < MAX_JOY; i++) g_capsValid[i] = false;
    return 0;
}

LUA_FUNCTION(fj_Count)
{
    LUA->PushNumber((double)joyGetNumDevs());
    return 1;
}

LUA_FUNCTION(fj_Info)
{
    int id = (int)LUA->CheckNumber(1);
    JOYINFOEX ji;
    if (!LoadCaps(id) || !ReadPos(id, &ji, nullptr)) {
        LUA->PushBool(false);
        return 1;
    }
    const JOYCAPSW& c = g_caps[id];
    char name[160];
    int n = WideCharToMultiByte(CP_UTF8, 0, c.szPname, -1, name, (int)sizeof(name), nullptr, nullptr);
    if (n <= 0) { name[0] = 'J'; name[1] = 'o'; name[2] = 'y'; name[3] = 0; }
    LUA->PushBool(true);
    LUA->PushString(name);
    LUA->PushNumber((double)c.wMid);
    LUA->PushNumber((double)c.wPid);
    LUA->PushNumber((double)c.wNumAxes);
    LUA->PushNumber((double)c.wNumButtons);
    return 6;
}

LUA_FUNCTION(fj_Read)
{
    int id = (int)LUA->CheckNumber(1);
    if (id < 0 || id >= MAX_JOY || (!g_capsValid[id] && !LoadCaps(id))) {
        LUA->PushBool(false);
        LUA->PushNumber(-1);
        return 2;
    }
    JOYINFOEX ji;
    MMRESULT err = 0;
    if (!ReadPos(id, &ji, &err)) {
        g_capsValid[id] = false;
        LUA->PushBool(false);
        LUA->PushNumber((double)err);
        return 2;
    }
    const JOYCAPSW& c = g_caps[id];
    LUA->PushBool(true);
    LUA->PushNumber(Norm(ji.dwXpos, c.wXmin, c.wXmax));
    LUA->PushNumber(Norm(ji.dwYpos, c.wYmin, c.wYmax));
    LUA->PushNumber((c.wCaps & JOYCAPS_HASZ) ? Norm(ji.dwZpos, c.wZmin, c.wZmax) : 0.0);
    LUA->PushNumber((c.wCaps & JOYCAPS_HASR) ? Norm(ji.dwRpos, c.wRmin, c.wRmax) : 0.0);
    LUA->PushNumber((c.wCaps & JOYCAPS_HASU) ? Norm(ji.dwUpos, c.wUmin, c.wUmax) : 0.0);
    LUA->PushNumber((c.wCaps & JOYCAPS_HASV) ? Norm(ji.dwVpos, c.wVmin, c.wVmax) : 0.0);
    LUA->PushNumber((double)ji.dwButtons);
    LUA->PushNumber(ji.dwPOV == 0xFFFF ? -1.0 : (double)ji.dwPOV / 100.0);
    return 9;
}

LUA_FUNCTION(fj_MusicPickFolder)
{
    static char buf[1600];
    if (!FpvMusic_PickFolder(buf, (int)sizeof(buf))) {
        LUA->PushNil();
        return 1;
    }
    LUA->PushString(buf);
    return 1;
}

LUA_FUNCTION(fj_MusicImport)
{
    const char* p = LUA->CheckString(1);
    LUA->PushBool(FpvMusic_StartImport(p));
    return 1;
}

LUA_FUNCTION(fj_MusicStatus)
{
    int st = 0, done = 0, total = 0;
    const char* msg = "";
    FpvMusic_Status(&st, &done, &total, &msg);
    LUA->PushNumber((double)st);
    LUA->PushNumber((double)done);
    LUA->PushNumber((double)total);
    LUA->PushString(msg ? msg : "");
    return 4;
}

LUA_FUNCTION(fj_MusicClear)
{
    LUA->PushBool(FpvMusic_Clear());
    return 1;
}

static void SetFn(ILuaBase* LUA, const char* name, CFunc fn)
{
    LUA->PushCFunction(fn);
    LUA->SetField(-2, name);
}

GMOD_MODULE_OPEN()
{
    for (int i = 0; i < MAX_JOY; i++) g_capsValid[i] = false;
    LUA->PushSpecial(SPECIAL_GLOB);
    LUA->CreateTable();
    SetFn(LUA, "Version", fj_Version);
    SetFn(LUA, "Refresh", fj_Refresh);
    SetFn(LUA, "Count", fj_Count);
    SetFn(LUA, "Info", fj_Info);
    SetFn(LUA, "Read", fj_Read);
    SetFn(LUA, "HidScan", fj_HidScan);
    SetFn(LUA, "HidInfo", fj_HidInfo);
    SetFn(LUA, "HidRead", fj_HidRead);
    SetFn(LUA, "XInputRead", fj_XInputRead);
    SetFn(LUA, "MusicPickFolder", fj_MusicPickFolder);
    SetFn(LUA, "MusicImport", fj_MusicImport);
    SetFn(LUA, "MusicStatus", fj_MusicStatus);
    SetFn(LUA, "MusicClear", fj_MusicClear);
    LUA->SetField(-2, "fpvjoy");
    LUA->Pop();
    return 0;
}

GMOD_MODULE_CLOSE()
{
    FpvHid_CloseAll();
    return 0;
}
