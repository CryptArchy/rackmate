#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>

@class MBInsomnia;
@class MBWebSocketClient;


@interface AppDelegate : NSObject <NSApplicationDelegate> {
    IBOutlet NSStatusItem *statusItem;
    IBOutlet NSMenu *menu;
    IBOutlet NSMenuItem *artistMenuItem;
    IBOutlet NSMenuItem *trackMenuItem;
    IBOutlet NSMenuItem *spotifyStatusMenuItem;
    IBOutlet NSMenuItem *websocketStatusMenuItem;
    IBOutlet NSMenuItem *separator;
    IBOutlet NSMenuItem *buildDateMenuItem;
    IBOutlet NSMenuItem *pauseMenuItem;

    MBInsomnia *insomnia;
    MBWebSocketClient *ws;
    NSThread *thread;
}

@end


@interface MBStatusItemView : NSView
@end


@interface MBWebSocketClient : NSObject
- (void)write:(id)dataOrString;
@end
