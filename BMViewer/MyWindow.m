#import "MyWindow.h"
#import "StillAwake.h"

@implementation MyWindow {
    BOOL _isFull;
}

@synthesize constrainingToScreenSuspended;
@synthesize IsFullscreen = _isFull;

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
    _isFull = !_isFull;
    [super toggleFullScreen:nil];
    if (_isFull) {
        // setup timer properly
        [self performSelector:@selector(checkAsleep) withObject:nil afterDelay:2.0];
    }
}

-(void)checkAsleep {
//    StillAwake *sa = [[StillAwake alloc] init];
//
//    convert to objc
//    let previewLayer: AVCaptureVideoPreviewLayer = AVCaptureVideoPreviewLayer(session: self.avCaptureSession)
//
//    previewLayer.frame = self.view.layer.frame
//
//    previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill
//
//    self.view.layer.addSublayer(previewLayer)
//
//    let cameraOverlay = CameraOverlay(nibName:"CameraOverlay",bundle: nil)
//
//    let cameraOverlayView:CameraOverlayView = cameraOverlay.view as! CameraOverlayView
//
//    let previewView = UIView(frame: view.frame)
//
//    self.view.addSubview(previewView)
//
//    previewView.layer.addSublayer(previewLayer)
//
//    self.view.addSubview(cameraOverlayView)
//
//    self.avCaptureSession?.startRunning()
    
}

@end
