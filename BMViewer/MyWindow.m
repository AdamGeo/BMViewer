#import "MyWindow.h"

@implementation MyWindow

@synthesize constrainingToScreenSuspended;

- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen
{
    if (constrainingToScreenSuspended)
    {
        return frameRect;
    }
    else
    {
        return [super constrainFrameRect:frameRect toScreen:screen];
    }
}

- (IBAction)ToggleFullscreen:(id)sender {
    [super toggleFullScreen:nil];
}

@end
