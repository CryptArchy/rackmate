#import <IOKit/pwr_mgt/IOPMLib.h>
#import "MBInsomnia.h"

@implementation MBInsomnia

- (void)dealloc {
    [super dealloc];
    [self off];
}

- (void)on {
    if (!assertionID) {
        IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep, kIOPMAssertionLevelOn, CFSTR("Making a rackit."), &assertionID);
    }
}

- (void)off {
    if (assertionID) {
        IOPMAssertionRelease(assertionID);
        assertionID = 0;
    }
}

@end