// menu.mm - draggable launcher + settings panel. Deliberately built from plain
// UIKit so it needs no resources, no bundle and no nib.
#import <UIKit/UIKit.h>
#include "config.h"
#include "game.h"
#include "menu.h"
#include "esp.h"
#include "aimbot.h"

bool g_menuOpen = false;

@interface CFRow : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) NSInteger kind;          // 0 switch, 1 slider, 2 action
@property (nonatomic, assign) float minValue;
@property (nonatomic, assign) float maxValue;
@property (nonatomic, copy) BOOL (^getBool)(void);
@property (nonatomic, copy) void (^setBool)(BOOL);
@property (nonatomic, copy) float (^getFloat)(void);
@property (nonatomic, copy) void (^setFloat)(float);
@property (nonatomic, copy) void (^onAction)(void);
@end
@implementation CFRow
@end

static NSArray<NSString *> *g_sectionTitles(void) {
    return @[@"VISUALS", @"AIM", @"PROTECTION", @"SYSTEM"];
}

static NSArray<NSArray<CFRow *> *> *build_rows(void) {
    NSMutableArray *sections = [NSMutableArray array];

    // ---- visuals
    NSMutableArray *visuals = [NSMutableArray array];
    CFRow *r = [CFRow new];
    r.title = @"ESP enabled"; r.kind = 0;
    r.getBool = ^BOOL { return g_cfg.espEnabled; };
    r.setBool = ^(BOOL v) { g_cfg.espEnabled = v; esp_set_visible(v); cfg_save(); };
    [visuals addObject:r];

    r = [CFRow new];
    r.title = @"Box"; r.kind = 0;
    r.getBool = ^BOOL { return g_cfg.espBox; };
    r.setBool = ^(BOOL v) { g_cfg.espBox = v; cfg_save(); };
    [visuals addObject:r];

    r = [CFRow new];
    r.title = @"Skeleton"; r.kind = 0;
    r.getBool = ^BOOL { return g_cfg.espSkeleton; };
    r.setBool = ^(BOOL v) { g_cfg.espSkeleton = v; cfg_save(); };
    [visuals addObject:r];

    r = [CFRow new];
    r.title = @"Names"; r.kind = 0;
    r.getBool = ^BOOL { return g_cfg.espName; };
    r.setBool = ^(BOOL v) { g_cfg.espName = v; cfg_save(); };
    [visuals addObject:r];

    r = [CFRow new];
    r.title = @"Distance"; r.kind = 0;
    r.getBool = ^BOOL { return g_cfg.espDistance; };
    r.setBool = ^(BOOL v) { g_cfg.espDistance = v; cfg_save(); };
    [visuals addObject:r];

    r = [CFRow new];
    r.title = @"Health bar"; r.kind = 0;
    r.getBool = ^BOOL { return g_cfg.espHealth; };
    r.setBool = ^(BOOL v) { g_cfg.espHealth = v; cfg_save(); };
    [visuals addObject:r];

    r = [CFRow new];
    r.title = @"Team check"; r.kind = 0;
    r.getBool = ^BOOL { return g_cfg.espTeamCheck; };
    r.setBool = ^(BOOL v) { g_cfg.espTeamCheck = v; cfg_save(); };
    [visuals addObject:r];

    r = [CFRow new];
    r.title = @"Range (m)"; r.kind = 1; r.minValue = 20; r.maxValue = 800;
    r.getFloat = ^float { return g_cfg.espRange; };
    r.setFloat = ^(float v) { g_cfg.espRange = v; cfg_save(); };
    [visuals addObject:r];

    r = [CFRow new];
    r.title = @"Font size"; r.kind = 1; r.minValue = 8; r.maxValue = 22;
    r.getFloat = ^float { return g_cfg.espFontSize; };
    r.setFloat = ^(float v) { g_cfg.espFontSize = v; cfg_save(); };
    [visuals addObject:r];

    r = [CFRow new];
    r.title = @"Red"; r.kind = 1; r.minValue = 0; r.maxValue = 1;
    r.getFloat = ^float { return g_cfg.espColor[0]; };
    r.setFloat = ^(float v) { g_cfg.espColor[0] = v; cfg_save(); };
    [visuals addObject:r];

    r = [CFRow new];
    r.title = @"Green"; r.kind = 1; r.minValue = 0; r.maxValue = 1;
    r.getFloat = ^float { return g_cfg.espColor[1]; };
    r.setFloat = ^(float v) { g_cfg.espColor[1] = v; cfg_save(); };
    [visuals addObject:r];

    r = [CFRow new];
    r.title = @"Blue"; r.kind = 1; r.minValue = 0; r.maxValue = 1;
    r.getFloat = ^float { return g_cfg.espColor[2]; };
    r.setFloat = ^(float v) { g_cfg.espColor[2] = v; cfg_save(); };
    [visuals addObject:r];

    [sections addObject:visuals];

    // ---- aim
    NSMutableArray *aim = [NSMutableArray array];
    r = [CFRow new];
    r.title = @"Aimbot"; r.kind = 0;
    r.getBool = ^BOOL { return g_cfg.aimEnabled; };
    r.setBool = ^(BOOL v) { g_cfg.aimEnabled = v; if (v) aimbot_install_hooks(); cfg_save(); };
    [aim addObject:r];

    r = [CFRow new];
    r.title = @"Silent aim"; r.kind = 0;
    r.getBool = ^BOOL { return g_cfg.aimSilent; };
    r.setBool = ^(BOOL v) { g_cfg.aimSilent = v; if (v) aimbot_install_hooks(); cfg_save(); };
    [aim addObject:r];

    r = [CFRow new];
    r.title = @"Auto fire"; r.kind = 0;
    r.getBool = ^BOOL { return g_cfg.aimAutoFire; };
    r.setBool = ^(BOOL v) { g_cfg.aimAutoFire = v; cfg_save(); };
    [aim addObject:r];

    r = [CFRow new];
    r.title = @"Only while shooting"; r.kind = 0;
    r.getBool = ^BOOL { return g_cfg.aimOnShootOnly; };
    r.setBool = ^(BOOL v) { g_cfg.aimOnShootOnly = v; cfg_save(); };
    [aim addObject:r];

    r = [CFRow new];
    r.title = @"Target"; r.kind = 2;
    r.onAction = ^{ g_cfg.aimBone = (g_cfg.aimBone + 1) % 2; cfg_save(); };
    [aim addObject:r];

    r = [CFRow new];
    r.title = @"FOV (px)"; r.kind = 1; r.minValue = 20; r.maxValue = 600;
    r.getFloat = ^float { return g_cfg.aimFov; };
    r.setFloat = ^(float v) { g_cfg.aimFov = v; cfg_save(); };
    [aim addObject:r];

    r = [CFRow new];
    r.title = @"Smoothing"; r.kind = 1; r.minValue = 0.05; r.maxValue = 1.0;
    r.getFloat = ^float { return g_cfg.aimSmooth; };
    r.setFloat = ^(float v) { g_cfg.aimSmooth = v; cfg_save(); };
    [aim addObject:r];

    [sections addObject:aim];

    // ---- protection
    NSMutableArray *prot = [NSMutableArray array];
    r = [CFRow new];
    r.title = @"Anti-ban"; r.kind = 0;
    r.getBool = ^BOOL { return g_cfg.antiBan; };
    r.setBool = ^(BOOL v) { g_cfg.antiBan = v; cfg_save(); };
    [prot addObject:r];

    r = [CFRow new];
    r.title = @"Hide while recording"; r.kind = 0;
    r.getBool = ^BOOL { return g_cfg.hideOnRecord; };
    r.setBool = ^(BOOL v) { g_cfg.hideOnRecord = v; cfg_save(); };
    [prot addObject:r];

    r = [CFRow new];
    r.title = @"Hide ESP in menu"; r.kind = 0;
    r.getBool = ^BOOL { return g_cfg.hideESPInMenu; };
    r.setBool = ^(BOOL v) { g_cfg.hideESPInMenu = v; cfg_save(); };
    [prot addObject:r];

    [sections addObject:prot];

    // ---- system
    NSMutableArray *sys = [NSMutableArray array];
    r = [CFRow new];
    r.title = @"Dump IL2CPP"; r.kind = 2;
    r.onAction = ^{
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *path = [docs stringByAppendingPathComponent:@"il2cpp_dump.txt"];
        g_game.dump(path.UTF8String);
        g_cfg.il2cppDumped = true;
        cfg_save();
    };
    [sys addObject:r];

    r = [CFRow new];
    r.title = @"Status"; r.kind = 2;
    r.onAction = ^{};
    [sys addObject:r];

    [sections addObject:sys];
    return sections;
}

