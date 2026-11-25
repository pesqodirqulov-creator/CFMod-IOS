// hook.h - minimal arm64 inline hooks + ObjC swizzling helpers.
#pragma once
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif

// Patches the first 16 bytes of `target` with an absolute branch to
// `replacement`. On success *original (may be NULL) receives a callable
// trampoline that runs the overwritten prologue and continues into `target`.
// Returns false (and leaves `target` untouched) when the prologue cannot be
// relocated safely or executable memory is unavailable.
bool hook_install(void *target, void *replacement, void **original);

// Restores the original bytes for a previously installed hook.
bool hook_remove(void *target);

#ifdef __cplusplus
}
#endif
