#define FPVMUSIC_STUB 1
#include "../src/fpvmusic.cpp"

#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <string>
#include <vector>
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>

static std::string g_root;
static int fails = 0;
#define CHECK(c, m) do { if (c) printf("ok   %s\n", m); else { printf("FAIL %s\n", m); fails++; } } while (0)

static std::string toU8(const WCHAR* w, int n = -1)
{
    std::string s;
    for (int i = 0; n < 0 ? w[i] : i < n; i++) {
        unsigned c = w[i];
        if (c >= 0xD800 && c < 0xDC00 && (n < 0 || i + 1 < n)) { c = 0x10000 + ((c - 0xD800) << 10) + (w[i + 1] - 0xDC00); i++; }
        if (c < 0x80) s += (char)c;
        else if (c < 0x800) { s += (char)(0xC0 | c >> 6); s += (char)(0x80 | (c & 63)); }
        else if (c < 0x10000) { s += (char)(0xE0 | c >> 12); s += (char)(0x80 | ((c >> 6) & 63)); s += (char)(0x80 | (c & 63)); }
        else { s += (char)(0xF0 | c >> 18); s += (char)(0x80 | ((c >> 12) & 63)); s += (char)(0x80 | ((c >> 6) & 63)); s += (char)(0x80 | (c & 63)); }
    }
    return s;
}
static std::vector<WCHAR> toW(const char* s)
{
    std::vector<WCHAR> w;
    const unsigned char* p = (const unsigned char*)s;
    while (*p) {
        unsigned c;
        if (*p < 0x80) c = *p++;
        else if ((*p & 0xE0) == 0xC0) { c = (*p & 31) << 6 | (p[1] & 63); p += 2; }
        else if ((*p & 0xF0) == 0xE0) { c = (*p & 15) << 12 | (p[1] & 63) << 6 | (p[2] & 63); p += 3; }
        else { c = (*p & 7) << 18 | (p[1] & 63) << 12 | (p[2] & 63) << 6 | (p[3] & 63); p += 4; }
        if (c >= 0x10000) { c -= 0x10000; w.push_back((WCHAR)(0xD800 + (c >> 10))); w.push_back((WCHAR)(0xDC00 + (c & 1023))); }
        else w.push_back((WCHAR)c);
    }
    w.push_back(0);
    return w;
}
static std::string posix(const WCHAR* w)
{
    std::string s = toU8(w);
    for (auto& c : s) if (c == '\\') c = '/';
    return s;
}

extern "C" {
int __stdcall MultiByteToWideChar(UINT, DWORD, const char* s, int, WCHAR* out, int cap)
{
    auto w = toW(s);
    if ((int)w.size() > cap) return 0;
    for (size_t i = 0; i < w.size(); i++) out[i] = w[i];
    return (int)w.size();
}
int __stdcall WideCharToMultiByte(UINT, DWORD, const WCHAR* w, int n, char* out, int cap, const char*, BOOL*)
{
    std::string s = toU8(w, n);
    if (n < 0) s += '\0';
    if ((int)s.size() > cap) return 0;
    memcpy(out, s.data(), s.size());
    return (int)s.size();
}
struct FindH { DIR* d; std::string dir; };
static bool fill(FindH* h, WIN32_FIND_DATAW_* fd)
{
    for (;;) {
        dirent* e = readdir(h->d);
        if (!e) return false;
        memset(fd, 0, sizeof(*fd));
        std::string full = h->dir + "/" + e->d_name;
        struct stat st;
        stat(full.c_str(), &st);
        fd->dwFileAttributes = S_ISDIR(st.st_mode) ? 0x10 : 0x80;
        auto w = toW(e->d_name);
        for (size_t i = 0; i < w.size() && i < 259; i++) fd->cFileName[i] = w[i];
        return true;
    }
}
HANDLE __stdcall FindFirstFileW(const WCHAR* pat, WIN32_FIND_DATAW_* fd)
{
    std::string p = posix(pat);
    if (p.size() < 2 || p.substr(p.size() - 2) != "/*") return INVALID_HANDLE;
    std::string dir = p.substr(0, p.size() - 2);
    DIR* d = opendir(dir.c_str());
    if (!d) return INVALID_HANDLE;
    FindH* h = new FindH{ d, dir };
    if (!fill(h, fd)) { closedir(d); delete h; return INVALID_HANDLE; }
    return h;
}
BOOL __stdcall FindNextFileW(HANDLE h, WIN32_FIND_DATAW_* fd) { return fill((FindH*)h, fd); }
BOOL __stdcall FindClose(HANDLE h) { closedir(((FindH*)h)->d); delete (FindH*)h; return 1; }
BOOL __stdcall CopyFileW(const WCHAR* a, const WCHAR* b, BOOL)
{
    FILE* in = fopen(posix(a).c_str(), "rb");
    if (!in) return 0;
    FILE* out = fopen(posix(b).c_str(), "wb");
    if (!out) { fclose(in); return 0; }
    char buf[4096];
    size_t n;
    while ((n = fread(buf, 1, sizeof buf, in)) > 0) fwrite(buf, 1, n, out);
    fclose(in); fclose(out);
    return 1;
}
BOOL __stdcall CreateDirectoryW(const WCHAR* p, void*) { return mkdir(posix(p).c_str(), 0755) == 0; }
BOOL __stdcall DeleteFileW(const WCHAR* p) { return unlink(posix(p).c_str()) == 0; }
DWORD __stdcall GetFileAttributesW(const WCHAR* p)
{
    struct stat st;
    if (stat(posix(p).c_str(), &st) != 0) return 0xFFFFFFFFu;
    return S_ISDIR(st.st_mode) ? 0x10 : 0x80;
}
DWORD __stdcall GetModuleFileNameW(HMODULE, WCHAR* out, DWORD cap)
{
    std::string s = g_root + "\\garrysmod\\lua\\bin\\gmcl_fpvjoy_win64.dll";
    auto w = toW(s.c_str());
    if (w.size() > cap) return cap;
    for (size_t i = 0; i < w.size(); i++) out[i] = w[i];
    return (DWORD)w.size() - 1;
}
BOOL __stdcall GetModuleHandleExW(DWORD, const WCHAR*, HMODULE* m) { *m = (HMODULE)1; return 1; }
HANDLE __stdcall CreateFileW(const WCHAR* p, DWORD, DWORD, void*, DWORD, DWORD, HANDLE)
{
    FILE* f = fopen(posix(p).c_str(), "wb");
    return f ? (HANDLE)f : INVALID_HANDLE;
}
BOOL __stdcall WriteFile(HANDLE h, const void* d, DWORD n, DWORD* w, void*) { *w = (DWORD)fwrite(d, 1, n, (FILE*)h); return 1; }
BOOL __stdcall CloseHandle(HANDLE h) { if (h != (HANDLE)2) fclose((FILE*)h); return 1; }
HANDLE __stdcall CreateThread(void*, SIZE_T, THREADPROC_ fn, void* a, DWORD, DWORD*) { fn(a); return (HANDLE)2; }
HWND __stdcall GetForegroundWindow(void) { return 0; }
void* __stdcall SHBrowseForFolderW(BROWSEINFOW_*) { return 0; }
BOOL __stdcall SHGetPathFromIDListW(void*, WCHAR*) { return 0; }
void __stdcall CoTaskMemFree(void*) {}
HRESULT __stdcall CoInitializeEx(void*, DWORD) { return 0; }
}

