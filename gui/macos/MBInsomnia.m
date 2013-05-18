#import <IOKit/pwr_mgt/IOPMLib.h>
#import "AppDelegate.h"

@implementation MBInsomnia

- (void)dealloc {
    [self toggle:NO];
    [super dealloc];
}

- (void)toggle:(BOOL)on {
    if (on && !assertionID) {
        IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep, kIOPMAssertionLevelOn, CFSTR("Making a rackit."), &assertionID);
    } else if (!on && assertionID) {
        IOPMAssertionRelease(assertionID);
        assertionID = 0;
    }
}

@end
