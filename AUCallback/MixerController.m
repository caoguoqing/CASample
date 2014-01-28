//
//  MixerController.m
//  AUCallback
//
//  Created by Chinh Nguyen on 1/28/14.
//  Copyright (c) 2014 Chinh Nguyen. All rights reserved.
//

#import "MixerController.h"

@implementation MixerController
const Float64 kGraphSampleRate = 44100.0; // 48000.0 optional tests

#pragma mark- RenderProc

- (AudioStreamBasicDescription *)mASBD{
    if(!_mASBD){
        _mASBD = calloc(1, sizeof(AudioStreamBasicDescription));
        _mASBD->mSampleRate			= kGraphSampleRate;
        _mASBD->mFormatID			= kAudioFormatLinearPCM;
        _mASBD->mFormatFlags         = kAudioFormatFlagsCanonical;
        _mASBD->mChannelsPerFrame	= 1; //mono
        _mASBD->mBitsPerChannel		= 8*sizeof(AudioUnitSampleType);
        _mASBD->mFramesPerPacket     = 1; //uncompressed
        _mASBD->mBytesPerFrame       = _mASBD->mChannelsPerFrame*_mASBD->mBitsPerChannel/8;
        _mASBD->mBytesPerPacket		= _mASBD->mBytesPerFrame*_mASBD->mFramesPerPacket;
    }
    return _mASBD;
}

// audio render procedure, don't allocate memory, don't take any locks, don't waste time, printf statements for debugging only may adversly affect render you have been warned
static OSStatus renderInput(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData)
{
    SoundBufferPtr sndbuf = (SoundBufferPtr)inRefCon;
    
    UInt32 sample = sndbuf[inBusNumber].sampleNum;      // frame number to start from
    UInt32 bufSamples = sndbuf[inBusNumber].numFrames;  // total number of frames in the sound buffer
	AudioUnitSampleType *in = sndbuf[inBusNumber].data; // audio data buffer
    
	AudioUnitSampleType *outA = (AudioUnitSampleType *)ioData->mBuffers[0].mData; // output audio buffer for L channel
    
    // for demonstration purposes we've configured 2 stereo input busses for the mixer unit
    // but only provide a single channel of data from each input bus when asked and silence for the other channel
    // alternating as appropriate when asked to render bus 0 or bus 1's input
	for (UInt32 i = 0; i < inNumberFrames; ++i) {
        outA[i] = in[sample++];
        if (sample > bufSamples) {
            // start over from the beginning of the data, our audio simply loops
            sample = 0;
        }
    }
    
    sndbuf[inBusNumber].sampleNum = sample; // keep track of where we are in the source data buffer
    
    //printf("bus %d sample %d\n", (unsigned int)inBusNumber, (unsigned int)sample);
    
	return noErr;
}
- (id) init{
    if (self = [super init]){
        memset(&mSoundBuffer, 0, sizeof(mSoundBuffer));
        NSString *sourceA = [[NSBundle mainBundle] pathForResource:@"GuitarMonoSTP" ofType:@"aif"];
        NSString *sourceB = [[NSBundle mainBundle] pathForResource:@"DrumsMonoSTP" ofType:@"aif"];
        sourceURL[0] = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)sourceA, kCFURLPOSIXPathStyle, false);
        sourceURL[1] = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)sourceB, kCFURLPOSIXPathStyle, false);
        [self initializeAUGraph];
    }
    return self;
}


- (void)initializeAUGraph
{
    printf("initialize\n");
    
    AUNode outputNode;
	AUNode mixerNode;
	
	OSStatus result = noErr;
    
    // load up the audio data
    [self performSelectorInBackground:@selector(loadFiles) withObject:nil];
    
    // create a new AUGraph
	result = NewAUGraph(&mGraph);
	
    // create two AudioComponentDescriptions for the AUs we want in the graph
    
    // output unit
    AudioComponentDescription cd;
	cd.componentType = kAudioUnitType_Output;
	cd.componentSubType = kAudioUnitSubType_RemoteIO;
	cd.componentManufacturer = kAudioUnitManufacturer_Apple;
	cd.componentFlags = cd.componentFlagsMask = 0;
    result = AUGraphAddNode(mGraph, &cd, &outputNode);
    
    cd.componentType = kAudioUnitType_Mixer;
	cd.componentSubType = kAudioUnitSubType_MultiChannelMixer;
    
	result = AUGraphAddNode(mGraph, &cd, &mixerNode );
    
    // connect a node's output to a node's input
	result = AUGraphConnectNodeInput(mGraph, mixerNode, 0, outputNode, 0);
	
    // open the graph AudioUnits are open but not initialized (no resource allocation occurs here)
	result = AUGraphOpen(mGraph);
	
	result = AUGraphNodeInfo(mGraph, mixerNode, NULL, &mMixer);
    
    result = AudioUnitSetParameter(mMixer, kMultiChannelMixerParam_Enable, kAudioUnitScope_Input, 0, true, 0);
    result = AudioUnitSetParameter(mMixer, kMultiChannelMixerParam_Enable, kAudioUnitScope_Input, 1, true, 0);

    
    // set bus count
	UInt32 numbuses = 2;
	UInt32 size = sizeof(numbuses);
	
	
    result = AudioUnitSetProperty(mMixer, kAudioUnitProperty_ElementCount, kAudioUnitScope_Input, 0, &numbuses, sizeof(UInt32));
    AudioStreamBasicDescription desc = *(self.mASBD);
	for (int i = 0; i < numbuses; ++i) {
		// setup render callback struct
		AURenderCallbackStruct rcbs;
		rcbs.inputProc = &renderInput;
		rcbs.inputProcRefCon = mSoundBuffer;
        
        printf("set kAudioUnitProperty_SetRenderCallback\n");
        
        // Set a callback for the specified node's specified input
        result = AUGraphSetNodeInputCallback(mGraph, mixerNode, i, &rcbs);
		// equivalent to AudioUnitSetProperty(mMixer, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, i, &rcbs, sizeof(rcbs));
        // set input stream format to what we want
        printf("get kAudioUnitProperty_StreamFormat\n");
		
        size = sizeof(desc);
		result = AudioUnitGetProperty(mMixer, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, i, &desc, &size);
        desc.mChannelsPerFrame = 1;
		
		printf("set kAudioUnitProperty_StreamFormat\n");
        
		result = AudioUnitSetProperty(mMixer, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, i, &desc, sizeof(desc));
	}
	
	// set output stream format to what we want
    printf("get kAudioUnitProperty_StreamFormat\n");
	
    result = AudioUnitGetProperty(mMixer, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &desc, &size);
	
    printf("set kAudioUnitProperty_StreamFormat\n");
    
	result = AudioUnitSetProperty(mMixer, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &desc, sizeof(desc));
    
    printf("AUGraphInitialize\n");
    
    // now that we've set everything up we can initialize the graph, this will also validate the connections
	result = AUGraphInitialize(mGraph);
    
    CAShow(mGraph);
}

