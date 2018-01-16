#import "BMViewerDocument.h"
#import <AVFoundation/AVFoundation.h>
#import "MyWindow.h"
#import "AVCaptureDeviceFormat_BMViewerAdditions.h"
#import "AVFrameRateRange_BMViewerAdditions.h"
#import <IOKit/pwr_mgt/IOPMLib.h>

@interface BMViewerDocument () <AVCaptureFileOutputDelegate, AVCaptureFileOutputRecordingDelegate, NSMenuDelegate>

@property (strong) AVCaptureDeviceInput *videoDeviceInput;
@property (strong) AVCaptureDeviceInput *audioDeviceInput;
@property (readonly) BOOL selectedVideoDeviceProvidesAudio;
@property (strong) AVCaptureAudioPreviewOutput *audioPreviewOutput;
@property (strong) AVCaptureMovieFileOutput *movieFileOutput;
@property (strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (weak) NSTimer *audioLevelTimer;
@property (strong) NSArray *observers;

@property (weak) IBOutlet NSPopUpButton *videoDeviceList;
@property (weak) IBOutlet NSPopUpButton *videoFormatList;
@property (weak) IBOutlet NSPopUpButton *videoFrmRteList;
@property (weak) IBOutlet NSPopUpButton *audioDeviceList;
@property (weak) IBOutlet NSPopUpButton *audioFormatList;

- (void)refreshDevices;
- (void)setTransportMode:(AVCaptureDeviceTransportControlsPlaybackMode)playbackMode speed:(AVCaptureDeviceTransportControlsSpeed)speed forDevice:(AVCaptureDevice *)device;

@end

@implementation BMViewerDocument {
    BOOL foundVideo;
    BOOL foundVFormat;
    BOOL foundVFR;
    BOOL foundAudio;
    BOOL foundAFormat;
    BOOL _firstLoad;
}

@synthesize videoDeviceInput;
@synthesize audioDeviceInput;
@synthesize videoDevices;
@synthesize audioDevices;
@synthesize session;
@synthesize audioLevelMeter;
@synthesize audioPreviewOutput;
@synthesize movieFileOutput;
@synthesize previewView;
@synthesize previewLayer;
@synthesize audioLevelTimer;
@synthesize observers;
@synthesize frameForNonFullScreenMode;
@synthesize viewForNonFullScreenMode;
@synthesize videoDeviceList;
@synthesize videoFormatList;
@synthesize videoFrmRteList;
@synthesize audioDeviceList;
@synthesize audioFormatList;

@synthesize defVideoDevice;
@synthesize defVideoFormat;
@synthesize defVideoFrmRte;
@synthesize defAudioDevice;
@synthesize defAudioFormat;

static BOOL cursorIsHidden = NO;

- (id)init
{
    self = [super init];
    if (self) {
        
        CFStringRef reasonForActivity= CFSTR("BMViewer is viewing");
        IOPMAssertionID assertionID;
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionLevelOn, reasonForActivity, &assertionID);
        
        _firstLoad = YES;
        self.defVideoDevice = [[NSUserDefaults standardUserDefaults] stringForKey:@"VideoDevice"];
        self.defVideoFormat = [[NSUserDefaults standardUserDefaults] stringForKey:@"VideoFormat"];
        self.defVideoFrmRte = [[NSUserDefaults standardUserDefaults] stringForKey:@"VideoFrmRte"];
        self.defAudioDevice = [[NSUserDefaults standardUserDefaults] stringForKey:@"AudioDevice"];
        self.defAudioFormat = [[NSUserDefaults standardUserDefaults] stringForKey:@"AudioFormat"];
        
        [[self.videoDeviceList menu] setDelegate:self];
        [[self.videoFormatList menu] setDelegate:self];
        [[self.videoFrmRteList menu] setDelegate:self];
        [[self.audioDeviceList menu] setDelegate:self];
        [[self.audioFormatList menu] setDelegate:self];
        
        // Create a capture session
        session = [[AVCaptureSession alloc] init];
        
        // Capture Notification Observers
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
                                                                     [self hideCursor];
                                                                 }];
        
        id exitFullScreenNotificationObserver = [notificationCenter addObserverForName:NSWindowDidExitFullScreenNotification
                                                                                object:nil
                                                                                 queue:[NSOperationQueue mainQueue]
                                                                            usingBlock:^(NSNotification *note) {
                                                                                [self performSelector:@selector(showCursor) withObject:nil afterDelay:0.25];
                                                                            }];
        
        id menuDidChangeObserver = [notificationCenter addObserverForName:NSMenuDidChangeItemNotification
                                                                   object:nil
                                                                    queue:[NSOperationQueue mainQueue]
                                                               usingBlock:^(NSNotification *note) {
                                                                   if (_firstLoad) {
                                                                       if (foundVideo == NO &&
                                                                           [(NSMenu*)note.object isEqual:self.videoDeviceList.menu] &&
                                                                           [self.videoDeviceList.selectedItem.title isEqualToString:self.defVideoDevice] == NO) {
                                                                           [self.videoDeviceList selectItemWithTitle:self.defVideoDevice];
                                                                           for (AVCaptureDevice* dev in videoDevices) {
                                                                               if ([dev.localizedName isEqualToString:self.defVideoDevice]) {
                                                                                   [self setSelectedVideoDevice:dev];
                                                                                   foundVideo = YES;
                                                                                   break;
                                                                               }
                                                                           }
                                                                       }
                                                                       else if (foundVFormat == NO &&
                                                                                [(NSMenu*)note.object isEqual:self.videoFormatList.menu] &&
                                                                                [self.selectedVideoDevice.localizedName isEqualToString:self.defVideoDevice] &&
                                                                                ((int)self.videoFormatList.itemArray.count == (int)self.selectedVideoDevice.formats.count) &&
                                                                                [self.selectedVideoDevice.activeFormat.localizedName isEqualToString:self.defVideoFormat] == NO) {
                                                                           foundVFormat = YES;
                                                                           for (AVCaptureDeviceFormat *frmt in self.selectedVideoDevice.formats) {
                                                                               if ([frmt.localizedName isEqualToString:self.defVideoFormat]) {
                                                                                   [self performSelector:@selector(setVideoDeviceFormat:) withObject:frmt afterDelay:0.5];
                                                                                   break;
                                                                               }
                                                                           }
                                                                       }
                                                                       if (foundAudio == NO &&
                                                                           [(NSMenu*)note.object isEqual:self.audioDeviceList.menu] &&
                                                                           [self.audioDeviceList.selectedItem.title isEqualToString:self.defAudioDevice] == NO) {
                                                                           [self.audioDeviceList selectItemWithTitle:self.defAudioDevice];
                                                                           for (AVCaptureDevice* dev in audioDevices) {
                                                                               if ([dev.localizedName isEqualToString:self.defAudioDevice]) {
                                                                                   [self setSelectedAudioDevice:dev];
                                                                                   foundAudio = YES;
                                                                                   break;
                                                                               }
                                                                           }
                                                                       }
                                                                   }
                                                               }];
        
        id menuDidAddItemObserver = [notificationCenter addObserverForName:NSMenuDidAddItemNotification
                                                                                object:nil
                                                                                 queue:[NSOperationQueue mainQueue]
                                                                            usingBlock:^(NSNotification *note) {
                                                                                if (_firstLoad) {
                                                                                    if (foundVFormat == NO &&
                                                                                             [(NSMenu*)note.object isEqual:self.videoFormatList.menu] &&
                                                                                             [self.selectedVideoDevice.localizedName isEqualToString:self.defVideoDevice] &&
                                                                                             ((int)self.videoFormatList.itemArray.count == (int)self.selectedVideoDevice.formats.count) &&
                                                                                             [self.selectedVideoDevice.activeFormat.localizedName isEqualToString:self.defVideoFormat] == NO) {
                                                                                        foundVFormat = YES;
                                                                                        for (AVCaptureDeviceFormat *frmt in self.selectedVideoDevice.formats) {
                                                                                            if ([frmt.localizedName isEqualToString:self.defVideoFormat]) {
                                                                                                [self performSelector:@selector(setVideoDeviceFormat:) withObject:frmt afterDelay:0.5];
                                                                                                if (foundVFR) {
                                                                                                    _firstLoad = NO;
                                                                                                }
                                                                                                break;
                                                                                            }
                                                                                        }
                                                                                    }
                                                                                    else if (foundVFormat && foundVFR == NO &&
                                                                                        [(NSMenu*)note.object isEqual:self.videoFrmRteList.menu] &&
                                                                                        [self.selectedVideoDevice.localizedName isEqualToString:self.defVideoDevice] &&
                                                                                        ((int)self.videoFrmRteList.menu.itemArray.count == (int)self.selectedVideoDevice.activeFormat.videoSupportedFrameRateRanges.count) &&
                                                                                        [self.selectedVideoDevice.activeFormat.localizedName isEqualToString:self.defVideoFormat] &&
                                                                                        [self.defVideoFrmRte isEqualToString:self.videoFrmRteList.selectedItem.title] == NO) {
                                                                                        foundVFR = YES;
                                                                                        for (AVFrameRateRange *frmt in self.selectedVideoDevice.activeFormat.videoSupportedFrameRateRanges) {
                                                                                            if ([frmt.localizedName isEqualToString:self.defVideoFrmRte]) {
                                                                                                [self performSelector:@selector(setFrameRateRange:) withObject:frmt afterDelay:0.5];
                                                                                                if (foundVFormat) {
                                                                                                    _firstLoad = NO;
                                                                                                }
                                                                                                break;
                                                                                            }
                                                                                        }
                                                                                    }
                                                                                }
                                                                            }];
        
        
        
        observers = [[NSArray alloc] initWithObjects:runtimeErrorObserver, didStartRunningObserver, didStopRunningObserver, deviceWasConnectedObserver, deviceWasDisconnectedObserver, enterFullScreenObserver, exitFullScreenNotificationObserver, menuDidAddItemObserver, menuDidChangeObserver, nil];
        movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
        [movieFileOutput setDelegate:self];
        [session addOutput:movieFileOutput];
        audioPreviewOutput = [[AVCaptureAudioPreviewOutput alloc] init];
        [audioPreviewOutput setVolume:1.f];
        [session addOutput:audioPreviewOutput];
        [self refreshDevices];
    }
    return self;
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

