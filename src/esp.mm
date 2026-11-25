// esp.mm - transparent overlay window that draws a box/skeleton/health ESP on
// top of the running Unity view. All managed reads happen on the main thread
// inside the display link callback, i.e. between Unity frame updates.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <vector>
#include <string>

#include "config.h"
#include "game.h"
#include "esp.h"
#include "aimbot.h"

extern bool g_menuOpen;

static UIWindow     *g_overlay      = nil;
static CADisplayLink *g_link        = nil;
static bool          g_visible      = true;
static std::vector<uint32_t> g_playerHandles;
static CFAbsoluteTime g_lastRefresh = 0;

// ---------------------------------------------------------------- helpers
static uint32_t gch_new(Il2CppObject *o) {
    if (!o || !g_il2cpp.gchandle_new) return 0;
    return ((uint32_t (*)(Il2CppObject *, bool))g_il2cpp.gchandle_new)(o, false);
}

static Il2CppObject *gch_get(uint32_t h) {
    if (!h || !g_il2cpp.gchandle_get_target) return NULL;
    return ((Il2CppObject *(*)(uint32_t))g_il2cpp.gchandle_get_target)(h);
}

static void gch_free(uint32_t h) {
    if (!h || !g_il2cpp.gchandle_free) return;
    ((void (*)(uint32_t))g_il2cpp.gchandle_free)(h);
}

static std::vector<Il2CppObject *> snapshot_from_handles(void) {
    std::vector<Il2CppObject *> out;
    out.reserve(g_playerHandles.size());
    for (uint32_t h : g_playerHandles) {
        Il2CppObject *o = gch_get(h);
        if (o) out.push_back(o);
    }
    return out;
}

// FindObjectsOfType(Type) -> Object[]
static void refresh_players(Il2CppObject *local) {
    for (uint32_t h : g_playerHandles) gch_free(h);
    g_playerHandles.clear();

    if (!g_game.mFindByType || !g_game.kPlayer || !g_il2cpp.type_get_object) return;

    const Il2CppType *t = ((const Il2CppType *(*)(Il2CppClass *))g_il2cpp.class_get_type)(g_game.kPlayer);
    if (!t) return;
    Il2CppObject *typeObj = ((Il2CppObject *(*)(const Il2CppType *))g_il2cpp.type_get_object)(t);
    if (!typeObj) return;

    void *args[1] = {&typeObj};
    Il2CppObject *arr = i2c_invoke(g_game.mFindByType, NULL, args);
    if (!arr) return;

    Il2CppArray *array = (Il2CppArray *)arr;
    uintptr_t n = i2c_arr_len(array);
    if (n > 256) n = 256;
    for (uintptr_t i = 0; i < n; i++) {
        Il2CppObject *p = (Il2CppObject *)i2c_arr_at(array, i);
        if (!p || p == local) continue;
        uint32_t h = gch_new(p);
        if (h) g_playerHandles.push_back(h);
    }
}

static const char *player_name(Il2CppObject *p) {
    static const MethodInfo *mName = NULL;
    static bool tried = false;
    if (!tried) {
        tried = true;
        for (const char *n : {"get_NickName", "get_PlayerName", "get_Name", "get_UserName"}) {
            const MethodInfo *m = i2c_method(g_game.kPlayer, n, 0);
            if (m) { mName = m; break; }
        }
    }
    if (!mName) return NULL;
    Il2CppObject *s = i2c_invoke(mName, p, NULL);
    static std::string buf;
    if (!s) return NULL;
    buf = i2c_to_std((Il2CppString *)s);
    return buf.c_str();
}

// ---------------------------------------------------------------- view
@interface AuxOverlayView : UIView
@end

@implementation AuxOverlayView

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event { return NO; }

