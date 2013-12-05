//
//  AudioController.m
//  AUCallback
//
//  Created by Chinh Nguyen on 11/15/13.
//  Copyright (c) 2013 Chinh Nguyen. All rights reserved.
//

#import "AudioController.h"
#import "FrameQueue.h"

@interface AudioController ()
@property (nonatomic) AudioUnit remoteIOUnit;
@property (nonatomic) ExtAudioFileRef outputAudioFile;
@property (nonatomic) double sampleRate;
@property (nonatomic) AudioStreamBasicDescription *myASBD;
@end

@implementation AudioController

- (id) init{
    if (self = [super init]){
        [self setUpAudioSession];
        [self setUpAUConnections];
    }
    return self;
}

- (void) start{
    OSStatus err = noErr;
    err = AudioOutputUnitStart(self.remoteIOUnit);
    NSAssert (err == noErr, @"Couldn't start RIO unit");
}
- (void) stop{
    OSStatus err = noErr;
    err = AudioOutputUnitStop(self.remoteIOUnit);
    NSAssert (err == noErr, @"Couldn't stop RIO unit");
}

- (AudioStreamBasicDescription *)myASBD{
    if(!_myASBD){
        _myASBD = calloc(1, sizeof(AudioStreamBasicDescription));
        _myASBD->mSampleRate			= self.sampleRate;
        _myASBD->mFormatID			= kAudioFormatLinearPCM;
        _myASBD->mFormatFlags         = kAudioFormatFlagsCanonical;
        _myASBD->mChannelsPerFrame	= 1; //mono
        _myASBD->mBitsPerChannel		= 8*sizeof(sample_t);
        _myASBD->mFramesPerPacket     = 1; //uncompressed
        _myASBD->mBytesPerFrame       = _myASBD->mChannelsPerFrame*_myASBD->mBitsPerChannel/8;
        _myASBD->mBytesPerPacket		= _myASBD->mBytesPerFrame*_myASBD->mFramesPerPacket;
    }
    return _myASBD;
}
- (FrameQueue*) readQueue{
    if(!_readQueue){
        _readQueue = [[FrameQueue alloc] init];
    }
    return _readQueue;
}
- (FrameQueue*) writeQueue{
    if(!_writeQueue){
        _writeQueue = [[FrameQueue alloc] init];
    }
    return _writeQueue;
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

static OSStatus PlaybackCallback (
                                  void *							inRefCon,
                                  AudioUnitRenderActionFlags *	ioActionFlags,
                                  const AudioTimeStamp *			inTimeStamp,
                                  UInt32							inBusNumber,
                                  UInt32							inNumberFrames,
                                  AudioBufferList *				ioData) {
	
    id self = (__bridge id)(inRefCon);
 
    FrameQueue* queue = [self writeQueue];
    if([queue isEmpty]) return noErr;
    AudioBuffer buffer = ioData->mBuffers[0];
    int retrieved = [queue get:buffer.mData length:inNumberFrames];
    buffer.mDataByteSize = retrieved*sizeof(sample_t);
	return noErr;
}


static OSStatus RecordingCallback (
                                   void *							inRefCon,
                                   AudioUnitRenderActionFlags *	ioActionFlags,
                                   const AudioTimeStamp *			inTimeStamp,
                                   UInt32							inBusNumber,
                                   UInt32							inNumberFrames,
                                   AudioBufferList *				ioData) {
	
    id self = (__bridge id)(inRefCon);
	AudioUnit rioUnit = [self remoteIOUnit];
    //    ExtAudioFileRef outputAudioFile = [self outputAudioFile];
	OSStatus err = noErr;
    
    AudioBuffer* buffer = malloc(sizeof(AudioBuffer));
	buffer->mNumberChannels = 1;
	buffer->mDataByteSize = inNumberFrames * sizeof(sample_t);
	buffer->mData = malloc(inNumberFrames * sizeof(sample_t));
    
	// Put buffer in a AudioBufferList
	AudioBufferList bufferList;
	bufferList.mNumberBuffers = 1;
	bufferList.mBuffers[0] = *buffer;
    
    
	err = AudioUnitRender(rioUnit,
                          ioActionFlags,
                          inTimeStamp,
                          1,
                          inNumberFrames,
                          &bufferList);
    
    
	// Render into audio buffer
	if( err )
		fprintf( stderr, "AudioUnitRender() failed with error %i\n", (int)err );
    
    FrameQueue* queue = [self readQueue];
    [queue add:buffer];

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
    self.outputAudioFile = outputAudioFile;
    
    // set input callback method
    AURenderCallbackStruct callbackStruct;
	callbackStruct.inputProc = RecordingCallback; // callback function
	callbackStruct.inputProcRefCon = (__bridge void*)self;
    
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
	callbackStruct.inputProcRefCon = (__bridge void*)self;
	
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
-(int) readPCM:(sample_t*) buffer length:(int) length{
    //buffer should already be malloc'd
    return [self.readQueue get:buffer length:length];
}
-(int) writePCM:(sample_t*) buffer length:(int) length{
    buffer_t* mbuffer = malloc(sizeof(buffer_t));
    mbuffer->mData = buffer;
    mbuffer->mDataByteSize = length;
    [self.writeQueue add:mbuffer];
    return 0;
}

-(void) testFrameQueue{
    FrameQueue* queue = [self readQueue];
    char* a = malloc(10);
    for(char i=0; i<10; i++) a[i]=i;
    buffer_t* buffer = malloc(sizeof(buffer_t));
    buffer->mData = a;
    buffer->mDataByteSize = 10;
    [queue add:buffer];
    
    a = malloc(7*sizeof(sample_t));
    for(char i=0; i<7; i++) a[i]=i+10;
    buffer = malloc(sizeof(buffer_t));
    buffer->mData = a;
    buffer->mDataByteSize = 7;
    [queue add:buffer];
    
    sample_t* b = malloc(11*sizeof(sample_t));
    int retrieved = [queue get:b length:11];
    printf("retrieved 1: %d\n",retrieved);
    for(int i=0; i<retrieved; i++){
        printf("item %d\n",b[i]);
    }
    
    b = malloc(10*sizeof(sample_t));
    retrieved = [queue get:b length:10];
    printf("retrieved 2: %d\n",retrieved);
    for(int i=0; i<retrieved; i++){
        printf("item %d\n",b[i]);
    }
}

@end
