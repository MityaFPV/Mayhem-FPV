#include "fpvmusic.h"

#if defined(FPVJOY_FREESTANDING) || defined(FPVMUSIC_STUB)
extern "C" {
typedef unsigned int DWORD;
typedef unsigned int UINT;
typedef int BOOL;
typedef unsigned short WCHAR;
typedef void* HANDLE;
typedef void* HWND;
typedef void* HMODULE;
typedef long long LPARAM;
typedef unsigned long long SIZE_T;
typedef long HRESULT;
typedef struct { DWORD lo, hi; } FILETIME_;
typedef struct {
    DWORD dwFileAttributes;
    FILETIME_ ftCreationTime, ftLastAccessTime, ftLastWriteTime;
    DWORD nFileSizeHigh, nFileSizeLow, dwReserved0, dwReserved1;
    WCHAR cFileName[260];
    WCHAR cAlternateFileName[14];
} WIN32_FIND_DATAW_;
static_assert(sizeof(WIN32_FIND_DATAW_) == 592, "WIN32_FIND_DATAW layout");
typedef struct {
    HWND hwndOwner;
    void* pidlRoot;
    WCHAR* pszDisplayName;
    const WCHAR* lpszTitle;
    UINT ulFlags;
    void* lpfn;
    LPARAM lParam;
    int iImage;
} BROWSEINFOW_;
static_assert(sizeof(BROWSEINFOW_) == 64, "BROWSEINFOW layout");
typedef DWORD(__stdcall* THREADPROC_)(void*);

__declspec(dllimport) int __stdcall MultiByteToWideChar(UINT, DWORD, const char*, int, WCHAR*, int);
__declspec(dllimport) int __stdcall WideCharToMultiByte(UINT, DWORD, const WCHAR*, int, char*, int, const char*, BOOL*);
__declspec(dllimport) HANDLE __stdcall FindFirstFileW(const WCHAR*, WIN32_FIND_DATAW_*);
__declspec(dllimport) BOOL __stdcall FindNextFileW(HANDLE, WIN32_FIND_DATAW_*);
__declspec(dllimport) BOOL __stdcall FindClose(HANDLE);
__declspec(dllimport) BOOL __stdcall CopyFileW(const WCHAR*, const WCHAR*, BOOL);
__declspec(dllimport) BOOL __stdcall CreateDirectoryW(const WCHAR*, void*);
__declspec(dllimport) BOOL __stdcall DeleteFileW(const WCHAR*);
__declspec(dllimport) DWORD __stdcall GetFileAttributesW(const WCHAR*);
__declspec(dllimport) DWORD __stdcall GetModuleFileNameW(HMODULE, WCHAR*, DWORD);
__declspec(dllimport) BOOL __stdcall GetModuleHandleExW(DWORD, const WCHAR*, HMODULE*);
__declspec(dllimport) HANDLE __stdcall CreateFileW(const WCHAR*, DWORD, DWORD, void*, DWORD, DWORD, HANDLE);
__declspec(dllimport) BOOL __stdcall WriteFile(HANDLE, const void*, DWORD, DWORD*, void*);
__declspec(dllimport) BOOL __stdcall CloseHandle(HANDLE);
__declspec(dllimport) HANDLE __stdcall CreateThread(void*, SIZE_T, THREADPROC_, void*, DWORD, DWORD*);
__declspec(dllimport) HWND __stdcall GetForegroundWindow(void);
__declspec(dllimport) void* __stdcall SHBrowseForFolderW(BROWSEINFOW_*);
__declspec(dllimport) BOOL __stdcall SHGetPathFromIDListW(void*, WCHAR*);
__declspec(dllimport) void __stdcall CoTaskMemFree(void*);
__declspec(dllimport) HRESULT __stdcall CoInitializeEx(void*, DWORD);
}
typedef WIN32_FIND_DATAW_ FINDDATA;
typedef BROWSEINFOW_ BROWSEINFO_T;
#define INVALID_HANDLE ((HANDLE)(long long)-1)
#else
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shlobj.h>
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "ole32.lib")
typedef WIN32_FIND_DATAW FINDDATA;
typedef BROWSEINFOW BROWSEINFO_T;
#define INVALID_HANDLE INVALID_HANDLE_VALUE
#endif

