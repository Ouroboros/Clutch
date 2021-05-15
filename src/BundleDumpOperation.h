//
//  BundleDumpOperation.h
//  Clutch
//
//  Created by Anton Titkov on 11.02.15.
//
//

#import <Foundation/Foundation.h>

@class ClutchBundle;

@interface BundleDumpOperation : NSOperation
@property (nonatomic, assign) BOOL failed;
@property (nonatomic, assign) BOOL mainExecutable;

- (instancetype)initWithBundle:(ClutchBundle *)application;

@end
