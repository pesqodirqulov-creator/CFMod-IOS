// aimbot.h
#pragma once

// Runs once per rendered frame; picks a target and, depending on settings,
// either snaps or smoothly rotates the view toward it.
void aimbot_frame(void);

// Installs the shoot hook (silent aim). Safe to call before the game is bound.
void aimbot_install_hooks(void);

// Current locked target in screen space, for the ESP ring.
bool aimbot_target_screen(float *x, float *y);
