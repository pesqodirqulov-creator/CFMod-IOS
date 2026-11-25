// aimbot.mm - target selection, smooth view rotation and silent aim.
// Silent aim works by hooking the native entry of the game's shoot routine and
// re-aiming the view transform for the duration of that single call, so the
// shot is computed against the enemy while the player's screen never moves.
#include <UIKit/UIKit.h>
#include <math.h>
#include <string.h>
#include <vector>

#include "config.h"
#include "game.h"
#include "hook.h"
#include "aimbot.h"

extern bool g_menuOpen;

struct Quat { float x, y, z, w; };

static const MethodInfo *g_setRotation = NULL;
static const MethodInfo *g_getRotation = NULL;
static const MethodInfo *g_lookAt      = NULL;
static bool  g_transformBound = false;

static uint32_t g_targetHandle = 0;
static Vec3     g_targetWorld;
static float    g_targetScreenX = 0, g_targetScreenY = 0;
static bool     g_hasTarget = false;

static void *g_origShoot = NULL;
static bool  g_shootHooked = false;

// ---------------------------------------------------------------- transform
static void bind_transform_methods(void) {
    if (g_transformBound) return;
    g_transformBound = true;
    if (!g_game.kTransform) return;
    g_setRotation = i2c_method(g_game.kTransform, "set_rotation", 1);
    g_getRotation = i2c_method(g_game.kTransform, "get_rotation", 0);
    g_lookAt      = i2c_method(g_game.kTransform, "LookAt", 1);
}

static Il2CppObject *camera_transform(void) {
    bind_transform_methods();
    Il2CppObject *cam = g_game.mainCamera();
    if (!cam) return NULL;
    const MethodInfo *m = i2c_method(g_game.kCamera, "get_transform", 0);
    if (!m) return NULL;
    return i2c_invoke(m, cam, NULL);
}

static bool transform_look_at(Il2CppObject *tr, const Vec3 &world) {
    if (!tr || !g_lookAt) return false;
    Vec3 arg = world;
    void *args[1] = {&arg};
    i2c_invoke(g_lookAt, tr, args);
    return true;
}

static bool transform_get_rotation(Il2CppObject *tr, Quat *out) {
    if (!tr || !g_getRotation || !out) return false;
    Il2CppObject *boxed = i2c_invoke(g_getRotation, tr, NULL);
    if (!boxed || !g_il2cpp.object_unbox) return false;
    void *p = ((void *(*)(Il2CppObject *))g_il2cpp.object_unbox)(boxed);
    if (!p) return false;
    memcpy(out, p, sizeof(Quat));
    return true;
}

static bool transform_set_rotation(Il2CppObject *tr, const Quat &q) {
    if (!tr || !g_setRotation) return false;
    Quat arg = q;
    void *args[1] = {&arg};
    i2c_invoke(g_setRotation, tr, args);
    return true;
}

// ---------------------------------------------------------------- selection
static Il2CppObject *local_cached = NULL;
static std::vector<uint32_t> g_scanHandles;

static void refresh_scan(void) {
    for (uint32_t h : g_scanHandles) {
        if (g_il2cpp.gchandle_free) ((void (*)(uint32_t))g_il2cpp.gchandle_free)(h);
    }
    g_scanHandles.clear();
    if (!g_game.mFindByType || !g_game.kPlayer || !g_il2cpp.type_get_object) return;

    const Il2CppType *t = ((const Il2CppType *(*)(Il2CppClass *))g_il2cpp.class_get_type)(g_game.kPlayer);
    Il2CppObject *typeObj = ((Il2CppObject *(*)(const Il2CppType *))g_il2cpp.type_get_object)(t);
    if (!typeObj) return;

    void *args[1] = {&typeObj};
    Il2CppArray *array = (Il2CppArray *)i2c_invoke(g_game.mFindByType, NULL, args);
    if (!array) return;

    uintptr_t n = i2c_arr_len(array);
    if (n > 256) n = 256;
    for (uintptr_t i = 0; i < n; i++) {
        Il2CppObject *p = (Il2CppObject *)i2c_arr_at(array, i);
        if (!p || !g_il2cpp.gchandle_new) continue;
        uint32_t h = ((uint32_t (*)(Il2CppObject *, bool))g_il2cpp.gchandle_new)(p, false);
        if (h) g_scanHandles.push_back(h);
    }
}