// ---------------------------------------------------------------- cells
@interface CFSwitchCell : UITableViewCell
@property (nonatomic, strong) UISwitch *sw;
@end
@implementation CFSwitchCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    _sw = [[UISwitch alloc] init];
    self.accessoryView = _sw;
    self.backgroundColor = [UIColor clearColor];
    self.textLabel.textColor = [UIColor whiteColor];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    return self;
}
@end

@interface CFSliderCell : UITableViewCell
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *value;
@end
@implementation CFSliderCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    _slider = [[UISlider alloc] init];
    _value = [[UILabel alloc] init];
    _value.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
    _value.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
    _value.textAlignment = NSTextAlignmentRight;
    [self.contentView addSubview:_slider];
    [self.contentView addSubview:_value];
    self.backgroundColor = [UIColor clearColor];
    self.textLabel.textColor = [UIColor whiteColor];
    self.textLabel.font = [UIFont systemFontOfSize:13];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;
    self.textLabel.frame = CGRectMake(14, 0, 96, h);
    self.value.frame = CGRectMake(w - 64, 0, 52, h);
    self.slider.frame = CGRectMake(112, 0, MAX(60.0, w - 112 - 72), h);
}
@end

// ---------------------------------------------------------------- panel
@interface CFMenuController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSArray<CFRow *> *> *rows;
@end

