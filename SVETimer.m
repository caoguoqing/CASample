//
//  SVETimer.m
//  AUCallback
//
//  Created by Chinh Nguyen on 12/26/13.
//  Copyright (c) 2013 Chinh Nguyen. All rights reserved.
//

#import "SVETimer.h"
@interface SVETimer()
@property (strong, nonatomic) void (^executedBlock)(void);
@property (nonatomic) void (*executedFunction)(void);
@end

@implementation SVETimer
- (void)scheduleBlock:(void (^)(void))block withInterval:(NSTimeInterval)interval{
    self.executedBlock = block;
    [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(executeBlock) userInfo:nil repeats:YES];
}
- (void) executeBlock{
    if([self.executedBlock isKindOfClass:NSClassFromString(@"NSBlock")]) self.executedBlock();
}

- (void)scheduleFunction:(void (*)(void))executedFunction withInterval:(NSTimeInterval)interval;{
    self.executedFunction = executedFunction;
    [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(executeFunction) userInfo:nil repeats:YES];
}

- (void) executeFunction{
    if(self.executedFunction)self.executedFunction();
}
@end
