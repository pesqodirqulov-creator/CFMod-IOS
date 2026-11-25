// il2cpp.h - runtime bindings + minimal type layout for Unity IL2CPP (arm64 iOS)
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct Il2CppClass      Il2CppClass;
typedef struct Il2CppObject      Il2CppObject;
typedef struct Il2CppString      Il2CppString;
typedef struct Il2CppArray       Il2CppArray;
typedef struct Il2CppArrayBounds Il2CppArrayBounds;
typedef struct Il2CppDomain      Il2CppDomain;
typedef struct Il2CppAssembly    Il2CppAssembly;
typedef struct Il2CppImage       Il2CppImage;
typedef struct Il2CppType        Il2CppType;
typedef struct Il2CppThread      Il2CppThread;
typedef struct MethodInfo        MethodInfo;
typedef struct FieldInfo         FieldInfo;

struct Il2CppObject { Il2CppClass *klass; void *monitor; };
struct Il2CppArrayBounds { uintptr_t length; };
struct Il2CppArray {
    Il2CppObject obj;
    Il2CppArrayBounds *bounds;
    uintptr_t max_length;
};
struct Il2CppString {
    Il2CppObject obj;
    int32_t length;
    uint16_t chars[1];
};

// ---------------------------------------------------------------- api table
// Every entry is resolved with dlsym and may legitimately be NULL on some
// builds; callers must null-check. Required ones are validated in
// il2cpp_resolve().
#define IL2CPP_API_REQUIRED(X)                                                 \
    X(domain_get)                  X(domain_get_assemblies)                    \
    X(assembly_get_image)          X(image_get_name)                           \
    X(class_from_name)             X(class_get_type)                           \
    X(type_get_object)                                                         \
    X(class_get_name)              X(class_get_namespace)                      \
    X(class_get_parent)            X(class_get_methods)                        \
    X(class_get_method_from_name)  X(class_get_field_from_name)                \
    X(method_get_name)             X(method_get_param_count)                   \
    X(runtime_invoke)              X(object_get_class)                         \
    X(object_unbox)                X(object_new)                               \
    X(gchandle_new)                X(gchandle_get_target)                      \
    X(gchandle_free)                                                           \
    X(string_new)                  X(string_length)                            \
    X(string_chars)                                                            \
    X(array_length)                X(array_new)                                \
    X(thread_current)              X(thread_attach)                            \
    X(thread_detach)                                                           \
    X(field_get_value)             X(field_static_get_value)                   \
    X(field_set_value)             X(field_static_set_value)                   \
    X(field_get_type)              X(field_get_flags)

#define IL2CPP_API_OPTIONAL(X)                                                 \
    X(assembly_get_name)           X(class_from_type)                          \
    X(class_get_element_class)     X(class_is_assignable_from)                 \
    X(class_value_size)            X(class_get_nested_types)                   \
    X(method_get_param)            X(method_get_return_type)                   \
    X(type_is_byref)               X(type_get_type)                            \
    X(field_get_value_object)      X(array_object_header_size)                 \
    X(format_exception)            X(free)                            \
    X(image_get_class_count)       X(image_get_class)                  \
    X(class_get_fields)

#define DECL_API(fn) void *fn;
typedef struct Il2CppApi {
    IL2CPP_API_REQUIRED(DECL_API)
    IL2CPP_API_OPTIONAL(DECL_API)
} Il2CppApi;
#undef DECL_API

extern Il2CppApi g_il2cpp;
extern bool     g_il2cppReady;

// Resolve the API out of the running Unity module. Returns false when the
// runtime could not be located (menu then reports "engine not found").
bool il2cpp_resolve(const char *framework_path, const char *framework_name);

// ------------------------------------------------------------ typed helpers
static inline Il2CppDomain *i2c_domain(void) {
    return ((Il2CppDomain *(*)(void))g_il2cpp.domain_get)();
}
static inline Il2CppImage *i2c_image(const char *image_name) {
    size_t n = 0;
    const Il2CppAssembly **as = ((const Il2CppAssembly **(*)(const Il2CppDomain *, size_t *))
                                 g_il2cpp.domain_get_assemblies)(i2c_domain(), &n);
    for (size_t i = 0; i < n; i++) {
        Il2CppImage *img = ((Il2CppImage *(*)(const Il2CppAssembly *))g_il2cpp.assembly_get_image)(as[i]);
        const char *nm = ((const char *(*)(const Il2CppImage *))g_il2cpp.image_get_name)(img);
        if (nm && strcmp(nm, image_name) == 0) return img;
    }
    return NULL;
}
static inline Il2CppClass *i2c_class(Il2CppImage *img, const char *ns, const char *name) {
    if (!img || !name) return NULL;
    return ((Il2CppClass *(*)(const Il2CppImage *, const char *, const char *))
            g_il2cpp.class_from_name)(img, ns, name);
}
static inline const MethodInfo *i2c_method(Il2CppClass *k, const char *name, int argc) {
    if (!k || !name) return NULL;
    return ((const MethodInfo *(*)(Il2CppClass *, const char *, int))
            g_il2cpp.class_get_method_from_name)(k, name, argc);
}
static inline FieldInfo *i2c_field(Il2CppClass *k, const char *name) {
    if (!k || !name) return NULL;
    return ((FieldInfo *(*)(Il2CppClass *, const char *))
            g_il2cpp.class_get_field_from_name)(k, name);
}
static inline Il2CppObject *i2c_invoke(const MethodInfo *m, void *obj, void **args) {
    if (!m) return NULL;
    Il2CppObject *exc = NULL;
    Il2CppObject *r = ((Il2CppObject *(*)(const MethodInfo *, void *, void **, Il2CppObject **))
                       g_il2cpp.runtime_invoke)(m, obj, args, &exc);
    return exc ? NULL : r;
}

#ifdef __cplusplus
}
#endif

#ifdef __cplusplus
#include <string>
std::string   i2c_to_std(Il2CppString *s);
Il2CppString *i2c_from_std(const char *s);
uintptr_t     i2c_arr_len(Il2CppArray *a);
void         *i2c_arr_at(Il2CppArray *a, uintptr_t i);
#endif
