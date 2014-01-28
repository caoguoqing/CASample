//
//  MixerController.h
//  AUCallback
//
//  Created by Chinh Nguyen on 1/28/14.
//  Copyright (c) 2014 Chinh Nguyen. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>


#define MAXBUFS  2
#define NUMFILES 2

typedef struct {
    AudioStreamBasicDescription asbd;
    AudioUnitSampleType *data;
	UInt32 numFrames;
	UInt32 sampleNum;
} SoundBuffer, *SoundBufferPtr;

@interface MixerController : NSObject
{
    CFURLRef sourceURL[2];
	AUGraph   mGraph;
	AudioUnit mMixer;
    SoundBuffer mSoundBuffer[MAXBUFS];
}
@property (nonatomic) AudioStreamBasicDescription *mASBD;
- (void)initializeAUGraph;
- (void)startAUGraph;
- (void)stopAUGraph;
@end
