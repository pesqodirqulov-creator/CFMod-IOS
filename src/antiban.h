// antiban.h
#pragma once

// Installs the stealth layer: hides this image from dyld enumeration, filters
// jailbreak/hook probes and neutralises common injected-library checks.
// Must run as early as possible, before the game's first integrity sweep.
void antiban_install(void);

// Re-applies swizzles that a framework may have replaced (called periodically).
void antiban_tick(void);
