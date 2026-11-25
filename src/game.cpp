// game.cpp - name-based binding into Assembly-CSharp + UnityEngine.
#include "game.h"
#include <stdio.h>
#include <string.h>
#include <vector>

GameBind g_game;

static int invoke_int(const MethodInfo *m, void *obj, void **args = nullptr) {
    if (!m) return 0;
    Il2CppObject *r = i2c_invoke(m, obj, args);
    if (!r || !g_il2cpp.object_unbox) return 0;
    void *p = ((void *(*)(Il2CppObject *))g_il2cpp.object_unbox)(r);
    return p ? *(int *)p : 0;
}

static Il2CppObject *invoke_obj(const MethodInfo *m, void *obj, void **args = nullptr) {
    if (!m) return nullptr;
    return i2c_invoke(m, obj, args);
}

// First class in `img` that exists, trying the given names.
static Il2CppClass *first_class(Il2CppImage *img, const std::vector<const char *> &names,
                                const char *ns = nullptr) {
    for (const char *n : names) {
        Il2CppClass *k = i2c_class(img, ns, n);
        if (k) return k;
    }
    return nullptr;
}

// First method present on any of the candidate classes.
static const MethodInfo *first_method(const std::vector<Il2CppClass *> &ks,
                                      const std::vector<const char *> &names, int argc) {
    for (Il2CppClass *k : ks) {
        if (!k) continue;
        for (const char *n : names) {
            const MethodInfo *m = i2c_method(k, n, argc);
            if (m) return m;
        }
    }
    return nullptr;
}

bool GameBind::attach() {
    if (attached) return true;

    // Metadata lookups are safe unattached, but invoking managed methods is not:
    // make sure the calling thread is registered with the IL2CPP runtime.
    if (g_il2cpp.thread_current && g_il2cpp.thread_attach) {
        if (!((Il2CppThread *(*)(void))g_il2cpp.thread_current)()) {
            ((Il2CppThread *(*)(Il2CppDomain *))g_il2cpp.thread_attach)(i2c_domain());
        }
    }

    img = i2c_image("Assembly-CSharp.dll");
    if (!img) {
        // some builds rename the assembly; fall back to any non-Unity image
        size_t n = 0;
        const Il2CppAssembly **as = ((const Il2CppAssembly **(*)(const Il2CppDomain *, size_t *))
                                     g_il2cpp.domain_get_assemblies)(i2c_domain(), &n);
        for (size_t i = 0; i < n; i++) {
            Il2CppImage *im = ((Il2CppImage *(*)(const Il2CppAssembly *))g_il2cpp.assembly_get_image)(as[i]);
            const char *nm = ((const char *(*)(const Il2CppImage *))g_il2cpp.image_get_name)(im);
            if (nm && !strstr(nm, "UnityEngine") && !strstr(nm, "mscorlib") &&
                !strstr(nm, "System") && !strstr(nm, "Mono.")) {
                img = im;
                break;
            }
        }
    }

    kPlayer     = first_class(img, {"PlayerController", "Player", "PlayerEntity"});
    kPlayerLife = first_class(img, {"PlayerLife", "PlayerHealth", "Health"});
    kWeapon     = first_class(img, {"WeaponController", "Weapon", "WeaponManager"});
    kBot        = first_class(img, {"ArenaBot", "Bot", "BotController"});

    Il2CppImage *coremod = i2c_image("UnityEngine.CoreModule.dll");
    Il2CppImage *uni     = coremod ? coremod : i2c_image("UnityEngine.dll");
    kTransform = first_class(uni, {"Transform"}, "UnityEngine");
    kCamera    = first_class(uni, {"Camera"}, "UnityEngine");
    kObject    = first_class(uni, {"Object"}, "UnityEngine");
    kType      = first_class(i2c_image("mscorlib.dll"), {"Type"}, "System");

    if (!kPlayer) {
        error = "PlayerController not found";
        return false;
    }

    std::vector<Il2CppClass *> playerCandidates = {kPlayer};
    for (const char *extra : {"PlayerNetwork", "PlayerMovement", "PlayerManager",
                              "GameManager", "MatchManager", "PlayerSpawner"}) {
        Il2CppClass *k = i2c_class(img, nullptr, extra);
        if (k) playerCandidates.push_back(k);
    }

    mGetLocalPlayer = first_method(playerCandidates,
                                   {"get_LocalPlayer", "get_Player", "get_LocalPlayerController"}, 0);
    mGetHealth    = first_method({kPlayerLife, kPlayer}, {"get_Health", "get_hp"}, 0);
    mGetMaxHealth = first_method({kPlayerLife, kPlayer}, {"get_MaxHealth", "get_maxHp"}, 0);
    mGetTeam      = first_method({kPlayer, kPlayerLife}, {"get_Team", "get_teamId", "get_TeamId"}, 0);
    mHeadBone     = first_method({kPlayer}, {"GetHeadBone", "get_HeadBone"}, 0);
    mPelvisBone   = first_method({kPlayer}, {"GetPelvisBone", "get_PelvisBone"}, 0);

    mMainCamera = first_method({kCamera}, {"get_main", "get_mainCamera"}, 0);
    if (!mMainCamera) mMainCamera = first_method({kPlayer}, {"get_MainCamera"}, 0);
    mWorldToScreen = first_method({kCamera}, {"WorldToScreenPoint"}, 1);

    mFindByType = first_method({kObject}, {"FindObjectsOfType"}, 1);
    mGetTransform = first_method({kPlayer}, {"get_transform"}, 0);
    mGetPosition  = first_method({kTransform}, {"get_position"}, 0);

    mShoot       = first_method({kWeapon, kPlayer}, {"Shoot", "Fire", "ShootServerRpc"}, 0);
    mCanShoot    = first_method({kWeapon, kPlayer}, {"get_CanShoot", "get_CanFire"}, 0);
    mFireAllowed = first_method({kWeapon, kPlayer}, {"get_IsFireAllowed"}, 0);

    attached = true;
    return true;
}

