//
//  AudioController.m
//  AUCallback
//
//  Created by Chinh Nguyen on 11/15/13.
//  Copyright (c) 2013 Chinh Nguyen. All rights reserved.
//

#import "AudioController.h"
#import "FrameQueue.h"


NSString *const AudioSessionPortBluetooth = @"AudioSessionPortBluetooth";
NSString *const AudioSessionPortSpeaker = @"AudioSessionPortSpeaker";
NSString *const AudioSessionPortReceiver = @"AudioSessionPortReceiver";

@interface AudioController ()
@property (nonatomic) AudioUnit remoteIOUnit;
@property (nonatomic) AudioUnit renderMixerUnit;
@property (nonatomic) AUGraph processingGraph;

@property (strong, nonatomic) FrameQueue* readQueue;
@property (strong, nonatomic) FrameQueue* writeQueue;

@property (nonatomic) ExtAudioFileRef outputAudioFile;
@property (nonatomic) double sampleRate;
@property (nonatomic) AudioStreamBasicDescription *mASBD;
@property (nonatomic) int readCount;
@property (nonatomic) int consumedPosition;
@end

@implementation AudioController

- (id) init{
    if (self = [super init]){
        self.consumedPosition = 0;
        [self setUpAudioSession];
        [self setUpAUConnections];
        //        [self reopenFile];
    }
    return self;
}

- (void) start{
    OSStatus err = noErr;
    err = AUGraphStart(_processingGraph);
    NSAssert (err == noErr, @"Couldn't start AUGraph");
}
- (void) stop{
    OSStatus err = noErr;
    err = AUGraphStop(_processingGraph);
//    err = AUGraphUninitialize(_processingGraph);
//    err = AUGraphClose(_processingGraph);
//    err = DisposeAUGraph(_processingGraph);
    NSAssert (err == noErr, @"Couldn't stop AUGraph");
    self.consumedPosition = 0;
}

- (AudioStreamBasicDescription *)mASBD{
    if(!_mASBD){
        _mASBD = calloc(1, sizeof(AudioStreamBasicDescription));
        _mASBD->mSampleRate			= 16000;
        _mASBD->mFormatID			= kAudioFormatLinearPCM;
        _mASBD->mFormatFlags         = kAudioFormatFlagsCanonical;
        _mASBD->mChannelsPerFrame	= 1; //mono
        _mASBD->mBitsPerChannel		= 8*sizeof(sample_t);
        _mASBD->mFramesPerPacket     = 1; //uncompressed
        _mASBD->mBytesPerFrame       = _mASBD->mChannelsPerFrame*_mASBD->mBitsPerChannel/8;
        _mASBD->mBytesPerPacket		= _mASBD->mBytesPerFrame*_mASBD->mFramesPerPacket;
    }
    return _mASBD;
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
                        withOptions:0
                             error: &error];
	NSAssert (success, @"Couldn't set audio session category");
	
	// check if input available?
	NSAssert (session.inputAvailable, @"Couldn't get current audio input available prop");
    self.sampleRate = session.sampleRate;
    
    CGFloat gain = 0.2;
    if (session.isInputGainSettable) {
        BOOL success = [session setInputGain:gain
                                       error:&error];
        if (!success){
            NSLog(@"Cannot set input gain");
        }
    } else {
        NSLog(@"Cannot set input gain");
    }
    
    [session setMode:AVAudioSessionModeMeasurement
               error:nil];
}

static OSStatus RenderCallback (
                                void *							inRefCon,
                                AudioUnitRenderActionFlags *	ioActionFlags,
                                const AudioTimeStamp *			inTimeStamp,
                                UInt32							inBusNumber,
                                UInt32							inNumberFrames,
                                AudioBufferList *				ioData) {
	
    id self = (__bridge id)(inRefCon);
    
    AudioBuffer buffer = ioData->mBuffers[0];
    FrameQueue* queue = [self readQueue];
    if([queue isEmpty]){
        *ioActionFlags |= kAudioUnitRenderAction_OutputIsSilence;
        memset(buffer.mData, 0, inNumberFrames*sizeof(sample_t));
    } else{
        int retrieved = [queue get:buffer.mData length:inNumberFrames];
        buffer.mDataByteSize = retrieved*sizeof(sample_t);
    }
    [self setConsumedPosition:([self consumedPosition]+inNumberFrames)];
    
	return noErr;
}


