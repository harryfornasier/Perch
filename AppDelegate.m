// AppDelegate.m
// Programmatic Cocoa UI for Frigate Native — Snow Leopard Edition.
// No NIB/XIB. Manual memory management (no ARC).
//
// Assumed tab content area for initial layout: 1096 x 650
// (based on 1100 x 700 window minus title bar, status bar, and tab strip).
// Autoresizing masks ensure everything adjusts when the window is resized.

#import "AppDelegate.h"
#import "FrigateAPI.h"
#import <QTKit/QTKit.h>

// ─── Poll intervals (seconds) ─────────────────────────────────────────────────
static const NSTimeInterval kLiveInterval       = 0.5;
static const NSTimeInterval kEventsInterval     = 6.0;
static const NSTimeInterval kDetectionsInterval = 7.0;
static const NSTimeInterval kNotifyInterval     = 8.0;

// ─── Assumed initial tab content area (for initial frame placement) ───────────
static const CGFloat kTabW   = 1096.0;
static const CGFloat kTabH   = 650.0;
static const CGFloat kSideW  = 170.0;  // camera sidebar width
static const CGFloat kToolH  =  28.0;  // toolbar strip height
static const CGFloat kDetailH= 200.0;  // events detail pane height

// ─── Formatting helpers ───────────────────────────────────────────────────────

static NSString *FNFormatTS(id val) {
    if (!val || [val isKindOfClass:[NSNull class]]) return @"-";
    NSTimeInterval ts = [val doubleValue];
    if (ts <= 0) return @"-";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts];
    NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
    [fmt setDateFormat:@"yyyy-MM-dd  HH:mm:ss"];
    return [fmt stringFromDate:date];
}

static NSString *FNFormatDur(id startVal, id endVal) {
    if (!startVal || [startVal isKindOfClass:[NSNull class]]) return @"-";
    if (!endVal   || [endVal   isKindOfClass:[NSNull class]]) return @"ongoing";
    double secs = [endVal doubleValue] - [startVal doubleValue];
    return secs >= 0 ? [NSString stringWithFormat:@"%.1fs", secs] : @"-";
}

static NSString *FNFormatScore(id val) {
    if (!val || [val isKindOfClass:[NSNull class]]) return @"-";
    return [NSString stringWithFormat:@"%.0f%%", [val doubleValue] * 100.0];
}

static NSString *FNZones(id val) {
    if (![val isKindOfClass:[NSArray class]] || [(NSArray *)val count] == 0)
        return @"-";
    return [(NSArray *)val componentsJoinedByString:@", "];
}

// ─── NSTableColumn convenience ────────────────────────────────────────────────

static NSTableColumn *FNCol(NSString *ident, NSString *title, CGFloat w) {
    NSTableColumn *col = [[[NSTableColumn alloc] initWithIdentifier:ident] autorelease];
    [[col headerCell] setStringValue:title];
    [col setWidth:w];
    [col setMinWidth:40];
    [col setResizingMask:NSTableColumnUserResizingMask | NSTableColumnAutoresizingMask];
    return col;
}

// ─── Scrolled table ───────────────────────────────────────────────────────────

static NSScrollView *FNScrolled(NSTableView *tv, NSRect frame) {
    NSScrollView *sv = [[[NSScrollView alloc] initWithFrame:frame] autorelease];
    [sv setDocumentView:tv];
    [sv setHasVerticalScroller:YES];
    [sv setAutohidesScrollers:YES];
    [sv setBorderType:NSBezelBorder];
    return sv;
}

// ─── Label factory ────────────────────────────────────────────────────────────

static NSTextField *FNLabel(NSString *text, NSRect frame, CGFloat size, BOOL bold) {
    NSTextField *f = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [f setStringValue:text];
    [f setBezeled:NO];
    [f setDrawsBackground:NO];
    [f setEditable:NO];
    [f setSelectable:NO];
    [f setFont:bold ? [NSFont boldSystemFontOfSize:size]
                    : [NSFont systemFontOfSize:size]];
    return f;
}

// ─── Button factory ───────────────────────────────────────────────────────────

static NSButton *FNButton(NSString *title, NSRect frame, id target, SEL action) {
    NSButton *b = [[[NSButton alloc] initWithFrame:frame] autorelease];
    [b setTitle:title];
    [b setBezelStyle:NSRoundedBezelStyle];
    [b setTarget:target];
    [b setAction:action];
    return b;
}

// ─── Accent colour ────────────────────────────────────────────────────────────

static NSColor *FNAccent(void) {
    return [NSColor colorWithCalibratedRed:0.0 green:0.6 blue:0.8 alpha:1.0];
}

// ─── AppDelegate ─────────────────────────────────────────────────────────────

@implementation AppDelegate

