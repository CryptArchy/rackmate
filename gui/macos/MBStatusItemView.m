#import "AppDelegate.h"
#import <QuartzCore/CoreAnimation.h>
#import "spotify.h"

@interface MBStatusItemView () <NSTextFieldDelegate>
@end

@interface MBWindow : NSWindow
@end

@interface BGView : NSView
@end

static MBStatusItemView *gself = nil;


@implementation MBStatusItemView {
    NSTextField *user;
    NSTextField *pass;
    NSButton *login;
    NSWindow *window;
}

- (void)dealloc {
    gself = nil;
    [self releaseWindow];
    [super dealloc];
}

- (void)mouseDown:(NSEvent *)event {
    [self toggle];
}

- (void)drawRect:(NSRect)rect {
    if (window) {
        [[NSColor selectedMenuItemColor] set];
        NSRectFill(rect);
    }
    NSImage *img = [NSImage imageNamed:window ? @"NSStatusItemInverted.png" : @"NSStatusItemDisabled.png"];

    NSPoint pt;
    pt.x = floorf((self.frame.size.width - img.size.width) / 2);
    pt.y = floorf((self.frame.size.height - img.size.height) / 2);
    pt.y++; // aesthetics tweak

    [img drawAtPoint:pt fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1];
}

- (void)releaseWindow {
    if (window) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidResignKeyNotification object:window];
        [window release];
        window = nil;
    }
}

- (void)toggle {
    if (!window) {
        [self newWindow];
        [NSApp activateIgnoringOtherApps:YES];
        [window makeKeyAndOrderFront:self];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(toggle) name:NSWindowDidResignKeyNotification object:window];
    } else {
        [self releaseWindow];
    }
    [self setNeedsDisplay:YES];
}

#define W 300
#define H 110

