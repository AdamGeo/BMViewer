#import "VideoView.h"
#import "MyWindow.h"

@implementation VideoView

-(void)mouseUp:(NSEvent *)theEvent
{
    if (theEvent.clickCount==2) {
        [(MyWindow*)self.window toggleFullScreen:nil];
    }
}

@end
