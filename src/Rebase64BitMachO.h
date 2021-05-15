//
//  Rebase64BitMacho.hpp
//  PP_Download
//
//  Created by piao on 16/5/31.
//  Copyright © 2016年 piao. All rights reserved.
//

#ifndef Rebase64BitMacho_hpp
#define Rebase64BitMacho_hpp

#import <stdio.h>
#import <substrate.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <mach-o/swap.h>
#import <mach-o/ldsyms.h>

CF_EXTERN_C_BEGIN

void set_rpath(NSString* path);
void* loadImageFromFile(NSString* path);

CF_EXTERN_C_END

int fuckPageZero(void* dyldBase);
void* loadLibrary(const char* path, int* imageIndex);
void modify64BitMacho(const char *machoPath);

#endif /* Rebase64BitMacho_hpp */