-(void) saveDeviceOptions {
    NSString *selVideoDevice = self.videoDeviceList.selectedItem.title;
    NSString *selVideoFormat  = self.videoFormatList.selectedItem.title;
    NSString *selVideoFrmRte  = self.videoFrmRteList.selectedItem.title;
    NSString *selAudioDevice  = self.audioDeviceList.selectedItem.title;
    NSString *selAudioFormat  = self.audioFormatList.selectedItem.title;
    [[NSUserDefaults standardUserDefaults] setObject:selVideoDevice forKey:@"VideoDevice"];
    [[NSUserDefaults standardUserDefaults] setObject:selVideoFormat forKey:@"VideoFormat"];
    [[NSUserDefaults standardUserDefaults] setObject:selVideoFrmRte forKey:@"VideoFrmRte"];
    [[NSUserDefaults standardUserDefaults] setObject:selAudioDevice forKey:@"AudioDevice"];
    [[NSUserDefaults standardUserDefaults] setObject:selAudioFormat forKey:@"AudioFormat"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSSize)window:(NSWindow *)window willUseFullScreenContentSize:(NSSize)proposedSize
{
    return proposedSize;
}

- (NSApplicationPresentationOptions)window:(NSWindow *)window willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)proposedOptions
{
    return (NSApplicationPresentationFullScreen |
            NSApplicationPresentationHideDock |
            NSApplicationPresentationAutoHideMenuBar);
}