static OSStatus CaptureCallback (
                                 void *							inRefCon,
                                 AudioUnitRenderActionFlags *	ioActionFlags,
                                 const AudioTimeStamp *			inTimeStamp,
                                 UInt32							inBusNumber,
                                 UInt32							inNumberFrames,
                                 AudioBufferList *				ioData) {
	
    id self = (__bridge id)(inRefCon);
	AudioUnit rioUnit = [self remoteIOUnit];
	OSStatus err = noErr;
    
    AudioBuffer* buffer = malloc(sizeof(AudioBuffer));
	buffer->mNumberChannels = 1;
	buffer->mDataByteSize = inNumberFrames * sizeof(sample_t);
	buffer->mData = malloc(inNumberFrames * sizeof(sample_t));
    AudioBufferList bufferList;
	bufferList.mNumberBuffers = 1;
	bufferList.mBuffers[0] = *buffer;
    
    // Render into audio buffer
	err = AudioUnitRender(rioUnit,
                          ioActionFlags,
                          inTimeStamp,
                          1,
                          inNumberFrames,
                          &bufferList);
	if(err)
		fprintf( stderr, "AudioUnitRender() failed with error %i\n", (int)err );
    
    FrameQueue* queue = [self readQueue];
    [queue add:buffer];
    
#ifdef _DEBUG_
    //	err = ExtAudioFileWriteAsync([self outputAudioFile], inNumberFrames, &bufferList);
    //	if( err != noErr )
    //	{
    //		char	formatID[5] = { 0 };
    //		*(UInt32 *)formatID = CFSwapInt32HostToBig(err);
    //		formatID[4] = '\0';
    //		fprintf(stderr, "ExtAudioFileWrite FAILED! %d '%-4.4s'\n",(int)err, formatID);
    //		return err;
    //	}
    //    int readCount = [self readCount];
    //    if([self readCount]==1000){
    //        err = ExtAudioFileDispose([self outputAudioFile]);
    //        printf("Disposing file %d\n",(int)err);
    //    }
    //    [self setReadCount:(readCount+1)];
#endif
    
	return noErr;
}
- (void) setUpAUConnections {
    
	OSStatus setupErr = noErr;
    AudioStreamBasicDescription mASBD = *(self.mASBD);
    UInt32 oneFlag = 1;
	AudioUnitElement bus0 = 0;
    AudioUnitElement bus1 = 1;
    AUNode ioNode, mixerNode;
    
    // setup AUGraph
    setupErr = NewAUGraph (&_processingGraph);
    NSAssert (setupErr == noErr, @"Couldn't create AUGraph");
    setupErr = AUGraphOpen (_processingGraph);
    NSAssert (setupErr == noErr, @"Couldn't open AUGraph");
    
    AudioComponentDescription cd;
	cd.componentType = kAudioUnitType_Output;
	cd.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
	cd.componentManufacturer = kAudioUnitManufacturer_Apple;
	cd.componentFlags = cd.componentFlagsMask = 0;
    setupErr = AUGraphAddNode (_processingGraph, &cd, &ioNode);
    NSAssert (setupErr == noErr, @"Couldn't add ioNode to AUGraph");
	cd.componentType = kAudioUnitType_Mixer;
	cd.componentSubType = kAudioUnitSubType_MultiChannelMixer;
    setupErr = AUGraphAddNode (_processingGraph, &cd, &mixerNode);
    NSAssert (setupErr == noErr, @"Couldn't add mixerNode to AUGraph");
    
    
    setupErr = AUGraphNodeInfo (_processingGraph, ioNode, NULL, &_remoteIOUnit);
    NSAssert (setupErr == noErr, @"Couldn't instantiate io unit");
    setupErr = AUGraphNodeInfo (_processingGraph, mixerNode, NULL, &_renderMixerUnit);
    NSAssert (setupErr == noErr, @"Couldn't instantiate mixer unit");
    setupErr = AUGraphConnectNodeInput(_processingGraph, mixerNode, bus0, ioNode, bus0);
    NSAssert (setupErr == noErr, @"Couldn't connect units");
    // end graph setup
	
	// enable io -- output defaulted
	setupErr =
	AudioUnitSetProperty (self.remoteIOUnit,
						  kAudioOutputUnitProperty_EnableIO,
						  kAudioUnitScope_Output,
						  bus0,
						  &oneFlag,
						  sizeof(oneFlag));
	NSAssert (setupErr == noErr, @"Couldn't enable RIO output");
	setupErr = AudioUnitSetProperty(self.remoteIOUnit,
									kAudioOutputUnitProperty_EnableIO,
									kAudioUnitScope_Input,
									bus1,
									&oneFlag,
									sizeof(oneFlag));
	NSAssert (setupErr == noErr, @"couldn't enable RIO input");
    
    
    // set format for output (bus 0) on rio's input scope
	setupErr =
	AudioUnitSetProperty (self.remoteIOUnit,
						  kAudioUnitProperty_StreamFormat,
						  kAudioUnitScope_Input,
						  bus0,
						  &mASBD,
						  sizeof (mASBD));
	NSAssert (setupErr == noErr, @"Couldn't set ASBD for RIO on input scope / bus 0");
    // set format for input (bus 1) on rio's output scope
	setupErr =
	AudioUnitSetProperty (self.remoteIOUnit,
						  kAudioUnitProperty_StreamFormat,
						  kAudioUnitScope_Output,
						  bus1,
						  &mASBD,
						  sizeof (mASBD));
	NSAssert (setupErr == noErr, @"Couldn't set ASBD for RIO on output scope / bus 1");
    // set format for output (bus 0) on mixer's input scope
    setupErr =
	AudioUnitSetProperty (self.renderMixerUnit,
						  kAudioUnitProperty_StreamFormat,
						  kAudioUnitScope_Input,
						  bus0,
						  &mASBD,
						  sizeof (mASBD));
	NSAssert (setupErr == noErr, @"Couldn't set ASBD for RIO on output scope / bus 1");
    
    // set capture callback method
    AURenderCallbackStruct captureCallbackStruct;
	captureCallbackStruct.inputProc = CaptureCallback;
	captureCallbackStruct.inputProcRefCon = (__bridge void*)self;
    setupErr = AudioUnitSetProperty(self.remoteIOUnit,
                                    kAudioOutputUnitProperty_SetInputCallback,
                                    kAudioUnitScope_Global,
                                    bus1,
                                    &captureCallbackStruct,
                                    sizeof (captureCallbackStruct));
    NSAssert (setupErr == noErr, @"Couldn't set RIO input callback");
    
    
	// set render callback method
    AURenderCallbackStruct renderCallbackStruct;
	renderCallbackStruct.inputProc = RenderCallback;
	renderCallbackStruct.inputProcRefCon = (__bridge void*)self;
    setupErr = AUGraphSetNodeInputCallback (_processingGraph,
                                            mixerNode,
                                            bus0,
                                            &renderCallbackStruct);
	NSAssert (setupErr == noErr, @"Couldn't set RIO output callback");
    
    setupErr = AUGraphInitialize (_processingGraph);
    NSAssert (setupErr == noErr, @"Couldn't initialize AUGraph");
}

