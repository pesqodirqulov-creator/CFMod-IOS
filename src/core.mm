// core.mm - dylib entry point. Waits for UIApplication + the Unity runtime,
// then brings up the stealth layer, the overlay and the menu.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include "config.h"
#include "game.h"
#include "esp.h"
#include "menu.h"
#include "antiban.h"
#include "aimbot.h"

static bool g_started = false;

static void bring_up(void) {
    if (g_started) return;
    g_started = true;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!g_game.attached) g_game.attach();
        menu_start();
        esp_start();
        aimbot_install_hooks();
        esp_set_visible(g_cfg.espEnabled);
    });
}

static void poll_unity(int attempt) {
    if (g_started) return;
    if (attempt > 150) return;   // ~45 s

    const char *path = "@executable_path/Frameworks/UnityFramework.framework/UnityFramework";
    if (il2cpp_resolve(path, "UnityFramework")) {
        if (g_game.attach()) {
            bring_up();
            return;
        }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        poll_unity(attempt + 1);
    });
}

__attribute__((constructor)) static void cf_early_init(void) {
    @autoreleasepool {
        cfg_load();
        if (g_cfg.antiBan) antiban_install();
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        __block id observer = nil;
        observer = [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        [[NSNotificationCenter defaultCenter] removeObserver:observer];
                        poll_unity(0);
                    }];
        if (UIApplication.sharedApplication) {
            [[NSNotificationCenter defaultCenter] removeObserver:observer];
            poll_unity(0);
        }
    });
}