#define CP_UTF8_ 65001
#define FILE_ATTRIBUTE_DIRECTORY_ 0x10
#define INVALID_ATTR_ 0xFFFFFFFFu

static const int MAXP = 520;
static const int MAX_TRACKS = 400;

static WCHAR g_src[MAXP];
static WCHAR g_dst[MAXP];
static WCHAR g_list[MAX_TRACKS][MAXP];
static volatile int g_state = 0, g_done = 0, g_total = 0;
static const char* volatile g_msg = "";
static WCHAR g_tmp[MAXP], g_tmp2[MAXP];
static char g_line[2048];
static FINDDATA g_fd[4];

static int wlen(const WCHAR* s) { int n = 0; while (s[n]) n++; return n; }
static bool wcpy(WCHAR* d, const WCHAR* s, int cap)
{
    int n = wlen(s);
    if (n >= cap) return false;
    for (int i = 0; i <= n; i++) d[i] = s[i];
    return true;
}
static bool wcat(WCHAR* d, const WCHAR* s, int cap)
{
    int a = wlen(d), b = wlen(s);
    if (a + b >= cap) return false;
    for (int i = 0; i <= b; i++) d[a + i] = s[i];
    return true;
}
static bool wcatA(WCHAR* d, const char* s, int cap)
{
    int a = wlen(d), b = 0;
    while (s[b]) b++;
    if (a + b >= cap) return false;
    for (int i = 0; i <= b; i++) d[a + i] = (WCHAR)(unsigned char)s[i];
    return true;
}
static WCHAR lower(WCHAR c) { return (c >= 'A' && c <= 'Z') ? (WCHAR)(c + 32) : c; }

static const WCHAR* audioExt(const WCHAR* name)
{
    int n = wlen(name);
    if (n < 5 || name[n - 4] != '.') return 0;
    WCHAR a = lower(name[n - 3]), b = lower(name[n - 2]), c = lower(name[n - 1]);
    if ((a == 'm' && b == 'p' && c == '3') || (a == 'o' && b == 'g' && c == 'g') || (a == 'w' && b == 'a' && c == 'v'))
        return name + n - 4;
    return 0;
}

static bool isDots(const WCHAR* n) { return n[0] == '.' && (n[1] == 0 || (n[1] == '.' && n[2] == 0)); }

static bool gmodDir(WCHAR* out)
{
    HMODULE self = 0;
    if (!GetModuleHandleExW(0x4 | 0x2, (const WCHAR*)(void*)&gmodDir, &self)) return false;
    DWORD n = GetModuleFileNameW(self, out, MAXP);
    if (n == 0 || n >= (DWORD)MAXP) return false;
    for (int up = 0; up < 3; up++) {
        int i = wlen(out) - 1;
        while (i >= 0 && out[i] != '\\' && out[i] != '/') i--;
        if (i < 0) return false;
        out[i] = 0;
    }
    return true;
}

static bool userDir(WCHAR* out, bool create)
{
    if (!gmodDir(out)) return false;
    if (!wcatA(out, "\\sound", MAXP)) return false;
    if (create) CreateDirectoryW(out, 0);
    if (!wcatA(out, "\\mayhem_music", MAXP)) return false;
    if (create) CreateDirectoryW(out, 0);
    if (!wcatA(out, "\\user", MAXP)) return false;
    if (create) CreateDirectoryW(out, 0);
    return true;
}

