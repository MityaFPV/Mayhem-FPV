#include <cstdio>
#include <cstring>
#define FPVJOY_FREESTANDING
#include "../src/fpvhid.cpp"

static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL %s:%d ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } else { printf("ok   "); printf(__VA_ARGS__); printf("\n"); } } while (0)

static unsigned short fakeAxis[8];
static bool fakeBtn[24];
static int pendingReports = 0;
static DWORD lastErr = 0;
static bool unplugged = false;
static int readsIssued = 0;
static HANDLE FAKE_H = (HANDLE)0x1234, FAKE_EV = (HANDLE)0x5678, FAKE_INFO = (HANDLE)0x9abc;
static int enumCalls = 0;

extern "C" {
void __stdcall HidD_GetHidGuid(GUID* g) { memset(g, 0, sizeof(*g)); }
HDEVINFO __stdcall SetupDiGetClassDevsW(const GUID*, const WCHAR*, void*, DWORD) { return FAKE_INFO; }
BOOL __stdcall SetupDiEnumDeviceInterfaces(HDEVINFO, void*, const GUID*, DWORD idx, SP_DEVICE_INTERFACE_DATA* d) { enumCalls++; return idx < 2; }
BOOL __stdcall SetupDiGetDeviceInterfaceDetailW(HDEVINFO, SP_DEVICE_INTERFACE_DATA*, SP_DEVICE_INTERFACE_DETAIL_DATA_W* det, DWORD, DWORD*, void*) {
    det->DevicePath[0] = 'x'; return 1; }
BOOL __stdcall SetupDiDestroyDeviceInfoList(HDEVINFO) { return 1; }
static int opened = 0;
HANDLE __stdcall CreateFileW(const WCHAR*, DWORD, DWORD, void*, DWORD, DWORD, HANDLE) {
    return (opened++ == 0) ? FAKE_H : INVALID_HANDLE_VALUE; }
BOOLEAN __stdcall HidD_GetAttributes(HANDLE, HIDD_ATTRIBUTES* a) { a->VendorID = 0x1209; a->ProductID = 0x4F54; return 1; }
BOOLEAN __stdcall HidD_GetPreparsedData(HANDLE, PHIDP_PREPARSED_DATA* p) { *p = (void*)0x77; return 1; }
BOOLEAN __stdcall HidD_FreePreparsedData(PHIDP_PREPARSED_DATA) { return 1; }
BOOLEAN __stdcall HidD_GetProductString(HANDLE, void* buf, ULONG) { const WCHAR* n = L"EdgeTX TX12"; int k = 0; while (n[k]) k++; memcpy(buf, n, (k + 1) * sizeof(WCHAR)); return 1; }
BOOLEAN __stdcall HidD_SetNumInputBuffers(HANDLE, ULONG) { return 1; }
NTSTATUS __stdcall HidP_GetCaps(PHIDP_PREPARSED_DATA, HIDP_CAPS* c) {
    memset(c, 0, sizeof(*c)); c->UsagePage = 1; c->Usage = 5; c->InputReportByteLength = 20;
    c->NumberInputButtonCaps = 1; c->NumberInputValueCaps = 8; return HIDP_STATUS_SUCCESS; }
NTSTATUS __stdcall HidP_GetValueCaps(int, HIDP_VALUE_CAPS* c, USHORT* len, PHIDP_PREPARSED_DATA) {
    unsigned short usages[8] = { 0x36, 0x35, 0x30, 0x36, 0x31, 0x34, 0x32, 0x33 };
    unsigned short idx[8]    = { 30,   29,   24,   31,   25,   28,   26,   27 };
    for (int i = 0; i < 8; i++) {
        memset(&c[i], 0, sizeof(c[i]));
        c[i].UsagePage = 1; c[i].IsRange = 0; c[i].BitSize = 16; c[i].ReportCount = 1;
        c[i].LogicalMin = 0; c[i].LogicalMax = 2047;
        c[i].NotRange.Usage = usages[i]; c[i].NotRange.DataIndex = idx[i];
    }
    *len = 8; return HIDP_STATUS_SUCCESS; }
NTSTATUS __stdcall HidP_GetButtonCaps(int, HIDP_BUTTON_CAPS* c, USHORT* len, PHIDP_PREPARSED_DATA) {
    memset(c, 0, sizeof(*c)); c->UsagePage = 9; c->IsRange = 1;
    c->Range.UsageMin = 1; c->Range.UsageMax = 24; c->Range.DataIndexMin = 0; c->Range.DataIndexMax = 23;
    *len = 1; return HIDP_STATUS_SUCCESS; }
NTSTATUS __stdcall HidP_GetData(int, HIDP_DATA* list, ULONG* len, PHIDP_PREPARSED_DATA, char*, ULONG) {
    ULONG n = 0;
    for (int b = 0; b < 24; b++) if (fakeBtn[b]) { list[n].DataIndex = b; list[n].On = 1; n++; }
    for (int a = 0; a < 8; a++) { list[n].DataIndex = 24 + a; list[n].RawValue = fakeAxis[a]; n++; }
    *len = n; return HIDP_STATUS_SUCCESS; }
BOOL __stdcall ReadFile(HANDLE, void*, DWORD, DWORD* got, OVERLAPPED*) {
    readsIssued++;
    if (unplugged) { lastErr = 1167; return 0; }
    lastErr = ERROR_IO_PENDING; return 0; }
BOOL __stdcall GetOverlappedResult(HANDLE, OVERLAPPED*, DWORD* got, BOOL) {
    if (unplugged) { lastErr = 1167; return 0; }
    if (pendingReports > 0) { pendingReports--; *got = 20; return 1; }
    lastErr = ERROR_IO_INCOMPLETE; return 0; }
BOOL __stdcall CancelIo(HANDLE) { return 1; }
BOOL __stdcall CloseHandle(HANDLE) { return 1; }
HANDLE __stdcall CreateEventW(void*, BOOL, BOOL, const WCHAR*) { return FAKE_EV; }
BOOL __stdcall ResetEvent(HANDLE) { return 1; }
DWORD __stdcall GetLastError(void) { return lastErr; }
int __stdcall WideCharToMultiByte(unsigned int, DWORD, const WCHAR* w, int, char* mb, int n, const char*, BOOL*) {
    int i = 0; for (; w[i] && i < n - 1; i++) mb[i] = (char)w[i]; mb[i] = 0; return i + 1; }
}

