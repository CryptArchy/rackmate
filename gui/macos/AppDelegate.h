@class MBInsomnia;
@class WebSocket;


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
    WebSocket *ws;
    NSThread *thread;
}

@end


@interface MBStatusItemView : NSView
@end