static void pick_target(void) {
    g_hasTarget = false;
    if (g_targetHandle && g_il2cpp.gchandle_free) {
        ((void (*)(uint32_t))g_il2cpp.gchandle_free)(g_targetHandle);
        g_targetHandle = 0;
    }
    if (!g_cfg.aimEnabled) return;
    if (!g_game.attached && !g_game.attach()) return;

    Il2CppObject *local = g_game.localPlayer();
    Il2CppObject *cam   = g_game.mainCamera();
    if (!cam) return;

    static CFAbsoluteTime lastScan = 0;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - lastScan > 0.15) { refresh_scan(); lastScan = now; }

    CGSize scr = UIScreen.mainScreen.bounds.size;
    float cx = scr.width * 0.5f, cy = scr.height * 0.5f;
    float best = g_cfg.aimFov;
    int localTeam = local ? g_game.teamOf(local) : -1;

    for (uint32_t h : g_scanHandles) {
        Il2CppObject *p = ((Il2CppObject *(*)(uint32_t))g_il2cpp.gchandle_get_target)(h);
        if (!p || p == local) continue;
        if (g_cfg.espTeamCheck && localTeam >= 0 && g_game.teamOf(p) == localTeam) continue;

        Vec3 world = g_game.bonePos(p, g_cfg.aimBone == 0);
        Vec3 screen = g_game.worldToScreen(cam, world);
        if (screen.z <= 0.01f) continue;

        float dx = screen.x - cx, dy = screen.y - cy;
        float dist = sqrtf(dx * dx + dy * dy);
        if (dist > best) continue;

        best = dist;
        g_targetWorld = world;
        g_targetScreenX = screen.x;
        g_targetScreenY = screen.y;
        g_hasTarget = true;
        if (g_targetHandle) ((void (*)(uint32_t))g_il2cpp.gchandle_free)(g_targetHandle);
        g_targetHandle = ((uint32_t (*)(Il2CppObject *, bool))g_il2cpp.gchandle_new)(p, false);
    }
}

// ---------------------------------------------------------------- hooks
static void shoot_hook(void *self) {
    if (!g_cfg.aimSilent || !g_hasTarget) {
        if (g_origShoot) ((void (*)(void *))g_origShoot)(self);
        return;
    }
    Il2CppObject *tr = camera_transform();
    Quat saved;
    bool haveSaved = tr ? transform_get_rotation(tr, &saved) : false;
    if (tr) transform_look_at(tr, g_targetWorld);

    if (g_origShoot) ((void (*)(void *))g_origShoot)(self);

    if (tr && haveSaved) transform_set_rotation(tr, saved);
}

void aimbot_install_hooks(void) {
    if (g_shootHooked) return;
    if (!g_game.attached && !g_game.attach()) return;
    if (!g_game.mShoot) return;

    void *entry = g_game.mShoot ? *(void **)g_game.mShoot : NULL;   // methodPointer
    if (!entry) return;
    g_shootHooked = hook_install(entry, (void *)shoot_hook, &g_origShoot);
}

bool aimbot_target_screen(float *x, float *y) {
    if (!g_hasTarget) return false;
    if (x) *x = g_targetScreenX;
    if (y) *y = g_targetScreenY;
    return true;
}

// ---------------------------------------------------------------- per frame
void aimbot_frame(void) {
    if (!g_game.attached && !g_game.attach()) return;
    pick_target();

    if (!g_cfg.aimEnabled || !g_hasTarget) return;
    if (g_menuOpen) return;                 // never fight the user inside the menu
    if (g_cfg.aimOnShootOnly) return;       // handled by the shoot hook instead

    Il2CppObject *tr = camera_transform();
    if (!tr) return;

    const MethodInfo *getRot = g_getRotation;
    const MethodInfo *setRot = g_setRotation;
    if (!getRot || !setRot) return;

    Il2CppObject *curBoxed = i2c_invoke(getRot, tr, NULL);
    if (!curBoxed) return;
    void *cp = ((void *(*)(Il2CppObject *))g_il2cpp.object_unbox)(curBoxed);
    if (!cp) return;
    Quat cur;
    memcpy(&cur, cp, sizeof(Quat));

    // Slerp(-ish) toward the target angle using LookAt as reference.
    Quat target = cur;
    Il2CppObject *probe = tr;
    (void)probe;
    transform_look_at(tr, g_targetWorld);
    Il2CppObject *newBoxed = i2c_invoke(getRot, tr, NULL);
    if (newBoxed) {
        void *np = ((void *(*)(Il2CppObject *))g_il2cpp.object_unbox)(newBoxed);
        if (np) memcpy(&target, np, sizeof(Quat));
    }

    float t = g_cfg.aimSmooth;
    if (t < 0.05f) t = 0.05f;
    if (t > 1.0f) t = 1.0f;

    float dot = cur.x * target.x + cur.y * target.y + cur.z * target.z + cur.w * target.w;
    if (dot < 0) { target.x = -target.x; target.y = -target.y; target.z = -target.z; target.w = -target.w; }
    Quat out;
    out.x = cur.x + (target.x - cur.x) * t;
    out.y = cur.y + (target.y - cur.y) * t;
    out.z = cur.z + (target.z - cur.z) * t;
    out.w = cur.w + (target.w - cur.w) * t;
    float len = sqrtf(out.x * out.x + out.y * out.y + out.z * out.z + out.w * out.w);
    if (len > 0.0001f) { out.x /= len; out.y /= len; out.z /= len; out.w /= len; }
    transform_set_rotation(tr, out);
}