Il2CppObject *GameBind::localPlayer() {
    if (!mGetLocalPlayer) return nullptr;
    Il2CppObject *p = invoke_obj(mGetLocalPlayer, nullptr);
    return p;
}

Il2CppObject *GameBind::mainCamera() {
    if (!mMainCamera) return nullptr;
    return invoke_obj(mMainCamera, nullptr);
}

Vec3 GameBind::positionOf(Il2CppObject *obj) {
    if (!obj || !mGetTransform || !mGetPosition) return Vec3();
    Il2CppObject *tr = invoke_obj(mGetTransform, obj);
    if (!tr) return Vec3();
    return v3_from_unbox(invoke_obj(mGetPosition, tr));
}

Vec3 GameBind::bonePos(Il2CppObject *player, bool head) {
    const MethodInfo *m = head ? mHeadBone : mPelvisBone;
    if (!player || !m) return positionOf(player);
    Il2CppObject *tr = invoke_obj(m, player);
    if (!tr) return positionOf(player);
    return v3_from_unbox(invoke_obj(mGetPosition, tr));
}

Vec3 GameBind::worldToScreen(Il2CppObject *camera, const Vec3 &world) {
    if (!camera || !mWorldToScreen) return Vec3();
    Vec3 arg = world;
    void *args[1] = {&arg};
    return v3_from_unbox(invoke_obj(mWorldToScreen, camera, args));
}

int GameBind::healthOf(Il2CppObject *player) {
    if (!player || !mGetHealth) return 0;
    return invoke_int(mGetHealth, player);
}

int GameBind::maxHealthOf(Il2CppObject *player) {
    if (!player || !mGetMaxHealth) return 100;
    int v = invoke_int(mGetMaxHealth, player);
    return v > 0 ? v : 100;
}

int GameBind::teamOf(Il2CppObject *player) {
    if (!player || !mGetTeam) return -1;
    return invoke_int(mGetTeam, player);
}

void GameBind::shoot() {
    if (!mShoot) return;
    if (mCanShoot && !invoke_int(mCanShoot, nullptr)) return;
    if (mFireAllowed && !invoke_int(mFireAllowed, nullptr)) return;
    invoke_obj(mShoot, nullptr);
}