- (void) setUpFile{
    // set up file
    OSStatus setupErr = noErr;
    AudioStreamBasicDescription mASBD = *(self.mASBD);
    NSArray *urls = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    NSURL *url = [urls[0] URLByAppendingPathComponent:@"audio.caf"];
    
    ExtAudioFileRef outputAudioFile;
    AudioFileTypeID fileType = kAudioFileCAFType;
    setupErr =  ExtAudioFileCreateWithURL (
                                           (__bridge CFURLRef)url,
                                           fileType,
                                           &mASBD,
                                           NULL,
                                           kAudioFileFlags_EraseFile,
                                           &outputAudioFile
                                           );
    NSAssert (setupErr == noErr, @"Couldn't create audio file");
    self.outputAudioFile = outputAudioFile;
    
}

- (void) reopenFile{
    OSStatus setupErr = noErr;
    NSArray *urls = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    NSURL *url = [urls[0] URLByAppendingPathComponent:@"audio.caf"];
    
    ExtAudioFileRef outputAudioFile;
    
    setupErr = ExtAudioFileOpenURL((__bridge CFURLRef)(url), &outputAudioFile);
    NSAssert (setupErr == noErr, @"Couldn't open audio file");
    NSLog(@"file reopened");
    self.outputAudioFile = outputAudioFile;
    
    
}

-(int) readSamples:(sample_t*) buffer length:(int) num{
    //buffer should already be malloc'd
    
    int retrieved = 0;
    while(retrieved<num){
        @autoreleasepool {
            usleep(100*5);
            int count = [self.readQueue get:(buffer+retrieved) length:(num-retrieved)];
            retrieved+=count;
        }
    }
    
    //NSLog(@"readSamples retrieved: %d\n",retrieved);
    
    AudioBuffer* mbuffer = malloc(sizeof(AudioBuffer));
    mbuffer->mNumberChannels = 1;
    mbuffer->mDataByteSize = retrieved * sizeof(sample_t);
    mbuffer->mData = buffer;
#if 0
    // Put buffer in a AudioBufferList
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0] = *mbuffer;
    
    
    OSStatus err = noErr;
    err = ExtAudioFileWriteAsync([self outputAudioFile], retrieved, &bufferList);
    if( err != noErr )
    {
        char	formatID[5] = { 0 };
        *(UInt32 *)formatID = CFSwapInt32HostToBig(err);
        formatID[4] = '\0';
        fprintf(stderr, "ExtAudioFileWrite FAILED! %d '%-4.4s'\n",(int)err, formatID);
        return err;
    }
    int readCount = [self readCount];
    if([self readCount]==500){
        err = ExtAudioFileDispose([self outputAudioFile]);
        printf("Disposing file %d\n",(int)err);
    }
    [self setReadCount:(readCount+1)];
