#include "fpvhid.h"

#ifdef FPVJOY_FREESTANDING
extern "C" {
typedef void* HANDLE;
typedef unsigned int DWORD;
typedef unsigned int ULONG;
typedef int LONG;
typedef unsigned short USHORT;
typedef unsigned short USAGE;
typedef unsigned char UCHAR;
typedef unsigned char BOOLEAN;
typedef int BOOL;
typedef wchar_t WCHAR;
typedef int NTSTATUS;
typedef unsigned long long ULONG_PTR;
typedef void* PHIDP_PREPARSED_DATA;
typedef void* HDEVINFO;

struct GUID { unsigned int Data1; unsigned short Data2, Data3; unsigned char Data4[8]; };

struct OVERLAPPED {
    ULONG_PTR Internal;
    ULONG_PTR InternalHigh;
    DWORD Offset;
    DWORD OffsetHigh;
    HANDLE hEvent;
};

struct SP_DEVICE_INTERFACE_DATA {
    DWORD cbSize;
    GUID InterfaceClassGuid;
    DWORD Flags;
    ULONG_PTR Reserved;
};

struct SP_DEVICE_INTERFACE_DETAIL_DATA_W {
    DWORD cbSize;
    WCHAR DevicePath[1];
};

struct HIDD_ATTRIBUTES {
    ULONG Size;
    USHORT VendorID;
    USHORT ProductID;
    USHORT VersionNumber;
};

struct HIDP_CAPS {
    USAGE Usage;
    USAGE UsagePage;
    USHORT InputReportByteLength;
    USHORT OutputReportByteLength;
    USHORT FeatureReportByteLength;
    USHORT Reserved[17];
    USHORT NumberLinkCollectionNodes;
    USHORT NumberInputButtonCaps;
    USHORT NumberInputValueCaps;
    USHORT NumberInputDataIndices;
    USHORT NumberOutputButtonCaps;
    USHORT NumberOutputValueCaps;
    USHORT NumberOutputDataIndices;
    USHORT NumberFeatureButtonCaps;
    USHORT NumberFeatureValueCaps;
    USHORT NumberFeatureDataIndices;
};

struct HIDP_RANGE {
    USAGE UsageMin, UsageMax;
    USHORT StringMin, StringMax;
    USHORT DesignatorMin, DesignatorMax;
    USHORT DataIndexMin, DataIndexMax;
};
struct HIDP_NOTRANGE {
    USAGE Usage, Reserved1;
    USHORT StringIndex, Reserved2;
    USHORT DesignatorIndex, Reserved3;
    USHORT DataIndex, Reserved4;
};

struct HIDP_VALUE_CAPS {
    USAGE UsagePage;
    UCHAR ReportID;
    BOOLEAN IsAlias;
    USHORT BitField;
    USHORT LinkCollection;
    USAGE LinkUsage;
    USAGE LinkUsagePage;
    BOOLEAN IsRange;
    BOOLEAN IsStringRange;
    BOOLEAN IsDesignatorRange;
    BOOLEAN IsAbsolute;
    BOOLEAN HasNull;
    UCHAR Reserved;
    USHORT BitSize;
    USHORT ReportCount;
    USHORT Reserved2[5];
    ULONG UnitsExp;
    ULONG Units;
    LONG LogicalMin, LogicalMax;
    LONG PhysicalMin, PhysicalMax;
    union { HIDP_RANGE Range; HIDP_NOTRANGE NotRange; };
};

struct HIDP_BUTTON_CAPS {
    USAGE UsagePage;
    UCHAR ReportID;
    BOOLEAN IsAlias;
    USHORT BitField;
    USHORT LinkCollection;
    USAGE LinkUsage;
    USAGE LinkUsagePage;
    BOOLEAN IsRange;
    BOOLEAN IsStringRange;
    BOOLEAN IsDesignatorRange;
    BOOLEAN IsAbsolute;
    ULONG Reserved[10];
    union { HIDP_RANGE Range; HIDP_NOTRANGE NotRange; };
};

struct HIDP_DATA {
    USHORT DataIndex;
    USHORT Reserved;
    union { ULONG RawValue; BOOLEAN On; };
};

static_assert(sizeof(HIDP_CAPS) == 64, "HIDP_CAPS");
static_assert(__builtin_offsetof(HIDP_CAPS, InputReportByteLength) == 4, "HIDP_CAPS.InputReportByteLength");
static_assert(__builtin_offsetof(HIDP_CAPS, NumberInputButtonCaps) == 46, "HIDP_CAPS.NumberInputButtonCaps");
static_assert(__builtin_offsetof(HIDP_CAPS, NumberInputValueCaps) == 48, "HIDP_CAPS.NumberInputValueCaps");
static_assert(sizeof(HIDP_VALUE_CAPS) == 72, "HIDP_VALUE_CAPS");
static_assert(__builtin_offsetof(HIDP_VALUE_CAPS, IsRange) == 12, "HIDP_VALUE_CAPS.IsRange");
static_assert(__builtin_offsetof(HIDP_VALUE_CAPS, BitSize) == 18, "HIDP_VALUE_CAPS.BitSize");
static_assert(__builtin_offsetof(HIDP_VALUE_CAPS, ReportCount) == 20, "HIDP_VALUE_CAPS.ReportCount");
static_assert(__builtin_offsetof(HIDP_VALUE_CAPS, LogicalMin) == 40, "HIDP_VALUE_CAPS.LogicalMin");
static_assert(__builtin_offsetof(HIDP_VALUE_CAPS, Range) == 56, "HIDP_VALUE_CAPS.Range");
static_assert(sizeof(HIDP_BUTTON_CAPS) == 72, "HIDP_BUTTON_CAPS");
static_assert(__builtin_offsetof(HIDP_BUTTON_CAPS, IsRange) == 12, "HIDP_BUTTON_CAPS.IsRange");
static_assert(__builtin_offsetof(HIDP_BUTTON_CAPS, Range) == 56, "HIDP_BUTTON_CAPS.Range");
static_assert(sizeof(HIDD_ATTRIBUTES) == 12, "HIDD_ATTRIBUTES");
static_assert(sizeof(SP_DEVICE_INTERFACE_DATA) == 32, "SP_DEVICE_INTERFACE_DATA");
static_assert(sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA_W) == 8, "SP_DEVICE_INTERFACE_DETAIL_DATA_W");
static_assert(sizeof(OVERLAPPED) == 32, "OVERLAPPED");
static_assert(__builtin_offsetof(OVERLAPPED, hEvent) == 24, "OVERLAPPED.hEvent");
static_assert(sizeof(HIDP_DATA) == 8, "HIDP_DATA");

