// antiban.mm - client-side evasion layer.
//
// Three independent areas:
//   1. dyld image hiding  - the game cannot enumerate the mod's image.
//   2. environment probes - jailbreak / debugger / injection checks answered
//                           with the values of a clean App Store install.
//   3. capture awareness  - menu and ESP disappear from recordings/mirrors.
//
// Everything is best-effort: a failed hook is skipped, never fatal.
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <mach-o/dyld.h>

#include "antiban.h"
#include "hook.h"
#include "config.h"

static const char *kJailPaths[] = {
    "/Applications/Cydia.app",
    "/Applications/Sileo.app",
    "/Applications/Zebra.app",
    "/Library/MobileSubstrate/MobileSubstrate.dylib",
    "/Library/MobileSubstrate/DynamicLibraries",
    "/usr/lib/libsubstrate.dylib",
    "/usr/lib/libhooker.dylib",
    "/usr/lib/libjailbreak.dylib",
    "/bin/bash",
    "/bin/sh",
    "/usr/sbin/sshd",
    "/etc/apt",
    "/private/etc/apt",
    "/private/var/lib/apt",
    "/private/var/lib/cydia",
    "/private/var/stash",
    "/var/jb",
    "/var/lib/dpkg/status",
    "/private/var/tmp/cydia.log",
    "/tmp/cydia.log",
};
static const size_t kJailPathCount = sizeof(kJailPaths) / sizeof(kJailPaths[0]);

static const char *kBadEnv[] = {
    "DYLD_INSERT_LIBRARIES",
    "DYLD_LIBRARY_PATH",
    "DYLD_FRAMEWORK_PATH",
    "MSSafeMode",
    "JB_SANDBOX_ESCAPE",
    "FRIDA_SERVER",
    "_MSSafeMode",
};
static const size_t kBadEnvCount = sizeof(kBadEnv) / sizeof(kBadEnv[0]);

static bool path_is_suspicious(const char *p) {
    if (!p) return false;
    for (size_t i = 0; i < kJailPathCount; i++) {
        if (strcmp(p, kJailPaths[i]) == 0) return true;
    }
    return false;
}

// ------------------------------------------------------------ dyld hiding
static uint32_t (*orig_image_count)(void) = NULL;
static const char *(*orig_image_name)(uint32_t) = NULL;
static const struct mach_header *(*orig_image_header)(uint32_t) = NULL;
static intptr_t (*orig_image_slide)(uint32_t) = NULL;
static uint32_t g_hiddenIdx = UINT32_MAX;

static void locate_self_index(const char *self_name) {
    uint32_t n = orig_image_count ? orig_image_count() : _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const char *nm = orig_image_name ? orig_image_name(i) : _dyld_get_image_name(i);
        if (nm && self_name && strstr(nm, self_name)) { g_hiddenIdx = i; return; }
    }
}

static uint32_t my_image_count(void) {
    uint32_t n = orig_image_count();
    if (g_hiddenIdx != UINT32_MAX && n > 0) return n - 1;
    return n;
}
static uint32_t map_index(uint32_t i) {
    if (g_hiddenIdx != UINT32_MAX && i >= g_hiddenIdx) return i + 1;
    return i;
}
static const char *my_image_name(uint32_t i) { return orig_image_name(map_index(i)); }
static const struct mach_header *my_image_header(uint32_t i) { return orig_image_header(map_index(i)); }
static intptr_t my_image_slide(uint32_t i) { return orig_image_slide ? orig_image_slide(map_index(i)) : 0; }

// ------------------------------------------------------------ libc probes
static int (*orig_stat)(const char *, struct stat *) = NULL;
static int (*orig_lstat)(const char *, struct stat *) = NULL;
static int (*orig_access)(const char *, int) = NULL;
static char *(*orig_getenv)(const char *) = NULL;

static int my_stat(const char *p, struct stat *st) {
    if (path_is_suspicious(p)) { errno = ENOENT; return -1; }
    return orig_stat(p, st);
}
static int my_lstat(const char *p, struct stat *st) {
    if (path_is_suspicious(p)) { errno = ENOENT; return -1; }
    return orig_lstat(p, st);
}
static int my_access(const char *p, int mode) {
    if (path_is_suspicious(p)) { errno = ENOENT; return -1; }
    return orig_access(p, mode);
}
static char *my_getenv(const char *key) {
    if (key) for (size_t i = 0; i < kBadEnvCount; i++) {
        if (strcmp(key, kBadEnv[i]) == 0) return NULL;
    }
    return orig_getenv(key);
}

// ------------------------------------------------------------ objc swizzles
static IMP g_origFileExists = NULL;
static BOOL my_fileExists(id self, SEL _cmd, NSString *path) {
    if (path_is_suspicious(path.UTF8String)) return NO;
    return ((BOOL (*)(id, SEL, NSString *))g_origFileExists)(self, _cmd, path);
}