// ── Lifecycle ─────────────────────────────────────────────────────────────────

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    _cameras         = [[NSArray alloc] init];
    _events          = [[NSArray alloc] init];
    _detections      = [[NSArray alloc] init];
    _selectedCamera  = -1;
    _lastDetectionTS = 0.0;
    _notifiedIds     = [[NSMutableSet alloc] init];

    // Load persisted Frigate URL (falls back to the compiled-in default)
    NSString *savedURL = [[NSUserDefaults standardUserDefaults]
                          stringForKey:@"FrigateURL"];
    if (savedURL && [savedURL length] > 0)
        [FrigateAPI sharedAPI].baseURL = savedURL;

    [self setupMenu];
    [self setupWindow];

    // Load cameras; everything else follows
    [[FrigateAPI sharedAPI] fetchCameraNames:^(NSArray *names, NSError *err) {
        if (names && [names count] > 0) {
            [self setCameras:names];
            [self setStatus:[NSString stringWithFormat:
                              @"Connected — %lu camera(s)",
                              (unsigned long)[names count]]];
            [_connField setStringValue:@"● Connected"];
            [_connField setTextColor:
             [NSColor colorWithCalibratedRed:0.3 green:0.75 blue:0.3 alpha:1.0]];
            [self refreshEvents];
            [self refreshDetections];
        } else {
            [self setStatus:[NSString stringWithFormat:
                              @"⚠  Could not connect to %@",
                              [FrigateAPI sharedAPI].baseURL]];
            [_connField setStringValue:@"● Offline"];
            [_connField setTextColor:[NSColor orangeColor]];
        }
    }];

    // Polling timers (run loop retains these; we keep a pointer to invalidate later)
    _liveTimer = [NSTimer scheduledTimerWithTimeInterval:kLiveInterval
                                                  target:self
                                                selector:@selector(tickLive:)
                                                userInfo:nil
                                                 repeats:YES];

    [NSTimer scheduledTimerWithTimeInterval:kEventsInterval
                                     target:self
                                   selector:@selector(tickEvents:)
                                   userInfo:nil
                                    repeats:YES];

    [NSTimer scheduledTimerWithTimeInterval:kDetectionsInterval
                                     target:self
                                   selector:@selector(tickDetections:)
                                   userInfo:nil
                                    repeats:YES];

    _notifyTimer = [NSTimer scheduledTimerWithTimeInterval:kNotifyInterval
                                                    target:self
                                                  selector:@selector(tickNotify:)
                                                  userInfo:nil
                                                   repeats:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    return YES;
}

- (void)dealloc {
    [_liveTimer    invalidate];
    [_notifyTimer  invalidate];
    [_cameras      release];
    [_events       release];
    [_detections   release];
    [_selectedEventId release];
    [_notifiedIds  release];
    [_playerPanel  release];   // releasedWhenClosed:NO so we own it
    [super dealloc];
}

// ── Menu ──────────────────────────────────────────────────────────────────────

- (void)setupMenu {
    NSMenu *bar = [[[NSMenu alloc] initWithTitle:@""] autorelease];

    NSMenuItem *appItem = [[[NSMenuItem alloc] initWithTitle:@"Frigate Native"
                                                       action:nil
                                                keyEquivalent:@""] autorelease];
    NSMenu *appMenu = [[[NSMenu alloc] initWithTitle:@"Frigate Native"] autorelease];
    [appMenu addItemWithTitle:@"About Frigate Native"
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Frigate Native"
                       action:@selector(terminate:)
                keyEquivalent:@"q"];
    [appItem setSubmenu:appMenu];
    [bar addItem:appItem];

    NSMenuItem *winItem = [[[NSMenuItem alloc] initWithTitle:@"Window"
                                                       action:nil
                                                keyEquivalent:@""] autorelease];
    NSMenu *winMenu = [[[NSMenu alloc] initWithTitle:@"Window"] autorelease];
    [winMenu addItemWithTitle:@"Minimize"
                       action:@selector(performMiniaturize:)
                keyEquivalent:@"m"];
    [winItem setSubmenu:winMenu];
    [bar addItem:winItem];

    [NSApp setMainMenu:bar];
}

// ── Window ────────────────────────────────────────────────────────────────────