#endif
    
    return retrieved;
}

-(int) writeSamples:(sample_t*) buffer length:(int) length{
    /*
     CFTimeInterval thisFunctionStartTime = CFAbsoluteTimeGetCurrent();
     NSLog(@"[%s] this functionStartTime = %f", __FUNCTION__, thisFunctionStartTime  );
     */
    
    buffer_t* audioBuffer = malloc(sizeof(buffer_t));
    audioBuffer->mNumberChannels = 1;
    audioBuffer->mDataByteSize = length*sizeof(sample_t);
    audioBuffer->mData = malloc(audioBuffer->mDataByteSize);
    memcpy(audioBuffer->mData, buffer, audioBuffer->mDataByteSize);
    [self.writeQueue add:audioBuffer];
    
    
    /* Saving the buffer into file */
#if 0
    AudioBufferList bufferList;
	bufferList.mNumberBuffers = 1;
	bufferList.mBuffers[0] = *audioBuffer;
    OSStatus err = noErr;
    
    
	err = ExtAudioFileWriteAsync([self outputAudioFile], length, &bufferList);
	if( err != noErr )
	{
		char	formatID[5] = { 0 };
		*(UInt32 *)formatID = CFSwapInt32HostToBig(err);
		formatID[4] = '\0';
		fprintf(stderr, "ExtAudioFileWrite FAILED! %d '%-4.4s'\n",(int)err, formatID);
		return err;
	}
    int readCount = [self readCount];
    if([self readCount]==500){
        err = ExtAudioFileDispose([self outputAudioFile]);
        printf("Disposing file %d\n",(int)err);
    }
    [self setReadCount:(readCount+1)];
#endif
    
    return noErr;
    //return length;
}

-(int) setOutputVolume:(float) volume{
    NSLog(@"set volume = %f",volume);
    OSStatus err = AudioUnitSetParameter(_renderMixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Output, 0, volume, 0);
    return err;
}

-(BOOL) setAudioPort:(SVEAudioSessionPort) port{
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;
    BOOL success = NO;
    switch (port) {
        case SVEAudioSessionPortReceiver:
            success = [session setCategory: AVAudioSessionCategoryPlayAndRecord
                               withOptions:0
                                     error: &error];
            if(!success){
                NSLog(@"Couldn't set options");
                return NO;
            }
            success = success && [session overrideOutputAudioPort:AVAudioSessionPortOverrideNone
                                                            error:&error];
            break;
        case SVEAudioSessionPortSpeaker:
            success = [session setCategory: AVAudioSessionCategoryPlayAndRecord
                               withOptions:0
                                     error: &error];
            if(!success){
                NSLog(@"Couldn't set options");
                return NO;
            }
            success = success && [session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker
                                                  error:&error];
            break;
        case SVEAudioSessionPortBluetooth:
            success = [session setCategory: AVAudioSessionCategoryPlayAndRecord
                               withOptions:AVAudioSessionCategoryOptionAllowBluetooth
                                     error: &error];
            if(!success){
                NSLog(@"Couldn't set options");
                return NO;
            }
            break;
        default:
            break;
    }
    if(!success) NSLog(@"Couldn't reroute audio");
    return success;
}

-(int) getConsumedChunk {
    return self.consumedPosition;
}
- (int) dumpwav:(short *) buf length:(int) len {
    
    AudioBuffer* mbuffer = malloc(sizeof(AudioBuffer));
    mbuffer->mNumberChannels = 1;
    mbuffer->mDataByteSize = len * sizeof(sample_t);
    mbuffer->mData = buf;
    
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0] = *mbuffer;
    
    
    OSStatus err = noErr;
    err = ExtAudioFileWriteAsync([self outputAudioFile], len, &bufferList);
    if( err != noErr )
    {
        char	formatID[5] = { 0 };
        *(UInt32 *)formatID = CFSwapInt32HostToBig(err);
        formatID[4] = '\0';
        fprintf(stderr, "ExtAudioFileWrite FAILED! %d '%-4.4s'\n",(int)err, formatID);
        return err;
    }
    int readCount = [self readCount];
    if([self readCount]==1500){
        err = ExtAudioFileDispose([self outputAudioFile]);
        printf("Disposing file %d\n",(int)err);
    }
    [self setReadCount:(readCount+1)];
    
    return len;
}

@end