- (void)newWindow {
////////////////////////////////////////////////////////////////////// spotify
    NSView *view = [[[BGView alloc] initWithFrame:NSMakeRect(0, 0, W, H)] autorelease];

    NSImageView *iv = [[[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 0, 0)] autorelease];
    iv.image = [NSImage imageNamed:@"spotify.png"];
    iv.frame = NSMakeRect(12, H - 52 - 12, 47, 52);
    [view addSubview:iv];

    const float x = 50 + 20;
    [view addSubview:user = [[[NSTextField alloc] initWithFrame:NSMakeRect(x, H - 33, W - 10 - x, 21)] autorelease]];
    [view addSubview:pass = [[[NSSecureTextField alloc] initWithFrame:NSMakeRect(x, H - 33 - 30, W - 10 - x, 21)] autorelease]];

    user.delegate = pass.delegate = self;

    NSButton *btn = [[[NSButton alloc] initWithFrame:NSMakeRect(W - 5 - 64 - 78 + 4, 10, 78, 32)] autorelease];
    btn.title = @"Not Now";
    [btn setButtonType:NSMomentaryLightButton];
    [btn setBezelStyle:NSRoundedBezelStyle];
    [view addSubview:btn];
    btn.target = [NSApp delegate];
    btn.action = @selector(notNow);

    login = btn = [[[NSButton alloc] initWithFrame:NSMakeRect(W - 5 - 64, 10, 64, 32)] autorelease];
    btn.title = @"Log In";
    [btn setButtonType:NSMomentaryLightButton];
    [btn setBezelStyle:NSRoundedBezelStyle];
    [view addSubview:btn];
    btn.target = self;
    btn.action = @selector(logIn);

    [user.cell setPlaceholderString:@"Spotify Username"];
    [pass.cell setPlaceholderString:@"Password"];

/////////////////////////////////////////////////////////////////////// window
    const float HH = 60;
    NSTextView *about = [[[NSTextView alloc] initWithFrame:NSMakeRect(10, H + 10, W - 20, HH - 20)] autorelease];
    about.string = @"Rackit sources music from your local computers and music providers like Spotify. A Spotify Premium account makes Rackit even better.";
    about.font = [NSFont systemFontOfSize:11];
    about.textColor = [NSColor colorWithCalibratedWhite:50.f/255.f alpha:1];
    about.drawsBackground = NO;
    about.editable = NO;
    about.selectable = NO;

    NSRect f = self.window.frame;
    NSPoint point = NSMakePoint(NSMidX(f), NSMinY(f));
    f.origin.x = point.x - W / 2;
    f.origin.y = point.y - (H + HH);
    f.size.width = W;
    f.size.height = H + HH;

    window = [[MBWindow alloc] initWithContentRect:f styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
    [window setMovableByWindowBackground:NO];
    [window setExcludedFromWindowsMenu:YES];
    [window setOpaque:YES];
    [window setHasShadow:YES];
    [window setReleasedWhenClosed:NO];

    [window.contentView setFrame:NSMakeRect(0, 0, W, H + HH)];
    [window.contentView addSubview:view];
    [window.contentView addSubview:about];

    window.defaultButtonCell = btn.cell;
}

- (BOOL)control:(NSControl *)control textView:(id)view doCommandBySelector:(SEL)cmd {
    if (cmd == @selector(insertNewline:)) {
        if (control == user) {
            [window makeFirstResponder:pass];
        } else if (control == pass) {
            [self logIn];
        }
        return YES;
    }
    return NO;
}


char *sp_username = NULL;
char *sp_password = NULL;
void tellmate(const char *what);
- (void)logIn {
    // we store the creds in variables so as to not transport the password over TCP in plain-text
    sp_username = strdup(user.stringValue.UTF8String);
    sp_password = strdup(pass.stringValue.UTF8String);
    tellmate("ctc:spotify.login()");

    login.title = @"…";
    user.enabled = pass.enabled = login.enabled = NO;
    gself = self;

    //TODO prevent closing the window during login
}

- (void)loginFailed {
    login.title = @"Log In";
    user.enabled = pass.enabled = login.enabled = YES;

    const float vigourOfShake = 0.05;

    NSRect frame = [window frame];
    CGMutablePathRef shakePath = CGPathCreateMutable();
    CGPathMoveToPoint(shakePath, NULL, NSMinX(frame), NSMinY(frame));
    for (int i = 0; i < 2; ++i) {
        CGPathAddLineToPoint(shakePath, NULL, NSMinX(frame) - frame.size.width * vigourOfShake, NSMinY(frame));
        CGPathAddLineToPoint(shakePath, NULL, NSMinX(frame) + frame.size.width * vigourOfShake, NSMinY(frame));
    }
    CGPathAddLineToPoint(shakePath, NULL, NSMinX(frame) - frame.size.width * vigourOfShake / 2, NSMinY(frame));
    CGPathAddLineToPoint(shakePath, NULL, NSMinX(frame) + frame.size.width * vigourOfShake / 2, NSMinY(frame));
    CGPathCloseSubpath(shakePath);

    CAKeyframeAnimation *anim = [CAKeyframeAnimation animation];
    anim.path = shakePath;
    anim.duration = 0.4;

    [window setAnimations:[NSDictionary dictionaryWithObject:anim forKey:@"frameOrigin"]];
    [window.animator setFrameOrigin:frame.origin];

    CGPathRelease(shakePath);

    [pass becomeFirstResponder];
}

@end


void spcb_logged_in(sp_session *session, sp_error err) {
    if (err != SP_ERROR_OK)
        [gself performSelectorOnMainThread:@selector(loginFailed) withObject:nil waitUntilDone:NO];
    // else state change is handled in AppDelegate
}


@implementation BGView
- (void)drawRect:(NSRect)rect {
    [[NSColor colorWithCalibratedWhite:221.0f/255.0f alpha:1] setFill];
    NSRectFill(rect);

    float w = NSMaxX(self.bounds);
    float y = NSMaxY(self.bounds);

    NSBezierPath *line = [NSBezierPath bezierPath];
    [line moveToPoint:NSMakePoint(0, y-0.5)];
    [line lineToPoint:NSMakePoint(w, y-0.5)];
    [[NSColor colorWithCalibratedWhite:189.f/255.f alpha:1] set];
    [line stroke];
    line = [NSBezierPath bezierPath];
    [line moveToPoint:NSMakePoint(0, y-1.5)];
    [line lineToPoint:NSMakePoint(w, y-1.5)];
    [[NSColor colorWithCalibratedWhite:211.f/255.f alpha:1] set];
    [line stroke];
}
@end


@implementation MBWindow
//http://stackoverflow.com/a/12363406/6444
- (BOOL)canBecomeKeyWindow {
    return YES;
}
@end
