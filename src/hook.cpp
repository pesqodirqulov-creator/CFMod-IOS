// hook.cpp - 16-byte absolute-branch patch hook for arm64/arm64e.
// Only the prologue is replaced, so no dyld rebinding is required and it works
// on injected dylibs that were never linked against a hooking framework.
#include "hook.h"

#include <mach/mach.h>
#include <mach/vm_page_size.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <libkern/OSCacheControl.h>
#include <vector>

#define HOOK_SLOT 16

struct HookSlot {
    void *target;
    uint8_t saved[HOOK_SLOT];
    void *trampoline;
};
static std::vector<HookSlot> g_hooks;
static pthread_mutex_t g_hookLock = PTHREAD_MUTEX_INITIALIZER;

static bool set_prot(void *addr, size_t len, int prot) {
    uintptr_t page = (uintptr_t)addr & ~(uintptr_t)(vm_page_size - 1);
    size_t span = ((uintptr_t)addr + len) - page;
    return vm_protect(mach_task_self(), (vm_address_t)page, span, false, prot) == KERN_SUCCESS;
}

static bool page_writable(void *addr, size_t len, bool writable) {
    if (writable) {
        if (set_prot(addr, len, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE)) return true;
        return set_prot(addr, len, VM_PROT_READ | VM_PROT_WRITE);
    }
    return set_prot(addr, len, VM_PROT_READ | VM_PROT_EXECUTE) ||
           set_prot(addr, len, VM_PROT_READ);
}

// Refuse to relocate prologues we cannot safely copy.
static bool prologue_relocatable(const uint32_t *insn) {
    for (int i = 0; i < 4; i++) {
        uint32_t in = insn[i];
        // ADRP (x1xx1 0000), B/BL (000101|100101), LDR literal, CBZ/CBNZ, TBZ/TBNZ
        if ((in & 0x9F000000) == 0x90000000) return false;         // ADRP
        if ((in & 0x7C000000) == 0x14000000) return false;         // B
        if ((in & 0xFC000000) == 0x94000000) return false;         // BL
        if ((in & 0x3B000000) == 0x18000000) return false;         // LDR (literal)
        if ((in & 0x7E000000) == 0x34000000) return false;         // CBZ/CBNZ
        if ((in & 0x7E000000) == 0x36000000) return false;         // TBZ/TBNZ
    }
    return true;
}

static void emit_absolute_branch(uint8_t *out, uintptr_t destination) {
    // ldr x16, #8 ; br x16 ; .quad destination
    uint32_t ldr = 0x58000050;
    uint32_t br  = 0xD61F0200;
    memcpy(out, &ldr, 4);
    memcpy(out + 4, &br, 4);
    memcpy(out + 8, &destination, 8);
}

static void *alloc_trampoline(void *target) {
    size_t page = vm_page_size;
    void *mem = mmap(NULL, page, PROT_READ | PROT_WRITE,
                     MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (mem == MAP_FAILED) return NULL;

    uint8_t *code = (uint8_t *)mem;
    memcpy(code, target, HOOK_SLOT);
    emit_absolute_branch(code + HOOK_SLOT, (uintptr_t)target + HOOK_SLOT);

    if (mprotect(mem, page, PROT_READ | PROT_EXEC) != 0) {
        munmap(mem, page);
        return NULL;
    }
    sys_icache_invalidate(mem, page);
    return mem;
}

bool hook_install(void *target, void *replacement, void **original) {
    if (!target || !replacement) return false;
    if (original) *original = NULL;

    pthread_mutex_lock(&g_hookLock);
    for (HookSlot &s : g_hooks) {
        if (s.target == target) {
            if (original) *original = s.trampoline;
            pthread_mutex_unlock(&g_hookLock);
            return true;
        }
    }

    if (!prologue_relocatable((const uint32_t *)target)) {
        pthread_mutex_unlock(&g_hookLock);
        return false;
    }

    void *tramp = alloc_trampoline(target);

    HookSlot slot;
    slot.target = target;
    slot.trampoline = tramp;
    memcpy(slot.saved, target, HOOK_SLOT);

    if (!page_writable(target, HOOK_SLOT, true)) {
        if (tramp) munmap(tramp, vm_page_size);
        pthread_mutex_unlock(&g_hookLock);
        return false;
    }

    uint8_t patch[HOOK_SLOT];
    emit_absolute_branch(patch, (uintptr_t)replacement);
    memcpy(target, patch, HOOK_SLOT);
    sys_icache_invalidate(target, HOOK_SLOT);
    page_writable(target, HOOK_SLOT, false);

    g_hooks.push_back(slot);
    if (original) *original = tramp;
    pthread_mutex_unlock(&g_hookLock);
    return true;
}

bool hook_remove(void *target) {
    pthread_mutex_lock(&g_hookLock);
    for (size_t i = 0; i < g_hooks.size(); i++) {
        if (g_hooks[i].target != target) continue;
        if (page_writable(target, HOOK_SLOT, true)) {
            memcpy(target, g_hooks[i].saved, HOOK_SLOT);
            sys_icache_invalidate(target, HOOK_SLOT);
            page_writable(target, HOOK_SLOT, false);
        }
        if (g_hooks[i].trampoline) munmap(g_hooks[i].trampoline, vm_page_size);
        g_hooks.erase(g_hooks.begin() + i);
        pthread_mutex_unlock(&g_hookLock);
        return true;
    }
    pthread_mutex_unlock(&g_hookLock);
    return false;
}
