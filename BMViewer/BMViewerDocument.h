#import <Cocoa/Cocoa.h>
#import <AudioUnit/AudioUnit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
//#import <AVFoundation/AVAudioses>
@class AVCaptureVideoPreviewLayer;
@class AVCaptureSession;
@class AVCaptureDeviceInput;
@class AVCaptureMovieFileOutput;
@class AVCaptureAudioPreviewOutput;
@class AVCaptureConnection;
@class AVCaptureDevice;
@class AVCaptureDeviceFormat;
@class AVFrameRateRange;

@interface BMViewerDocument : NSDocument 
{
@private
    IBOutlet NSView             *saveDialogCustomView;
    NSView                      *__weak previewView;
    AVCaptureVideoPreviewLayer  *previewLayer;
    
    AVCaptureSession            *session;
    AVCaptureDeviceInput        *videoDeviceInput;
    AVCaptureDeviceInput        *audioDeviceInput;
    AVCaptureMovieFileOutput    *movieFileOutput;
    AVCaptureAudioPreviewOutput *audioPreviewOutput;
    AVCaptureConnection         *movieFileOutputConnection;
    
    NSArray                     *videoDevices;
    NSArray                     *audioDevices;
    
    NSTimer                     *__weak audioLevelTimer;
    
    NSArray                     *observers;
}

//@property (strong) NSString *defVideoDevice;
//@property (strong) NSString *defVideoFormat;
//@property (strong) NSString *defVideoFrmRte;
//@property (strong) NSString *defAudioDevice;
//@property (strong) NSString *defAudioFormat;
//@property (nonatomic) NSInteger defBoost;

@property (assign) NSRect frameForNonFullScreenMode;
@property (assign) NSRect viewForNonFullScreenMode;

#pragma mark Device Selection
@property (strong) NSArray *videoDevices;
@property (strong) NSArray *audioDevices;
@property (weak) AVCaptureDevice *selectedVideoDevice;
@property (weak) AVCaptureDevice *selectedAudioDevice;

#pragma mark - Device Properties
@property (weak) AVCaptureDeviceFormat *videoDeviceFormat;
@property (weak) AVCaptureDeviceFormat *audioDeviceFormat;
@property (weak) AVFrameRateRange *frameRateRange;

#pragma mark - Recording
@property (strong) AVCaptureSession *session;
@property (readonly) BOOL hasRecordingDevice;
@property (assign,getter=isRecording) BOOL recording;

#pragma mark - Preview
@property (weak) IBOutlet NSView *previewView;
@property (assign) float previewVolume;

- (IBAction)savePreset:(id)sender;
- (IBAction)loadPreset:(id)sender;
- (IBAction)videoTypeChange:(id)sender;
@property (weak) IBOutlet NSButton *makeSmaller;
@property (weak) IBOutlet NSButton *rad_MOV;
@property (weak) IBOutlet NSTextField *exportLbl;

- (IBAction)recordOnOff:(id)sender;
- (IBAction)enableBoost:(id)sender;

@end
