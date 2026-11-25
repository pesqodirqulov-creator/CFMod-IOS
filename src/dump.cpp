// dump.cpp - offline mapping helper: writes every class/method/field of the
// game assembly to a text file so bindings can be extended without guessing.
#include "game.h"
#include <stdio.h>
#include <string>

void GameBind::dump(const char *path) {
    if (!path || !img) return;
    if (!g_il2cpp.image_get_class_count || !g_il2cpp.image_get_class) return;

    FILE *f = fopen(path, "w");
    if (!f) return;

    uint32_t count = ((uint32_t (*)(Il2CppImage *))g_il2cpp.image_get_class_count)(img);
    fprintf(f, "// image classes: %u\n", count);

    for (uint32_t i = 0; i < count; i++) {
        Il2CppClass *k = ((Il2CppClass *(*)(Il2CppImage *, uint32_t))g_il2cpp.image_get_class)(img, i);
        if (!k) continue;

        const char *ns = ((const char *(*)(Il2CppClass *))g_il2cpp.class_get_namespace)(k);
        const char *nm = ((const char *(*)(Il2CppClass *))g_il2cpp.class_get_name)(k);
        Il2CppClass *parent = ((Il2CppClass *(*)(Il2CppClass *))g_il2cpp.class_get_parent)(k);
        const char *pnm = parent ? ((const char *(*)(Il2CppClass *))g_il2cpp.class_get_name)(parent) : "";

        fprintf(f, "\nclass %s%s%s : %s\n", (ns && *ns) ? ns : "", (ns && *ns) ? "." : "",
                nm ? nm : "?", pnm ? pnm : "");

        if (g_il2cpp.class_get_fields) {
            void *iter = NULL;
            FieldInfo *fld = NULL;
            while ((fld = ((FieldInfo *(*)(Il2CppClass *, void **))g_il2cpp.class_get_fields)(k, &iter)) != NULL) {
                // FieldInfo: name is the first member on every il2cpp version we target
                const char *fname = *(const char **)fld;
                fprintf(f, "    field %s\n", fname ? fname : "?");
            }
        }

        void *iter = NULL;
        const MethodInfo *m = NULL;
        while ((m = ((const MethodInfo *(*)(Il2CppClass *, void **))g_il2cpp.class_get_methods)(k, &iter)) != NULL) {
            const char *mname = ((const char *(*)(const MethodInfo *))g_il2cpp.method_get_name)(m);
            int argc = ((int (*)(const MethodInfo *))g_il2cpp.method_get_param_count)(m);
            void *entry = *(void **)m;   // methodPointer
            fprintf(f, "    method %s/%d  entry=%p\n", mname ? mname : "?", argc, entry);
        }
    }
    fclose(f);
}
