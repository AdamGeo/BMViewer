#import "BMViewerDocument.h"
#import <AVFoundation/AVFoundation.h>
#import "MyWindow.h"
#import "AVCaptureDeviceFormat_BMViewerAdditions.h"
#import "AVFrameRateRange_BMViewerAdditions.h"
#import <IOKit/pwr_mgt/IOPMLib.h>
@import AudioKit;

@interface BMViewerDocument () <NSOpenSavePanelDelegate, AVCaptureFileOutputDelegate, AVCaptureFileOutputRecordingDelegate, NSMenuDelegate, AVCaptureAudioDataOutputSampleBufferDelegate> {
    BOOL foundVideo;
    BOOL foundVFormat;
    BOOL foundVFR;
    BOOL foundAudio;
    BOOL foundAFormat;
    BOOL _exportMP4;
    BOOL _EnableAudioEffects;
    NSEvent *eventMon;
    NSTextField *alertLbl;
    NSInteger lastPreset;
    AVAssetExportSession *exporter;
    IOPMAssertionID assertionID;
    CFStringRef reasonForActivity;
    
    AKEqualizerFilter *f1;
    AKEqualizerFilter *f2;
    AKEqualizerFilter *f3;
    AKEqualizerFilter *f4;
    AKEqualizerFilter *f5;
    AKEqualizerFilter *f6;
    AKEqualizerFilter *f7;
    AKEqualizerFilter *f8;
    AKEqualizerFilter *f9;
    AKEqualizerFilter *f10;
    AKBooster *boost;
}

@property (strong) AVCaptureDeviceInput *videoDeviceInput;
@property (strong) AVCaptureDeviceInput *audioDeviceInput;
@property (readonly) BOOL selectedVideoDeviceProvidesAudio;
@property (strong) AVCaptureAudioPreviewOutput *audioPreviewOutput;
@property (strong) AVCaptureMovieFileOutput *movieFileOutput;
@property (strong) AVCaptureConnection *movieFileOutputConnection;
//@property (strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (weak) NSTimer *audioLevelTimer;
@property (weak) NSTimer *exportProgressTimer;
@property (strong) NSArray *observers;

@property (weak) IBOutlet NSPopUpButton *videoDeviceList;
@property (weak) IBOutlet NSPopUpButton *videoFormatList;
@property (weak) IBOutlet NSPopUpButton *videoFrmRteList;
@property (weak) IBOutlet NSPopUpButton *audioDeviceList;
@property (weak) IBOutlet NSPopUpButton *audioFormatList;
@property (weak) IBOutlet NSSlider      *boostLevel;
@property (weak) IBOutlet NSSlider *filterBand1;
@property (weak) IBOutlet NSSlider *filterBand2;
@property (weak) IBOutlet NSSlider *filterBand3;
@property (weak) IBOutlet NSSlider *filterBand4;
@property (weak) IBOutlet NSSlider *filterBand5;
@property (weak) IBOutlet NSSlider *filterBand6;
@property (weak) IBOutlet NSSlider *filterBand7;
@property (weak) IBOutlet NSSlider *filterBand8;
@property (weak) IBOutlet NSSlider *filterBand9;
@property (weak) IBOutlet NSSlider *filterBand10;
@property (weak) IBOutlet NSButton *AudioEffectsEnabled;
- (IBAction)AudioEffectsEnabledChanged:(NSButton *)sender;

- (void)refreshDevices;
- (IBAction)filterChange:(id)sender;
- (IBAction)boostChange:(id)sender;
- (IBAction)EqReset:(id)sender;

@end

#pragma mark -
#pragma mark TODO


@implementation BMViewerDocument {}

@synthesize videoDeviceInput, audioDeviceInput, videoDevices, audioDevices, session, audioPreviewOutput, movieFileOutput, movieFileOutputConnection, previewView, previewLayer, audioLevelTimer, exportProgressTimer, observers, frameForNonFullScreenMode, viewForNonFullScreenMode, videoDeviceList, videoFormatList, videoFrmRteList, audioDeviceList, audioFormatList, makeSmaller, rad_MOV, exportLbl, filterBand1, filterBand2, filterBand3, filterBand4, filterBand5, filterBand6, filterBand7, filterBand8, filterBand9, filterBand10, boostLevel, AudioEffectsEnabled;
static BOOL cursorIsHidden = NO; 