#define DIGCF_PRESENT 0x2
#define DIGCF_DEVICEINTERFACE 0x10
#define GENERIC_READ 0x80000000ul
#define GENERIC_WRITE 0x40000000ul
#define FILE_SHARE_READ 0x1
#define FILE_SHARE_WRITE 0x2
#define OPEN_EXISTING 3
#define FILE_FLAG_OVERLAPPED 0x40000000ul
#define ERROR_IO_PENDING 997
#define ERROR_IO_INCOMPLETE 996
#define HIDP_STATUS_SUCCESS 0x00110000
#define HidP_Input 0
#define INVALID_HANDLE_VALUE ((HANDLE)(long long)-1)

__declspec(dllimport) void __stdcall HidD_GetHidGuid(GUID* HidGuid);
__declspec(dllimport) BOOLEAN __stdcall HidD_GetAttributes(HANDLE h, HIDD_ATTRIBUTES* a);
__declspec(dllimport) BOOLEAN __stdcall HidD_GetPreparsedData(HANDLE h, PHIDP_PREPARSED_DATA* p);
__declspec(dllimport) BOOLEAN __stdcall HidD_FreePreparsedData(PHIDP_PREPARSED_DATA p);
__declspec(dllimport) BOOLEAN __stdcall HidD_GetProductString(HANDLE h, void* buf, ULONG len);
__declspec(dllimport) BOOLEAN __stdcall HidD_SetNumInputBuffers(HANDLE h, ULONG n);
__declspec(dllimport) NTSTATUS __stdcall HidP_GetCaps(PHIDP_PREPARSED_DATA p, HIDP_CAPS* caps);
__declspec(dllimport) NTSTATUS __stdcall HidP_GetValueCaps(int type, HIDP_VALUE_CAPS* c, USHORT* len, PHIDP_PREPARSED_DATA p);
__declspec(dllimport) NTSTATUS __stdcall HidP_GetButtonCaps(int type, HIDP_BUTTON_CAPS* c, USHORT* len, PHIDP_PREPARSED_DATA p);
__declspec(dllimport) NTSTATUS __stdcall HidP_GetData(int type, HIDP_DATA* list, ULONG* len, PHIDP_PREPARSED_DATA p, char* report, ULONG reportLen);

