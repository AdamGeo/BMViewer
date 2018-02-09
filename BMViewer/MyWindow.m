#import "MyWindow.h"
#import "StillAwake.h"
#import <AVFoundation/AVFoundation.h>
#import "BMViewerDocument.h"

#define SLEEP_TIME 7200 // 2 hours
//#define SLEEP_TIME 5 // 5 seconds

@implementation MyWindow {
    CALayer *overlayLayer;
    BOOL _isFullscreen;
}

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
- (IBAction)ToggleFullscreen:(id)sender 
{
    [self toggleFullScreen:sender];
}

- (void)toggleFullScreen:(nullable id)sender
{
    if (overlayLayer != NULL) {
        [overlayLayer removeFromSuperlayer];
        overlayLayer = nil;
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(disablePreventUserIdleDisplaySleep) object:nil];
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkAsleep) object:nil];
        NSLog(@"@selector(checkAsleep) unscheduled toggleFullScreen 1");
        if (_isFullscreen) {
            [self performSelector:@selector(checkAsleep) withObject:nil afterDelay:SLEEP_TIME];
            NSLog(@"@selector(checkAsleep) scheduled toggleFullScreen 1");
        }
    }
    else {
        [super toggleFullScreen:nil];
        _isFullscreen = !_isFullscreen;
//        NSLog(@"isFull: %@", _isFullscreen ? @"YES" : @"NO");
        if (_isFullscreen) {
            [self performSelector:@selector(checkAsleep) withObject:nil afterDelay:SLEEP_TIME];
            NSLog(@"@selector(checkAsleep) scheduled toggleFullScreen 2");
        }
        else {
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(disablePreventUserIdleDisplaySleep) object:nil];
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkAsleep) object:nil];
            NSLog(@"@selector(checkAsleep) unscheduled toggleFullScreen 2");
        }
    }
}

-(void)checkAsleep
{
    if (_isFullscreen) {
        NSView *previewView = [(BMViewerDocument*)[[self windowController] document] previewView];
        overlayLayer = [CALayer layer];
        NSImage *overlayImage = [NSImage imageNamed:@"StillAwake"];
        NSGraphicsContext *context = [NSGraphicsContext currentContext];
        CGRect imageCGRect = CGRectMake(0, 0, overlayImage.size.width, overlayImage.size.height);
        NSRect imageRect = NSRectFromCGRect(imageCGRect);
        CGImageRef imageRef = [overlayImage CGImageForProposedRect:&imageRect context:context hints:nil];
        [overlayLayer setContents:(__bridge id)imageRef];
        overlayLayer.frame = CGRectMake(0, 0, previewView.frame.size.width, previewView.frame.size.height);
        [overlayLayer setMasksToBounds:YES];
        [previewView.layer addSublayer:overlayLayer];
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(disablePreventUserIdleDisplaySleep) object:nil];
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkAsleep) object:nil];
        NSLog(@"@selector(checkAsleep) unscheduled checkAsleep");
        [self performSelector:@selector(disablePreventUserIdleDisplaySleep) withObject:nil afterDelay:30.0]; // 30.0
    }
}

-(void) disablePreventUserIdleDisplaySleep
{
    if (_isFullscreen) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkAsleep) object:nil];
        NSLog(@"@selector(checkAsleep) unscheduled disablePreventUserIdleDisplaySleep");
        _isFullscreen = NO;
        [super toggleFullScreen:nil];
    }
}

@end
