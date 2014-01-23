//
//  AudioController.m
//  AUCallback
//
//  Created by Chinh Nguyen on 11/15/13.
//  Copyright (c) 2013 Chinh Nguyen. All rights reserved.
//

#import "AudioController.h"

@interface AudioController ()
@property (nonatomic) AUGraph processingGraph;
@property (nonatomic) AudioUnit remoteIOUnit;
@property (nonatomic) AudioUnit renderMixerUnit;

@property (strong, nonatomic) FrameQueue* readQueue;
@property (strong, nonatomic) FrameQueue* writeQueue;

@property (nonatomic) ExtAudioFileRef outputAudioFile;
@property (nonatomic) double sampleRate;
@property (nonatomic) AudioStreamBasicDescription *mASBD;
@property (nonatomic) int readCount;
@end

int consumedPostion = 0;

@implementation AudioController
@synthesize processingGraph=processingGraph;

- (id) init{
    if (self = [super init]){
        [self setUpAudioSession];
        [self setUpAUConnections];
        //   [self setUpFile];
    }
    return self;
}

- (void) start{
    OSStatus err = noErr;
    err = AudioOutputUnitStart(self.remoteIOUnit);
    NSAssert (err == noErr, @"Couldn't start AUGraph");
}
- (void) stop{
    OSStatus err = noErr;
    err = AudioOutputUnitStop(self.remoteIOUnit);
    NSAssert (err == noErr, @"Couldn't stop AUGraph");
}

