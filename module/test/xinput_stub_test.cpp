#define FPVXINPUT_STUB 1
#include "../src/fpvxinput.cpp"
#include <cstdio>
#include <cstring>

static int fails = 0;
#define CHECK(c, m) do { if (c) printf("ok   %s\n", m); else { printf("FAIL %s\n", m); fails++; } } while (0)

static XState g_state;
static bool g_connected = true;
static DWORD stubGet(DWORD slot, void* out)
{
    if (slot != 0 || !g_connected) return 1167;
    memcpy(out, &g_state, sizeof(g_state));
    return 0;
}
XGetStateFn g_stubGetState = stubGet;

static bool near(double a, double b) { return a - b < 1e-3 && b - a < 1e-3; }

int main()
{
    double ax[8];
    unsigned int b = 0;
    unsigned long pk = 0;
    CHECK(!FpvXInput_Read(1, ax, 8, &b, &pk), "empty slot -> false");
    g_state.dwPacketNumber = 7;
    g_state.Gamepad.sThumbLX = 32767;
    g_state.Gamepad.sThumbLY = 32767;
    g_state.Gamepad.sThumbRX = -32768;
    g_state.Gamepad.sThumbRY = 1000;
    g_state.Gamepad.bRightTrigger = 255;
    g_state.Gamepad.wButtons = 0x1000 | 0x0020;
    CHECK(FpvXInput_Read(0, ax, 8, &b, &pk), "slot 0 reads");
    CHECK(near(ax[0], 1) && near(ax[1], -1), "left stick: X right +1, up = -1 like HID");
    CHECK(near(ax[3], -1) && near(ax[4], -1000.0 / 32767.0), "right stick, no dead zone");
    CHECK(near(ax[2], -1) && near(ax[6], 1) && near(ax[5], -1), "triggers: combined Z and separate");
    CHECK(b == ((1u << 0) | (1u << 6)) && pk == 7, "A = button 1, Back = button 7");
    g_state.Gamepad.sThumbLX = 300;
    FpvXInput_Read(0, ax, 8, &b, &pk);
    CHECK(ax[0] > 0.009 && ax[0] < 0.0093, "small movement passes through");
    g_connected = false;
    CHECK(!FpvXInput_Read(0, ax, 8, &b, &pk), "unplugged -> false");
    printf(fails ? "%d FAILURE(S)\n" : "ALL XINPUT TESTS PASSED\n", fails);
    return fails != 0;
}