__declspec(dllimport) HDEVINFO __stdcall SetupDiGetClassDevsW(const GUID* g, const WCHAR* e, void* hwnd, DWORD flags);
__declspec(dllimport) BOOL __stdcall SetupDiEnumDeviceInterfaces(HDEVINFO d, void* devInfo, const GUID* g, DWORD idx, SP_DEVICE_INTERFACE_DATA* out);
__declspec(dllimport) BOOL __stdcall SetupDiGetDeviceInterfaceDetailW(HDEVINFO d, SP_DEVICE_INTERFACE_DATA* i, SP_DEVICE_INTERFACE_DETAIL_DATA_W* det, DWORD size, DWORD* req, void* devInfo);
__declspec(dllimport) BOOL __stdcall SetupDiDestroyDeviceInfoList(HDEVINFO d);

__declspec(dllimport) HANDLE __stdcall CreateFileW(const WCHAR* name, DWORD access, DWORD share, void* sa, DWORD disp, DWORD flags, HANDLE tmpl);
__declspec(dllimport) BOOL __stdcall ReadFile(HANDLE h, void* buf, DWORD n, DWORD* got, OVERLAPPED* ov);
__declspec(dllimport) BOOL __stdcall GetOverlappedResult(HANDLE h, OVERLAPPED* ov, DWORD* got, BOOL wait);
__declspec(dllimport) BOOL __stdcall CancelIo(HANDLE h);
__declspec(dllimport) BOOL __stdcall CloseHandle(HANDLE h);
__declspec(dllimport) HANDLE __stdcall CreateEventW(void* sa, BOOL manual, BOOL initial, const WCHAR* name);
__declspec(dllimport) BOOL __stdcall ResetEvent(HANDLE h);
__declspec(dllimport) DWORD __stdcall GetLastError(void);
__declspec(dllimport) int __stdcall WideCharToMultiByte(unsigned int cp, DWORD flags, const WCHAR* w, int wn, char* mb, int mbn, const char* def, BOOL* used);
}
#else
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <setupapi.h>
#include <hidsdi.h>
#include <hidpi.h>
#pragma comment(lib, "hid.lib")
#pragma comment(lib, "setupapi.lib")
#endif

