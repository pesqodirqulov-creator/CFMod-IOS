// unity.h - small math types and object helpers used against UnityEngine.
#pragma once
#include "il2cpp.h"
#include <math.h>
#include <string>

struct Vec2 { float x, y; };

struct Vec3 {
    float x, y, z;
    Vec3() : x(0), y(0), z(0) {}
    Vec3(float a, float b, float c) : x(a), y(b), z(c) {}
    Vec3 operator-(const Vec3 &o) const { return Vec3(x - o.x, y - o.y, z - o.z); }
    Vec3 operator+(const Vec3 &o) const { return Vec3(x + o.x, y + o.y, z + o.z); }
    Vec3 operator*(float s) const { return Vec3(x * s, y * s, z * s); }
    float dot(const Vec3 &o) const { return x * o.x + y * o.y + z * o.z; }
    float len() const { return sqrtf(x * x + y * y + z * z); }
    Vec3 norm() const { float l = len(); return l > 1e-5f ? Vec3(x / l, y / l, z / l) : Vec3(); }
};

// UnityEngine.Camera.WorldToScreenPoint returns Vector3 (x, y, depth in z).
static inline Vec3 v3_from_unbox(Il2CppObject *boxed) {
    if (!boxed || !g_il2cpp.object_unbox) return Vec3();
    Vec3 *p = (Vec3 *)((void *(*)(Il2CppObject *))g_il2cpp.object_unbox)(boxed);
    return p ? *p : Vec3();
}

static inline float distance3(const Vec3 &a, const Vec3 &b) { return (a - b).len(); }

// Object identity helpers -------------------------------------------------
static inline bool obj_alive(Il2CppObject *o) { return o != NULL; }

static inline Il2CppClass *obj_class(Il2CppObject *o) {
    if (!o) return NULL;
    return ((Il2CppClass *(*)(Il2CppObject *))g_il2cpp.object_get_class)(o);
}

// True when `o` is an instance of `k` (walks the parent chain).
static inline bool obj_is(Il2CppObject *o, Il2CppClass *k) {
    if (!o || !k) return false;
    Il2CppClass *c = obj_class(o);
    for (int depth = 0; c && depth < 32; depth++) {
        if (c == k) return true;
        c = ((Il2CppClass *(*)(Il2CppClass *))g_il2cpp.class_get_parent)(c);
    }
    return false;
}