@implementation CFMenuController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.rows = build_rows();

    self.view.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.92];
    self.view.layer.cornerRadius = 14.0;
    self.view.layer.masksToBounds = YES;
    self.view.layer.borderWidth = 0.5;
    self.view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.15].CGColor;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, 240, 28)];
    title.text = @"AUX";
    title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightHeavy];
    title.textColor = [UIColor colorWithRed:0.15 green:1.0 blue:0.35 alpha:1.0];
    [self.view addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(self.view.bounds.size.width - 44, 6, 38, 32);
    close.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [close setTitle:@"✕" forState:UIControlStateNormal];
    [close addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];

    self.table = [[UITableView alloc] initWithFrame:CGRectMake(0, 40, self.view.bounds.size.width,
                                                               self.view.bounds.size.height - 40)
                                             style:UITableViewStyleGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.backgroundColor = [UIColor clearColor];
    self.table.separatorColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.view addSubview:self.table];
}

- (void)dismiss {
    g_menuOpen = false;
    self.view.hidden = YES;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.rows.count; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.rows[section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return g_sectionTitles()[section];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 44.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CFRow *row = self.rows[indexPath.section][indexPath.row];

    if (row.kind == 0) {
        CFSwitchCell *c = [tableView dequeueReusableCellWithIdentifier:@"sw"];
        if (!c) c = [[CFSwitchCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"sw"];
        c.textLabel.text = row.title;
        c.sw.on = row.getBool ? row.getBool() : NO;
        c.sw.tag = indexPath.section * 1000 + indexPath.row;
        [c.sw removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
        [c.sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        return c;
    }
    if (row.kind == 1) {
        CFSliderCell *c = [tableView dequeueReusableCellWithIdentifier:@"sl"];
        if (!c) c = [[CFSliderCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"sl"];
        c.textLabel.text = row.title;
        c.slider.minimumValue = row.minValue;
        c.slider.maximumValue = row.maxValue;
        c.slider.value = row.getFloat ? row.getFloat() : 0;
        c.value.text = [NSString stringWithFormat:@"%.2f", c.slider.value];
        c.slider.tag = indexPath.section * 1000 + indexPath.row;
        [c.slider removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
        [c.slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        return c;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"act"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"act"];
    cell.backgroundColor = [UIColor clearColor];
    cell.textLabel.textColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
    if ([row.title isEqualToString:@"Target"]) {
        cell.textLabel.text = [NSString stringWithFormat:@"Target: %@",
                               g_cfg.aimBone == 0 ? @"Head" : @"Body"];
    } else {
        cell.textLabel.text = row.title;
    }
    return cell;
}

- (void)switchChanged:(UISwitch *)sw {
    NSInteger s = sw.tag / 1000, r = sw.tag % 1000;
    CFRow *row = self.rows[s][r];
    if (row.setBool) row.setBool(sw.on);
}

- (void)sliderChanged:(UISlider *)sl {
    NSInteger s = sl.tag / 1000, r = sl.tag % 1000;
    CFRow *row = self.rows[s][r];
    if (row.setFloat) row.setFloat(sl.value);
    CFSliderCell *cell = (CFSliderCell *)sl.superview.superview;
    if ([cell isKindOfClass:[CFSliderCell class]]) {
        cell.value.text = [NSString stringWithFormat:@"%.2f", sl.value];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    CFRow *row = self.rows[indexPath.section][indexPath.row];
    if (row.kind != 2) return;
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (row.onAction == nil) {
        if ([row.title isEqualToString:@"Target"]) return;
        return;
    }
    if ([row.title isEqualToString:@"Status"]) {
        NSString *msg = g_game.attached
            ? [NSString stringWithFormat:@"bound: %s", g_game.kPlayer ? ((const char *(*)(Il2CppClass *))g_il2cpp.class_get_name)(g_game.kPlayer) : "n/a"]
            : [NSString stringWithFormat:@"not bound: %s", g_game.error.c_str()];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Engine"
                                                                  message:msg
                                                           preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    row.onAction();
    [tableView reloadData];
}
@end

// ---------------------------------------------------------------- launcher
@interface CFLauncherButton : UIView
@end
@implementation CFLauncherButton
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.06 alpha:0.82].CGColor);
    CGContextFillEllipseInRect(ctx, rect);
    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:0.15 green:1.0 blue:0.35 alpha:0.9].CGColor);
    CGContextSetLineWidth(ctx, 1.5);
    CGContextStrokeEllipseInRect(ctx, CGRectInset(rect, 1, 1));
    CGContextSetLineWidth(ctx, 2.0);
    CGFloat cx = rect.size.width / 2, cy = rect.size.height / 2;
    CGContextMoveToPoint(ctx, cx, cy - 7);
    CGContextAddLineToPoint(ctx, cx, cy + 7);
    CGContextMoveToPoint(ctx, cx - 7, cy);
    CGContextAddLineToPoint(ctx, cx + 7, cy);
    CGContextStrokePath(ctx);
}
@end

// Window that stays invisible to hit-testing unless a real control was hit, so
// the game keeps receiving every touch.
@interface CFTouchWindow : UIWindow
@property (nonatomic, assign) BOOL passthrough;
@end
@implementation CFTouchWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (!_passthrough) return v;
    if (v == self.rootViewController.view) return nil;
    return v;
}
@end

@interface CFMenuRoot : UIViewController
@end
@implementation CFMenuRoot
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end

static UIWindow        *g_menuWindow = nil;
static CFMenuController *g_panel     = nil;
static CFLauncherButton *g_launcher  = nil;

static void open_panel(void);

@interface CFLauncherTarget : NSObject
@end
@implementation CFLauncherTarget
- (void)onTap:(UITapGestureRecognizer *)g {
    open_panel();
}
- (void)onPan:(UIPanGestureRecognizer *)g {
    UIView *v = g.view;
    if (!v) return;
    CGPoint t = [g translationInView:v.superview];
    CGPoint c = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    UIWindow *w = v.window;
    CGFloat half = v.bounds.size.width / 2;
    c.x = MAX(half + 4, MIN(w.bounds.size.width - half - 4, c.x));
    c.y = MAX(70, MIN(w.bounds.size.height - half - 4, c.y));
    v.center = c;
    [g setTranslation:CGPointZero inView:v.superview];
}
@end

@interface CFDismissTarget : NSObject
- (void)onTap:(id)sender;
@end
@implementation CFDismissTarget
- (void)onTap:(id)sender { g_menuOpen = false; g_panel.view.hidden = YES; }
@end

static void open_panel(void) {
    if (!g_menuWindow || !g_panel) return;
    CGFloat w = MIN(320.0, UIScreen.mainScreen.bounds.size.width - 32.0);
    CGFloat h = MIN(560.0, UIScreen.mainScreen.bounds.size.height - 100.0);
    g_panel.view.frame = CGRectMake(0, 0, w, h);
    g_panel.view.center = CGPointMake(g_menuWindow.bounds.size.width / 2,
                                      g_menuWindow.bounds.size.height / 2);
    g_panel.view.hidden = NO;
    g_menuOpen = true;
    [g_panel.table reloadData];
}

void menu_start(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_menuWindow) return;

        CFMenuRoot *root = [[CFMenuRoot alloc] init];
        root.view.backgroundColor = [UIColor clearColor];

        CFTouchWindow *w = [[CFTouchWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        w.windowLevel = UIWindowLevelStatusBar + 1200.0;
        w.backgroundColor = [UIColor clearColor];
        w.rootViewController = root;
        w.passthrough = YES;
        w.hidden = NO;
        g_menuWindow = w;

        CGFloat size = 44.0;
        g_launcher = [[CFLauncherButton alloc] initWithFrame:CGRectMake(14, 92, size, size)];
        g_launcher.backgroundColor = [UIColor clearColor];
        g_launcher.userInteractionEnabled = YES;
        [root.view addSubview:g_launcher];

        CFLauncherTarget *target = [[CFLauncherTarget alloc] init];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:target
                                                                             action:@selector(onTap:)];
        [g_launcher addGestureRecognizer:tap];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:target
                                                                             action:@selector(onPan:)];
        pan.maximumNumberOfTouches = 1;
        [g_launcher addGestureRecognizer:pan];

        CGFloat mw = MIN(320.0, UIScreen.mainScreen.bounds.size.width - 32.0);
        CGFloat mh = MIN(560.0, UIScreen.mainScreen.bounds.size.height - 100.0);
        g_panel = [[CFMenuController alloc] init];
        g_panel.view.frame = CGRectMake(0, 0, mw, mh);
        g_panel.view.center = CGPointMake(w.bounds.size.width / 2, w.bounds.size.height / 2);
        g_panel.view.hidden = YES;
        [root.view addSubview:g_panel.view];
    });
}

void menu_set_visible(bool visible) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_menuWindow) [g_menuWindow setHidden:!visible];
    });
}
