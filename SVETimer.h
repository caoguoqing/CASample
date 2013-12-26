//
//  SVETimer.h
//  AUCallback
//
//  Created by Chinh Nguyen on 12/26/13.
//  Copyright (c) 2013 Chinh Nguyen. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SVETimer : NSObject
- (void)scheduleBlock:(void (^)(void))block withInterval:(NSTimeInterval)interval;
- (void)scheduleFunction:(void (*)(void))executedFunction withInterval:(NSTimeInterval)interval;
@end
