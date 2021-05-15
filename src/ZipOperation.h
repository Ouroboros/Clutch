//
//  ZipOperation.h
//  Clutch
//
//  Created by Anton Titkov on 11.02.15.
//
//

#import <Foundation/Foundation.h>

#define PRINT_ZIP_LOGS DEBUG

@class ClutchBundle;

@interface ZipOperation : NSOperation

- (instancetype)initWithApplication:(ClutchBundle *)clutchBundle;

@end
