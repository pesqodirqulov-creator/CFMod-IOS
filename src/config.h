// config.h - persisted mod settings (NSUserDefaults) shared by all modules.
#pragma once
#include <stdbool.h>

struct ModSettings {
    // visuals
    bool  espEnabled;
    bool  espBox;
    bool  espSkeleton;
    bool  espName;
    bool  espDistance;
    bool  espHealth;
    bool  espTeamCheck;
    float espRange;
    float espFontSize;
    float espColor[4];       // r,g,b,a 0..1
    float espBoxThickness;

    // aim
    bool  aimEnabled;
    bool  aimSilent;
    bool  aimAutoFire;
    bool  aimVisibleOnly;
    int   aimBone;           // 0 = head, 1 = body
    float aimFov;            // pixels
    float aimSmooth;         // 0..1, 1 = instant
    bool  aimOnShootOnly;

    // protection
    bool  antiBan;
    bool  hideOnRecord;
    bool  hideESPInMenu;

    // system
    bool  il2cppDumped;
};

extern struct ModSettings g_cfg;

void cfg_load(void);
void cfg_save(void);
void cfg_defaults(void);