#pragma mark -
#pragma mark Enter Full Screen
- (NSArray *)customWindowsToEnterFullScreenForWindow:(NSWindow *)window
{
    return [NSArray arrayWithObject:window];
}

- (void)window:(NSWindow *)window startCustomAnimationToEnterFullScreenWithDuration:(NSTimeInterval)duration
{
    self.frameForNonFullScreenMode = [window frame];
    self.viewForNonFullScreenMode = previewView.frame;
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

#pragma mark -
#pragma mark Full Screen Support: Persisting and Restoring Window's Non-FullScreen Frame

+ (NSArray *)restorableStateKeyPaths
{
    return [[super restorableStateKeyPaths] arrayByAddingObject:@"frameForNonFullScreenMode"];
}

// -------------------------------------------------------------------------------
//    didEnterFull:notif
// -------------------------------------------------------------------------------
- (void)didExitFull:(NSNotification *)notif
{
    // our window "exited" full screen mode
}

// -------------------------------------------------------------------------------
//    willEnterFull:notif
// -------------------------------------------------------------------------------
- (void)willEnterFull:(NSNotification *)notif
{
    // our window "entered" full screen mode
}

- (void)windowWillClose:(NSNotification *)notification
{
    [NSCursor unhide];
    cursorIsHidden = NO;
    _firstLoad = YES;
    
    [self saveDeviceOptions];
    
    // Invalidate the level meter timer here to avoid a retain cycle
    [[self audioLevelTimer] invalidate];
    
    // Stop the session
    [[self session] stopRunning];
    
    // Set movie file output delegate to nil to avoid a dangling pointer
    [[self movieFileOutput] setDelegate:nil];
    
    // Remove Observers
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    for (id observer in [self observers])
        [notificationCenter removeObserver:observer];
}


- (NSString *)windowNibName
{
    return @"BMViewerDocument";
}

- (void)windowControllerDidLoadNib:(NSWindowController *) aController
{
    [super windowControllerDidLoadNib:aController];
    if (([self.defVideoDevice isEqualToString:@"No Value"] || [self.defAudioDevice isEqualToString:@"No Value"])||(self.defVideoDevice == nil || self.defAudioDevice == nil)) {
        _firstLoad = NO;
    }
    else {
        _firstLoad = YES;
    }
    
    // Attach preview to session
    CALayer *previewViewLayer = [[self previewView] layer];
    [previewViewLayer setBackgroundColor:CGColorGetConstantColor(kCGColorBlack)];
    AVCaptureVideoPreviewLayer *newPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:[self session]];
    [newPreviewLayer setFrame:[previewViewLayer bounds]];
    [newPreviewLayer setAutoresizingMask:kCALayerWidthSizable | kCALayerHeightSizable];
    [previewViewLayer addSublayer:newPreviewLayer];
    [self setPreviewLayer:newPreviewLayer];
    [[self session] startRunning];
    [self setAudioLevelTimer:[NSTimer scheduledTimerWithTimeInterval:0.1f target:self selector:@selector(updateAudioLevels:) userInfo:nil repeats:YES]];
}

