#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"
#import "MBInsomnia.h"
#import "SPMediaKeyTap.h"
#import "spotify.h"
#import "JSONKit.h"

extern sp_session *session;
int lua_thread_loop();


@implementation AppDelegate {
    BOOL notNow;
    BOOL waitingToQuit;
}

+ (void)initialize {
	[[NSUserDefaults standardUserDefaults] registerDefaults:@{kMediaKeyUsingBundleIdentifiersDefaultsKey: [SPMediaKeyTap defaultMediaKeyUserBundleIdentifiers]}];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    ws = [MBWebSocketClient new];

    thread = [[NSThread alloc] initWithTarget:self selector:@selector(luaInBackground) object:nil];
    thread.threadPriority = 1.0;
    [thread start];

    statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:29] retain];
    [self resetMenu];

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
    artistMenuItem.hidden = YES;
    trackMenuItem.hidden = YES;
    separator.hidden = YES;
    pauseMenuItem.hidden = YES;

    insomnia = [MBInsomnia new];
}

- (void)webSocketData:(NSData *)msg {
    @try {
        NSDictionary *o = msg.objectFromJSONData;
        if (o[@"spotify"]) {
            NSLog(@"%@", o[@"spotify"]);
            if ([o[@"spotify"] isEqual:@"loggedin"])
                statusItem.image = [NSImage imageNamed:@"NSStatusItem.png"];
            else {
                statusItem.image = [NSImage imageNamed:@"NSStatusItemDisabled.png"];
                if (!notNow && !statusItem.view && [o[@"spotify"] isEqual:@"loggedout"])
                    [self showLogIn];
            }
            spotifyStatusMenuItem.title = o[@"spotify"];
        } else {
            BOOL const stopped = [o[@"state"] isEqual:@"stopped"];
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
        }
    } @catch (id e) {
        NSLog(@"%@", e);
    }

    //statusItem.image = [NSImage imageNamed:@"NSStatusItem.png"];
}

- (void)resetMenu {
    statusItem.view = nil;
    statusItem.highlightMode = YES;
    statusItem.alternateImage = [NSImage imageNamed:@"NSStatusItemInverted.png"];
    statusItem.menu = menu;
    statusItem.image = [NSImage imageNamed:@"NSStatusItemDisabled.png"];
}

- (void)notNow {
    notNow = YES;
    [self resetMenu];
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

- (IBAction)openHomeURL:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://rackit.co"]];
}

- (IBAction)pause:(NSMenuItem *)menuItem {
    [ws send:@"{\"play\": \"toggle\"}"];
}

-(void)mediaKeyTap:(SPMediaKeyTap *)keyTap receivedMediaKeyEvent:(NSEvent *)event;
{
	NSAssert([event type] == NSSystemDefined && [event subtype] == SPSystemDefinedEventMediaKeys, @"Unexpected NSEvent in mediaKeyTap:receivedMediaKeyEvent:");
	// here be dragons...
	int keyCode = (([event data1] & 0xFFFF0000) >> 16);
	int keyFlags = ([event data1] & 0x0000FFFF);
	BOOL keyIsPressed = (((keyFlags & 0xFF00) >> 8)) == 0xA;
	int keyRepeat = (keyFlags & 0x1); //TODO

	if (keyIsPressed && !keyRepeat) {
		switch (keyCode) {
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
}

@end