static void clearDir(const WCHAR* dir)
{
    if (!wcpy(g_tmp, dir, MAXP) || !wcatA(g_tmp, "\\*", MAXP)) return;
    FINDDATA fd;
    HANDLE h = FindFirstFileW(g_tmp, &fd);
    if (h == INVALID_HANDLE) return;
    do {
        if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY_)) {
            if (wcpy(g_tmp2, dir, MAXP) && wcatA(g_tmp2, "\\", MAXP) && wcat(g_tmp2, fd.cFileName, MAXP)) DeleteFileW(g_tmp2);
        }
    } while (FindNextFileW(h, &fd));
    FindClose(h);
}

static void scan(const WCHAR* dir, int depth)
{
    static WCHAR pat[4][MAXP];
    static WCHAR sub[4][MAXP];
    if (depth > 3 || g_total >= MAX_TRACKS) return;
    if (!wcpy(pat[depth], dir, MAXP) || !wcatA(pat[depth], "\\*", MAXP)) return;
    FINDDATA* fd = &g_fd[depth];
    HANDLE h = FindFirstFileW(pat[depth], fd);
    if (h == INVALID_HANDLE) return;
    do {
        if (isDots(fd->cFileName)) continue;
        if (!wcpy(sub[depth], dir, MAXP) || !wcatA(sub[depth], "\\", MAXP) || !wcat(sub[depth], fd->cFileName, MAXP)) continue;
        if (fd->dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY_) {
            if (depth < 3) scan(sub[depth], depth + 1);
        } else if (audioExt(fd->cFileName) && g_total < MAX_TRACKS) {
            wcpy(g_list[g_total], sub[depth], MAXP);
            g_total = g_total + 1;
        }
    } while (g_total < MAX_TRACKS && FindNextFileW(h, fd));
    FindClose(h);
}

static int wcmpi(const WCHAR* a, const WCHAR* b)
{
    for (int i = 0;; i++) {
        WCHAR x = lower(a[i]), y = lower(b[i]);
        if (x != y || !x) return (int)x - (int)y;
    }
}
static void sortList()
{
    for (int i = 1; i < g_total; i++) {
        wcpy(g_tmp, g_list[i], MAXP);
        int j = i - 1;
        while (j >= 0 && wcmpi(g_list[j], g_tmp) > 0) { wcpy(g_list[j + 1], g_list[j], MAXP); j--; }
        wcpy(g_list[j + 1], g_tmp, MAXP);
    }
}

static void num3(char* out, int v)
{
    out[0] = (char)('0' + (v / 100) % 10);
    out[1] = (char)('0' + (v / 10) % 10);
    out[2] = (char)('0' + v % 10);
    out[3] = 0;
}

static DWORD __stdcall importThread(void*)
{
    if (!userDir(g_dst, true)) { g_msg = "can't find the garrysmod folder"; g_state = 3; return 0; }
    clearDir(g_dst);
    g_total = 0;
    scan(g_src, 0);
    if (g_total == 0) { g_msg = "no .mp3 / .ogg / .wav files in that folder"; g_state = 3; return 0; }
    sortList();

    if (!wcpy(g_tmp, g_dst, MAXP) || !wcatA(g_tmp, "\\index.txt", MAXP)) { g_msg = "path too long"; g_state = 3; return 0; }
    HANDLE idx = CreateFileW(g_tmp, 0x40000000u , 0, 0, 2 , 0x80, 0);
    int copied = 0;
    for (int i = 0; i < g_total; i++) {
        const WCHAR* src = g_list[i];
        const WCHAR* ext = audioExt(src);
        char nm[8];
        num3(nm, copied + 1);
        if (!wcpy(g_tmp2, g_dst, MAXP) || !wcatA(g_tmp2, "\\track_", MAXP) || !wcatA(g_tmp2, nm, MAXP)) continue;
        char e[5] = { '.', (char)lower(ext[1]), (char)lower(ext[2]), (char)lower(ext[3]), 0 };
        wcatA(g_tmp2, e, MAXP);
        if (CopyFileW(src, g_tmp2, 0)) {
            copied++;
            if (idx != INVALID_HANDLE) {
                int s = wlen(src);
                int b = s;
                while (b > 0 && src[b - 1] != '\\' && src[b - 1] != '/') b--;
                int len = (int)(ext - src) - b;
                int p = 0;
                g_line[p++] = 't'; g_line[p++] = 'r'; g_line[p++] = 'a'; g_line[p++] = 'c'; g_line[p++] = 'k'; g_line[p++] = '_';
                g_line[p++] = nm[0]; g_line[p++] = nm[1]; g_line[p++] = nm[2];
                for (int k = 0; k < 4; k++) g_line[p++] = e[k];
                g_line[p++] = '\t';
                int w = WideCharToMultiByte(CP_UTF8_, 0, src + b, len, g_line + p, (int)sizeof(g_line) - p - 2, 0, 0);
                if (w > 0) p += w;
                g_line[p++] = '\n';
                DWORD wr = 0;
                WriteFile(idx, g_line, (DWORD)p, &wr, 0);
            }
        }
        g_done = i + 1;
    }
    if (idx != INVALID_HANDLE) CloseHandle(idx);
    g_total = copied;
    g_done = copied;
    g_msg = copied > 0 ? "ok" : "copying failed";
    g_state = copied > 0 ? 2 : 3;
    return 0;
}