namespace {

const int MAX_AXES = 16;
const int MAX_VCAPS = 32;
const int MAX_BCAPS = 16;
const int MAX_DATA = 128;
const int MAX_REPORT = 256;

struct Axis {
    unsigned short usagePage, usage, dataIndex, bitSize;
    long lmin, lmax;
    double value;
};

struct Device {
    bool used;
    bool alive;
    HANDLE h;
    HANDLE ev;
    OVERLAPPED ov;
    bool pending;
    PHIDP_PREPARSED_DATA pp;
    unsigned short vid, pid, usage, reportLen;
    char name[128];
    int nAxes;
    Axis axes[MAX_AXES];
    int nBtnRanges;
    unsigned short btnIdxMin[MAX_BCAPS], btnIdxMax[MAX_BCAPS], btnUsageMin[MAX_BCAPS];
    int nButtons;
    unsigned int buttons;
    unsigned int buttonsHi;
    unsigned long reports;
    char report[MAX_REPORT];
};

Device g_dev[FPVHID_MAX_DEVICES];
int g_count = 0;

void zero(void* p, unsigned long long n)
{
    volatile unsigned char* d = (volatile unsigned char*)p;
    while (n--) *d++ = 0;
}

void closeDevice(Device& d)
{
    if (d.h && d.h != INVALID_HANDLE_VALUE) {
        if (d.pending) CancelIo(d.h);
        CloseHandle(d.h);
    }
    if (d.ev) CloseHandle(d.ev);
    if (d.pp) HidD_FreePreparsedData(d.pp);
    zero(&d, sizeof(Device));
}

void sortAxes(Device& d)
{
    for (int i = 1; i < d.nAxes; i++) {
        Axis a = d.axes[i];
        int j = i - 1;
        while (j >= 0) {
            const Axis& b = d.axes[j];
            bool greater = b.usagePage > a.usagePage ||
                (b.usagePage == a.usagePage && (b.usage > a.usage || (b.usage == a.usage && b.dataIndex > a.dataIndex)));
            if (!greater) break;
            d.axes[j + 1] = d.axes[j];
            j--;
        }
        d.axes[j + 1] = a;
    }
}

bool isAxisUsage(unsigned short page, unsigned short usage)
{
    if (page == 0x01) return usage >= 0x30 && usage <= 0x38;
    if (page == 0x02) return usage >= 0xB0 && usage <= 0xC8;
    return false;
}

bool setup(Device& d)
{
    if (!HidD_GetPreparsedData(d.h, &d.pp)) return false;
    HIDP_CAPS caps;
    zero(&caps, sizeof(caps));
    if (HidP_GetCaps(d.pp, &caps) != (NTSTATUS)HIDP_STATUS_SUCCESS) return false;
    if (caps.UsagePage != 0x01 || !(caps.Usage == 0x04 || caps.Usage == 0x05 || caps.Usage == 0x08)) return false;
    d.usage = caps.Usage;
    d.reportLen = caps.InputReportByteLength;
    if (d.reportLen == 0 || d.reportLen > MAX_REPORT) return false;

    static HIDP_VALUE_CAPS vc[MAX_VCAPS];
    USHORT nv = caps.NumberInputValueCaps > MAX_VCAPS ? MAX_VCAPS : caps.NumberInputValueCaps;
    if (nv > 0 && HidP_GetValueCaps(HidP_Input, vc, &nv, d.pp) != (NTSTATUS)HIDP_STATUS_SUCCESS) nv = 0;
    for (int i = 0; i < nv && d.nAxes < MAX_AXES; i++) {
        const HIDP_VALUE_CAPS& c = vc[i];
        if (c.IsRange) {
            for (int u = c.Range.UsageMin; u <= c.Range.UsageMax && d.nAxes < MAX_AXES; u++) {
                if (!isAxisUsage(c.UsagePage, (unsigned short)u)) continue;
                Axis& a = d.axes[d.nAxes++];
                a.usagePage = c.UsagePage; a.usage = (unsigned short)u;
                a.dataIndex = (unsigned short)(c.Range.DataIndexMin + (u - c.Range.UsageMin));
                a.bitSize = c.BitSize; a.lmin = c.LogicalMin; a.lmax = c.LogicalMax; a.value = 0;
            }
        } else if (isAxisUsage(c.UsagePage, c.NotRange.Usage)) {
            Axis& a = d.axes[d.nAxes++];
            a.usagePage = c.UsagePage; a.usage = c.NotRange.Usage; a.dataIndex = c.NotRange.DataIndex;
            a.bitSize = c.BitSize; a.lmin = c.LogicalMin; a.lmax = c.LogicalMax; a.value = 0;
        }
    }
    sortAxes(d);

    static HIDP_BUTTON_CAPS bc[MAX_BCAPS];
    USHORT nb = caps.NumberInputButtonCaps > MAX_BCAPS ? MAX_BCAPS : caps.NumberInputButtonCaps;
    if (nb > 0 && HidP_GetButtonCaps(HidP_Input, bc, &nb, d.pp) != (NTSTATUS)HIDP_STATUS_SUCCESS) nb = 0;
    for (int i = 0; i < nb; i++) {
        const HIDP_BUTTON_CAPS& c = bc[i];
        if (c.UsagePage != 0x09) continue;
        int k = d.nBtnRanges++;
        if (c.IsRange) {
            d.btnIdxMin[k] = c.Range.DataIndexMin; d.btnIdxMax[k] = c.Range.DataIndexMax;
            d.btnUsageMin[k] = c.Range.UsageMin;
            int top = c.Range.UsageMax;
            if (top > d.nButtons) d.nButtons = top;
        } else {
            d.btnIdxMin[k] = d.btnIdxMax[k] = c.NotRange.DataIndex;
            d.btnUsageMin[k] = c.NotRange.Usage;
            if (c.NotRange.Usage > d.nButtons) d.nButtons = c.NotRange.Usage;
        }
    }
    if (d.nButtons > 64) d.nButtons = 64;
    return d.nAxes > 0 || d.nButtons > 0;
}

void parse(Device& d)
{
    static HIDP_DATA data[MAX_DATA];
    ULONG n = MAX_DATA;
    if (HidP_GetData(HidP_Input, data, &n, d.pp, d.report, d.reportLen) != (NTSTATUS)HIDP_STATUS_SUCCESS) return;
    unsigned int lo = 0, hi = 0;
    for (ULONG i = 0; i < n; i++) {
        unsigned short idx = data[i].DataIndex;
        bool done = false;
        for (int a = 0; a < d.nAxes; a++) {
            Axis& ax = d.axes[a];
            if (ax.dataIndex != idx) continue;
            long long raw = (long long)data[i].RawValue;
            if (ax.lmin < 0 && ax.bitSize > 0 && ax.bitSize < 32 && raw >= (1ll << (ax.bitSize - 1))) raw -= (1ll << ax.bitSize);
            double span = (double)ax.lmax - (double)ax.lmin;
            double t = span > 0 ? ((double)raw - (double)ax.lmin) / span : 0.5;
            if (t < 0) t = 0;
            if (t > 1) t = 1;
            ax.value = t * 2.0 - 1.0;
            done = true;
            break;
        }
        if (done) continue;
        for (int b = 0; b < d.nBtnRanges; b++) {
            if (idx >= d.btnIdxMin[b] && idx <= d.btnIdxMax[b]) {
                if (data[i].On) {
                    int btn = d.btnUsageMin[b] + (idx - d.btnIdxMin[b]);
                    if (btn >= 1 && btn <= 32) lo |= 1u << (btn - 1);
                    else if (btn >= 33 && btn <= 64) hi |= 1u << (btn - 33);
                }
                break;
            }
        }
    }
    d.buttons = lo;
    d.buttonsHi = hi;
    d.reports++;
}

bool startRead(Device& d)
{
    for (int guard = 0; guard < 32; guard++) {
        ResetEvent(d.ev);
        zero(&d.ov, sizeof(d.ov));
        d.ov.hEvent = d.ev;
        DWORD got = 0;
        if (ReadFile(d.h, d.report, d.reportLen, &got, &d.ov)) {
            if (got > 0) parse(d);
            continue;
        }
        DWORD err = GetLastError();
        if (err == ERROR_IO_PENDING) { d.pending = true; return true; }
        d.pending = false;
        return false;
    }
    d.pending = false;
    return true;
}

void utf8(const WCHAR* w, char* out, int outLen)
{
    int n = WideCharToMultiByte(65001, 0, w, -1, out, outLen, 0, 0);
    if (n <= 0) { out[0] = 'H'; out[1] = 'I'; out[2] = 'D'; out[3] = 0; }
}

}