- (void)didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void  *)contextInfo
{
    // Do nothing
}


- (void)PresentErrorInLog:(NSError *)error
{
    NSLog(@"%@",[error localizedDescription]);
}
- (void)PresentErrorInLog:(NSString*) lbl error:(NSError *)error
{
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
//    [self logConfig];
    [[self session] commitConfiguration];
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
//    [self logConfig];
    [[self session] commitConfiguration];
}

- (void)setSelectedVideoDevice:(AVCaptureDevice *)selectedVideoDevice withFormat:(AVCaptureDeviceFormat *)deviceFormat andFrameRate:(AVFrameRateRange *)frameRateRange
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
            if ([newVideoDeviceInput.device lockForConfiguration:&error]) {
                [newVideoDeviceInput.device setActiveFormat:deviceFormat];
                [newVideoDeviceInput.device unlockForConfiguration];
            } else {
                dispatch_async(dispatch_get_main_queue(), ^(void) {
                    [self PresentErrorInLog:error];
                });
            }
            if ([newVideoDeviceInput.device lockForConfiguration:&error]) {
                [newVideoDeviceInput.device setActiveVideoMinFrameDuration:[frameRateRange minFrameDuration]];
                [newVideoDeviceInput.device unlockForConfiguration];
            } else {
                dispatch_async(dispatch_get_main_queue(), ^(void) {
                    [self PresentErrorInLog:error];
                });
            }
            [[self session] addInput:newVideoDeviceInput];
            [self setVideoDeviceInput:newVideoDeviceInput];
        }
    }
    
