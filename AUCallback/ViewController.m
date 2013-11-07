//
//  ViewController.m
//  AUCallback
//
//  Edited by Chinh Nguyen on 11/05/13.
//  Copyright (c) 2013 Chinh Nguyen. All rights reserved.
//

#import "ViewController.h"

@interface ViewController (){
    EffectState effectState;
}
@property (nonatomic) double sampleRate;
@property (nonatomic) AudioUnit remoteIOUnit;
@property (nonatomic) AudioStreamBasicDescription *myASBD;
@property (weak, nonatomic) IBOutlet UISwitch *passingThroughSwitch;
@property (strong, nonatomic) AVAudioPlayer* player;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    [self setUpAudioSession];
    [self setUpAUConnections];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
// Dispose of any resources that can be recreated.
}

- (AudioStreamBasicDescription *)myASBD{
    if(!_myASBD){
        _myASBD = calloc(1, sizeof(AudioStreamBasicDescription));
        _myASBD->mSampleRate			= self.sampleRate;
        _myASBD->mFormatID			= kAudioFormatLinearPCM;
        _myASBD->mFormatFlags         = kAudioFormatFlagsCanonical;
        _myASBD->mChannelsPerFrame	= 1; //mono
        _myASBD->mBitsPerChannel		= 8*sizeof(AudioSampleType);
        _myASBD->mFramesPerPacket     = 1; //uncompressed
        _myASBD->mBytesPerFrame       = _myASBD->mChannelsPerFrame*_myASBD->mBitsPerChannel/8;
        _myASBD->mBytesPerPacket		= _myASBD->mBytesPerFrame*_myASBD->mFramesPerPacket;
    }
    return _myASBD;
}
- (void) setUpAudioSession {
	NSLog(@"setUpAudioSession");
    
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;
    
    BOOL success = [session setActive: YES error: &error];
    NSAssert (success, @"Couldn't initialize audio session");
    
	success = [session setCategory: AVAudioSessionCategoryPlayAndRecord
                             error: &error];
	NSAssert (success, @"Couldn't set audio session category");
	
	// check if input available?
	NSAssert (session.inputAvailable, @"Couldn't get current audio input available prop");
	if (! session.inputAvailable) {
		UIAlertView *noInputAlert =
		[[UIAlertView alloc] initWithTitle:@"No audio input"
								   message:@"No audio input device is currently attached"
								  delegate:nil
						 cancelButtonTitle:@"OK"
						 otherButtonTitles:nil];
		[noInputAlert show];
	}
    
    self.sampleRate = session.sampleRate;
}

OSStatus PlaybackCallback (
                           void *							inRefCon,
                           AudioUnitRenderActionFlags *	ioActionFlags,
                           const AudioTimeStamp *			inTimeStamp,
                           UInt32							inBusNumber,
                           UInt32							inNumberFrames,
                           AudioBufferList *				ioData) {
	
	EffectState *effectState = (EffectState*) inRefCon;
	AudioUnit rioUnit = effectState->rioUnit;
	OSStatus renderErr = noErr;
	UInt32 bus1 = 1;
	// just copy samples
	renderErr = AudioUnitRender(rioUnit,
								ioActionFlags,
								inTimeStamp,
								bus1,
								inNumberFrames,
								ioData);
	
	return noErr;
}


OSStatus RecordingCallback (
                            void *							inRefCon,
                            AudioUnitRenderActionFlags *	ioActionFlags,
                            const AudioTimeStamp *			inTimeStamp,
                            UInt32							inBusNumber,
                            UInt32							inNumberFrames,
                            AudioBufferList *				ioData) {
	
	EffectState *effectState = (EffectState*) inRefCon;
	AudioUnit rioUnit = effectState->rioUnit;
    ExtAudioFileRef outputAudioFile = effectState->outputAudioFile;
	OSStatus err = noErr;
    
    AudioBuffer buffer;
	buffer.mNumberChannels = 1;
	buffer.mDataByteSize = inNumberFrames * sizeof(SInt16);
	buffer.mData = malloc(inNumberFrames * sizeof(SInt16));
    
	// Put buffer in a AudioBufferList
	AudioBufferList bufferList;
	bufferList.mNumberBuffers = 1;
	bufferList.mBuffers[0] = buffer;
    
    
	err = AudioUnitRender(rioUnit,
								ioActionFlags,
								inTimeStamp,
								1,
								inNumberFrames,
								&bufferList);
    
    
	// Render into audio buffer
	if( err )
		fprintf( stderr, "AudioUnitRender() failed with error %i\n", (int)err );

	// Write to file, ExtAudioFile auto-magicly handles conversion/encoding
	// NOTE: Async writes may not be flushed to disk until a the file
	// reference is disposed using ExtAudioFileDispose
    
	err = ExtAudioFileWriteAsync( outputAudioFile, inNumberFrames, &bufferList);
	if( err != noErr )
	{
		char	formatID[5] = { 0 };
		*(UInt32 *)formatID = CFSwapInt32HostToBig(err);
		formatID[4] = '\0';
		fprintf(stderr, "ExtAudioFileWrite FAILED! %d '%-4.4s'\n",(int)err, formatID);
		return err;
	}
	
	return noErr;
}


