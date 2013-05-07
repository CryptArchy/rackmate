#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"
#import "MBInsomnia.h"
#import "SPMediaKeyTap.h"

int lua_thread_loop();


@implementation AppDelegate

+ (void)initialize {
	[[NSUserDefaults standardUserDefaults] registerDefaults:@{kMediaKeyUsingBundleIdentifiersDefaultsKey: [SPMediaKeyTap defaultMediaKeyUserBundleIdentifiers]}];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    [self performSelectorInBackground:@selector(luaInBackground) withObject:nil];

    statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:29] retain];
    statusItem.highlightMode = YES;
    statusItem.alternateImage = [NSImage imageNamed:@"NSStatusItemInverted.png"];
    statusItem.menu = menu;
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

- (void)luaInBackground {
    id s = [[[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"rackmate.lua"];
    lua_thread_loop([s UTF8String]);
}

- (void)applicationWillTerminate:(NSNotification *)note {

}

- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent {
    NSURL *url = [NSURL URLWithString:[[event paramDescriptorForKeyword:keyDirectObject] stringValue]];
    //TODO
}

- (void)onSleepNotification:(NSNotification *)note {
    //TODO pause
}

- (IBAction)openHomeURL:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://rackit.co"]];
}

- (IBAction)pause:(NSMenuItem *)menuItem {

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
