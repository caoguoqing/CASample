//
//  FrameQueue.h
//  AUCallback
//
//  Created by Chinh Nguyen on 11/15/13.
//  Copyright (c) 2013 Chinh Nguyen. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

typedef AudioBuffer buffer_t;
typedef char sample_t;
@interface FrameQueue : NSObject
-(void) add:(buffer_t*)data;
-(int) get:(sample_t*) buffer length:(int) length;
//-(buffer_t*) poll;
-(BOOL) isEmpty;
@end
