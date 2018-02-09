#import <Foundation/Foundation.h>

@interface MyWindow : NSWindow
{
    BOOL constrainingToScreenSuspended;
}

@property BOOL constrainingToScreenSuspended;

- (IBAction)ToggleFullscreen:(id)sender;

@end
