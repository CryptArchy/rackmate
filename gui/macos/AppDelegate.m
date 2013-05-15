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

    websocketStatusMenuItem.title = @"WebSocket disconnected";
    artistMenuItem.hidden = YES;
    trackMenuItem.hidden = YES;
    separator.hidden = YES;
    pauseMenuItem.hidden = YES;

    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:[NSBundle mainBundle].executablePath error:nil];
    NSDateFormatter *df = [NSDateFormatter new];
    df.dateFormat = @"MM/dd/yy HH:mm:ss";
    df.timeZone = [NSTimeZone timeZoneWithName:@"EST"];
    NSString *timestamp = [df stringFromDate:attrs.fileModificationDate];
    if (timestamp.length)
        buildDateMenuItem.title = timestamp;

    insomnia = [MBInsomnia new];
}

- (void)webSocketData:(NSData *)msg {
    @try {
        NSDictionary *o = msg.objectFromJSONData;
        if (o[@"status"]) {
            statusItem.image = [NSImage imageNamed:o[@"green"] ? @"NSStatusItem.png" : @"NSStatusItemDisabled.png"];
        } else {
            BOOL const stopped = [o[@"state"] isEqual:@"stopped"];
            artistMenuItem.hidden = trackMenuItem.hidden = separator.hidden = stopped;
            if (!stopped) {
                id track = o[@"tapes"][o[@"index"]][@"tracks"][o[@"subindex"]];
                artistMenuItem.title = track[@"artist"];
                trackMenuItem.title = track[@"title"];
            }
        }
    } @catch (id e) {
        NSLog(@"%@", e);
        artistMenuItem.hidden = trackMenuItem.hidden = separator.hidden = YES;
    }

    //statusItem.image = [NSImage imageNamed:@"NSStatusItem.png"];
}

- (void)didReceiveBinaryMessage:(NSData *)msg {

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
        [NSApp replyToApplicationShouldTerminate:YES];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSNotification *)note {
    //TODO handle case where socket didn't bind
    NSLog(@"HI");
    [ws write:@"quit"];
    waitingToQuit = YES;
    return NSTerminateLater;
}

- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent {
    NSURL *url = [NSURL URLWithString:[[event paramDescriptorForKeyword:keyDirectObject] stringValue]];
    //TODO
}

- (void)onSleepNotification:(NSNotification *)note {
    //[ws send:@"\"pause\""];
}

- (IBAction)openHomeURL:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://rackit.co"]];
}

- (IBAction)pause:(NSMenuItem *)menuItem {
    //[ws send:@"{\"play\": \"toggle\"}"];
}

-(void)mediaKeyTap:(SPMediaKeyTap *)keyTap receivedMediaKeyEvent:(NSEvent *)event;
{
	NSAssert([event type] == NSSystemDefined && [event subtype] == SPSystemDefinedEventMediaKeys, @"Unexpected NSEvent in mediaKeyTap:receivedMediaKeyEvent:");
	// here be dragons...
	int keyCode = (([event data1] & 0xFFFF0000) >> 16);
	int keyFlags = ([event data1] & 0x0000FFFF);
	BOOL keyIsPressed = (((keyFlags & 0xFF00) >> 8)) == 0xA;
	//int keyRepeat = (keyFlags & 0x1); //TODO

	if (keyIsPressed) {
		switch (keyCode) {
			// case NX_KEYTYPE_PLAY:
			// 	switch (musicbox.state) {
   //                  case Paused:
   //                      musicbox.paused = NO;
   //                      break;
   //                  case Playing:
   //                      musicbox.paused = YES;
   //                      break;
   //                  case Stopped:
   //                      [musicbox play:[NSIndexPath indexPathWithIndexes:(const NSUInteger[]){0, 0} length:2]];
   //                      break;
   //              }
			// 	break;

			// case NX_KEYTYPE_FAST:
			// 	[musicbox next];
			// 	break;

			// case NX_KEYTYPE_REWIND:
			// 	[musicbox prev];
			// 	break;
		}
	}
}

@end
