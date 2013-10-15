//
//  ViewController.m
//  AUCallback
//
//  Created by Chinh Nguyen on 10/14/13.
//  Copyright (c) 2013 Chinh Nguyen. All rights reserved.
//

#import "ViewController.h"

@interface ViewController (){
    EffectState effectState;
}
@property (atomic) double sampleRate;
@property (atomic) AudioUnit remoteIOUnit;
@end

@implementation ViewController

@synthesize remoteIOUnit;

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
	buffer.mDataByteSize = inNumberFrames * 2;
	buffer.mData = malloc( inNumberFrames * 2 );
    
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
	setupErr = AudioComponentInstanceNew(rioComponent, &remoteIOUnit);
	NSAssert (setupErr == noErr, @"Couldn't get RIO unit instance");
	
	// set up the rio unit for playback
	UInt32 oneFlag = 1;
	AudioUnitElement bus0 = 0;
	setupErr =
	AudioUnitSetProperty (remoteIOUnit,
						  kAudioOutputUnitProperty_EnableIO,
						  kAudioUnitScope_Output,
						  bus0,
						  &oneFlag,
						  sizeof(oneFlag));
	NSAssert (setupErr == noErr, @"Couldn't enable RIO output");
	
	// setup an asbd in the iphone canonical format
	AudioStreamBasicDescription myASBD;
	memset (&myASBD, 0, sizeof (myASBD));
//	myASBD.mSampleRate = self.sampleRate;
//	myASBD.mFormatID = kAudioFormatLinearPCM;
//	myASBD.mFormatFlags = kAudioFormatFlagsCanonical;
//	myASBD.mBytesPerPacket = 4;
//	myASBD.mFramesPerPacket = 1;
//	myASBD.mBytesPerFrame = myASBD.mBytesPerPacket * myASBD.mFramesPerPacket;
//	myASBD.mChannelsPerFrame = 2;
//	myASBD.mBitsPerChannel = 16;
    
    myASBD.mSampleRate			= 44100.00;
    myASBD.mFormatID			= kAudioFormatLinearPCM;
    myASBD.mFormatFlags		= kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    myASBD.mFramesPerPacket	= 1;
    myASBD.mChannelsPerFrame	= 1;
    myASBD.mBitsPerChannel		= 16;
    myASBD.mBytesPerPacket		= 2;
    myASBD.mBytesPerFrame		= 2;
	
	// set format for output (bus 0) on rio's input scope
	setupErr =
	AudioUnitSetProperty (remoteIOUnit,
						  kAudioUnitProperty_StreamFormat,
						  kAudioUnitScope_Input,
						  bus0,
						  &myASBD,
						  sizeof (myASBD));
	NSAssert (setupErr == noErr, @"Couldn't set ASBD for RIO on input scope / bus 0");
    
	// enable rio input
	AudioUnitElement bus1 = 1;
	setupErr = AudioUnitSetProperty(remoteIOUnit,
									kAudioOutputUnitProperty_EnableIO,
									kAudioUnitScope_Input,
									bus1,
									&oneFlag,
									sizeof(oneFlag));
	NSAssert (setupErr == noErr, @"couldn't enable RIO input");
	
	// set asbd for mic input
	setupErr =
	AudioUnitSetProperty (remoteIOUnit,
						  kAudioUnitProperty_StreamFormat,
						  kAudioUnitScope_Output,
						  bus1,
						  &myASBD,
						  sizeof (myASBD));
	NSAssert (setupErr == noErr, @"Couldn't set ASBD for RIO on output scope / bus 1");
    
    
    
    // set up file
    NSArray  *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *recordFile = [documentsDirectory stringByAppendingPathComponent: @"audio.caf"];
    NSURL *url = [NSURL fileURLWithPath:recordFile];
    
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
    effectState.rioUnit = remoteIOUnit;
	effectState.asbd = myASBD;
    effectState.outputAudioFile = outputAudioFile;
    
    
// set input callback method
    AURenderCallbackStruct callbackStruct;
	callbackStruct.inputProc = RecordingCallback; // callback function
	callbackStruct.inputProcRefCon = &effectState;
    
    setupErr =
	AudioUnitSetProperty(remoteIOUnit,
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
	AudioUnitSetProperty(remoteIOUnit,
						 kAudioUnitProperty_SetRenderCallback,
						 kAudioUnitScope_Global,
						 bus0,
						 &callbackStruct,
						 sizeof (callbackStruct));
	NSAssert (setupErr == noErr, @"Couldn't set RIO output callback");
    
    
	setupErr =	AudioUnitInitialize(remoteIOUnit);
	NSAssert (setupErr == noErr, @"Couldn't initialize RIO unit");
    
}

- (IBAction)startPassingThrough:(id)sender {
	OSStatus startErr = noErr;
	startErr = AudioOutputUnitStart(self.remoteIOUnit);
	NSAssert (startErr == noErr, @"Couldn't start RIO unit");
	NSLog (@"Started RIO unit");
    
    
}

- (IBAction)stopPassingThrough:(id)sender {
    OSStatus startErr = noErr;
	startErr = AudioOutputUnitStop(self.remoteIOUnit);
	NSAssert (startErr == noErr, @"Couldn't stop RIO unit");
	NSLog (@"Stopped RIO unit");

}

@end