bool FpvMusic_StartImport(const char* srcUtf8)
{
    if (g_state == 1) return false;
    int n = MultiByteToWideChar(CP_UTF8_, 0, srcUtf8, -1, g_src, MAXP);
    if (n <= 0) { g_msg = "bad folder name"; g_state = 3; return false; }
    int l = wlen(g_src);
    while (l > 3 && (g_src[l - 1] == '\\' || g_src[l - 1] == '/')) g_src[--l] = 0;
    DWORD a = GetFileAttributesW(g_src);
    if (a == INVALID_ATTR_ || !(a & FILE_ATTRIBUTE_DIRECTORY_)) { g_msg = "folder not found"; g_state = 3; return false; }
    g_done = 0;
    g_total = 0;
    g_msg = "copying";
    g_state = 1;
    HANDLE t = CreateThread(0, 0, importThread, 0, 0, 0);
    if (!t) { g_msg = "couldn't start the copy"; g_state = 3; return false; }
    CloseHandle(t);
    return true;
}

void FpvMusic_Status(int* state, int* done, int* total, const char** message)
{
    *state = g_state;
    *done = g_done;
    *total = g_total;
    *message = g_msg;
}

bool FpvMusic_Clear()
{
    if (g_state == 1) return false;
    if (!userDir(g_dst, false)) return false;
    clearDir(g_dst);
    g_state = 0;
    return true;
}

bool FpvMusic_PickFolder(char* outUtf8, int cap)
{
    static WCHAR display[MAXP];
    static WCHAR path[MAXP];
    static const char* titleA = "Choose your music folder (mp3 / ogg / wav)";
    static WCHAR title[64];
    int i = 0;
    for (; titleA[i] && i < 63; i++) title[i] = (WCHAR)titleA[i];
    title[i] = 0;
    CoInitializeEx(0, 0x2 );
    BROWSEINFO_T bi;
    unsigned char* z = (unsigned char*)&bi;
    for (unsigned k = 0; k < sizeof(bi); k++) z[k] = 0;
    bi.hwndOwner = GetForegroundWindow();
    bi.pszDisplayName = display;
    bi.lpszTitle = title;
    bi.ulFlags = 0x1  | 0x40  | 0x200 ;
    void* pidl = SHBrowseForFolderW(&bi);
    if (!pidl) return false;
    BOOL ok = SHGetPathFromIDListW(pidl, path);
    CoTaskMemFree(pidl);
    if (!ok) return false;
    int n = WideCharToMultiByte(CP_UTF8_, 0, path, -1, outUtf8, cap, 0, 0);
    return n > 0;
}
