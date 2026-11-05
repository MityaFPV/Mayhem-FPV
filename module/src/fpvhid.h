#pragma once

#define FPVHID_MAX_DEVICES 8
#define FPVHID_MAX_AXES 16

int FpvHid_Scan();
int FpvHid_Count();
bool FpvHid_Info(int i, const char** name, int* vid, int* pid, int* axes, int* buttons, int* usage);
bool FpvHid_Read(int i, double* axes, int maxAxes, unsigned int* buttons, unsigned int* buttonsHi, unsigned long* reports);
void FpvHid_CloseAll();