- (id)init
{
    self = [super init];
    if (self) {
        reasonForActivity = CFSTR("BMViewer is viewing");
        _exportMP4 = NO;
        lastPreset = -1;
        
        [[self.videoDeviceList menu] setDelegate:self];
        [[self.videoFormatList menu] setDelegate:self];
        [[self.videoFrmRteList menu] setDelegate:self];
        [[self.audioDeviceList menu] setDelegate:self];
        [[self.audioFormatList menu] setDelegate:self];
        
        session = [[AVCaptureSession alloc] init];
        
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        id runtimeErrorObserver = [notificationCenter addObserverForName:AVCaptureSessionRuntimeErrorNotification
                                                                  object:session
                                                                   queue:[NSOperationQueue mainQueue]
                                                              usingBlock:^(NSNotification *note) {
                                                                  dispatch_async(dispatch_get_main_queue(), ^(void) {
                                                                      [self PresentErrorInLog:@"Session Error: " error:[[note userInfo] objectForKey:AVCaptureSessionErrorKey]];
                                                                  });
                                                              }];
        id didStartRunningObserver = [notificationCenter addObserverForName:AVCaptureSessionDidStartRunningNotification
                                                                     object:session
                                                                      queue:[NSOperationQueue mainQueue]
                                                                 usingBlock:^(NSNotification *note) {
                                                                     NSLog(@"did start running");
                                                                 }];
        id didStopRunningObserver = [notificationCenter addObserverForName:AVCaptureSessionDidStopRunningNotification
                                                                    object:session
                                                                     queue:[NSOperationQueue mainQueue]
                                                                usingBlock:^(NSNotification *note) {
                                                                    NSLog(@"did stop running");
                                                                }];
        id deviceWasConnectedObserver = [notificationCenter addObserverForName:AVCaptureDeviceWasConnectedNotification
                                                                        object:nil
                                                                         queue:[NSOperationQueue mainQueue]
                                                                    usingBlock:^(NSNotification *note) {
                                                                        [self refreshDevices];
                                                                    }];
        id deviceWasDisconnectedObserver = [notificationCenter addObserverForName:AVCaptureDeviceWasDisconnectedNotification
                                                                           object:nil
                                                                            queue:[NSOperationQueue mainQueue]
                                                                       usingBlock:^(NSNotification *note) {
                                                                           [self refreshDevices];
                                                                       }];
        
        id enterFullScreenObserver = [notificationCenter addObserverForName:NSWindowWillEnterFullScreenNotification
                                                                     object:nil
                                                                      queue:[NSOperationQueue mainQueue]
                                                                 usingBlock:^(NSNotification *note) {
                                                                     self.frameForNonFullScreenMode = [(MyWindow*)note.object frame];
                                                                     self.viewForNonFullScreenMode = previewView.frame;
                                                                     [self hideCursor];
                                                                     IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionLevelOn, reasonForActivity, &assertionID);
                                                                 }];
        
        id exitFullScreenNotificationObserver = [notificationCenter addObserverForName:NSWindowDidExitFullScreenNotification
                                                                                object:nil
                                                                                 queue:[NSOperationQueue mainQueue]
                                                                            usingBlock:^(NSNotification *note) {
                                                                                [self performSelector:@selector(showCursor) withObject:nil afterDelay:0.25];
                                                                                if (assertionID)
                                                                                    IOPMAssertionRelease(assertionID);
                                                                            }];
        
        id willSleepNotificationObserver = [[[NSWorkspace sharedWorkspace] notificationCenter] addObserverForName:NSWorkspaceScreensDidSleepNotification
                                                                                                           object:nil queue:[NSOperationQueue mainQueue]
                                                                                                       usingBlock:^(NSNotification *note) {
                                                                                                           [AudioKit stop];
                                                                                                           [[self session] stopRunning];
                                                                                                       }];
        id didWakeNotificationObserver = [[[NSWorkspace sharedWorkspace] notificationCenter] addObserverForName:NSWorkspaceScreensDidWakeNotification
                                                                                                           object:nil queue:[NSOperationQueue mainQueue]
                                                                                                       usingBlock:^(NSNotification *note) {
                                                                                                           [[self session] startRunning];
                                                                                                           [AudioKit start];
                                                                                                       }];
        
        eventMon = [NSEvent addLocalMonitorForEventsMatchingMask: (NSEventMaskKeyDown)
                                                handler:^(NSEvent *incomingEvent) {
                                                    NSEvent *result = incomingEvent;
                                                    if ([incomingEvent type] == NSEventTypeKeyDown) {
                                                        NSUInteger flags = [incomingEvent modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;
                                                        if ([incomingEvent keyCode] == 11 && flags == NSEventModifierFlagCommand ) {
                                                            [self.AudioEffectsEnabled performClick:self];
                                                            result = nil;
                                                        }
                                                        if ([incomingEvent keyCode] == 53) {
                                                            [(MyWindow*)self.windowForSheet toggleFullScreen:nil];
                                                            result = nil;
                                                        }
                                                        else {
                                                        }
                                                    }
                                                    return result;
                                                }];
        
        observers = [[NSArray alloc] initWithObjects:runtimeErrorObserver, didStartRunningObserver, didStopRunningObserver, deviceWasConnectedObserver, deviceWasDisconnectedObserver, enterFullScreenObserver, exitFullScreenNotificationObserver, didWakeNotificationObserver, willSleepNotificationObserver, nil];
        movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
        [movieFileOutput setDelegate:self];
        movieFileOutputConnection = [movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
        [session addOutput:movieFileOutput];
        audioPreviewOutput = [[AVCaptureAudioPreviewOutput alloc] init];
        [audioPreviewOutput setVolume:1.f];
        [session addOutput:audioPreviewOutput];
        [self refreshDevices];
    }
    return self;
}

-(BOOL) validateMenuItem:(NSMenuItem *)menuItem {
    if ([menuItem.title isEqualToString:@"Load Next Preset"]) {
        NSDictionary *presetDict = [[NSUserDefaults standardUserDefaults] objectForKey:@"presets"];
        [menuItem setEnabled:(presetDict && [presetDict allKeys].count>0)];
    }
    return [menuItem isEnabled];
}

#pragma mark -
#pragma mark Enter Full Screen
- (NSSize)window:(NSWindow *)window willUseFullScreenContentSize:(NSSize)proposedSize
{
    return proposedSize;
}
-(void) hideCursor
{
    if (!cursorIsHidden)
    {
        [NSCursor hide];
        cursorIsHidden = YES;
    }
}

-(void) showCursor
{
    if (cursorIsHidden)
    {
        [NSCursor unhide];
        cursorIsHidden = NO;
    }
}
- (NSApplicationPresentationOptions)window:(NSWindow *)window willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)proposedOptions
{
    return (NSApplicationPresentationFullScreen |
            NSApplicationPresentationHideDock |
            NSApplicationPresentationAutoHideMenuBar);
}

- (NSArray *)customWindowsToEnterFullScreenForWindow:(NSWindow *)window
{
    return [NSArray arrayWithObject:window];
}

- (void)window:(NSWindow *)window startCustomAnimationToEnterFullScreenWithDuration:(NSTimeInterval)duration
{
    [previewView setAutoresizingMask:NSViewNotSizable];
    [self invalidateRestorableState];
    NSScreen *screen = [[NSScreen screens] objectAtIndex:0];
    NSRect screenFrame = [screen frame];
    NSRect proposedFrame = screenFrame;
    proposedFrame.size = [self window:window willUseFullScreenContentSize:proposedFrame.size];
    proposedFrame.origin.x += floor((NSWidth(screenFrame) - NSWidth(proposedFrame))/2);
    proposedFrame.origin.y += floor((NSHeight(screenFrame) - NSHeight(proposedFrame))/2);
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [context setDuration:duration];
        [[window animator] setFrame:proposedFrame display:YES];
        [[previewView animator]setFrame:proposedFrame];
    } completionHandler:^{}];
}

- (void)windowDidFailToEnterFullScreen:(NSWindow *)window
{
    [NSCursor unhide];
    cursorIsHidden = NO;
}

#pragma mark -
#pragma mark Exit Full Screen

- (NSArray *)customWindowsToExitFullScreenForWindow:(NSWindow *)window
{
    return [NSArray arrayWithObject:window];
}

- (void)window:(NSWindow *)window startCustomAnimationToExitFullScreenWithDuration:(NSTimeInterval)duration
{
    [(MyWindow*)window setConstrainingToScreenSuspended:YES];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context)
     {
         [context setDuration:duration/4];
         [[window animator] setFrame:self.frameForNonFullScreenMode display:YES];
         [self.previewView setFrame:self.viewForNonFullScreenMode];
     } completionHandler:^{[previewView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];}];
}

- (void)windowDidFailToExitFullScreen:(NSWindow *)window
{
}

- (void)cancelOperation:(id)sender
{
    NSLog(@"cancelOperation: %@", sender);
}

#pragma mark -
#pragma mark Full Screen Support: Persisting and Restoring Window's Non-FullScreen Frame

+ (NSArray *)restorableStateKeyPaths
{
    return [[super restorableStateKeyPaths] arrayByAddingObject:@"frameForNonFullScreenMode"];
}

- (void)windowWillClose:(NSNotification *)notification
{
    [AudioKit stop];
    [NSCursor unhide];
    [NSEvent removeMonitor:eventMon];
    cursorIsHidden = NO;
    [[self audioLevelTimer] invalidate];
    [[self session] stopRunning];
    [[self movieFileOutput] setDelegate:nil];
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    for (id observer in [self observers])
        [notificationCenter removeObserver:observer];
    if (assertionID)
        IOPMAssertionRelease(assertionID);
}
- (NSString *)windowNibName
{
    return @"BMViewerDocument";
}

- (void)windowControllerDidLoadNib:(NSWindowController *) aController
{
    [super windowControllerDidLoadNib:aController];
    CALayer *previewViewLayer = [[self previewView] layer];
    [previewViewLayer setBackgroundColor:CGColorGetConstantColor(kCGColorBlack)];
    AVCaptureVideoPreviewLayer *newPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:[self session]];
    [newPreviewLayer setFrame:[previewViewLayer bounds]];
    [newPreviewLayer setAutoresizingMask:kCALayerWidthSizable | kCALayerHeightSizable];
    [previewViewLayer addSublayer:newPreviewLayer];
    [self setPreviewLayer:newPreviewLayer];
    // make sure video view is on top for fullscreen
    NSView *pview = self.previewView.superview;
    [self.previewView removeFromSuperview];
    [pview addSubview:self.previewView];
    [[self session] startRunning];
    [self.exportLbl setHidden:YES];
    lastPreset = -1;
    [self loadPreset:nil];
}

