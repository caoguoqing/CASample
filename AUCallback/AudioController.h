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
-(void) stop;
-(void) start;
-(int) readPCM:(sample_t*) buffer length:(int) length;
-(int) writePCM:(sample_t*) buffer length:(int) length;
@end