- (AudioStreamBasicDescription *)mASBD{
    if(!_mASBD){
        _mASBD = calloc(0, sizeof(AudioStreamBasicDescription));
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

    //    Float32 preferredBufferDuration = 0.020;

    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;

    BOOL success = [session setActive: YES error: &error];
    NSAssert (success, @"Couldn't initialize audio session");

    success = [session setCategory: AVAudioSessionCategoryPlayAndRecord
                             error: &error];
    NSAssert (success, @"Couldn't set audio session category");

    // check if input available?
    NSAssert (session.inputAvailable, @"Couldn't get current audio input available prop");
    //self.sampleRate = session.sampleRate;


    //  AudioSessionSet


}

static OSStatus RenderCallback (
        void *							inRefCon,
        AudioUnitRenderActionFlags *	ioActionFlags,
        const AudioTimeStamp *			inTimeStamp,
        UInt32							inBusNumber,
        UInt32							inNumberFrames,
        AudioBufferList *				ioData) {
    /*
     NSLog(@"[%s] Number of Buffers = %d \n", __FUNCTION__, ioData->mNumberBuffers);
     NSLog(@"[%s] inNumberFrames =%d \n", __FUNCTION__, (unsigned int) inNumberFrames);
     NSLog(@"[%s] inBusNumber =%d \n", __FUNCTION__, (unsigned int) inBusNumber);
     NSLog(@"[%s] AudioTimeStamp = %f \n", __FUNCTION__, inTimeStamp->mSampleTime);
     NSLog(@"[%s] AudioTimeStamp = %d \n", __FUNCTION__, inTimeStamp->mHostTime);
     
     
     NSLog(@"[%s] this functionStartTime = %f", __FUNCTION__, thisFunctionStartTime  );
     */
    //   NSLog(@"[%s] AudioTimeStamp = %f \n", __FUNCTION__, inTimeStamp->mSampleTime);



    static CFTimeInterval lastFunctionStartTime;
    CFTimeInterval thisFunctionStartTime = CFAbsoluteTimeGetCurrent();
    //NSLog(@"[%s] this is called after %f ms", __FUNCTION__, thisFunctionStartTime - lastFunctionStartTime );

    lastFunctionStartTime = thisFunctionStartTime;

    id self = (__bridge id)(inRefCon);

    AudioBuffer buffer = ioData->mBuffers[0];
    FrameQueue* queue = [self readQueue];
    if([queue isEmpty]){

        *ioActionFlags |= kAudioUnitRenderAction_OutputIsSilence;
        memset(buffer.mData, 0, inNumberFrames*sizeof(sample_t));
        NSLog(@"[%s] queue is empty \n", __FUNCTION__);

        return -1;
    } else{
        int retrieved = [queue get:buffer.mData length:inNumberFrames];
        buffer.mDataByteSize = retrieved*sizeof(sample_t);
    }
    ioData->mNumberBuffers = 1;
    //    [self dumpwav:buffer.mData length:buffer.mDataByteSize/2];

    //    thisFunctionStartTime = CFAbsoluteTimeGetCurrent();
    //    NSLog(@"[%s] this functionEndTime = %f", __FUNCTION__, thisFunctionStartTime  );

    // consumedPostion = inTimeStamp->mSampleTime;
    consumedPostion += inNumberFrames;
    return noErr;
}


static OSStatus CaptureCallback (
        void *							inRefCon,
        AudioUnitRenderActionFlags *	ioActionFlags,
        const AudioTimeStamp *			inTimeStamp,
        UInt32							inBusNumber,
        UInt32							inNumberFrames,
        AudioBufferList *				ioData) {
#if 1
    static CFTimeInterval lastFunctionStartTime;
    CFTimeInterval thisFunctionStartTime = CFAbsoluteTimeGetCurrent();
    //NSLog(@"[%s] this is called after %f ms", __FUNCTION__, thisFunctionStartTime - lastFunctionStartTime );

    lastFunctionStartTime = thisFunctionStartTime;


    //    NSLog(@"[%s] Entering ----> \n", __FUNCTION__);
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
    printf("CaptureCallback\n");
    sample_t* samples = buffer->mData;
    for(int i=0; i<inNumberFrames; i++){
        printf("%d ", samples[i]);
    }
    printf("\n");
    
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
#else
    
    return noErr;
#endif
}

- (void) setUpAUConnections {

    OSStatus setupErr = noErr;
    UInt32 oneFlag = 1;
    AudioUnitElement bus0 = 0;
    AudioUnitElement bus1 = 1;
    AudioStreamBasicDescription mASBD = *(self.mASBD);

    // describe unit
    AudioComponentDescription ioUnitDesc;
    ioUnitDesc.componentType = kAudioUnitType_Output;
    ioUnitDesc.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    ioUnitDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    ioUnitDesc.componentFlags = 0;
    ioUnitDesc.componentFlagsMask = 0;

    // mixer desc
    AudioComponentDescription mixerDesc;
    mixerDesc.componentType = kAudioUnitType_Mixer;
    mixerDesc.componentSubType = kAudioUnitSubType_MultiChannelMixer;
    mixerDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    mixerDesc.componentFlags = 0;
    mixerDesc.componentFlagsMask = 0;


    // get rio unit from audio component manager
    AudioComponent rioComponent = AudioComponentFindNext(NULL, &ioUnitDesc);
    setupErr = AudioComponentInstanceNew(rioComponent, &_remoteIOUnit);
    NSAssert (setupErr == noErr, @"Couldn't get RIO unit instance");

    // get mixer unit from audio component manager
    AudioComponent mixerComponent = AudioComponentFindNext(NULL, &mixerDesc);
    setupErr = AudioComponentInstanceNew(mixerComponent, &_renderMixerUnit);
    NSAssert (setupErr == noErr, @"Couldn't get mixer unit instance");

    // enable rio for capture and playback
    setupErr =
            AudioUnitSetProperty(self.remoteIOUnit,
                    kAudioOutputUnitProperty_EnableIO,
                    kAudioUnitScope_Input,
                    bus1,
                    &oneFlag,
                    sizeof(oneFlag));
    NSAssert (setupErr == noErr, @"couldn't enable RIO input");
    setupErr =
            AudioUnitSetProperty (self.remoteIOUnit,
                    kAudioOutputUnitProperty_EnableIO,
                    kAudioUnitScope_Output,
                    bus0,
                    &oneFlag,
                    sizeof(oneFlag));
    NSAssert (setupErr == noErr, @"Couldn't enable RIO output");


    // set format
    setupErr =
            AudioUnitSetProperty (self.remoteIOUnit,
                    kAudioUnitProperty_StreamFormat,
                    kAudioUnitScope_Input,
                    bus0,
                    &mASBD,
                    sizeof (mASBD));
    NSAssert (setupErr == noErr, @"Couldn't set ASBD for RIO on input scope / bus 0");
    setupErr =
            AudioUnitSetProperty (self.remoteIOUnit,
                    kAudioUnitProperty_StreamFormat,
                    kAudioUnitScope_Output,
                    bus1,
                    &mASBD,
                    sizeof (mASBD));
    NSAssert (setupErr == noErr, @"Couldn't set ASBD for RIO on output scope / bus 1");
    setupErr =
            AudioUnitSetProperty (self.renderMixerUnit,
                    kAudioUnitProperty_StreamFormat,
                    kAudioUnitScope_Input,
                    bus0,
                    &mASBD,
                    sizeof (mASBD));
    NSAssert (setupErr == noErr, @"Couldn't set ASBD for mixer on input scope / bus 0");


    // set input callback method
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = CaptureCallback; // callback function
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
    callbackStruct.inputProc = RenderCallback; // callback function
    callbackStruct.inputProcRefCon = (__bridge void*)self;
    setupErr =
            AudioUnitSetProperty(self.renderMixerUnit,
                    kAudioUnitProperty_SetRenderCallback,
                    kAudioUnitScope_Global,
                    bus0,
                    &callbackStruct,
                    sizeof (callbackStruct));
    NSAssert (setupErr == noErr, @"Couldn't set RIO output callback");


    // direct connect mic to output
    AudioUnitConnection connection;
    connection.sourceAudioUnit = _renderMixerUnit;
    connection.sourceOutputNumber = bus0;
    connection.destInputNumber = bus0;
    setupErr =
            AudioUnitSetProperty(_remoteIOUnit,
                    kAudioUnitProperty_MakeConnection,
                    kAudioUnitScope_Input,
                    bus0,
                    &connection,
                    sizeof (connection));
    NSAssert (setupErr == noErr, @"Couldn't set units connection");


    setupErr =	AudioUnitInitialize(self.remoteIOUnit);
    NSAssert (setupErr == noErr, @"Couldn't initialize RIO unit");

    setupErr =	AudioUnitInitialize(self.renderMixerUnit);
    NSAssert (setupErr == noErr, @"Couldn't initialize mixer unit");
}

- (void) setUpFile{
    // set up file
    OSStatus setupErr = noErr;
    AudioStreamBasicDescription mASBD = *(self.mASBD);
    NSArray *urls = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    NSURL *url = [urls[0] URLByAppendingPathComponent:@"audio2.caf"];

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
	bufferList.mBuffers[0] = *mbuffer;
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

-(int) getConsumedChunk {

    return consumedPostion;
}

@end
