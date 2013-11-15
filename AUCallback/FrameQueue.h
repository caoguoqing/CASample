//
//  FrameQueue.h
//  AUCallback
//
//  Created by Chinh Nguyen on 11/15/13.
//  Copyright (c) 2013 Chinh Nguyen. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef SInt16 sample_t;
@interface FrameQueue : NSObject
-(void) add:(sample_t)data;
-(sample_t) poll;
-(BOOL) isEmpty;
@end
