#pragma once

bool FpvXInput_Available();
bool FpvXInput_Read(int slot, double* axes, int nAxes, unsigned int* buttons, unsigned long* packet);
