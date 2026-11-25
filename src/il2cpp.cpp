// il2cpp.cpp - locate the Unity IL2CPP runtime inside the host process and
// resolve the exported C API. Three-stage: dlopen path, dlsym on RTLD_DEFAULT,
// then a manual Mach-O symbol table walk for builds that hide their exports.
#include "il2cpp.h"

#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <stdio.h>
#include <string>
#include <vector>

Il2CppApi g_il2cpp;
bool     g_il2cppReady = false;

#define ASSIGN(fn) g_il2cpp.fn = NULL;

static void clear_api(void) {
    IL2CPP_API_REQUIRED(ASSIGN)
    IL2CPP_API_OPTIONAL(ASSIGN)
}

// ------------------------------------------------------------- mach-o walk
static const struct mach_header_64 *image_header_named(const char *needle) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        if (strstr(name, needle)) {
            return (const struct mach_header_64 *)_dyld_get_image_header(i);
        }
    }
    return NULL;
}

// Returns the real load address of a symbol exported by `header`, or NULL.
static void *symbol_in_image(const struct mach_header_64 *header, const char *sym) {
    if (!header || header->magic != MH_MAGIC_64) return NULL;

    const uint8_t *base = (const uint8_t *)header;
    const struct symtab_command *symtab = NULL;
    uintptr_t text_vmaddr = 0;

    const uint8_t *p = base + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)p;
        if (lc->cmd == LC_SYMTAB) {
            symtab = (const struct symtab_command *)lc;
        } else if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (strcmp(seg->segname, "__TEXT") == 0) text_vmaddr = seg->vmaddr;
        }
        if (lc->cmdsize == 0) break;
        p += lc->cmdsize;
    }
    if (!symtab) return NULL;

    const struct nlist_64 *syms = (const struct nlist_64 *)(base + symtab->symoff);
    const char *strs = (const char *)(base + symtab->stroff);

    size_t want = strlen(sym);
    for (uint32_t i = 0; i < symtab->nsyms; i++) {
        if (syms[i].n_un.n_strx == 0) continue;
        const char *name = strs + syms[i].n_un.n_strx;
        // Mach-O C symbols carry a leading underscore.
        const char *cmp = (name[0] == '_') ? name + 1 : name;
        if (strncmp(cmp, sym, want) != 0 || cmp[want] != '\0') continue;
        if ((syms[i].n_type & N_TYPE) != N_SECT) continue;
        return (void *)((uintptr_t)base + (syms[i].n_value - text_vmaddr));
    }
    return NULL;
}

// ------------------------------------------------------------- resolution
static void *g_unity_handle = NULL;

static void *lookup_symbol(const char *name) {
    if (g_unity_handle) {
        void *s = dlsym(g_unity_handle, name);
        if (s) return s;
    }
    void *s = dlsym(RTLD_DEFAULT, name);
    if (s) return s;
    static const struct mach_header_64 *hdr = NULL;
    static bool scanned = false;
    if (!scanned) {
        hdr = image_header_named("UnityFramework");
        scanned = true;
    }
    if (hdr) return symbol_in_image(hdr, name);
    return NULL;
}

bool il2cpp_resolve(const char *framework_path, const char *framework_name) {
    if (g_il2cppReady) return true;
    clear_api();

    // 1. the usual Unity layout: <App>/Frameworks/UnityFramework.framework/...
    if (framework_path && !g_unity_handle) {
        g_unity_handle = dlopen(framework_path, RTLD_NOW | RTLD_GLOBAL);
    }
    // 2. instance already loaded under a different path
    if (!g_unity_handle && framework_name) {
        const char *candidates[] = {
            "@executable_path/Frameworks/UnityFramework.framework/UnityFramework",
            "@rpath/UnityFramework.framework/UnityFramework",
            "UnityFramework",
        };
        for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]) && !g_unity_handle; i++) {
            g_unity_handle = dlopen(candidates[i], RTLD_NOW | RTLD_GLOBAL);
        }
    }

    // Optional extras first; the table is complete either way.
#define RESOLVE(fn) g_il2cpp.fn = lookup_symbol("il2cpp_" #fn);
    IL2CPP_API_OPTIONAL(RESOLVE)
    IL2CPP_API_REQUIRED(RESOLVE)
#undef RESOLVE

    // Everything the mod touches at minimum.
    g_il2cppReady = g_il2cpp.domain_get && g_il2cpp.domain_get_assemblies &&
                    g_il2cpp.assembly_get_image && g_il2cpp.image_get_name &&
                    g_il2cpp.class_from_name && g_il2cpp.class_get_method_from_name &&
                    g_il2cpp.runtime_invoke && g_il2cpp.object_new &&
                    g_il2cpp.string_new && g_il2cpp.thread_attach &&
                    g_il2cpp.field_get_value && g_il2cpp.field_set_value;
    return g_il2cppReady;
}

// ------------------------------------------------------------- utilities
std::string i2c_to_std(Il2CppString *s) {
    if (!s || !g_il2cpp.string_chars || !g_il2cpp.string_length) return std::string();
    int32_t len = ((int32_t (*)(Il2CppString *))g_il2cpp.string_length)(s);
    const uint16_t *ch = ((uint16_t *(*)(Il2CppString *))g_il2cpp.string_chars)(s);
    if (!ch || len <= 0) return std::string();
    std::string out;
    out.reserve((size_t)len);
    for (int32_t i = 0; i < len; i++) out.push_back(ch[i] < 0x80 ? (char)ch[i] : '?');
    return out;
}

Il2CppString *i2c_from_std(const char *s) {
    if (!g_il2cpp.string_new || !s) return NULL;
    return ((Il2CppString *(*)(const char *))g_il2cpp.string_new)(s);
}

uintptr_t i2c_arr_len(Il2CppArray *a) {
    if (!a || !g_il2cpp.array_length) return 0;
    return ((uintptr_t (*)(Il2CppArray *))g_il2cpp.array_length)(a);
}

void *i2c_arr_at(Il2CppArray *a, uintptr_t i) {
    if (!a || i >= a->max_length) return NULL;
    // element data follows the header; pointer-sized elements for reference types
    void **vec = (void **)((uint8_t *)a + ((g_il2cpp.array_object_header_size)
                                           ? ((uint32_t (*)(void))g_il2cpp.array_object_header_size)()
                                           : (uint32_t)sizeof(Il2CppArray)));
    return vec[i];
}
