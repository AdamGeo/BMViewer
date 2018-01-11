#import "VideoView.h"

@implementation VideoView

-(void)mouseUp:(NSEvent *)theEvent
{
    if (theEvent.clickCount==2) {
        [self.window toggleFullScreen:nil];
    }
}

@end