int main()
{
    int n = FpvHid_Scan();
    CHECK(n == 1, "scan finds the radio, skips the keyboard (%d)", n);
    const char* name; int vid, pid, axes, buttons, usage;
    bool ok = FpvHid_Info(0, &name, &vid, &pid, &axes, &buttons, &usage);
    CHECK(ok && strcmp(name, "EdgeTX TX12") == 0 && vid == 0x1209 && pid == 0x4F54, "info: %s %04X:%04X", ok ? name : "?", vid, pid);
    CHECK(axes == 8 && buttons == 24 && usage == 5, "8 axes, 24 buttons, gamepad (%d, %d, %d)", axes, buttons, usage);

    unsigned short raw[8] = { 0, 2047, 1024, 512, 1536, 100, 2047, 0 };
    memcpy(fakeAxis, raw, sizeof(raw));
    fakeBtn[0] = fakeBtn[4] = fakeBtn[23] = true;
    pendingReports = 3;
    double a[8]; unsigned lo, hi; unsigned long reps;
    ok = FpvHid_Read(0, a, 8, &lo, &hi, &reps);
    CHECK(ok && reps == 3, "drained 3 queued reports (%lu)", reps);
    double expect[8];
    for (int i = 0; i < 8; i++) expect[i] = raw[i] / 2047.0 * 2 - 1;
    bool order = true;
    for (int i = 0; i < 8; i++) if (a[i] < expect[i] - 1e-9 || a[i] > expect[i] + 1e-9) order = false;
    CHECK(order, "axes in channel order: %.2f %.2f %.2f %.2f %.2f %.2f %.2f %.2f", a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7]);
    CHECK(lo == ((1u << 0) | (1u << 4) | (1u << 23)) && hi == 0, "buttons 1, 5, 24 (0x%X)", lo);

    ok = FpvHid_Read(0, a, 8, &lo, &hi, &reps);
    CHECK(ok && reps == 3, "idle poll keeps last values");

    unplugged = true;
    pendingReports = 0;
    ok = FpvHid_Read(0, a, 8, &lo, &hi, &reps);
    CHECK(!ok, "unplug detected");
    unplugged = false;
    opened = 0;
    n = FpvHid_Scan();
    CHECK(n == 1, "rescan after replug");
    FpvHid_CloseAll();
    CHECK(FpvHid_Count() == 0, "close all");
    printf(fails ? "%d FAILURE(S)\n" : "ALL HID TESTS PASSED\n", fails);
    return fails != 0;
}
