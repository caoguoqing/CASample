//
//  AudioController.h
//  AUCallback
//
//  Created by Chinh Nguyen on 11/15/13.
//  Copyright (c) 2013 Chinh Nguyen. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "FrameQueue.h"

@interface AudioController : NSObject
@property (strong, nonatomic) FrameQueue* readQueue;
@property (strong, nonatomic) FrameQueue* writeQueue;
-(int) startRendering;
-(int) stopRendering;
-(int) startRecording;
-(int) stopRecording;
-(int) setUpInputUnit;
-(int) setUpOutputUnit;
//-(int) readPCM:(char*) buffer length:(int) length;
//-(int) writePCM:(char*) buffer length:(int) length;

@end