- (void)didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void  *)contextInfo
{
}

- (void)PresentErrorInLog:(NSError *)error
{
    if (error)
        NSLog(@"%@",[error localizedDescription]);
}
- (void)PresentErrorInLog:(NSString*) lbl error:(NSError *)error
{
    if (error)
        NSLog(@"%@%@", lbl, [error localizedDescription]);
}

#pragma mark - Device selection

- (void)refreshDevices
{
    [self setVideoDevices:[[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] arrayByAddingObjectsFromArray:[AVCaptureDevice devicesWithMediaType:AVMediaTypeMuxed]]];
    [self setAudioDevices:[AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio]];
    
    [[self session] beginConfiguration];
    
    if (![[self videoDevices] containsObject:[self selectedVideoDevice]])
        [self setSelectedVideoDevice:nil];
    
    if (![[self audioDevices] containsObject:[self selectedAudioDevice]])
        [self setSelectedAudioDevice:nil];
//    [[self session] commitConfiguration]; // frame rate changes here!!???!! defaults to preset value??
    AVCaptureDeviceFormat *videoDeviceFormat = [self videoDeviceFormat];
    AVFrameRateRange      *videoDeviceFrmrte = [self frameRateRange];
    [[self session] commitConfiguration]; // changes video format here ?
    [self setVideoDeviceFormat:videoDeviceFormat];
    [self setFrameRateRange:videoDeviceFrmrte];
}



- (AVCaptureDevice *)selectedVideoDevice
{
    return [videoDeviceInput device];
}

- (void)setSelectedVideoDevice:(AVCaptureDevice *)selectedVideoDevice
{
    [[self session] beginConfiguration];
    
    if ([self videoDeviceInput]) {
        [session removeInput:[self videoDeviceInput]];
        [self setVideoDeviceInput:nil];
    }
    
    if (selectedVideoDevice) {
        NSError *error = nil;
        AVCaptureDeviceInput *newVideoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:selectedVideoDevice error:&error];
        if (newVideoDeviceInput == nil) {
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                [self PresentErrorInLog:error];
            });
        } else {
            [[self session] addInput:newVideoDeviceInput];
            [self setVideoDeviceInput:newVideoDeviceInput];
        }
    }
    
    if ([self selectedVideoDeviceProvidesAudio])
        [self setSelectedAudioDevice:nil];
    [[self session] commitConfiguration];
    
    
    
}

-(void) deviceChangedAlert:(NSString*)message {
    if (alertLbl && [alertLbl.superview isEqual:self.windowForSheet.contentView]) {
        [alertLbl removeFromSuperview];
        alertLbl = nil;
    }
    alertLbl = [NSTextField textFieldWithString:message];
    alertLbl.bezeled         = NO;
    alertLbl.editable        = NO;
    alertLbl.drawsBackground = NO;
    [alertLbl setBackgroundColor:[NSColor clearColor]];
    NSFontManager *fontManager = [NSFontManager sharedFontManager];
    NSFont *boldFnt = [fontManager fontWithFamily:@"Verdana" traits:NSBoldFontMask weight:0 size:23];
    [alertLbl setFont:boldFnt];
    [alertLbl setTextColor:[NSColor whiteColor]];
    [alertLbl sizeToFit];
    [alertLbl setFrame:NSMakeRect((self.previewView.frame.origin.x + (self.previewView.frame.size.width / 2))-(alertLbl.frame.size.width*0.5), (self.previewView.frame.origin.y + (self.previewView.frame.size.height -(alertLbl.frame.size.height*1.5))), alertLbl.frame.size.width, alertLbl.frame.size.height)];
    [self.windowForSheet.contentView addSubview:alertLbl];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 2;
            alertLbl.animator.alphaValue = 0;
        }
        completionHandler:^{
            [alertLbl removeFromSuperview];
            alertLbl = nil;
        }];
    });
}

- (AVCaptureDevice *)selectedAudioDevice
{
    return [audioDeviceInput device];
}

- (void)setSelectedAudioDevice:(AVCaptureDevice *)selectedAudioDevice
{
    [self resetAudioKit];
    [[self session] beginConfiguration];
    
    if ([self audioDeviceInput]) {
        [session removeInput:[self audioDeviceInput]];
        [self setAudioDeviceInput:nil];
    }
    
    if (selectedAudioDevice && ![self selectedVideoDeviceProvidesAudio]) {
        NSError *error = nil;
        AVCaptureDeviceInput *newAudioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:selectedAudioDevice error:&error];
        if (newAudioDeviceInput == nil) {
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                [self PresentErrorInLog:error];
            });
        } else {
            [[self session] addInput:newAudioDeviceInput];
            [self setAudioDeviceInput:newAudioDeviceInput];
            [self enableAudioEffects];
        }
        
    }
    AVCaptureDeviceFormat *videoDeviceFormat = [self videoDeviceFormat];
    AVFrameRateRange      *videoDeviceFrmrte = [self frameRateRange];
    [[self session] commitConfiguration]; // changes video format here ?
    [self setVideoDeviceFormat:videoDeviceFormat];
    [self setFrameRateRange:videoDeviceFrmrte];
    [self enableAudioEffects];
}

#pragma mark - Audio Boost

- (IBAction)AudioEffectsEnabledChanged:(NSButton *)sender {
    if (_EnableAudioEffects != (sender.state == NSControlStateValueOn)) {
        _EnableAudioEffects = (sender.state == NSControlStateValueOn);
        [self resetAudioKit];
        [self enableAudioEffects];
    }
}

- (void) resetAudioKit {
    [AudioKit stop];
    [AudioKit disconnectAllInputs];
    [audioPreviewOutput setVolume:1];
}
- (void)enableAudioEffects {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(setupAudiokit) object:nil];
    if ([self selectedAudioDevice] != nil && _EnableAudioEffects == YES) {
        [self performSelector:@selector(setupAudiokit) withObject:nil afterDelay:0.5];
    }
    else {
        [audioPreviewOutput setVolume:1];
    }
}

- (IBAction)filterChange:(id)sender
{
    if ([sender isEqual:self.filterBand1])
        [f1 setGain:self.filterBand1.doubleValue];
    else if ([sender isEqual:self.filterBand2])
        [f2 setGain:self.filterBand2.doubleValue];
    else if ([sender isEqual:self.filterBand3])
        [f3 setGain:self.filterBand3.doubleValue];
    else if ([sender isEqual:self.filterBand4])
        [f4 setGain:self.filterBand4.doubleValue];
    else if ([sender isEqual:self.filterBand5])
        [f5 setGain:self.filterBand5.doubleValue];
    else if ([sender isEqual:self.filterBand6])
        [f6 setGain:self.filterBand6.doubleValue];
    else if ([sender isEqual:self.filterBand7])
        [f7 setGain:self.filterBand7.doubleValue];
    else if ([sender isEqual:self.filterBand8])
        [f8 setGain:self.filterBand8.doubleValue];
    else if ([sender isEqual:self.filterBand9])
        [f9 setGain:self.filterBand9.doubleValue];
    else if ([sender isEqual:self.filterBand10])
        [f10 setGain:self.filterBand10.doubleValue];
}

