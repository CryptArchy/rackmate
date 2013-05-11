#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"
#import "MBInsomnia.h"
#import "SPMediaKeyTap.h"
#import "WebSocket.h"
#import "JSONKit.h"

int lua_thread_loop();

@interface AppDelegate () <WebSocketDelegate>
@end


@implementation AppDelegate

+ (void)initialize {
	[[NSUserDefaults standardUserDefaults] registerDefaults:@{kMediaKeyUsingBundleIdentifiersDefaultsKey: [SPMediaKeyTap defaultMediaKeyUserBundleIdentifiers]}];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    WebSocketConnectConfig *conf = [WebSocketConnectConfig configWithURLString:@"ws://localhost:13581" origin:nil protocols:@[@"GUI"] tlsSettings:nil headers:nil verifySecurityKey:NO extensions:nil];
    ws = [[WebSocket alloc] initWithConfig:conf delegate:self];

    thread = [[NSThread alloc] initWithTarget:self selector:@selector(luaInBackground) object:nil];
    thread.threadPriority = 1.0;
    [thread start];

    statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:29] retain];
    statusItem.highlightMode = YES;
    statusItem.alternateImage = [NSImage imageNamed:@"NSStatusItemInverted.png"];
    statusItem.menu = menu;
    statusItem.image = [NSImage imageNamed:@"NSStatusItemDisabled.png"];
    statusItem.view = [[[MBStatusItemView alloc] initWithFrame:NSMakeRect(0, 0, 29, [NSStatusBar systemStatusBar].thickness)] autorelease];

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

- (void)didOpen {
    statusItem.image = [NSImage imageNamed:@"NSStatusItem.png"];
}

- (void)didClose:(NSUInteger)statuscode message:(NSString *)msg error:(NSError *)error {
    statusItem.image = [NSImage imageNamed:@"NSStatusItemDisabled.png"];
    NSLog(@"%@", error);
}

- (void)didReceiveError:(NSError *)error {
    NSLog(@"%@", error);
}

- (void)didReceiveTextMessage:(NSString *)msg {
    @try {
        NSDictionary *o = msg.objectFromJSONString;
        BOOL const stopped = [o[@"state"] isEqual:@"stopped"];
        artistMenuItem.hidden = trackMenuItem.hidden = separator.hidden = stopped;
        if (!stopped) {
            id track = o[@"tapes"][o[@"index"]][@"tracks"][o[@"subindex"]];
            artistMenuItem.title = track[@"artist"];
            trackMenuItem.title = track[@"title"];
        }
    } @catch (id e) {
        NSLog(@"%@", e);
        artistMenuItem.hidden = trackMenuItem.hidden = separator.hidden = YES;
    }
}

- (void)didReceiveBinaryMessage:(NSData *)msg {

}

- (void)doopen {
    [ws performSelector:@selector(open) withObject:nil afterDelay:5];
}

- (void)luaInBackground {
    id pool = [NSAutoreleasePool new];
    id nspath = [[[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"rackmate.lua"];
    char path[[nspath lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
    strcpy(path, [nspath UTF8String]);
    [self performSelectorOnMainThread:@selector(doopen) withObject:nil waitUntilDone:NO];
    [pool release];
    lua_thread_loop(path);
}

- (void)applicationWillTerminate:(NSNotification *)note {

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
