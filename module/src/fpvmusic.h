#pragma once

bool FpvMusic_PickFolder(char* outUtf8, int cap);

bool FpvMusic_StartImport(const char* srcUtf8);

void FpvMusic_Status(int* state, int* done, int* total, const char** message);

bool FpvMusic_Clear();
