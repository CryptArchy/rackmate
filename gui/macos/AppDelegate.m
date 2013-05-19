#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"
#import "rackmate.h"
#import "SPMediaKeyTap.h"
#import "JSONKit.h"



int main(int argc, const char **argv) {
    [NSApplication sharedApplication];
    [NSApp setDelegate:[AppDelegate new]];
    [NSApp run];
    return 0;
}


@implementation AppDelegate {
    NSStatusItem *statusItem;
    NSMenu *menu;
    NSMenuItem *artistMenuItem;
    NSMenuItem *trackMenuItem;
    NSMenuItem *spotifyStatusMenuItem;
    NSMenuItem *separator;
    NSMenuItem *pauseMenuItem;
    NSThread *thread;

    MBInsomnia *insomnia;
    MBWebSocketClient *ws;

    BOOL notNow;
    BOOL waitingToQuit;
}

+ (void)initialize {
	[[NSUserDefaults standardUserDefaults] registerDefaults:@{kMediaKeyUsingBundleIdentifiersDefaultsKey: [SPMediaKeyTap defaultMediaKeyUserBundleIdentifiers]}];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    thread = [[NSThread alloc] initWithTarget:self selector:@selector(luaInBackground) object:nil];
    [thread start];

    artistMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
    trackMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
    pauseMenuItem = [[NSMenuItem alloc] initWithTitle:@"Pause" action:@selector(pause) keyEquivalent:@""];
    separator = [NSMenuItem separatorItem];
    spotifyStatusMenuItem = [[NSMenuItem alloc] initWithTitle:@"unintialized" action:NULL keyEquivalent:@""];
    NSMenuItem *home = [[NSMenuItem alloc] initWithTitle:@"Open rackit.co…" action:@selector(openHomeURL) keyEquivalent:@""];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit Rackmate" action:@selector(terminate:) keyEquivalent:@""];

    pauseMenuItem.target = home.target = self;
    artistMenuItem.hidden = trackMenuItem.hidden = separator.hidden = pauseMenuItem.hidden = YES;

    menu = [NSMenu new];
    [menu addItem:artistMenuItem];
    [menu addItem:trackMenuItem];
    [menu addItem:pauseMenuItem];
    [menu addItem:separator];
    [menu addItem:spotifyStatusMenuItem];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:home];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:quit];

    statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:29] retain];
    [self resetMenu];
    statusItem.image = [NSImage imageNamed:@"NSStatusItemDisabled.png"];

    if ([SPMediaKeyTap usesGlobalMediaKeyTap])
		[[[SPMediaKeyTap alloc] initWithDelegate:self] startWatchingMediaKeys];

    [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
                                                       andSelector:@selector(handleGetURLEvent:withReplyEvent:)
                                                     forEventClass:kInternetEventClass
                                                        andEventID:kAEGetURL];

    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(onSleepNotification:)
                                                               name:NSWorkspaceWillSleepNotification
                                                             object:NULL];
    insomnia = [MBInsomnia new];
    ws = [MBWebSocketClient new];
}

- (void)webSocketData:(NSData *)msg {
    @try {
        NSDictionary *o = msg.objectFromJSONData;
        if (o[@"spotify"]) {
            if ([o[@"spotify"] isEqual:@"loggedin"]) {
                [self resetMenu];
                statusItem.image = [NSImage imageNamed:@"NSStatusItem.png"];
            } else if (!notNow && !statusItem.view && [o[@"spotify"] isEqual:@"loggedout"])
                [self showLogIn];
            else
                statusItem.image = [NSImage imageNamed:@"NSStatusItemDisabled.png"];
            spotifyStatusMenuItem.title = o[@"spotify"];
        }
        BOOL const stopped = [o[@"state"] isEqual:@"stopped"];
        BOOL const playing = [o[@"state"] isEqual:@"playing"];
        artistMenuItem.hidden = trackMenuItem.hidden = separator.hidden = pauseMenuItem.hidden = stopped;
        if (!stopped) {
            int i = [o[@"index"] intValue];
            int si = [o[@"subindex"] intValue];
            id track = o[@"tapes"][i][@"tracks"][si];
            artistMenuItem.title = track[@"artist"];
            trackMenuItem.title = track[@"title"];
        }
        if ([o[@"state"] isEqual:@"paused"]) {
            pauseMenuItem.state = NSOnState;
            pauseMenuItem.title = @"Paused";
        } else {
            pauseMenuItem.state = NSOffState;
            pauseMenuItem.title = @"Pause";
        }
        [insomnia toggle:playing];
    } @catch (id e) {
        NSLog(@"%@", e);
    }
}

- (void)resetMenu {
    statusItem.view = nil;
    statusItem.highlightMode = YES;
    statusItem.alternateImage = [NSImage imageNamed:@"NSStatusItemInverted.png"];
    statusItem.menu = menu;
}

- (void)notNow {
    notNow = YES;
    [self resetMenu];
    statusItem.image = [NSImage imageNamed:@"NSStatusItemDisabled.png"];
}

- (void)showLogIn {
    statusItem.view = [[[MBStatusItemView alloc] initWithFrame:NSMakeRect(0, 0, 29, [NSStatusBar systemStatusBar].thickness)] autorelease];
    [statusItem.view performSelector:@selector(toggle) withObject:nil afterDelay:0.1];
}

- (void)luaInBackground {
    id pool = [NSAutoreleasePool new];
    id nspath = [[[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"rackmate.lua"];
    char path[[nspath lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
    strcpy(path, [nspath UTF8String]);
    [pool release];
    lua_thread_loop(path);
    if (waitingToQuit)
        [NSApp terminate:self];
    else
        NSLog(@"Lua thread ended, but we weren't expecting it!");
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSNotification *)note {
    if (waitingToQuit)
        return NSTerminateNow;
    //TODO handle case where socket didn't bind
    [ws send:@"\"quit\""];
    waitingToQuit = YES;
    // NSTerminateLater causes the RunLoop to not work with AsyncSocket
    return NSTerminateCancel;
}

- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent {
    NSURL *url = [NSURL URLWithString:[[event paramDescriptorForKeyword:keyDirectObject] stringValue]];
    //TODO
}

- (void)onSleepNotification:(NSNotification *)note {
    [ws send:@"{\"pause\": true}"];
}

- (IBAction)openHomeURL {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://rackit.co"]];
}

- (IBAction)pause {
    [ws send:@"{\"play\": \"toggle\"}"];
}

- (void)mediaKeyTap:(SPMediaKeyTap *)keyTap receivedMediaKeyEvent:(NSEvent *)event; {
	NSAssert([event type] == NSSystemDefined && [event subtype] == SPSystemDefinedEventMediaKeys, @"Unexpected NSEvent in mediaKeyTap:receivedMediaKeyEvent:");
	// here be dragons...
	int keyCode = (([event data1] & 0xFFFF0000) >> 16);
	int keyFlags = ([event data1] & 0x0000FFFF);
	BOOL keyIsPressed = (((keyFlags & 0xFF00) >> 8)) == 0xA;
	int keyRepeat = (keyFlags & 0x1);

	if (keyIsPressed && !keyRepeat) switch (keyCode) {
		case NX_KEYTYPE_PLAY:
            [ws send:@"{\"play\": \"toggle\"}"];
			break;
		case NX_KEYTYPE_FAST:
			[ws send:@"{\"play\": \"next\"}"];
			break;
		case NX_KEYTYPE_REWIND:
			[ws send:@"{\"play\": \"prev\"}"];
			break;
	}
}

@end