- (void)loadFiles
{
    for (int i = 0; i < NUMFILES && i < MAXBUFS; i++)  {
        
        ExtAudioFileRef xafref = 0;
        
        // open one of the two source files
        OSStatus result = ExtAudioFileOpenURL(sourceURL[i], &xafref);
        
        // get the file data format, this represents the file's actual data format
        AudioStreamBasicDescription clientFormat;
        UInt32 propSize = sizeof(clientFormat);
        
        result = ExtAudioFileGetProperty(xafref, kExtAudioFileProperty_FileDataFormat, &propSize, &clientFormat);
        
        // set the client format to be what we want back
        double rateRatio = kGraphSampleRate / clientFormat.mSampleRate;
        clientFormat.mSampleRate = kGraphSampleRate;
        
        clientFormat.mFormatID = kAudioFormatLinearPCM;
#if CA_PREFER_FIXED_POINT
        clientFormat.mFormatFlags = kAudioFormatFlagsCanonical | (kAudioUnitSampleFractionBits << kLinearPCMFormatFlagsSampleFractionShift);
#else
        clientFormat.mFormatFlags = kAudioFormatFlagsCanonical;
#endif
        clientFormat.mChannelsPerFrame = 1;
        clientFormat.mFramesPerPacket = 1;
        clientFormat.mBitsPerChannel = 8 * sizeof(AudioUnitSampleType);
        clientFormat.mBytesPerPacket = clientFormat.mBytesPerFrame = clientFormat.mChannelsPerFrame * sizeof(AudioUnitSampleType);
        
        
        propSize = sizeof(clientFormat);
        result = ExtAudioFileSetProperty(xafref, kExtAudioFileProperty_ClientDataFormat, propSize, &clientFormat);
        
        // get the file's length in sample frames
        UInt64 numFrames = 0;
        propSize = sizeof(numFrames);
        result = ExtAudioFileGetProperty(xafref, kExtAudioFileProperty_FileLengthFrames, &propSize, &numFrames);
        
        numFrames = (UInt32)(numFrames * rateRatio); // account for any sample rate conversion
        
        // set up our buffer
        mSoundBuffer[i].numFrames = numFrames;
        mSoundBuffer[i].asbd = clientFormat;
        
        UInt32 samples = numFrames * mSoundBuffer[i].asbd.mChannelsPerFrame;
        mSoundBuffer[i].data = (AudioUnitSampleType *)calloc(samples, sizeof(AudioUnitSampleType));
        mSoundBuffer[i].sampleNum = 0;
        
        // set up a AudioBufferList to read data into
        AudioBufferList bufList;
        bufList.mNumberBuffers = 1;
        bufList.mBuffers[0].mNumberChannels = 1;
        bufList.mBuffers[0].mData = mSoundBuffer[i].data;
        bufList.mBuffers[0].mDataByteSize = samples * sizeof(AudioUnitSampleType);
        
        // perform a synchronous sequential read of the audio data out of the file into our allocated data buffer
        UInt32 numPackets = numFrames;
        result = ExtAudioFileRead(xafref, &numPackets, &bufList);
        if (result) {
            free(mSoundBuffer[i].data);
            mSoundBuffer[i].data = 0;
            return;
        }
        
        // close the file and dispose the ExtAudioFileRef
        ExtAudioFileDispose(xafref);
    }
}


- (void)startAUGraph
{
	AUGraphStart(mGraph);
}

// stops render
- (void)stopAUGraph
{
    Boolean isRunning = false;
    OSStatus result = AUGraphIsRunning(mGraph, &isRunning);
    if (isRunning) {
        result = AUGraphStop(mGraph);
    }
}



@end