//    if ([self selectedVideoDeviceProvidesAudio])
//        [self setSelectedAudioDevice:nil];
//    [self logConfig];
    [[self session] commitConfiguration];
}

- (AVCaptureDevice *)selectedAudioDevice
{
    return [audioDeviceInput device];
}

- (void)setSelectedAudioDevice:(AVCaptureDevice *)selectedAudioDevice
{
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
        }
    }
    [self logConfig];
    [[self session] commitConfiguration]; // changes video format here ?????!!!!!!??????
    [self logConfig];
}

-(void) logConfig {
    NSString *logTxt = @"\n-----------------------------------------------";
    for (AVCaptureDeviceInput* devp in session.inputs) {
        AVCaptureDevice * dev = devp.device;
        NSString *devName = dev.localizedName;
        NSString *activeFormat = dev.activeFormat.localizedName;
        NSString *frmRte = [NSString stringWithFormat:@"FPS: %0.2f", CMTimeGetSeconds(dev.activeVideoMinFrameDuration)];
        logTxt = [NSString stringWithFormat:@"%@\n%@ - %@ - %@", logTxt, devName, activeFormat, frmRte];
    }
    logTxt = [NSString stringWithFormat:@"%@\n-----------------------------------------------", logTxt];
    NSLog(@"%@", logTxt);
}

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
    NSError *error = nil;
    AVCaptureDevice *videoDevice = [self selectedVideoDevice];
    if ([videoDevice lockForConfiguration:&error]) {
        [videoDevice setActiveFormat:deviceFormat];
        [videoDevice unlockForConfiguration];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            [self PresentErrorInLog:error];
        });
    }
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
}

- (IBAction)lockVideoDeviceForConfiguration:(id)sender
{
    if ([(NSButton *)sender state] == NSOnState)
    {
        [[self selectedVideoDevice] lockForConfiguration:nil];
    }
    else
    {
        [[self selectedVideoDevice] unlockForConfiguration];
    }
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
        NSURL *template = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"BMViewer_XXXXXX"];
        char buffer[PATH_MAX] = {0};
        [template getFileSystemRepresentation:buffer maxLength:sizeof(buffer)];
        int fd = mkstemp(buffer);
        if (fd != -1) {
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
    }
}

#pragma mark - Audio Preview
- (void)updateAudioLevels:(NSTimer *)timer
{
    NSInteger channelCount = 0;
    float decibels = 0.f;
    for (AVCaptureConnection *connection in [[self movieFileOutput] connections]) {
        for (AVCaptureAudioChannel *audioChannel in [connection audioChannels]) {
            decibels += [audioChannel averagePowerLevel];
            channelCount += 1;
        }
    }
    decibels /= channelCount;
    [[self audioLevelMeter] setFloatValue:(pow(10.f, 0.05f * decibels) * 100.0f)];
}

#pragma mark - Transport Controls

- (IBAction)stop:(id)sender
{
    [self setTransportMode:AVCaptureDeviceTransportControlsNotPlayingMode speed:0.f forDevice:[self selectedVideoDevice]];
}

+ (NSSet *)keyPathsForValuesAffectingPlaying
{
    return [NSSet setWithObjects:@"selectedVideoDevice.transportControlsPlaybackMode", @"selectedVideoDevice.transportControlsSpeed",nil];
}

