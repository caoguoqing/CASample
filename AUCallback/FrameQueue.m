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
    sample_t data;
    struct Node* next;
} Node;
@property (nonatomic) Node* head;
@property (atomic) Node* tail;
@end
@implementation FrameQueue
-(id)init{
    if(self = [super init]){
        _head = malloc(sizeof(Node));
        _tail = _head;
    }
    return self;
}
-(void)add:(sample_t)data{
    Node* next = (Node*) malloc(sizeof(Node));
    next->data = data;
    next->next = NULL;
    
    self.tail->next = (struct Node*) next;
    self.tail = next;
}
-(sample_t)poll{
    if ([self isEmpty]) return -1;
    Node* tmp = self.head;
    self.head = (Node*)self.head->next;
    free(tmp);
    return self.head->data;
}
-(BOOL) isEmpty{
    return(self.head==self.tail);
}
@end