- (IBAction)boostChange:(id)sender {
//    NSLog(@"boost set: %f", self.boostLevel.floatValue);
    [boost setGain:self.boostLevel.doubleValue];
}

- (IBAction)EqReset:(id)sender {
    [self.filterBand1 setDoubleValue:0 ];
    [self filterChange:self.filterBand1];
    [self.filterBand2 setDoubleValue:0 ];
    [self filterChange:self.filterBand2];
    [self.filterBand3 setDoubleValue:0 ];
    [self filterChange:self.filterBand3];
    [self.filterBand4 setDoubleValue:0 ];
    [self filterChange:self.filterBand4];
    [self.filterBand5 setDoubleValue:0 ];
    [self filterChange:self.filterBand5];
    [self.filterBand6 setDoubleValue:0 ];
    [self filterChange:self.filterBand6];
    [self.filterBand7 setDoubleValue:0 ];
    [self filterChange:self.filterBand7];
    [self.filterBand8 setDoubleValue:0 ];
    [self filterChange:self.filterBand8];
    [self.filterBand9 setDoubleValue:0 ];
    [self filterChange:self.filterBand9];
    [self.filterBand10 setDoubleValue:0 ];
    [self filterChange:self.filterBand10];
}

- (IBAction)EqPreset:(id)sender {
    [self.filterBand1 setDoubleValue:4 ];
    [self filterChange:self.filterBand1];
    [self.filterBand2 setDoubleValue:2 ];
    [self filterChange:self.filterBand2];
    [self.filterBand3 setDoubleValue:0.5 ];
    [self filterChange:self.filterBand3];
    [self.filterBand4 setDoubleValue:0 ];
    [self filterChange:self.filterBand4];
    [self.filterBand5 setDoubleValue:-0.5 ];
    [self filterChange:self.filterBand5];
    [self.filterBand6 setDoubleValue:-1 ];
    [self filterChange:self.filterBand6];
    [self.filterBand7 setDoubleValue:-0.5 ];
    [self filterChange:self.filterBand7];
    [self.filterBand8 setDoubleValue:0.5 ];
    [self filterChange:self.filterBand8];
    [self.filterBand9 setDoubleValue:3 ];
    [self filterChange:self.filterBand9];
    [self.filterBand10 setDoubleValue:4 ];
    [self filterChange:self.filterBand10];
}

-(void)setupAudiokit {
    [AudioKit stop];
    [AudioKit disconnectAllInputs];
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        AKDevice* inputDevice;
        for (AKDevice* d in [AudioKit inputDevices]) {
            if ([[d.description stringByReplacingOccurrencesOfString:@"<Device: " withString:@""] hasPrefix:[self selectedAudioDevice].localizedName]) {
                inputDevice = d;
                
                break;
            }
        }
        if (inputDevice != nil) {
            NSError *error = nil;
            if ([AudioKit setInputDevice:inputDevice error:&error]) {
                
                // audiokit destroys sync in recording... ??? ... ???
                
                [audioPreviewOutput setVolume:0];
                
                AKMicrophone *mic = [[AKMicrophone alloc] init];
                
//                CMClockRef clock = session.masterClock;
                
                NSLog(@"this is shit. make paramatric eq");
                //    var parametricEQ = AKParametricEQ(player)
                //    parametricEQ.centerFrequency = 4000 // Hz
                //    parametricEQ.q = 1.0 // Hz
                //    parametricEQ.gain = 10 // dB
                
                boost = [[AKBooster alloc] init:mic gain:self.boostLevel.doubleValue];
                
                
                f1 = [[AKEqualizerFilter alloc] init:boost centerFrequency:32 bandwidth:8 gain:self.filterBand1.doubleValue];
                f2 = [[AKEqualizerFilter alloc] init:f1 centerFrequency:64 bandwidth:16 gain:self.filterBand2.doubleValue];
                f3 = [[AKEqualizerFilter alloc] init:f2 centerFrequency:125 bandwidth:32 gain:self.filterBand3.doubleValue];
                f4 = [[AKEqualizerFilter alloc] init:f3 centerFrequency:250 bandwidth:64 gain:self.filterBand4.doubleValue];
                f5 = [[AKEqualizerFilter alloc] init:f4 centerFrequency:500 bandwidth:128 gain:self.filterBand5.doubleValue];
                f6 = [[AKEqualizerFilter alloc] init:f5 centerFrequency:1000 bandwidth:256 gain:self.filterBand6.doubleValue];
                f7 = [[AKEqualizerFilter alloc] init:f6 centerFrequency:2000 bandwidth:512 gain:self.filterBand7.doubleValue];
                f8 = [[AKEqualizerFilter alloc] init:f7 centerFrequency:4000 bandwidth:1024 gain:self.filterBand8.doubleValue];
                f9 = [[AKEqualizerFilter alloc] init:f8 centerFrequency:8000 bandwidth:2048 gain:self.filterBand9.doubleValue];
                f10 = [[AKEqualizerFilter alloc] init:f9 centerFrequency:16000 bandwidth:4096 gain:self.filterBand10.doubleValue];
                
                [AudioKit setOutput:f10];
                [AKSettings setDisableAVAudioSessionCategoryManagement:TRUE];
                [AKSettings setDefaultToSpeaker:TRUE];
                [AKSettings setPlaybackWhileMuted:FALSE];
                [AKSettings setAudioInputEnabled:FALSE];
                [AudioKit start];
                
                [self filterChange:self.filterBand1];
                [self filterChange:self.filterBand2];
                [self filterChange:self.filterBand3];
                [self filterChange:self.filterBand4];
                [self filterChange:self.filterBand5];
                [self filterChange:self.filterBand6];
                [self filterChange:self.filterBand7];
                [self filterChange:self.filterBand8];
                [self filterChange:self.filterBand9];
                [self filterChange:self.filterBand10];
                
            }
            else {
                NSLog(@"Set InputDevice for AudioKit failed: %@", error.localizedDescription);
            }
        }
    });
}

//AVCaptureDeviceFormat *videoDeviceFormat = [self videoDeviceFormat];
//AVFrameRateRange      *videoDeviceFrmrte = [self frameRateRange];
//[[self session] commitConfiguration]; // changes video format here ?
//[self setVideoDeviceFormat:videoDeviceFormat];
//[self setFrameRateRange:videoDeviceFrmrte];

#pragma mark - Device Properties

+ (NSSet *)keyPathsForValuesAffectingSelectedVideoDeviceProvidesAudio
{
    return [NSSet setWithObjects:@"selectedVideoDevice", nil];
}

- (BOOL)selectedVideoDeviceProvidesAudio
{
    return ([[self selectedVideoDevice] hasMediaType:AVMediaTypeMuxed] || [[self selectedVideoDevice] hasMediaType:AVMediaTypeAudio]);
}

+ (NSSet *)keyPathsForValuesAffectingVideoDeviceFormat
{
    return [NSSet setWithObjects:@"selectedVideoDevice.activeFormat", nil];
}

- (AVCaptureDeviceFormat *)videoDeviceFormat
{
    return [[self selectedVideoDevice] activeFormat];
}