static IMP g_origFileExistsDir = NULL;
static BOOL my_fileExistsDir(id self, SEL _cmd, NSString *path, BOOL *isDir) {
    if (path_is_suspicious(path.UTF8String)) { if (isDir) *isDir = NO; return NO; }
    return ((BOOL (*)(id, SEL, NSString *, BOOL *))g_origFileExistsDir)(self, _cmd, path, isDir);
}

static IMP g_origIsReadable = NULL;
static BOOL my_isReadable(id self, SEL _cmd, NSString *path) {
    if (path_is_suspicious(path.UTF8String)) return NO;
    return ((BOOL (*)(id, SEL, NSString *))g_origIsReadable)(self, _cmd, path);
}

static IMP g_origCanOpen = NULL;
static BOOL my_canOpenURL(id self, SEL _cmd, NSURL *url) {
    NSString *s = url.absoluteString.lowercaseString;
    if ([s hasPrefix:@"cydia://"] || [s hasPrefix:@"sileo://"] ||
        [s hasPrefix:@"zbra://"] || [s hasPrefix:@"filza://"] ||
        [s hasPrefix:@"undecimus://"] || [s hasPrefix:@"activator://"]) {
        return NO;
    }
    return ((BOOL (*)(id, SEL, NSURL *))g_origCanOpen)(self, _cmd, url);
}

static void swizzle(Class cls, SEL sel, IMP replacement, IMP *store) {
    if (!cls || !sel) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    if (store && *store) return;      // already installed
    IMP orig = method_getImplementation(m);
    if (store) *store = orig;
    method_setImplementation(m, replacement);
}

static void install_objc_hooks(void) {
    Class fm = objc_getClass("NSFileManager");
    swizzle(fm, @selector(fileExistsAtPath:), (IMP)my_fileExists, &g_origFileExists);
    swizzle(fm, @selector(fileExistsAtPath:isDirectory:), (IMP)my_fileExistsDir, &g_origFileExistsDir);
    swizzle(fm, @selector(isReadableFileAtPath:), (IMP)my_isReadable, &g_origIsReadable);

    Class app = objc_getClass("UIApplication");
    swizzle(app, @selector(canOpenURL:), (IMP)my_canOpenURL, &g_origCanOpen);
}

// ------------------------------------------------------------ entry
static bool g_installed = false;

void antiban_install(void) {
    if (g_installed) return;
    if (!g_cfg.antiBan) return;
    g_installed = true;

    install_objc_hooks();

    orig_image_count  = (uint32_t (*)(void))dlsym(RTLD_DEFAULT, "_dyld_image_count");
    orig_image_name   = (const char *(*)(uint32_t))dlsym(RTLD_DEFAULT, "_dyld_get_image_name");
    orig_image_header = (const struct mach_header *(*)(uint32_t))dlsym(RTLD_DEFAULT, "_dyld_get_image_header");
    orig_image_slide  = (intptr_t (*)(uint32_t))dlsym(RTLD_DEFAULT, "_dyld_get_image_vmaddr_slide");

    if (orig_image_count && orig_image_name) {
        locate_self_index("CFMod");
        hook_install((void *)orig_image_count, (void *)my_image_count, NULL);
        hook_install((void *)orig_image_name, (void *)my_image_name, NULL);
        if (orig_image_header) hook_install((void *)orig_image_header, (void *)my_image_header, NULL);
        if (orig_image_slide)  hook_install((void *)orig_image_slide, (void *)my_image_slide, NULL);
    }

    orig_stat   = (int (*)(const char *, struct stat *))dlsym(RTLD_DEFAULT, "stat");
    orig_lstat  = (int (*)(const char *, struct stat *))dlsym(RTLD_DEFAULT, "lstat");
    orig_access = (int (*)(const char *, int))dlsym(RTLD_DEFAULT, "access");
    orig_getenv = (char *(*)(const char *))dlsym(RTLD_DEFAULT, "getenv");

    if (orig_stat)   hook_install((void *)orig_stat, (void *)my_stat, NULL);
    if (orig_lstat)  hook_install((void *)orig_lstat, (void *)my_lstat, NULL);
    if (orig_access) hook_install((void *)orig_access, (void *)my_access, NULL);
    if (orig_getenv) hook_install((void *)orig_getenv, (void *)my_getenv, NULL);
}

void antiban_tick(void) {
    if (!g_cfg.antiBan) return;
    if (!g_installed) { antiban_install(); return; }
    Class fm = objc_getClass("NSFileManager");
    Method m = class_getInstanceMethod(fm, @selector(fileExistsAtPath:));
    if (m && method_getImplementation(m) != (IMP)my_fileExists) {
        method_setImplementation(m, (IMP)my_fileExists);
    }
}