int FpvHid_Scan()
{
    for (int i = 0; i < FPVHID_MAX_DEVICES; i++) if (g_dev[i].used) closeDevice(g_dev[i]);
    g_count = 0;

    GUID hidGuid;
    HidD_GetHidGuid(&hidGuid);
    HDEVINFO info = SetupDiGetClassDevsW(&hidGuid, 0, 0, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
    if (info == INVALID_HANDLE_VALUE || info == 0) return 0;

    alignas(8) static unsigned char detailBuf[2048];
    for (DWORD idx = 0; idx < 256 && g_count < FPVHID_MAX_DEVICES; idx++) {
        SP_DEVICE_INTERFACE_DATA ifd;
        zero(&ifd, sizeof(ifd));
        ifd.cbSize = sizeof(ifd);
        if (!SetupDiEnumDeviceInterfaces(info, 0, &hidGuid, idx, &ifd)) break;
        SP_DEVICE_INTERFACE_DETAIL_DATA_W* det = (SP_DEVICE_INTERFACE_DETAIL_DATA_W*)detailBuf;
        zero(detailBuf, sizeof(detailBuf));
        det->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA_W);
        DWORD req = 0;
        if (!SetupDiGetDeviceInterfaceDetailW(info, &ifd, det, sizeof(detailBuf), &req, 0)) continue;

        HANDLE h = CreateFileW(det->DevicePath, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, 0,
            OPEN_EXISTING, FILE_FLAG_OVERLAPPED, 0);
        if (h == INVALID_HANDLE_VALUE)
            h = CreateFileW(det->DevicePath, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, 0, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, 0);
        if (h == INVALID_HANDLE_VALUE) continue;

        Device& d = g_dev[g_count];
        zero(&d, sizeof(Device));
        d.h = h;
        HIDD_ATTRIBUTES at;
        zero(&at, sizeof(at));
        at.Size = sizeof(at);
        if (HidD_GetAttributes(h, &at)) { d.vid = at.VendorID; d.pid = at.ProductID; }
        if (!setup(d)) { closeDevice(d); continue; }
        WCHAR wname[128];
        zero(wname, sizeof(wname));
        if (HidD_GetProductString(h, wname, sizeof(wname) - 2)) utf8(wname, d.name, sizeof(d.name));
        else utf8(L"HID joystick", d.name, sizeof(d.name));
        HidD_SetNumInputBuffers(h, 8);
        d.ev = CreateEventW(0, 1, 0, 0);
        if (!d.ev) { closeDevice(d); continue; }
        d.used = true;
        d.alive = startRead(d);
        if (!d.alive) { closeDevice(d); continue; }
        g_count++;
    }
    SetupDiDestroyDeviceInfoList(info);
    return g_count;
}

