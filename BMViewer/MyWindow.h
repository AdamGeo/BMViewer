#import <Foundation/Foundation.h>

@interface MyWindow : NSWindow
{
    BOOL constrainingToScreenSuspended;
}

@property BOOL constrainingToScreenSuspended;
@property BOOL IsFullscreen;

- (IBAction)ToggleFullscreen:(id)sender;

@end