static void touch(const std::string& p, const char* content)
{
    FILE* f = fopen(p.c_str(), "wb");
    fputs(content, f);
    fclose(f);
}
static std::string slurp(const std::string& p)
{
    FILE* f = fopen(p.c_str(), "rb");
    if (!f) return "";
    std::string s;
    char b[4096];
    size_t n;
    while ((n = fread(b, 1, sizeof b, f)) > 0) s.append(b, n);
    fclose(f);
    return s;
}

int main()
{
    char tmpl[] = "/tmp/fpvmusicXXXXXX";
    g_root = mkdtemp(tmpl);
    std::string gm = g_root + "/garrysmod";
    mkdir(gm.c_str(), 0755);
    mkdir((gm + "/lua").c_str(), 0755);
    mkdir((gm + "/lua/bin").c_str(), 0755);
    std::string src = g_root + "/My Music";
    mkdir(src.c_str(), 0755);
    mkdir((src + "/Альбом").c_str(), 0755);
    touch(src + "/B track.MP3", "bbb");
    touch(src + "/a track.ogg", "aaa");
    touch(src + "/cover.jpg", "x");
    touch(src + "/Альбом/Пісня.wav", "ccc");

    int st, done, total;
    const char* msg;
    CHECK(!FpvMusic_StartImport((g_root + "/nope").c_str()), "missing folder rejected");
    FpvMusic_Status(&st, &done, &total, &msg);
    CHECK(st == 3, msg);

    std::string winSrc = src;
    CHECK(FpvMusic_StartImport(winSrc.c_str()), "import starts");
    FpvMusic_Status(&st, &done, &total, &msg);
    CHECK(st == 2 && total == 3 && done == 3, "3 tracks copied (jpg skipped, sub-folder included)");
    std::string dst = gm + "/sound/mayhem_music/user/";
    CHECK(slurp(dst + "track_001.ogg") == "aaa", "sorted: a track first, extension lowercased");
    CHECK(slurp(dst + "track_002.mp3") == "bbb", "B track second, .MP3 -> .mp3");
    CHECK(slurp(dst + "track_003.wav") == "ccc", "file from the Cyrillic sub-folder");
    std::string idx = slurp(dst + "index.txt");
    printf("     index.txt:\n%s", idx.c_str());
    CHECK(idx.find("track_001.ogg\ta track\n") != std::string::npos, "index: names without extension");
    CHECK(idx.find("track_003.wav\tПісня\n") != std::string::npos, "index: UTF-8 names");

    std::string src2 = g_root + "/Other";
    mkdir(src2.c_str(), 0755);
    touch(src2 + "/only.mp3", "zzz");
    CHECK(FpvMusic_StartImport(src2.c_str()), "second import");
    FpvMusic_Status(&st, &done, &total, &msg);
    CHECK(st == 2 && total == 1 && access((dst + "track_002.mp3").c_str(), F_OK) != 0 && slurp(dst + "track_001.mp3") == "zzz",
        "old tracks removed");

    std::string empty = g_root + "/Empty";
    mkdir(empty.c_str(), 0755);
    FpvMusic_StartImport(empty.c_str());
    FpvMusic_Status(&st, &done, &total, &msg);
    CHECK(st == 3, "empty folder -> error message");
    CHECK(FpvMusic_Clear() && access((dst + "track_001.mp3").c_str(), F_OK) != 0, "clear");

    char out[64];
    CHECK(!FpvMusic_PickFolder(out, sizeof out), "cancelled dialog -> false");
    printf(fails ? "%d FAILURE(S)\n" : "ALL MUSIC TESTS PASSED\n", fails);
    return fails != 0;
}