int FpvHid_Count() { return g_count; }

bool FpvHid_Info(int i, const char** name, int* vid, int* pid, int* axes, int* buttons, int* usage)
{
    if (i < 0 || i >= g_count || !g_dev[i].used) return false;
    Device& d = g_dev[i];
    *name = d.name; *vid = d.vid; *pid = d.pid; *axes = d.nAxes; *buttons = d.nButtons; *usage = d.usage;
    return true;
}

bool FpvHid_Read(int i, double* axes, int maxAxes, unsigned int* buttons, unsigned int* buttonsHi, unsigned long* reports)
{
    if (i < 0 || i >= g_count || !g_dev[i].used || !g_dev[i].alive) return false;
    Device& d = g_dev[i];
    for (int guard = 0; guard < 64 && d.pending; guard++) {
        DWORD got = 0;
        if (GetOverlappedResult(d.h, &d.ov, &got, 0)) {
            d.pending = false;
            if (got > 0) parse(d);
            if (!startRead(d)) { d.alive = false; return false; }
        } else {
            DWORD err = GetLastError();
            if (err == ERROR_IO_INCOMPLETE || err == ERROR_IO_PENDING) break;
            d.alive = false;
            d.pending = false;
            return false;
        }
    }
    for (int a = 0; a < maxAxes; a++) axes[a] = a < d.nAxes ? d.axes[a].value : 0.0;
    *buttons = d.buttons;
    *buttonsHi = d.buttonsHi;
    *reports = d.reports;
    return true;
}

void FpvHid_CloseAll()
{
    for (int i = 0; i < FPVHID_MAX_DEVICES; i++) if (g_dev[i].used) closeDevice(g_dev[i]);
    g_count = 0;
}