- (void)setVideoDeviceFormat:(AVCaptureDeviceFormat *)deviceFormat
{
//    NSLog(@"setVideoDeviceFormat: %@", deviceFormat.localizedName);
    NSError *error = nil;
    AVCaptureDevice *videoDevice = [self selectedVideoDevice];
    if ([videoDevice lockForConfiguration:&error]) {
        [videoDevice setActiveFormat:deviceFormat];
        [videoDevice unlockForConfiguration];
//        if (_firstLoad) {
//            dispatch_async(dispatch_get_main_queue(), ^(void) {
//                for (AVFrameRateRange *frmt in self.selectedVideoDevice.activeFormat.videoSupportedFrameRateRanges) {
//                    if ([frmt.localizedName isEqualToString:self.defVideoFrmRte]) {
//                        NSLog(@"set frame rate cause %@ = %@", frmt.localizedName, self.defVideoFrmRte);
//                        [self setFrameRateRange:frmt];
//                        break;
//                    }
//                }
//            });
//        }
    } else {
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            [self PresentErrorInLog:error];
        });
    }
    [self enableAudioEffects];
}

+ (NSSet *)keyPathsForValuesAffectingAudioDeviceFormat
{
    return [NSSet setWithObjects:@"selectedAudioDevice.activeFormat", nil];
}

- (AVCaptureDeviceFormat *)audioDeviceFormat
{
    return [[self selectedAudioDevice] activeFormat];
}

- (void)setAudioDeviceFormat:(AVCaptureDeviceFormat *)deviceFormat
{
    [self resetAudioKit];
    NSError *error = nil;
    AVCaptureDevice *audioDevice = [self selectedAudioDevice];
    if ([audioDevice lockForConfiguration:&error]) {
        [audioDevice setActiveFormat:deviceFormat];
        [audioDevice unlockForConfiguration];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            [self PresentErrorInLog:error];
        });
    }
    [self enableAudioEffects];
}

+ (NSSet *)keyPathsForValuesAffectingFrameRateRange
{
    return [NSSet setWithObjects:@"selectedVideoDevice.activeFormat.videoSupportedFrameRateRanges", @"selectedVideoDevice.activeVideoMinFrameDuration", nil];
}

- (AVFrameRateRange *)frameRateRange
{
    AVFrameRateRange *activeFrameRateRange = nil;
    for (AVFrameRateRange *frameRateRange in [[[self selectedVideoDevice] activeFormat] videoSupportedFrameRateRanges])
    {
        if (CMTIME_COMPARE_INLINE([frameRateRange minFrameDuration], ==, [[self selectedVideoDevice] activeVideoMinFrameDuration]))
        {
            activeFrameRateRange = frameRateRange;
            break;
        }
    }
    
    return activeFrameRateRange;
}

- (void)setFrameRateRange:(AVFrameRateRange *)frameRateRange
{
    NSError *error = nil;
    if ([[[[self selectedVideoDevice] activeFormat] videoSupportedFrameRateRanges] containsObject:frameRateRange])
    {
        if ([[self selectedVideoDevice] lockForConfiguration:&error]) {
            [[self selectedVideoDevice] setActiveVideoMinFrameDuration:[frameRateRange minFrameDuration]];
            [[self selectedVideoDevice] unlockForConfiguration];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                [self PresentErrorInLog:error];
            });
        }
    }
    [self enableAudioEffects];
}
#pragma mark - Recording

+ (NSSet *)keyPathsForValuesAffectingHasRecordingDevice
{
    return [NSSet setWithObjects:@"selectedVideoDevice", @"selectedAudioDevice", nil];
}

- (BOOL)hasRecordingDevice
{
    return ((videoDeviceInput != nil) || (audioDeviceInput != nil));
}

+ (NSSet *)keyPathsForValuesAffectingRecording
{
    return [NSSet setWithObject:@"movieFileOutput.recording"];
}

- (BOOL)isRecording
{
    return [[self movieFileOutput] isRecording];
}

-(void) setDisplayName:(NSString *)displayNameOrNil {
    [super setDisplayName:displayNameOrNil];
}
-(void) setWindow:(NSWindow *)window {
    [super setWindow:window];
    
}
- (void)setRecording:(BOOL)record
{
    if (record) {
        
        [self resetAudioKit];
        
        NSURL *tmplte = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"BMViewer_XXXXXX"];
        char buffer[PATH_MAX] = {0};
        [tmplte getFileSystemRepresentation:buffer maxLength:sizeof(buffer)];
        int fd = mkstemp(buffer);
        if (fd != -1) {
            
            [self.movieFileOutput setOutputSettings:@{ AVVideoCodecKey : AVVideoCodecTypeHEVC } forConnection:movieFileOutputConnection];

            NSURL *url = [[NSURL fileURLWithFileSystemRepresentation:buffer isDirectory:NO relativeToURL:nil] URLByAppendingPathExtension:@"mov"];;
            [[self movieFileOutput] startRecordingToOutputFileURL:url
                                                recordingDelegate:self];
        }
        else {
            NSDictionary *userInfo = @{
                                       NSLocalizedDescriptionKey: NSLocalizedString(@"Operation was unsuccessful.", nil),
                                       NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"The operation timed out.", nil),
                                       NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"An error occured writing to disk", nil)
                                       };
            NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                                 code:-57
                                             userInfo:userInfo];
            [self PresentErrorInLog:error];
        }
    } else {
        [[self movieFileOutput] stopRecording];
        [self enableAudioEffects];
    }
}

#pragma mark - Presets load/save