- (void)drawRect:(CGRect)rect {
    if (!g_visible || !g_cfg.espEnabled) return;
    if (g_cfg.hideOnRecord && UIScreen.mainScreen.isCaptured) return;
    if (g_menuOpen && g_cfg.hideESPInMenu) return;
    if (!g_game.attached && !g_game.attach()) return;

    Il2CppObject *local = g_game.localPlayer();
    Il2CppObject *cam   = g_game.mainCamera();
    if (!cam) return;

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - g_lastRefresh > 0.2) {
        refresh_players(local);
        g_lastRefresh = now;
    }

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGSize scr = self.bounds.size;
    UIColor *espColor = [UIColor colorWithRed:g_cfg.espColor[0]
                                        green:g_cfg.espColor[1]
                                         blue:g_cfg.espColor[2]
                                        alpha:g_cfg.espColor[3]];

    Vec3 localPos = local ? g_game.positionOf(local) : Vec3();
    int  localTeam = local ? g_game.teamOf(local) : -1;

    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.alignment = NSTextAlignmentCenter;
    NSDictionary *textAttrs = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:g_cfg.espFontSize],
        NSForegroundColorAttributeName: espColor,
        NSParagraphStyleAttributeName: para,
    };

    for (Il2CppObject *p : snapshot_from_handles()) {
        if (!p) continue;
        if (g_cfg.espTeamCheck && localTeam >= 0 && g_game.teamOf(p) == localTeam) continue;

        Vec3 wHead = g_game.bonePos(p, true);
        Vec3 wPelvis = g_game.bonePos(p, false);
        if (local) {
            float d = distance3(localPos, wHead);
            if (d > g_cfg.espRange) continue;
        }

        Vec3 sHead = g_game.worldToScreen(cam, wHead);
        Vec3 sPelvis = g_game.worldToScreen(cam, wPelvis);
        if (sHead.z <= 0.01f || sPelvis.z <= 0.01f) continue;
        if (sHead.x < -200 || sHead.y < -200 || sHead.x > scr.width + 200 || sHead.y > scr.height + 200) continue;

        float seg = sPelvis.y - sHead.y;
        if (seg <= 1.0f) continue;

        CGFloat top    = sHead.y - seg * 0.12f;
        CGFloat bottom = sPelvis.y + seg * 0.95f;
        CGFloat height = bottom - top;
        CGFloat width  = height * 0.42f;
        CGFloat left   = sHead.x - width * 0.5f;
        CGRect box = CGRectMake(left, top, width, height);

        if (g_cfg.espBox) {
            CGContextSetStrokeColorWithColor(ctx, espColor.CGColor);
            CGContextSetLineWidth(ctx, g_cfg.espBoxThickness);
            CGContextStrokeRect(ctx, box);
        }

        if (g_cfg.espSkeleton) {
            CGContextSetStrokeColorWithColor(ctx, espColor.CGColor);
            CGContextSetLineWidth(ctx, 1.0f);
            CGContextMoveToPoint(ctx, sHead.x, sHead.y);
            CGContextAddLineToPoint(ctx, sPelvis.x, sPelvis.y);
            CGFloat hipY = sPelvis.y;
            CGFloat footY = bottom;
            CGFloat spread = width * 0.45f;
            CGContextMoveToPoint(ctx, sPelvis.x - spread, footY);
            CGContextAddLineToPoint(ctx, sPelvis.x, hipY);
            CGContextAddLineToPoint(ctx, sPelvis.x + spread, footY);
            CGContextStrokePath(ctx);
        }

        if (g_cfg.espHealth && g_game.mGetHealth) {
            int hp = g_game.healthOf(p);
            int maxHp = g_game.maxHealthOf(p);
            if (maxHp <= 0) maxHp = 100;
            float frac = (float)hp / (float)maxHp;
            if (frac < 0) frac = 0;
            if (frac > 1) frac = 1;
            CGFloat barW = 3.0f;
            CGFloat barX = box.origin.x - barW - 3.0f;
            CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.0 alpha:0.55].CGColor);
            CGContextFillRect(ctx, CGRectMake(barX, top, barW, height));
            CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:1.0 - frac
                                                                green:frac
                                                                 blue:0.15
                                                                alpha:1.0].CGColor);
            CGContextFillRect(ctx, CGRectMake(barX, top + height * (1.0f - frac), barW, height * frac));
        }

        NSMutableString *label = [NSMutableString string];
        if (g_cfg.espName) {
            const char *nm = player_name(p);
            if (nm && *nm) [label appendFormat:@"%s ", nm];
        }
        if (g_cfg.espDistance && local) {
            [label appendFormat:@"%.0fm", distance3(localPos, wHead)];
        }
        if (label.length) {
            CGSize ts = [label sizeWithAttributes:textAttrs];
            [label drawInRect:CGRectMake(sHead.x - ts.width / 2.0f, top - ts.height - 2.0f,
                                         ts.width, ts.height)
               withAttributes:textAttrs];
        }
    }

    // aim FOV ring
    if (g_cfg.aimEnabled) {
        CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:0.35].CGColor);
        CGContextSetLineWidth(ctx, 1.0f);
        CGContextStrokeEllipseInRect(ctx, CGRectMake(scr.width / 2.0f - g_cfg.aimFov,
                                                     scr.height / 2.0f - g_cfg.aimFov,
                                                     g_cfg.aimFov * 2.0f, g_cfg.aimFov * 2.0f));
    }
}
@end

// ---------------------------------------------------------------- driver
@interface AuxOverlayController : UIViewController
@end
@implementation AuxOverlayController
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}
- (void)loadView {
    self.view = [[AuxOverlayView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.view.backgroundColor = [UIColor clearColor];
    self.view.opaque = NO;
    self.view.userInteractionEnabled = NO;
}
@end

@interface AuxLinkProxy : NSObject
+ (instancetype)shared;
- (void)onFrame:(CADisplayLink *)link;
@end

@implementation AuxLinkProxy
+ (instancetype)shared {
    static AuxLinkProxy *proxy = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ proxy = [[AuxLinkProxy alloc] init]; });
    return proxy;
}
- (void)onFrame:(CADisplayLink *)link {
    UIWindow *w = g_overlay;
    if (!w) return;
    [w.rootViewController.view setNeedsDisplay];
    esp_tick();
}
@end

void esp_tick(void) {
    aimbot_frame();
}

void esp_start(void) {
    if (g_overlay) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_overlay) return;
        AuxOverlayController *vc = [[AuxOverlayController alloc] init];
        UIWindow *w = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        w.windowLevel = UIWindowLevelStatusBar + 1000.0;
        w.backgroundColor = [UIColor clearColor];
        w.userInteractionEnabled = NO;
        w.rootViewController = vc;
        w.hidden = NO;
        g_overlay = w;

        g_link = [CADisplayLink displayLinkWithTarget:[AuxLinkProxy shared] selector:@selector(onFrame:)];
        g_link.preferredFramesPerSecond = 60;
        [g_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    });
}

void esp_set_visible(bool visible) { g_visible = visible; }
bool esp_is_visible(void) { return g_visible; }