- (BOOL)isPlaying
{
    AVCaptureDevice *device = [self selectedVideoDevice];
    return ([device transportControlsSupported] &&
            [device transportControlsPlaybackMode] == AVCaptureDeviceTransportControlsPlayingMode &&
            [device transportControlsSpeed] == 1.f);
}

- (void)setPlaying:(BOOL)play
{
    AVCaptureDevice *device = [self selectedVideoDevice];
    [self setTransportMode:AVCaptureDeviceTransportControlsPlayingMode speed:play ? 1.f : 0.f forDevice:device];
}

+ (NSSet *)keyPathsForValuesAffectingRewinding
{
    return [NSSet setWithObjects:@"selectedVideoDevice.transportControlsPlaybackMode", @"selectedVideoDevice.transportControlsSpeed",nil];
}

- (BOOL)isRewinding
{
    AVCaptureDevice *device = [self selectedVideoDevice];
    return [device transportControlsSupported] && ([device transportControlsSpeed] < -1.f);
}

- (void)setRewinding:(BOOL)rewind
{
    AVCaptureDevice *device = [self selectedVideoDevice];
    [self setTransportMode:[device transportControlsPlaybackMode] speed:rewind ? -2.f : 0.f forDevice:device];
}

+ (NSSet *)keyPathsForValuesAffectingFastForwarding
{
    return [NSSet setWithObjects:@"selectedVideoDevice.transportControlsPlaybackMode", @"selectedVideoDevice.transportControlsSpeed",nil];
}

- (BOOL)isFastForwarding
{
    AVCaptureDevice *device = [self selectedVideoDevice];
    return [device transportControlsSupported] && ([device transportControlsSpeed] > 1.f);
}

- (void)setFastForwarding:(BOOL)fastforward
{
    AVCaptureDevice *device = [self selectedVideoDevice];
    [self setTransportMode:[device transportControlsPlaybackMode] speed:fastforward ? 2.f : 0.f forDevice:device];
}

- (void)setTransportMode:(AVCaptureDeviceTransportControlsPlaybackMode)playbackMode speed:(AVCaptureDeviceTransportControlsSpeed)speed forDevice:(AVCaptureDevice *)device
{
    NSError *error = nil;
    if ([device transportControlsSupported]) {
        if ([device lockForConfiguration:&error]) {
            [device setTransportControlsPlaybackMode:playbackMode speed:speed];
            [device unlockForConfiguration];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                [self PresentErrorInLog:error];
            });
        }
    }
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
        // Move the recorded temporary file to a user-specified location
        NSSavePanel *savePanel = [NSSavePanel savePanel];
        [savePanel setAllowedFileTypes:[NSArray arrayWithObject:AVFileTypeQuickTimeMovie]];
        [savePanel setCanSelectHiddenExtension:YES];
        [savePanel beginSheetModalForWindow:[self windowForSheet] completionHandler:^(NSInteger result) {
            NSError *error = nil;
            if (result == NSModalResponseOK ) { // NSOKButton
                [[NSFileManager defaultManager] removeItemAtURL:[savePanel URL] error:nil]; // attempt to remove file at the desired save location before moving the recorded file to that location
                if ([[NSFileManager defaultManager] moveItemAtURL:outputFileURL toURL:[savePanel URL] error:&error]) {
                    [[NSWorkspace sharedWorkspace] openURL:[savePanel URL]];
                } else {
                    [savePanel orderOut:self];
                    [self presentError:error modalForWindow:[self windowForSheet] delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
                }
            } else {
                // remove the temporary recording file if it's not being saved
                [[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
            }
        }];
    }
}

- (BOOL)captureOutputShouldProvideSampleAccurateRecordingStart:(AVCaptureOutput *)captureOutput
{
    // We don't require frame accurate start when we start a recording. If we answer YES, the capture output
    // applies outputSettings immediately when the session starts previewing, resulting in higher CPU usage
    // and shorter battery life.
    return NO;
}


@end