- (IBAction)SaveNewPreset:(id)sender {
    
//    save currently loaded preset or save new for command hold
    
    NSMutableDictionary *newpreset = [NSMutableDictionary dictionary];
    NSString *encodedVideoDevice = [self selectedVideoDevice].localizedName;
    NSString *encodedVideoFormat = [self videoDeviceFormat].localizedName;
    NSString *encodedVideoFrmRte = [self frameRateRange].localizedName;
    NSString *encodedAudioDevice = [self selectedAudioDevice].localizedName;
    NSString *encodedAudioFormat = [self audioDeviceFormat].localizedName;
    [newpreset setValue:encodedVideoDevice ? encodedVideoDevice : @"No Value" forKey:@"VideoDevice"];
    [newpreset setValue:encodedVideoFormat ? encodedVideoFormat : @"No Value" forKey:@"VideoFormat"];
    [newpreset setValue:encodedVideoFrmRte ? encodedVideoFrmRte : @"No Value" forKey:@"VideoFrmRte"];
    [newpreset setValue:encodedAudioDevice ? encodedAudioDevice : @"No Value" forKey:@"AudioDevice"];
    [newpreset setValue:encodedAudioFormat ? encodedAudioFormat : @"No Value" forKey:@"AudioFormat"];
    [newpreset setValue:[NSNumber numberWithDouble:self.boostLevel.doubleValue] forKey:@"boostLevel"];
    [newpreset setValue:[NSNumber numberWithDouble:self.filterBand1.doubleValue] forKey:@"filterBand1"];
    [newpreset setValue:[NSNumber numberWithDouble:self.filterBand2.doubleValue] forKey:@"filterBand2"];
    [newpreset setValue:[NSNumber numberWithDouble:self.filterBand3.doubleValue] forKey:@"filterBand3"];
    [newpreset setValue:[NSNumber numberWithDouble:self.filterBand4.doubleValue] forKey:@"filterBand4"];
    [newpreset setValue:[NSNumber numberWithDouble:self.filterBand5.doubleValue] forKey:@"filterBand5"];
    [newpreset setValue:[NSNumber numberWithDouble:self.filterBand6.doubleValue] forKey:@"filterBand6"];
    [newpreset setValue:[NSNumber numberWithDouble:self.filterBand7.doubleValue] forKey:@"filterBand7"];
    [newpreset setValue:[NSNumber numberWithDouble:self.filterBand8.doubleValue] forKey:@"filterBand8"];
    [newpreset setValue:[NSNumber numberWithDouble:self.filterBand9.doubleValue] forKey:@"filterBand9"];
    [newpreset setValue:[NSNumber numberWithDouble:self.filterBand10.doubleValue] forKey:@"filterBand10"];
    [newpreset setValue:[NSNumber numberWithBool:_EnableAudioEffects] forKey:@"EnableAudioEffects"];
    
    NSInteger psKey = 0;
    NSMutableDictionary *presetDict = [[[NSUserDefaults standardUserDefaults] objectForKey:@"presets"] mutableCopy];
    if (!presetDict) {
        presetDict = [NSMutableDictionary dictionary];
    }
    else {
        psKey = [[presetDict allKeys] count];
    }
    [presetDict setValue:newpreset forKey:[NSString stringWithFormat:@"%li", (long)psKey]];
    [[NSUserDefaults standardUserDefaults] setObject:presetDict forKey:@"presets"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (IBAction)savePreset:(id)sender {
    NSDictionary *presetDict = [[[NSUserDefaults standardUserDefaults] objectForKey:@"presets"] mutableCopy];
    if (!presetDict)
        return;
    NSMutableDictionary *newpreset = [[presetDict objectForKey:[NSString stringWithFormat:@"%li", (long)lastPreset]] mutableCopy];
    NSString *encodedVideoDevice = [self selectedVideoDevice].localizedName;
    NSString *encodedVideoFormat = [self videoDeviceFormat].localizedName;
    NSString *encodedVideoFrmRte = [self frameRateRange].localizedName;
    NSString *encodedAudioDevice = [self selectedAudioDevice].localizedName;
    NSString *encodedAudioFormat = [self audioDeviceFormat].localizedName;
    [newpreset setValue:encodedVideoDevice ? encodedVideoDevice : @"No Value" forKey:@"VideoDevice"];
    [newpreset setValue:encodedVideoFormat ? encodedVideoFormat : @"No Value" forKey:@"VideoFormat"];
    [newpreset setValue:encodedVideoFrmRte ? encodedVideoFrmRte : @"No Value" forKey:@"VideoFrmRte"];
    [newpreset setValue:encodedAudioDevice ? encodedAudioDevice : @"No Value" forKey:@"AudioDevice"];
    [newpreset setValue:encodedAudioFormat ? encodedAudioFormat : @"No Value" forKey:@"AudioFormat"];
    [newpreset setValue:[NSNumber numberWithDouble:self.boostLevel.doubleValue] forKey:@"boostLevel"];
    [newpreset setValue:[NSNumber numberWithDouble:self.filterBand1.doubleValue] forKey:@"filterBand1"];
    [newpreset setValue:[NSNumber numberWithDouble:self.filterBand2.doubleValue] forKey:@"filterBand2"];
    [newpreset setValue:[NSNumber numberWithDouble:self.filterBand3.doubleValue] forKey:@"filterBand3"];
    [newpreset setValue:[NSNumber numberWithDouble:self.filterBand4.doubleValue] forKey:@"filterBand4"];
    [newpreset setValue:[NSNumber numberWithDouble:self.filterBand5.doubleValue] forKey:@"filterBand5"];
    [newpreset setValue:[NSNumber numberWithDouble:self.filterBand6.doubleValue] forKey:@"filterBand6"];
    [newpreset setValue:[NSNumber numberWithDouble:self.filterBand7.doubleValue] forKey:@"filterBand7"];
    [newpreset setValue:[NSNumber numberWithDouble:self.filterBand8.doubleValue] forKey:@"filterBand8"];
    [newpreset setValue:[NSNumber numberWithDouble:self.filterBand9.doubleValue] forKey:@"filterBand9"];
    [newpreset setValue:[NSNumber numberWithDouble:self.filterBand10.doubleValue] forKey:@"filterBand10"];
    [newpreset setValue:[NSNumber numberWithBool:_EnableAudioEffects] forKey:@"EnableAudioEffects"];
    
    [presetDict setValue:newpreset forKey:[NSString stringWithFormat:@"%li", (long)lastPreset]];
    [[NSUserDefaults standardUserDefaults] setObject:presetDict forKey:@"presets"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (IBAction)loadPreset:(id)sender {
    NSDictionary *presetDict = [[NSUserDefaults standardUserDefaults] objectForKey:@"presets"];
    if (!presetDict)
        return;
    lastPreset++;
    if (lastPreset >= [presetDict allKeys].count) {
        lastPreset = 0;
    }
//    NSLog(@"load lastPreset: %li", (long)lastPreset);
    NSDictionary *nextDict = [presetDict objectForKey:[NSString stringWithFormat:@"%li", (long)lastPreset]];
    NSString *encodedVideoDevice = [nextDict objectForKey:@"VideoDevice"];
    NSString *encodedVideoFormat = [nextDict objectForKey:@"VideoFormat"];
    NSString *encodedVideoFrmRte = [nextDict objectForKey:@"VideoFrmRte"];
    NSString *encodedAudioDevice = [nextDict objectForKey:@"AudioDevice"];
    NSString *encodedAudioFormat = [nextDict objectForKey:@"AudioFormat"];
    
    [[self session] beginConfiguration];
    
    if ([self videoDeviceInput]) {
        [session removeInput:[self videoDeviceInput]];
        [self setVideoDeviceInput:nil];
    }
    
    if ([self selectedVideoDeviceProvidesAudio])
        [self setSelectedAudioDevice:nil];
    [[self session] commitConfiguration];
    
    AVFrameRateRange *frameRateRange;
    if ([encodedVideoDevice isEqualToString:@"No Value"]) {
        [self setSelectedVideoDevice:nil];
    }
    else {
        if ([encodedVideoFormat isEqualToString:@"No Value"]) {
            [self setVideoDeviceFormat:nil];
        }
        else {
            if ([encodedVideoFrmRte isEqualToString:@"No Value"]) {
                [self setFrameRateRange:nil];
            }
            else {
//                NSLog(@"got through ifs");
                
                //set video device
                NSError *error = nil;
                for (AVCaptureDevice* dev in videoDevices) {
                    if ([dev.localizedName isEqualToString:encodedVideoDevice]) {
                        self.selectedVideoDevice = dev;
                        break;
                    }
                }
//                NSLog(@"selectedVideoDevice: %@", self.selectedVideoDevice.localizedName);
                AVCaptureDeviceInput *newVideoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:self.selectedVideoDevice error:&error];
                if (newVideoDeviceInput == nil) {
                    dispatch_async(dispatch_get_main_queue(), ^(void) {
                        [self PresentErrorInLog:error];
                    });
                } else {
                    [[self session] addInput:newVideoDeviceInput];
                    [self setVideoDeviceInput:newVideoDeviceInput];
                }
                
                
                
                //set video format
                AVCaptureDeviceFormat *deviceFormat;
                for (AVCaptureDeviceFormat *frmt in self.selectedVideoDevice.formats) {
                    if ([frmt.localizedName isEqualToString:encodedVideoFormat]) {
                        deviceFormat = frmt;
                        break;
                    }
                }
//                NSLog(@"setActiveFormat: %@", deviceFormat.localizedName);
                if ([self.selectedVideoDevice lockForConfiguration:&error]) {
                    [self.selectedVideoDevice setActiveFormat:deviceFormat];
                    [self.selectedVideoDevice unlockForConfiguration];
                } else {
                    dispatch_async(dispatch_get_main_queue(), ^(void) {
                        [self PresentErrorInLog:error];
                    });
                }
                //set video framte rate
                
                for (AVFrameRateRange *frmt in self.selectedVideoDevice.activeFormat.videoSupportedFrameRateRanges) {
                    if ([frmt.localizedName isEqualToString:encodedVideoFrmRte]) {
                        frameRateRange = frmt;
                        break;
                    }
                }
//                NSLog(@"setActiveVideoMinFrameDuration: %@", frameRateRange.localizedName);
                if ([[[self.selectedVideoDevice activeFormat] videoSupportedFrameRateRanges] containsObject:frameRateRange])
                {
                    if ([self.selectedVideoDevice lockForConfiguration:&error]) {
                        [self.selectedVideoDevice setActiveVideoMinFrameDuration:[frameRateRange minFrameDuration]];
                        [self.selectedVideoDevice unlockForConfiguration];
                    } else {
                        dispatch_async(dispatch_get_main_queue(), ^(void) {
                            [self PresentErrorInLog:error];
                        });
                    }
                }
            }
        }
    }
    
    if ([encodedAudioDevice isEqualToString:@"No Value"]) {
        [self setSelectedAudioDevice:nil];
    }
    else {
        if ([encodedAudioFormat isEqualToString:@"No Value"]) {
            [self setAudioDeviceFormat:nil];
        }
        else {
            NSError *error = nil;
            //set audio device
            if ([self audioDeviceInput]) {
                [session removeInput:[self audioDeviceInput]];
                [self setAudioDeviceInput:nil];
            }
            
            for (AVCaptureDevice* dev in audioDevices) {
                if ([dev.localizedName isEqualToString:encodedAudioDevice]) {
                    self.selectedAudioDevice = dev;
                    break;
                }
            }
//            NSLog(@"selectedAudioDevice: %@", self.selectedAudioDevice.localizedName);
            if (self.selectedAudioDevice && ![self selectedVideoDeviceProvidesAudio]) {
                NSError *error = nil;
                AVCaptureDeviceInput *newAudioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:self.selectedAudioDevice error:&error];
                if (newAudioDeviceInput == nil) {
                    dispatch_async(dispatch_get_main_queue(), ^(void) {
                        [self PresentErrorInLog:error];
                    });
                } else {
                    [[self session] addInput:newAudioDeviceInput];
                    [self setAudioDeviceInput:newAudioDeviceInput];
                    [self enableAudioEffects];
                }
            }
            //set audio format
            for (AVCaptureDeviceFormat *frmt in self.selectedAudioDevice.formats) {
                if ([frmt.localizedName isEqualToString:encodedAudioFormat]) {
                    self.audioDeviceFormat = frmt;
                    break;
                }
            }
//            NSLog(@"audioDeviceFormat: %@", self.audioDeviceFormat.localizedName);
            if ([self.selectedAudioDevice lockForConfiguration:&error]) {
                [self.selectedAudioDevice setActiveFormat:self.audioDeviceFormat];
                [self.selectedAudioDevice unlockForConfiguration];
            } else {
                dispatch_async(dispatch_get_main_queue(), ^(void) {
                    [self PresentErrorInLog:error];
                });
            }
            [self setFrameRateRange:frameRateRange];
            
            
            [self.filterBand1 setDoubleValue:[[nextDict objectForKey:@"filterBand1"] doubleValue]];
            [self.filterBand2 setDoubleValue:[[nextDict objectForKey:@"filterBand2"] doubleValue]];
            [self.filterBand3 setDoubleValue:[[nextDict objectForKey:@"filterBand3"] doubleValue]];
            [self.filterBand4 setDoubleValue:[[nextDict objectForKey:@"filterBand4"] doubleValue]];
            [self.filterBand5 setDoubleValue:[[nextDict objectForKey:@"filterBand5"] doubleValue]];
            [self.filterBand6 setDoubleValue:[[nextDict objectForKey:@"filterBand6"] doubleValue]];
            [self.filterBand7 setDoubleValue:[[nextDict objectForKey:@"filterBand7"] doubleValue]];
            [self.filterBand8 setDoubleValue:[[nextDict objectForKey:@"filterBand8"] doubleValue]];
            [self.filterBand9 setDoubleValue:[[nextDict objectForKey:@"filterBand9"] doubleValue]];
            [self.filterBand10 setDoubleValue:[[nextDict objectForKey:@"filterBand10"] doubleValue]];
            

            
//            NSLog(@"filterBand10 setDoubleValue: %f", [[nextDict objectForKey:@"filterBand10"] doubleValue]);
            
            //                        [self.filterBand1 setNeedsDisplay:YES];
            //                        [self.filterBand2 setNeedsDisplay:YES];
            //                        [self.filterBand3 setNeedsDisplay:YES];
            //                        [self.filterBand4 setNeedsDisplay:YES];
            //                        [self.filterBand5 setNeedsDisplay:YES];
            //                        [self.filterBand6 setNeedsDisplay:YES];
            //                        [self.filterBand7 setNeedsDisplay:YES];
            //                        [self.filterBand8 setNeedsDisplay:YES];
            //                        [self.filterBand9 setNeedsDisplay:YES];
            //                        [self.filterBand10 setNeedsDisplay:YES];
            
            [self.boostLevel setDoubleValue:[[nextDict objectForKey:@"boostLevel"] doubleValue]];
            //                        [newpreset setValue:[NSNumber numberWithDouble:self.boostLevel.doubleValue] forKey:@"boostLevel"];
            
            
            
            _EnableAudioEffects = ![[nextDict objectForKey:@"EnableAudioEffects"] boolValue];
            if (_EnableAudioEffects)
                [self.AudioEffectsEnabled setState:NSControlStateValueOn];
            else
                [self.AudioEffectsEnabled setState:NSControlStateValueOff];
            [self.AudioEffectsEnabled performClick:self];
            
        }
    }
    
    
    
    //    if ([encodedAudioDevice isEqualToString:@"No Value"]) {
    //        [self setSelectedVideoDevice:nil];
    //    }
    //    else {
    //        for (AVCaptureDevice* dev in videoDevices) {
    //            if ([dev.localizedName isEqualToString:encodedVideoDevice]) {
    //                [self setSelectedVideoDevice:dev];
    //                break;
    //            }
    //        }
    //    }
    //    if ([encodedVideoFormat isEqualToString:@"No Value"]) {
    //        [self setVideoDeviceFormat:nil];
    //    }
    //    else {
    //        for (AVCaptureDeviceFormat *frmt in self.selectedVideoDevice.formats) {
    //            if ([frmt.localizedName isEqualToString:encodedVideoFormat]) {
    //                [self setVideoDeviceFormat:frmt];
    //                break;
    //            }
    //        }
    //    }
    //    if ([encodedVideoFrmRte isEqualToString:@"No Value"]) {
    //        [self setFrameRateRange:nil];
    //    }
    //    else {
    //        for (AVFrameRateRange *frmt in self.selectedVideoDevice.activeFormat.videoSupportedFrameRateRanges) {
    //            if ([frmt.localizedName isEqualToString:encodedVideoFrmRte]) {
    //                NSLog(@"setFrameRateRange - %@", encodedVideoFrmRte);
    //                [self setFrameRateRange:frmt];
    //                break;
    //            }
    //        }
    //    }
    //    if ([encodedAudioDevice isEqualToString:@"No Value"]) {
    //        [self setSelectedAudioDevice:nil];
    //    }
    //    else {
    //        for (AVCaptureDevice* dev in audioDevices) {
    //            if ([dev.localizedName isEqualToString:encodedAudioDevice]) {
    //                [self setSelectedAudioDevice:dev];
    //                break;
    //            }
    //        }
    //    }
    //    if ([encodedAudioFormat isEqualToString:@"No Value"]) {
    //        [self setAudioDeviceFormat:nil];
    //    }
    //    else {
    //        for (AVCaptureDeviceFormat *frmt in self.selectedAudioDevice.formats) {
    //            if ([frmt.localizedName isEqualToString:encodedAudioFormat]) {
    //                [self setAudioDeviceFormat:frmt];
    //                break;
    //            }
    //        }
    //    }
//    if ([isBoostEnabled boolValue]) {
//        [self.boostEnabled setState:NSControlStateValueOff];
//        [self.boostEnabled performClick:self];
//    }
//    else {
//        [self.boostEnabled setState:NSControlStateValueOn];
//        [self.boostEnabled performClick:self];
//    }
}

#pragma mark - Delegate methods

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
//    NSLog(@"Did start recording to %@", [fileURL description]);
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didPauseRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
//    NSLog(@"Did pause recording to %@", [fileURL description]);
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didResumeRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
//    NSLog(@"Did resume recording to %@", [fileURL description]);
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput willFinishRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections dueToError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [self PresentErrorInLog:error];
    });
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)recordError
{
    if (recordError != nil && [[[recordError userInfo] objectForKey:AVErrorRecordingSuccessfullyFinishedKey] boolValue] == NO) {
        [[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            [self PresentErrorInLog:recordError];
        });
    } else {
        NSSavePanel *savePanel = [NSSavePanel savePanel];
        [savePanel setAccessoryView:saveDialogCustomView];
        [savePanel setAllowedFileTypes:[NSArray arrayWithObjects:AVFileTypeQuickTimeMovie, AVFileTypeMPEG4, nil]];
        [savePanel setCanSelectHiddenExtension:YES];
        [savePanel beginSheetModalForWindow:[self windowForSheet] completionHandler:^(NSInteger result) {
            if (result == NSModalResponseOK ) {
                
                if (_exportMP4) {
                    [[NSFileManager defaultManager] removeItemAtURL:[savePanel URL] error:nil];
                    AVAsset *asset = [AVAsset assetWithURL:outputFileURL];
                    NSString *tracksKey = @"tracks";
                    [asset loadValuesAsynchronouslyForKeys:@[tracksKey] completionHandler:
                     ^{
                         dispatch_async(dispatch_get_main_queue(), ^(void) {
                             NSError *error;
                             AVKeyValueStatus status = [asset statusOfValueForKey:tracksKey error:&error];
                             if (status == AVKeyValueStatusLoaded) {
                                 NSString *quality = AVAssetExportPresetHEVCHighestQuality;
                                 if ([self.makeSmaller state] == NSOnState) {
                                     quality = AVAssetExportPreset640x480;
                                 }
                                 [self resetSaveDialog];
                                 
                                 exporter = [[AVAssetExportSession alloc] initWithAsset:asset presetName:quality];
                                 exporter.videoComposition = [AVVideoComposition videoCompositionWithPropertiesOfAsset:asset];
                                 exporter.outputFileType = AVFileTypeMPEG4;
                                 exporter.shouldOptimizeForNetworkUse = NO;
                                 exporter.outputURL = [savePanel URL];
                                 [[self audioLevelTimer] invalidate];
                                 [self.exportLbl setHidden:NO];
                                 [exporter exportAsynchronouslyWithCompletionHandler:^{
                                     [[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
                                 }];
                                 self.exportProgressTimer = [NSTimer scheduledTimerWithTimeInterval:.1 target:self selector:@selector(exportProgress:) userInfo:nil repeats:YES];
                             }
                         });
                     }];
                }
                else {
                    NSError *error = nil;
                    [[NSFileManager defaultManager] removeItemAtURL:[savePanel URL] error:nil];
                    if ([[NSFileManager defaultManager] moveItemAtURL:outputFileURL toURL:[savePanel URL] error:&error]) {
                    } else {
                        [savePanel orderOut:self];
                        [self presentError:error modalForWindow:[self windowForSheet] delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
                    }
                }
            } else {
                [[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
                [self resetSaveDialog];
            }
        }];
    }
}

-(void)resetSaveDialog {
    self.makeSmaller.state = NSOffState;
    [self.rad_MOV setState:NSControlStateValueOn];
}

-(void) exportProgress:(NSTimer *)timer {
    [self.exportLbl setStringValue:[NSString stringWithFormat:@"Exporting... %i%%", (int)(exporter.progress*100)]];
    if (exporter.progress == 1 || (exporter.status != AVAssetExportSessionStatusExporting && exporter.status != AVAssetExportSessionStatusWaiting)) {
        [self.exportProgressTimer invalidate];
        [self.exportLbl setStringValue:[NSString stringWithFormat:@"Exporting...%f", exporter.progress]];
        [self.exportLbl setHidden:YES];
    }
}

- (BOOL)captureOutputShouldProvideSampleAccurateRecordingStart:(AVCaptureOutput *)captureOutput
{
    return NO;
}

- (IBAction)videoTypeChange:(id)sender {
    NSSavePanel *savePanel = (NSSavePanel*)((NSButton*)sender).superview.window;
    NSString *fileName = [[savePanel nameFieldStringValue] stringByDeletingPathExtension];
    switch ((int)[(NSButton*)sender tag]) {
        case 0:{
            _exportMP4 = NO;
            self.makeSmaller.state = NSOffState;
            self.makeSmaller.enabled = NO;
            NSString *nameFieldStringWithExt = [NSString stringWithFormat:@"%@.%@",fileName, @"mov"];
            [savePanel setNameFieldStringValue:nameFieldStringWithExt];
        }
            break;
        case 1:{
            _exportMP4 = YES;
            self.makeSmaller.enabled = YES;
            NSString *nameFieldStringWithExt = [NSString stringWithFormat:@"%@.%@",fileName, @"mp4"];
            [savePanel setNameFieldStringValue:nameFieldStringWithExt];
        }
            break;
        default:
            _exportMP4 = NO;
            break;
    }
}

- (IBAction)recordOnOff:(id)sender {
    if ([(NSButton*)sender state] == NSOnState) {
        [(NSButton*)sender setTitle:@"Recording..."];
    }
    else {
        [(NSButton*)sender setTitle:@"Record"];
    }
}





@end
