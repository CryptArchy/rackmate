#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>


@interface MBStatusItemView : NSView
@end


@interface MBWebSocketClient : NSObject
- (void)send:(NSString *)string;
@end


@interface MBInsomnia : NSObject
- (void)toggle:(BOOL)on;
@end


@interface AppDelegate : NSObject <NSApplicationDelegate>
@end
