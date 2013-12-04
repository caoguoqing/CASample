//
//  FrameQueue.m
//  AUCallback
//
//  Created by Chinh Nguyen on 11/15/13.
//  Copyright (c) 2013 Chinh Nguyen. All rights reserved.
//

#import "FrameQueue.h"

@interface FrameQueue()
typedef struct{
    buffer_t* data;
    struct Node* next;
} Node;
@property (nonatomic) Node* head;
@property (atomic) Node* tail;
@property (atomic) UInt32 index;
@end
@implementation FrameQueue
-(id)init{
    if(self = [super init]){
        _head = malloc(sizeof(Node));
        _tail = _head;
        _index = 0;
    }
    return self;
}
-(void)add:(buffer_t*)data{
    Node* next = (Node*) malloc(sizeof(Node));
    next->data = data;
    next->next = NULL;
    
    self.tail->next = (struct Node*) next;
    self.tail = next;
}
-(buffer_t*)poll{
    if ([self isEmpty]) return NULL;
    Node* tmp = self.head;
    self.head = (Node*)self.head->next;
    free(tmp);
    return self.head->data;
}
-(int) get:(sample_t*) buffer length:(int) length{
    int required = length;
    int cur = 0;
    while (![self isEmpty] && required>0){
        Node* targetNode = (Node*)self.head->next;
        buffer_t* targetData = targetNode->data;
        sample_t* mbuffer = targetData->mData;
        int available = targetData->mDataByteSize/sizeof(sample_t) - self.index;
        if(required<available){
            memcpy(buffer+cur, mbuffer+self.index, required*sizeof(sample_t));
            cur += required;
            self.index+=required;
            required = 0;
        } else{
            memcpy(buffer+cur, mbuffer+self.index, available*sizeof(sample_t));
            cur += available;
            required -= available;
            //move next;
            self.index = 0;
            Node* tmp = self.head;
            self.head = (Node*)self.head->next;
            free(tmp);
        }
    }
    return cur;    
}

-(BOOL) isEmpty{
    return(self.head==self.tail);
}
@end