- (void)setupWindow {
    NSRect frame = NSMakeRect(0, 0, 1100, 700);
    NSUInteger style = NSTitledWindowMask | NSClosableWindowMask |
                       NSMiniaturizableWindowMask | NSResizableWindowMask;

    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:style
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [_window setTitle:@"Frigate Native"];
    [_window setMinSize:NSMakeSize(800, 520)];
    [_window setDelegate:self];
    [_window center];

    NSView *cv    = [_window contentView];
    CGFloat cvW   = [cv bounds].size.width;
    CGFloat cvH   = [cv bounds].size.height;
    CGFloat sbH   = 36.0;   // generous height so text is never clipped

    // Status bar (bottom) — plain NSView, no NSBox clipping risk
    NSView *sb = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, cvW, sbH)] autorelease];
    [sb setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];

    // Light background
    NSBox *sbBg = [[[NSBox alloc] initWithFrame:NSMakeRect(0, 0, cvW, sbH)] autorelease];
    [sbBg setBoxType:NSBoxCustom];
    [sbBg setBorderType:NSNoBorder];
    [sbBg setFillColor:[NSColor colorWithCalibratedWhite:0.91 alpha:1.0]];
    [sbBg setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [sb addSubview:sbBg];

    // Status text — vertically centred in the bar
    CGFloat fieldH = 20.0;
    CGFloat fieldY = (sbH - fieldH) / 2.0;
    _statusField = [FNLabel(@"Connecting…",
                             NSMakeRect(10, fieldY, cvW - 180, fieldH), 12, NO) retain];
    [_statusField setTextColor:[NSColor darkGrayColor]];
    [[_statusField cell] setLineBreakMode:NSLineBreakByClipping];
    [[_statusField cell] setScrollable:YES];
    [_statusField setAutoresizingMask:NSViewWidthSizable];
    [sb addSubview:_statusField];

    // Right edge at cvW-22 to stay clear of the Snow Leopard resize handle (15x15px)
    _connField = [FNLabel(@"● Connecting…",
                           NSMakeRect(cvW - 172, fieldY, 150, fieldH), 12, NO) retain];
    [_connField setTextColor:[NSColor orangeColor]];
    [_connField setAlignment:NSRightTextAlignment];
    [[_connField cell] setLineBreakMode:NSLineBreakByClipping];
    [_connField setAutoresizingMask:NSViewMinXMargin];
    [sb addSubview:_connField];
    [cv addSubview:sb];

    // Tab view fills everything above the status bar
    _tabView = [[NSTabView alloc] initWithFrame:
                 NSMakeRect(0, sbH, cvW, cvH - sbH)];
    [_tabView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [_tabView setTabViewType:NSTopTabsBezelBorder];

    NSTabViewItem *t1 = [[[NSTabViewItem alloc] initWithIdentifier:@"live"] autorelease];
    [t1 setLabel:@"  Live  "];
    [t1 setView:[self buildLiveTab]];
    [_tabView addTabViewItem:t1];

    NSTabViewItem *t2 = [[[NSTabViewItem alloc] initWithIdentifier:@"events"] autorelease];
    [t2 setLabel:@"  Events  "];
    [t2 setView:[self buildEventsTab]];
    [_tabView addTabViewItem:t2];

    NSTabViewItem *t3 = [[[NSTabViewItem alloc] initWithIdentifier:@"detections"] autorelease];
    [t3 setLabel:@"  Detections  "];
    [t3 setView:[self buildDetectionsTab]];
    [_tabView addTabViewItem:t3];

    NSTabViewItem *t4 = [[[NSTabViewItem alloc] initWithIdentifier:@"prefs"] autorelease];
    [t4 setLabel:@"  Preferences  "];
    [t4 setView:[self buildPrefsTab]];
    [_tabView addTabViewItem:t4];

    [cv addSubview:_tabView];
    [_window makeKeyAndOrderFront:nil];
}

// ── Live tab ──────────────────────────────────────────────────────────────────

- (NSView *)buildLiveTab {
    NSView *root = [[[NSView alloc] initWithFrame:
                      NSMakeRect(0, 0, kTabW, kTabH)] autorelease];
    [root setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    // Left sidebar
    NSView *side = [[[NSView alloc] initWithFrame:
                      NSMakeRect(0, 0, kSideW, kTabH)] autorelease];
    [side setAutoresizingMask:NSViewHeightSizable | NSViewMaxXMargin];

    NSTextField *camTitle = [FNLabel(@"CAMERAS",
                                      NSMakeRect(8, kTabH - 24, kSideW - 16, 18),
                                      10, YES) retain];
    [camTitle setTextColor:FNAccent()];
    [camTitle setAutoresizingMask:NSViewMinYMargin];
    [side addSubview:camTitle];
    [camTitle release];

    _cameraTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    [_cameraTable setDataSource:self];
    [_cameraTable setDelegate:self];
    [_cameraTable setHeaderView:nil];
    [_cameraTable setAllowsMultipleSelection:NO];
    NSTableColumn *camCol = FNCol(@"name", @"", kSideW - 20);
    [camCol setResizingMask:NSTableColumnAutoresizingMask];
    [_cameraTable addTableColumn:camCol];

    NSScrollView *camSV = FNScrolled(_cameraTable,
        NSMakeRect(4, 4, kSideW - 8, kTabH - 32));
    [camSV setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [side addSubview:camSV];

    // Divider line
    NSBox *divider = [[[NSBox alloc] initWithFrame:
                        NSMakeRect(kSideW, 0, 1, kTabH)] autorelease];
    [divider setBoxType:NSBoxSeparator];
    [divider setAutoresizingMask:NSViewHeightSizable | NSViewMaxXMargin];

    // Right feed area
    CGFloat rw = kTabW - kSideW - 1;
    NSView *feed = [[[NSView alloc] initWithFrame:
                      NSMakeRect(kSideW + 1, 0, rw, kTabH)] autorelease];
    [feed setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    // Camera name label (top-left)
    CGFloat labelY = kTabH - 26;
    _liveCamLabel = [FNLabel(@"← Select a camera",
                              NSMakeRect(8, labelY, rw - 120, 22), 14, YES) retain];
    [_liveCamLabel setTextColor:FNAccent()];
    [_liveCamLabel setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
    [feed addSubview:_liveCamLabel];

    // Timestamp label (top-right)
    _liveTimeLabel = [FNLabel(@"", NSMakeRect(rw - 110, labelY, 102, 22),
                               11, NO) retain];
    [_liveTimeLabel setTextColor:[NSColor grayColor]];
    [_liveTimeLabel setAlignment:NSRightTextAlignment];
    [_liveTimeLabel setAutoresizingMask:NSViewMinYMargin | NSViewMinXMargin];
    [feed addSubview:_liveTimeLabel];

    // Image view fills remaining space
    _liveImageView = [[NSImageView alloc] initWithFrame:
                       NSMakeRect(8, 8, rw - 16, kTabH - 38)];
    [_liveImageView setImageScaling:NSImageScaleProportionallyUpOrDown];
    [_liveImageView setImageAlignment:NSImageAlignCenter];
    [_liveImageView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [feed addSubview:_liveImageView];

    [root addSubview:side];
    [root addSubview:divider];
    [root addSubview:feed];
    return root;
}

// ── Events tab ────────────────────────────────────────────────────────────────

- (NSView *)buildEventsTab {
    NSView *root = [[[NSView alloc] initWithFrame:
                      NSMakeRect(0, 0, kTabW, kTabH)] autorelease];
    [root setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    // Toolbar (top, fixed height)
    CGFloat toolY = kTabH - kToolH;
    NSView *bar = [[[NSView alloc] initWithFrame:
                     NSMakeRect(0, toolY, kTabW, kToolH)] autorelease];
    [bar setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];

    NSTextField *barTitle = [FNLabel(@"Recent Events",
                                      NSMakeRect(10, 4, 200, 20), 13, YES) retain];
    [barTitle setTextColor:FNAccent()];
    [bar addSubview:barTitle];
    [barTitle release];

    NSButton *refBtn = FNButton(@"↺  Refresh",
                                 NSMakeRect(kTabW - 100, 2, 90, 24),
                                 self, @selector(refreshEventsAction:));
    [refBtn setAutoresizingMask:NSViewMinXMargin];
    [bar addSubview:refBtn];
    [root addSubview:bar];

    // Events table (fills space between toolbar and detail pane)
    CGFloat tableH = toolY - kDetailH - 2;
    _eventsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    [_eventsTable setDataSource:self];
    [_eventsTable setDelegate:self];
    [_eventsTable setAllowsMultipleSelection:NO];
    [_eventsTable setColumnAutoresizingStyle:NSTableViewLastColumnOnlyAutoresizingStyle];
    [_eventsTable addTableColumn:FNCol(@"time",     @"Time",       170)];
    [_eventsTable addTableColumn:FNCol(@"camera",   @"Camera",     120)];
    [_eventsTable addTableColumn:FNCol(@"label",    @"Label",       90)];
    [_eventsTable addTableColumn:FNCol(@"duration", @"Duration",    80)];
    [_eventsTable addTableColumn:FNCol(@"score",    @"Score",       70)];

    NSScrollView *evSV = FNScrolled(_eventsTable,
        NSMakeRect(0, kDetailH + 2, kTabW, tableH));
    [evSV setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [root addSubview:evSV];

    // Separator
    NSBox *sep = [[[NSBox alloc] initWithFrame:
                    NSMakeRect(0, kDetailH, kTabW, 1)] autorelease];
    [sep setBoxType:NSBoxSeparator];
    [sep setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [root addSubview:sep];

    // Detail pane (bottom, fixed height)
    NSView *detail = [[[NSView alloc] initWithFrame:
                        NSMakeRect(0, 0, kTabW, kDetailH)] autorelease];
    [detail setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];

    // Thumbnail on the left
    _thumbView = [[NSImageView alloc] initWithFrame:
                   NSMakeRect(4, 4, 290, kDetailH - 8)];
    [_thumbView setImageScaling:NSImageScaleProportionallyUpOrDown];
    [_thumbView setImageAlignment:NSImageAlignCenter];
    [_thumbView setAutoresizingMask:NSViewHeightSizable];
    [detail addSubview:_thumbView];

    // Placeholder label centred over the thumbnail
    _thumbPlaceholder = [FNLabel(@"Select an event\nto preview",
                                  NSMakeRect(4, kDetailH / 2 - 20, 290, 40),
                                  12, NO) retain];
    [_thumbPlaceholder setAlignment:NSCenterTextAlignment];
    [_thumbPlaceholder setTextColor:[NSColor grayColor]];
    [detail addSubview:_thumbPlaceholder];

    // Play clip button
    _playClipBtn = [FNButton(@"▶  Play Clip",
                              NSMakeRect(306, kDetailH - 50, 140, 32),
                              self, @selector(playClip:)) retain];
    [_playClipBtn setEnabled:NO];
    [_playClipBtn setAutoresizingMask:NSViewMinYMargin];
    [detail addSubview:_playClipBtn];

    // Open in browser button
    _browserBtn = [FNButton(@"Open in Browser",
                             NSMakeRect(306, kDetailH - 92, 140, 32),
                             self, @selector(openInBrowser:)) retain];
    [_browserBtn setEnabled:NO];
    [_browserBtn setAutoresizingMask:NSViewMinYMargin];
    [detail addSubview:_browserBtn];

    [root addSubview:detail];
    return root;
}

// ── Preferences tab ───────────────────────────────────────────────────────────

- (NSView *)buildPrefsTab {
    NSView *root = [[[NSView alloc] initWithFrame:
                      NSMakeRect(0, 0, kTabW, kTabH)] autorelease];
    [root setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    // Centre the form panel in the tab
    CGFloat formW = 480.0;
    CGFloat formX = (kTabW - formW) / 2.0;
    CGFloat topY  = kTabH - 80.0;

    // Section title
    NSTextField *title = [FNLabel(@"Connection",
                                   NSMakeRect(formX, topY, formW, 24),
                                   16, YES) retain];
    [title setTextColor:FNAccent()];
    [title setAutoresizingMask:NSViewMinYMargin | NSViewMinXMargin | NSViewMaxXMargin];
    [root addSubview:title];
    [title release];

    // Sub-title
    NSTextField *sub = [FNLabel(@"Enter the base URL of your Frigate instance.",
                                 NSMakeRect(formX, topY - 22, formW, 17),
                                 12, NO) retain];
    [sub setTextColor:[NSColor grayColor]];
    [sub setAutoresizingMask:NSViewMinYMargin | NSViewMinXMargin | NSViewMaxXMargin];
    [root addSubview:sub];
    [sub release];

    // URL label
    NSTextField *lbl = [FNLabel(@"Frigate URL:",
                                 NSMakeRect(formX, topY - 58, 100, 20),
                                 12, YES) retain];
    [lbl setAutoresizingMask:NSViewMinYMargin | NSViewMinXMargin | NSViewMaxXMargin];
    [root addSubview:lbl];
    [lbl release];

    // Editable URL text field
    _prefsURLField = [[NSTextField alloc] initWithFrame:
                       NSMakeRect(formX + 108, topY - 60, formW - 108, 22)];
    [_prefsURLField setStringValue:[FrigateAPI sharedAPI].baseURL];
    [_prefsURLField setFont:[NSFont systemFontOfSize:13]];
    [_prefsURLField setBezeled:YES];
    [_prefsURLField setBezelStyle:NSTextFieldSquareBezel];
    [_prefsURLField setEditable:YES];
    [_prefsURLField setSelectable:YES];
    [[_prefsURLField cell] setPlaceholderString:@"http://192.168.1.x:5000"];
    [_prefsURLField setAutoresizingMask:NSViewMinYMargin | NSViewMinXMargin | NSViewMaxXMargin];
    [root addSubview:_prefsURLField];

    // Buttons row
    CGFloat btnY = topY - 102;
    NSButton *saveBtn = FNButton(@"Save & Reconnect",
                                  NSMakeRect(formX + 108, btnY, 160, 28),
                                  self, @selector(savePrefs:));
    [saveBtn setKeyEquivalent:@"\r"];
    [saveBtn setAutoresizingMask:NSViewMinYMargin | NSViewMinXMargin | NSViewMaxXMargin];
    [root addSubview:saveBtn];

    NSButton *testBtn = FNButton(@"Test Connection",
                                  NSMakeRect(formX + 278, btnY, 140, 28),
                                  self, @selector(testConnection:));
    [testBtn setAutoresizingMask:NSViewMinYMargin | NSViewMinXMargin | NSViewMaxXMargin];
    [root addSubview:testBtn];

    // Status / feedback label
    _prefsStatusField = [FNLabel(@"",
                                  NSMakeRect(formX + 108, btnY - 28, formW - 108, 20),
                                  12, NO) retain];
    [_prefsStatusField setTextColor:[NSColor grayColor]];
    [_prefsStatusField setAutoresizingMask:NSViewMinYMargin | NSViewMinXMargin | NSViewMaxXMargin];
    [root addSubview:_prefsStatusField];

    // Divider
    NSBox *div = [[[NSBox alloc] initWithFrame:
                   NSMakeRect(formX, topY - 150, formW, 1)] autorelease];
    [div setBoxType:NSBoxSeparator];
    [div setAutoresizingMask:NSViewMinYMargin | NSViewMinXMargin | NSViewMaxXMargin];
    [root addSubview:div];

    // Help text
    NSTextField *help = [FNLabel(
        @"Default: http://192.168.1.x:5000\n"
         "The URL is saved in your user preferences and persists across launches.\n"
         "Growl notifications require growlnotify in /usr/local/bin or /opt/local/bin.",
        NSMakeRect(formX, topY - 230, formW, 70), 11, NO) retain];
    [help setTextColor:[NSColor grayColor]];
    [(NSTextFieldCell *)[help cell] setWraps:YES];
    [help setAutoresizingMask:NSViewMinYMargin | NSViewMinXMargin | NSViewMaxXMargin];
    [root addSubview:help];
    [help release];

    return root;
}

// ── Preferences actions ───────────────────────────────────────────────────────

- (void)savePrefs:(id)sender {
    NSString *url = [[_prefsURLField stringValue]
                     stringByTrimmingCharactersInSet:
                     [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([url length] == 0) {
        [_prefsStatusField setStringValue:@"URL cannot be empty."];
        [_prefsStatusField setTextColor:[NSColor orangeColor]];
        return;
    }
    // Strip trailing slash for consistency
    while ([url hasSuffix:@"/"])
        url = [url substringToIndex:[url length] - 1];

    [FrigateAPI sharedAPI].baseURL = url;
    [[NSUserDefaults standardUserDefaults] setObject:url forKey:@"FrigateURL"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [_prefsStatusField setStringValue:@"Saved. Reconnecting…"];
    [_prefsStatusField setTextColor:[NSColor grayColor]];
    [self setStatus:@"Reconnecting…"];
    [_connField setStringValue:@"● Connecting…"];
    [_connField setTextColor:[NSColor orangeColor]];

    // Reset notification horizon so we don't fire stale alerts after URL change
    _lastDetectionTS = 0.0;
    [_notifiedIds removeAllObjects];

    [[FrigateAPI sharedAPI] fetchCameraNames:^(NSArray *names, NSError *err) {
        if (names && [names count] > 0) {
            [self setCameras:names];
            [self setStatus:[NSString stringWithFormat:
                              @"Connected -- %lu camera(s)",
                              (unsigned long)[names count]]];
            [_connField setStringValue:@"● Connected"];
            [_connField setTextColor:
             [NSColor colorWithCalibratedRed:0.3 green:0.75 blue:0.3 alpha:1.0]];
            [_prefsStatusField setStringValue:
             [NSString stringWithFormat:@"Connected to %@", url]];
            [_prefsStatusField setTextColor:
             [NSColor colorWithCalibratedRed:0.2 green:0.65 blue:0.2 alpha:1.0]];
            [self refreshEvents];
            [self refreshDetections];
        } else {
            [self setStatus:[NSString stringWithFormat:@"Could not connect to %@", url]];
            [_connField setStringValue:@"● Offline"];
            [_connField setTextColor:[NSColor orangeColor]];
            [_prefsStatusField setStringValue:@"Could not connect. Check the URL."];
            [_prefsStatusField setTextColor:[NSColor redColor]];
        }
    }];
}

- (void)testConnection:(id)sender {
    NSString *url = [[_prefsURLField stringValue]
                     stringByTrimmingCharactersInSet:
                     [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([url length] == 0) {
        [_prefsStatusField setStringValue:@"Enter a URL first."];
        [_prefsStatusField setTextColor:[NSColor orangeColor]];
        return;
    }
    while ([url hasSuffix:@"/"])
        url = [url substringToIndex:[url length] - 1];

    [_prefsStatusField setStringValue:@"Testing…"];
    [_prefsStatusField setTextColor:[NSColor grayColor]];

    // Temporarily set baseURL for the test, restore if it fails
    NSString *previous = [[FrigateAPI sharedAPI].baseURL copy];
    [FrigateAPI sharedAPI].baseURL = url;

    [[FrigateAPI sharedAPI] fetchCameraNames:^(NSArray *names, NSError *err) {
        if (names && [names count] > 0) {
            [_prefsStatusField setStringValue:
             [NSString stringWithFormat:@"OK -- found %lu camera(s): %@",
              (unsigned long)[names count],
              [names componentsJoinedByString:@", "]]];
            [_prefsStatusField setTextColor:
             [NSColor colorWithCalibratedRed:0.2 green:0.65 blue:0.2 alpha:1.0]];
        } else {
            [FrigateAPI sharedAPI].baseURL = previous;
            [_prefsStatusField setStringValue:@"No response from that URL."];
            [_prefsStatusField setTextColor:[NSColor redColor]];
        }
        [previous release];
    }];
}

// ── Detections tab ────────────────────────────────────────────────────────────

- (NSView *)buildDetectionsTab {
    NSView *root = [[[NSView alloc] initWithFrame:
                      NSMakeRect(0, 0, kTabW, kTabH)] autorelease];
    [root setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    // Toolbar (top, fixed)
    CGFloat toolY = kTabH - kToolH;
    NSView *bar = [[[NSView alloc] initWithFrame:
                     NSMakeRect(0, toolY, kTabW, kToolH)] autorelease];
    [bar setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];

    NSTextField *barTitle = [FNLabel(@"Person Detections",
                                      NSMakeRect(10, 4, 200, 20), 13, YES) retain];
    [barTitle setTextColor:FNAccent()];
    [bar addSubview:barTitle];
    [barTitle release];

    _detCountField = [FNLabel(@"", NSMakeRect(218, 6, 160, 16), 11, NO) retain];
    [_detCountField setTextColor:[NSColor grayColor]];
    [bar addSubview:_detCountField];

    NSButton *refBtn = FNButton(@"↺  Refresh",
                                 NSMakeRect(kTabW - 100, 2, 90, 24),
                                 self, @selector(refreshDetectionsAction:));
    [refBtn setAutoresizingMask:NSViewMinXMargin];
    [bar addSubview:refBtn];
    [root addSubview:bar];

    // Detections table (fills below toolbar)
    _detectionsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    [_detectionsTable setDataSource:self];
    [_detectionsTable setDelegate:self];
    [_detectionsTable setAllowsMultipleSelection:NO];
    [_detectionsTable setColumnAutoresizingStyle:NSTableViewLastColumnOnlyAutoresizingStyle];
    [_detectionsTable addTableColumn:FNCol(@"time",   @"Time",         180)];
    [_detectionsTable addTableColumn:FNCol(@"camera", @"Camera",       130)];
    [_detectionsTable addTableColumn:FNCol(@"score",  @"Confidence",    90)];
    [_detectionsTable addTableColumn:FNCol(@"zone",   @"Zone",         140)];
    [_detectionsTable addTableColumn:FNCol(@"clip",   @"Clip?",         70)];

    NSScrollView *detSV = FNScrolled(_detectionsTable,
        NSMakeRect(0, 4, kTabW, toolY - 6));
    [detSV setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [root addSubview:detSV];

    return root;
}

// ── Data helpers ──────────────────────────────────────────────────────────────

- (void)setCameras:(NSArray *)cameras {
    [_cameras release];
    _cameras = [cameras retain];
    _selectedCamera = ([_cameras count] > 0) ? 0 : -1;
    [_cameraTable reloadData];
    if (_selectedCamera >= 0) {
        [_cameraTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0]
                  byExtendingSelection:NO];
        [_liveCamLabel setStringValue:[_cameras objectAtIndex:0]];
    }
}

- (void)setStatus:(NSString *)msg {
    [_statusField setStringValue:msg];
}

// ── Timer callbacks ───────────────────────────────────────────────────────────

- (void)tickLive:(NSTimer *)t {
    if (_selectedCamera < 0 || _selectedCamera >= (NSInteger)[_cameras count]) return;
    NSString *cam = [_cameras objectAtIndex:_selectedCamera];
    [[FrigateAPI sharedAPI] fetchLatestFrame:cam completion:^(NSImage *img, NSError *e) {
        if (!img) return;
        [_liveImageView setImage:img];
        NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
        [fmt setDateFormat:@"HH:mm:ss"];
        [_liveTimeLabel setStringValue:[fmt stringFromDate:[NSDate date]]];
    }];
}

- (void)tickEvents:(NSTimer *)t    { [self refreshEvents]; }
- (void)tickDetections:(NSTimer *)t { [self refreshDetections]; }

- (void)tickNotify:(NSTimer *)t {
    [[FrigateAPI sharedAPI] fetchPersonEventsSince:_lastDetectionTS
                                        completion:^(NSArray *events, NSError *e) {
        if (!events) return;

        // First run: just record the current horizon so we don't re-notify old events
        if (_lastDetectionTS == 0.0 && [events count] > 0) {
            double maxTS = 0;
            for (NSDictionary *ev in events) {
                double ts = [[ev objectForKey:@"start_time"] doubleValue];
                if (ts > maxTS) maxTS = ts;
            }
            _lastDetectionTS = maxTS;
            for (NSDictionary *ev in events)
                [_notifiedIds addObject:[ev objectForKey:@"id"]];
            return;
        }

        NSMutableArray *newEvts = [NSMutableArray array];
        for (NSDictionary *ev in events) {
            NSString *eid = [ev objectForKey:@"id"];
            double ts = [[ev objectForKey:@"start_time"] doubleValue];
            if (ts > _lastDetectionTS && ![_notifiedIds containsObject:eid]) {
                [newEvts addObject:ev];
                [_notifiedIds addObject:eid];
                if (ts > _lastDetectionTS) _lastDetectionTS = ts;
            }
        }

        for (NSDictionary *ev in newEvts) {
            NSString *cam   = [ev objectForKey:@"camera"] ?: @"unknown";
            NSString *score = FNFormatScore([ev objectForKey:@"top_score"]);
            [self sendGrowl:@"Person Detected"
                    message:[NSString stringWithFormat:@"Camera: %@  |  %@",
                             cam, score]];
        }

        if ([newEvts count] > 0) {
            NSTabViewItem *detTab = [_tabView tabViewItemAtIndex:2];
            [detTab setLabel:[NSString stringWithFormat:
                              @"  Detections (%lu new)  ",
                              (unsigned long)[newEvts count]]];
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    [detTab setLabel:@"  Detections  "];
                });
            [self refreshDetections];
        }
    }];
}

// ── Data refresh ──────────────────────────────────────────────────────────────

- (void)refreshEvents {
    [[FrigateAPI sharedAPI] fetchEvents:50 completion:^(NSArray *events, NSError *e) {
        if (!events) return;
        [_events release];
        _events = [events retain];
        [_eventsTable reloadData];
    }];
}

- (void)refreshDetections {
    [[FrigateAPI sharedAPI] fetchPersonDetections:100
                                       completion:^(NSArray *events, NSError *e) {
        if (!events) return;
        [_detections release];
        _detections = [events retain];
        [_detectionsTable reloadData];
        [_detCountField setStringValue:
         [NSString stringWithFormat:@"%lu detections",
          (unsigned long)[_detections count]]];
    }];
}

// ── Button actions ────────────────────────────────────────────────────────────

- (void)refreshEventsAction:(id)sender     { [self refreshEvents]; }
- (void)refreshDetectionsAction:(id)sender { [self refreshDetections]; }

// ── In-app clip player ────────────────────────────────────────────────────────

- (void)buildPlayerPanel {
    NSRect frame = NSMakeRect(0, 0, 680, 460);
    _playerPanel = [[NSPanel alloc]
                    initWithContentRect:frame
                              styleMask:NSTitledWindowMask | NSClosableWindowMask |
                                        NSResizableWindowMask | NSMiniaturizableWindowMask
                                backing:NSBackingStoreBuffered
                                  defer:NO];
    [_playerPanel setTitle:@"Clip Playback"];
    [_playerPanel setReleasedWhenClosed:NO];
    [_playerPanel center];
    [_playerPanel setMinSize:NSMakeSize(320, 240)];

    // QTMovieView fills the panel content area
    _movieView = [[QTMovieView alloc] initWithFrame:
                   [[_playerPanel contentView] bounds]];
    [(QTMovieView *)_movieView setControllerVisible:YES];
    [(QTMovieView *)_movieView setPreservesAspectRatio:YES];
    [_movieView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [[_playerPanel contentView] addSubview:_movieView];
}

- (void)playClip:(id)sender {
    if (!_selectedEventId) return;

    // Download clip to a temp file, then play via QTMovieView.
    // QTKit handles local H.264 MP4 natively; streaming from a LAN URL is unreliable.
    NSURL *url = [[FrigateAPI sharedAPI] clipURLForEvent:_selectedEventId];
    NSString *eid = [[_selectedEventId copy] autorelease];

    [_playClipBtn setTitle:@"Downloading…"];
    [_playClipBtn setEnabled:NO];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *dlError = nil;
        NSURLRequest *req = [NSURLRequest requestWithURL:url
                                             cachePolicy:NSURLRequestReloadIgnoringCacheData
                                         timeoutInterval:60.0];
        NSHTTPURLResponse *resp = nil;
        NSData *data = [NSURLConnection sendSynchronousRequest:req
                                             returningResponse:&resp
                                                         error:&dlError];

        dispatch_async(dispatch_get_main_queue(), ^{
            [_playClipBtn setTitle:@"▶  Play Clip"];
            [_playClipBtn setEnabled:YES];

            if (!data || dlError) {
                NSAlert *alert = [NSAlert
                    alertWithMessageText:@"Could not download clip"
                             defaultButton:@"OK"
                           alternateButton:nil
                               otherButton:nil
                 informativeTextWithFormat:@"%@",
                 dlError ? [dlError localizedDescription] : @"No data received"];
                [alert runModal];
                return;
            }

            NSString *tmp = [NSTemporaryDirectory()
                             stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"frigate_%@.mp4", eid]];
            if (![data writeToFile:tmp atomically:YES]) {
                return;
            }

            // Build the player panel the first time
            if (!_playerPanel) [self buildPlayerPanel];

            NSError *qtError = nil;
            QTMovie *movie = [QTMovie movieWithFile:tmp error:&qtError];
            if (movie) {
                [(QTMovieView *)_movieView setMovie:movie];
                // Title: camera name + timestamp from selected event row
                NSString *panelTitle = @"Clip Playback";
                NSInteger row = [_eventsTable selectedRow];
                if (row >= 0 && row < (NSInteger)[_events count]) {
                    NSDictionary *ev = [_events objectAtIndex:row];
                    panelTitle = [NSString stringWithFormat:@"%@  —  %@",
                                  [ev objectForKey:@"camera"] ?: @"",
                                  FNFormatTS([ev objectForKey:@"start_time"])];
                }
                [_playerPanel setTitle:panelTitle];
                [_playerPanel makeKeyAndOrderFront:nil];
                [movie play];
            } else {
                NSAlert *alert = [NSAlert
                    alertWithMessageText:@"Could not open clip"
                             defaultButton:@"OK"
                           alternateButton:nil
                               otherButton:nil
                 informativeTextWithFormat:@"%@",
                 qtError ? [qtError localizedDescription] : @"Unknown error"];
                [alert runModal];
            }
        });
    });
}

- (void)openInBrowser:(id)sender {
    if (!_selectedEventId) return;
    [[NSWorkspace sharedWorkspace]
     openURL:[[FrigateAPI sharedAPI] webURLForEvent:_selectedEventId]];
}

// ── Growl ─────────────────────────────────────────────────────────────────────

- (void)sendGrowl:(NSString *)title message:(NSString *)msg {
    NSArray *args = [NSArray arrayWithObjects:
                     @"--name",    @"Frigate Native",
                     @"--title",   title,
                     @"--message", msg, nil];
    for (NSString *path in [NSArray arrayWithObjects:
                             @"/usr/local/bin/growlnotify",
                             @"/opt/local/bin/growlnotify", nil]) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
            NSTask *task = [[[NSTask alloc] init] autorelease];
            [task setLaunchPath:path];
            [task setArguments:args];
            @try { [task launch]; } @catch (NSException *ex) {}
            return;
        }
    }
}

// ── NSTableViewDataSource ─────────────────────────────────────────────────────

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    if (tv == _cameraTable)     return (NSInteger)[_cameras count];
    if (tv == _eventsTable)     return (NSInteger)[_events count];
    if (tv == _detectionsTable) return (NSInteger)[_detections count];
    return 0;
}

- (id)           tableView:(NSTableView *)tv
    objectValueForTableColumn:(NSTableColumn *)col
                          row:(NSInteger)row {
    NSString *ident = [col identifier];

    if (tv == _cameraTable) {
        return (row < (NSInteger)[_cameras count])
               ? [_cameras objectAtIndex:row] : @"";
    }

    if (tv == _eventsTable) {
        if (row >= (NSInteger)[_events count]) return @"";
        NSDictionary *ev = [_events objectAtIndex:row];
        if ([ident isEqualToString:@"time"])
            return FNFormatTS([ev objectForKey:@"start_time"]);
        if ([ident isEqualToString:@"camera"])
            return [ev objectForKey:@"camera"] ?: @"-";
        if ([ident isEqualToString:@"label"])
            return [ev objectForKey:@"label"] ?: @"-";
        if ([ident isEqualToString:@"duration"])
            return FNFormatDur([ev objectForKey:@"start_time"],
                               [ev objectForKey:@"end_time"]);
        if ([ident isEqualToString:@"score"])
            return FNFormatScore([ev objectForKey:@"top_score"]);
        return @"";
    }

    if (tv == _detectionsTable) {
        if (row >= (NSInteger)[_detections count]) return @"";
        NSDictionary *ev = [_detections objectAtIndex:row];
        if ([ident isEqualToString:@"time"])
            return FNFormatTS([ev objectForKey:@"start_time"]);
        if ([ident isEqualToString:@"camera"])
            return [ev objectForKey:@"camera"] ?: @"-";
        if ([ident isEqualToString:@"score"])
            return FNFormatScore([ev objectForKey:@"top_score"]);
        if ([ident isEqualToString:@"zone"])
            return FNZones([ev objectForKey:@"zones"]);
        if ([ident isEqualToString:@"clip"])
            return [[ev objectForKey:@"has_clip"] boolValue] ? @"Yes" : @"No";
        return @"";
    }

    return @"";
}

// ── NSTableViewDelegate ───────────────────────────────────────────────────────

- (void)tableViewSelectionDidChange:(NSNotification *)notif {
    NSTableView *tv = (NSTableView *)[notif object];

    if (tv == _cameraTable) {
        NSInteger row = [tv selectedRow];
        if (row >= 0 && row < (NSInteger)[_cameras count]) {
            _selectedCamera = row;
            [_liveCamLabel setStringValue:[_cameras objectAtIndex:row]];
        }
        return;
    }

    if (tv == _eventsTable) {
        NSInteger row = [tv selectedRow];
        if (row < 0 || row >= (NSInteger)[_events count]) return;

        NSDictionary *ev = [_events objectAtIndex:row];
        NSString *eid = [ev objectForKey:@"id"];

        [_selectedEventId release];
        _selectedEventId = [eid copy];

        [_playClipBtn setEnabled:YES];
        [_browserBtn  setEnabled:YES];
        [_thumbPlaceholder setHidden:YES];

        [[FrigateAPI sharedAPI] fetchThumbnail:eid
                                    completion:^(NSImage *img, NSError *e) {
            if (img) [_thumbView setImage:img];
        }];
    }
}

@end
