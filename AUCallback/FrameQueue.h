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
-(buffer_t*) poll;
-(BOOL) isEmpty;
@end