- (void) setUpAUConnections {
    
	OSStatus setupErr = noErr;
	
	// describe unit
	AudioComponentDescription audioCompDesc;
	audioCompDesc.componentType = kAudioUnitType_Output;
	audioCompDesc.componentSubType = kAudioUnitSubType_RemoteIO;
	audioCompDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
	audioCompDesc.componentFlags = 0;
	audioCompDesc.componentFlagsMask = 0;
	
	// get rio unit from audio component manager
	AudioComponent rioComponent = AudioComponentFindNext(NULL, &audioCompDesc);
	setupErr = AudioComponentInstanceNew(rioComponent, &_remoteIOUnit);
	NSAssert (setupErr == noErr, @"Couldn't get RIO unit instance");
	
	// set up the rio unit for playback
	UInt32 oneFlag = 1;
	AudioUnitElement bus0 = 0;
	setupErr =
	AudioUnitSetProperty (self.remoteIOUnit,
						  kAudioOutputUnitProperty_EnableIO,
						  kAudioUnitScope_Output,
						  bus0,
						  &oneFlag,
						  sizeof(oneFlag));
	NSAssert (setupErr == noErr, @"Couldn't enable RIO output");
	
	// setup an asbd in the iphone canonical format
	AudioStreamBasicDescription myASBD = *(self.myASBD);

	// set format for output (bus 0) on rio's input scope
	setupErr =
	AudioUnitSetProperty (self.remoteIOUnit,
						  kAudioUnitProperty_StreamFormat,
						  kAudioUnitScope_Input,
						  bus0,
						  &myASBD,
						  sizeof (myASBD));
	NSAssert (setupErr == noErr, @"Couldn't set ASBD for RIO on input scope / bus 0");
    
	// enable rio input
	AudioUnitElement bus1 = 1;
	setupErr = AudioUnitSetProperty(self.remoteIOUnit,
									kAudioOutputUnitProperty_EnableIO,
									kAudioUnitScope_Input,
									bus1,
									&oneFlag,
									sizeof(oneFlag));
	NSAssert (setupErr == noErr, @"couldn't enable RIO input");
	
	// set asbd for mic input
	setupErr =
	AudioUnitSetProperty (self.remoteIOUnit,
						  kAudioUnitProperty_StreamFormat,
						  kAudioUnitScope_Output,
						  bus1,
						  &myASBD,
						  sizeof (myASBD));
	NSAssert (setupErr == noErr, @"Couldn't set ASBD for RIO on output scope / bus 1");
    
    
    
    // set up file
    NSArray *urls = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    NSURL *url = [urls[0] URLByAppendingPathComponent:@"audio.caf"];
    
    ExtAudioFileRef outputAudioFile;
    AudioFileTypeID fileType = kAudioFileCAFType;
    setupErr =  ExtAudioFileCreateWithURL (
                                      (__bridge CFURLRef)url,
                                      fileType,
                                      &myASBD,
                                      NULL,
                                      kAudioFileFlags_EraseFile,
                                      &outputAudioFile
                                      );
    
    NSAssert (setupErr == noErr, @"Couldn't create audio file");


	
    
//init data to be passed to callbacks
    effectState.rioUnit = self.remoteIOUnit;
	effectState.asbd = myASBD;
    effectState.outputAudioFile = outputAudioFile;
    
    
// set input callback method
    AURenderCallbackStruct callbackStruct;
	callbackStruct.inputProc = RecordingCallback; // callback function
	callbackStruct.inputProcRefCon = &effectState;
    
    setupErr =
	AudioUnitSetProperty(self.remoteIOUnit,
						 kAudioOutputUnitProperty_SetInputCallback,
						 kAudioUnitScope_Global,
						 bus1,
						 &callbackStruct,
						 sizeof (callbackStruct));
	NSAssert (setupErr == noErr, @"Couldn't set RIO input callback");
    
    
	// set render callback method
	callbackStruct.inputProc = PlaybackCallback; // callback function
	callbackStruct.inputProcRefCon = &effectState;
	
	setupErr =
	AudioUnitSetProperty(self.remoteIOUnit,
						 kAudioUnitProperty_SetRenderCallback,
						 kAudioUnitScope_Global,
						 bus0,
						 &callbackStruct,
						 sizeof (callbackStruct));
	NSAssert (setupErr == noErr, @"Couldn't set RIO output callback");
    
    
	setupErr =	AudioUnitInitialize(self.remoteIOUnit);
	NSAssert (setupErr == noErr, @"Couldn't initialize RIO unit");
    
}

- (IBAction)togglePassingThrough:(id)sender {
    OSStatus startErr = noErr;
    if(self.passingThroughSwitch.on){
        startErr = AudioOutputUnitStart(self.remoteIOUnit);
        NSAssert (startErr == noErr, @"Couldn't start RIO unit");
    } else{
        startErr = AudioOutputUnitStop(self.remoteIOUnit);
        NSAssert (startErr == noErr, @"Couldn't stop RIO unit");
    }

}
- (IBAction)play:(id)sender {
    NSArray *urls = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    NSURL *url = [urls[0] URLByAppendingPathComponent:@"audio.caf"];
    NSError *error = nil;
    self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&error];
    [self.player play];
}

@end
