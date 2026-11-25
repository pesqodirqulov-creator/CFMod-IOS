// config.mm - settings defaults + persistence.
#import <Foundation/Foundation.h>
#include <string.h>
#include "config.h"

struct ModSettings g_cfg;

void cfg_defaults(void) {
    memset(&g_cfg, 0, sizeof(g_cfg));
    g_cfg.espBox = true;
    g_cfg.espSkeleton = true;
    g_cfg.espName = true;
    g_cfg.espDistance = true;
    g_cfg.espHealth = true;
    g_cfg.espTeamCheck = true;
    g_cfg.espRange = 250.0f;
    g_cfg.espFontSize = 11.0f;
    g_cfg.espColor[0] = 0.15f;
    g_cfg.espColor[1] = 1.00f;
    g_cfg.espColor[2] = 0.35f;
    g_cfg.espColor[3] = 1.00f;
    g_cfg.espBoxThickness = 1.2f;

    g_cfg.aimBone = 0;
    g_cfg.aimFov = 220.0f;
    g_cfg.aimSmooth = 0.65f;
    g_cfg.aimOnShootOnly = true;

    g_cfg.antiBan = true;
    g_cfg.hideOnRecord = true;
}

static NSString *const kStoreKey = @"io.aux.session";

void cfg_load(void) {
    cfg_defaults();
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kStoreKey];
    if (!d) return;
#define GET_BOOL(k, f) if (d[@k]) g_cfg.f = [d[@k] boolValue];
#define GET_FLOAT(k, f) if (d[@k]) g_cfg.f = [d[@k] floatValue];
#define GET_INT(k, f) if (d[@k]) g_cfg.f = [d[@k] intValue];
    GET_BOOL("espEnabled", espEnabled)
    GET_BOOL("espBox", espBox)
    GET_BOOL("espSkeleton", espSkeleton)
    GET_BOOL("espName", espName)
    GET_BOOL("espDistance", espDistance)
    GET_BOOL("espHealth", espHealth)
    GET_BOOL("espTeamCheck", espTeamCheck)
    GET_FLOAT("espRange", espRange)
    GET_FLOAT("espFontSize", espFontSize)
    GET_FLOAT("espBoxThickness", espBoxThickness)
    GET_BOOL("aimEnabled", aimEnabled)
    GET_BOOL("aimSilent", aimSilent)
    GET_BOOL("aimAutoFire", aimAutoFire)
    GET_BOOL("aimVisibleOnly", aimVisibleOnly)
    GET_BOOL("aimOnShootOnly", aimOnShootOnly)
    GET_INT("aimBone", aimBone)
    GET_FLOAT("aimFov", aimFov)
    GET_FLOAT("aimSmooth", aimSmooth)
    GET_BOOL("antiBan", antiBan)
    GET_BOOL("hideOnRecord", hideOnRecord)
    GET_BOOL("hideESPInMenu", hideESPInMenu)
    GET_BOOL("il2cppDumped", il2cppDumped)
    if (d[@"espColor"]) { NSArray *c = d[@"espColor"]; for (int i = 0; i < 4 && i < (int)c.count; i++) g_cfg.espColor[i] = [c[i] floatValue]; }
#undef GET_BOOL
#undef GET_FLOAT
#undef GET_INT
}

void cfg_save(void) {
    NSDictionary *d = @{
        @"espEnabled": @(g_cfg.espEnabled),
        @"espBox": @(g_cfg.espBox),
        @"espSkeleton": @(g_cfg.espSkeleton),
        @"espName": @(g_cfg.espName),
        @"espDistance": @(g_cfg.espDistance),
        @"espHealth": @(g_cfg.espHealth),
        @"espTeamCheck": @(g_cfg.espTeamCheck),
        @"espRange": @(g_cfg.espRange),
        @"espFontSize": @(g_cfg.espFontSize),
        @"espBoxThickness": @(g_cfg.espBoxThickness),
        @"aimEnabled": @(g_cfg.aimEnabled),
        @"aimSilent": @(g_cfg.aimSilent),
        @"aimAutoFire": @(g_cfg.aimAutoFire),
        @"aimVisibleOnly": @(g_cfg.aimVisibleOnly),
        @"aimOnShootOnly": @(g_cfg.aimOnShootOnly),
        @"aimBone": @(g_cfg.aimBone),
        @"aimFov": @(g_cfg.aimFov),
        @"aimSmooth": @(g_cfg.aimSmooth),
        @"antiBan": @(g_cfg.antiBan),
        @"hideOnRecord": @(g_cfg.hideOnRecord),
        @"hideESPInMenu": @(g_cfg.hideESPInMenu),
        @"il2cppDumped": @(g_cfg.il2cppDumped),
        @"espColor": @[@(g_cfg.espColor[0]), @(g_cfg.espColor[1]), @(g_cfg.espColor[2]), @(g_cfg.espColor[3])],
    };
    [[NSUserDefaults standardUserDefaults] setObject:d forKey:kStoreKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
