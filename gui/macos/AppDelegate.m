#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"
#import "rackmate.h"
#import "SPMediaKeyTap.h"
#import "JSONKit.h"

#define NEXT_RACKMATE "rackmate-macos-1.tar.bz2"
#define NEXT_RACKMATE_DLPATH [NSString stringWithFormat:@"%s/%s/" NEXT_RACKMATE, homepath(), syspath(0)]

@interface AppDelegate () <NSURLDownloadDelegate>
@end

static void relaunch() {
    const char *path = [NSBundle mainBundle].executablePath.fileSystemRepresentation;
    execl(path, path, NULL);
}

int main(int argc, const char **argv) {
    [NSApplication sharedApplication];
    [NSApp setDelegate:[AppDelegate new]];
    [NSApp run];
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
    BOOL updateWaiting;
    BOOL extracting;
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

    // fire our first update check in 30 minutes, this is to prevent a constant
    // update-restart cycle that is possible if a) user hasn't run rackmate for
    // several updates or b) I accidentally upload a build with the wrong version
    // number (in which case this 30 minute buffer will give me time to fix it
    // when detected).
    id timer = [[NSTimer alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:30*60]
                                        interval:60*60*24 target:self
                                        selector:@selector(checkForUpdates)
                                        userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];

//////////////////////////////////////////////////////////////////// LoginItem
    // TODO shouldn't always add ourselves back :P
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    id rackmate = [NSURL fileURLWithPath:[NSBundle mainBundle].bundlePath];
    LSSharedFileListInsertItemURL(loginItems, kLSSharedFileListItemBeforeFirst, NULL, NULL, (CFURLRef)rackmate, NULL, NULL);
    CFRelease(loginItems);
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

        if (stopped && updateWaiting) {
            atexit(relaunch); // [NSApp run] never returns, so this is the only option
            [NSApp terminate:self];
        }
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
    NSLog(@"Sent quit");
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

- (void)checkForUpdates {
    if (updateWaiting)
        return;
    // we deliberately ALWAYS download, because I may have uploaded a bad
    // update I need to replace in order to prevent a restart-cycle
    id url = [NSURL URLWithString:@"http://rackit.co/static/downloads/" NEXT_RACKMATE];
    id rq = [NSURLRequest requestWithURL:url];
    [[NSURLDownload alloc] initWithRequest:rq delegate:self];
}

- (void)download:(NSURLDownload *)dl decideDestinationWithSuggestedFilename:(NSString *)filename {
    [dl setDestination:NEXT_RACKMATE_DLPATH allowOverwrite:YES];
}

- (void)download:(NSURLDownload *)dl didFailWithError:(NSError *)error {
    NSLog(@"%@", error);
    [dl release]; //TODO:ERROR
}

- (void)downloadDidFinish:(NSURLDownload *)dl {
    if (!extracting) {
        extracting = YES;
        [self performSelectorInBackground:@selector(extract) withObject:nil];
    }
    [dl release];
}

- (void)extract {
    //TODO if we can't extract due to permissions we need to non-intrusively
    // prompt for permissions, sadly. So check *first*
    //TODO would be better to pipe the data to tar so that it is harder for
    // another process to exploit us
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSTask *task = [NSTask new];
    task.currentDirectoryPath = [NSBundle mainBundle].bundlePath;
    task.arguments = @[@"xjf", NEXT_RACKMATE_DLPATH, @"--strip", @"1"];
    task.launchPath = @"/usr/bin/tar";
    [task launch];
    [task waitUntilExit];
    updateWaiting = YES;
    extracting = NO;
}

@end
