#!/bin/sh
set -e
cd "$(dirname "$0")"
GMB=third_party/gmod-module-base
if [ ! -f "$GMB/include/GarrysMod/Lua/Interface.h" ]; then
    git clone https://github.com/Facepunch/gmod-module-base.git "$GMB"
    git -C "$GMB" checkout e0156e5f96cd0bad8eed738f0d20e2c9a14b2a0d
fi
mkdir -p build && cd build
printf 'LIBRARY winmm.dll\nEXPORTS\njoyGetNumDevs\njoyGetDevCapsW\njoyGetPosEx\njoyConfigChanged\n' > winmm.def
printf 'LIBRARY kernel32.dll\nEXPORTS\nWideCharToMultiByte\nMultiByteToWideChar\nCreateFileW\nReadFile\nWriteFile\nGetOverlappedResult\nCancelIo\nCloseHandle\nCreateEventW\nResetEvent\nGetLastError\nFindFirstFileW\nFindNextFileW\nFindClose\nCopyFileW\nCreateDirectoryW\nDeleteFileW\nGetFileAttributesW\nGetModuleFileNameW\nGetModuleHandleExW\nCreateThread\n' > kernel32.def
printf 'LIBRARY user32.dll\nEXPORTS\nGetForegroundWindow\n' > user32.def
printf 'LIBRARY shell32.dll\nEXPORTS\nSHBrowseForFolderW\nSHGetPathFromIDListW\n' > shell32.def
printf 'LIBRARY ole32.dll\nEXPORTS\nCoTaskMemFree\nCoInitializeEx\n' > ole32.def
printf 'LIBRARY hid.dll\nEXPORTS\nHidD_GetHidGuid\nHidD_GetAttributes\nHidD_GetPreparsedData\nHidD_FreePreparsedData\nHidD_GetProductString\nHidD_SetNumInputBuffers\nHidP_GetCaps\nHidP_GetValueCaps\nHidP_GetButtonCaps\nHidP_GetData\n' > hid.def
printf 'LIBRARY setupapi.dll\nEXPORTS\nSetupDiGetClassDevsW\nSetupDiEnumDeviceInterfaces\nSetupDiGetDeviceInterfaceDetailW\nSetupDiDestroyDeviceInfoList\n' > setupapi.def
for l in winmm kernel32 hid setupapi user32 shell32 ole32; do llvm-dlltool -m i386:x86-64 -d $l.def -l $l.lib; done
FLAGS="--target=x86_64-pc-windows-msvc -std=c++17 -O2 -ffreestanding -fno-exceptions -fno-rtti -fno-stack-protector -fno-builtin -DFPVJOY_FREESTANDING -I ../compat -I ../src -I ../$GMB/include"
clang++ $FLAGS -c ../src/fpvjoy.cpp -o fpvjoy.obj
clang++ $FLAGS -c ../src/fpvhid.cpp -o fpvhid.obj
clang++ $FLAGS -c ../src/fpvmusic.cpp -o fpvmusic.obj
lld-link /dll /noentry /nodefaultlib /machine:x64 /out:gmcl_fpvjoy_win64.dll fpvjoy.obj fpvhid.obj fpvmusic.obj winmm.lib kernel32.lib hid.lib setupapi.lib user32.lib shell32.lib ole32.lib
echo "built build/gmcl_fpvjoy_win64.dll"
