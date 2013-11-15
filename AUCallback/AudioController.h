//
//  AudioController.h
//  AUCallback
//
//  Created by Chinh Nguyen on 11/15/13.
//  Copyright (c) 2013 Chinh Nguyen. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

typedef struct{
    SInt16 data;
    struct Node* next;
} Node;

typedef struct{
    Node* head;
    Node* tail;
} FrameQueue;

@interface AudioController : NSObject
@property (nonatomic) FrameQueue* readQueue;
@property (nonatomic) FrameQueue* writeQueue;
-(void) stop;
-(void) start;
@end
