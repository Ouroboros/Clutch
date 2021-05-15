//
//  ARM64Dumper.m
//  Clutch
//
//  Created by Anton Titkov on 22.03.15.
//
//

#import "ARM64Dumper.h"
#import <mach-o/fat.h>
#import "Device.h"
#import <dlfcn.h>
#import <mach/mach_traps.h>
#import <mach/mach_init.h>
#import <mach-o/dyld.h>
#import "ClutchPrint.h"
#import "Rebase64BitMachO.h"

@implementation ARM64Dumper

- (cpu_type_t)supportedCPUType
{
    return CPU_TYPE_ARM64;
}

- (BOOL)dumpBinary {
    __block BOOL dumpResult;
    NSString *binaryDumpPath = [_originalBinary.workingPath stringByAppendingPathComponent:_originalBinary.binaryPath.lastPathComponent];

    NSFileHandle *newFileHandle = [[NSFileHandle alloc]initWithFileDescriptor:fileno(fopen(binaryDumpPath.UTF8String, "r+"))];

    NSString* swappedBinaryPath = _originalBinary.binaryPath, *newSinf = _originalBinary.sinfPath, *newSupp = _originalBinary.suppPath, *newSupf = _originalBinary.supfPath; // default values if we dont need to swap archs

    //check if cpusubtype matches
    if ((_thinHeader.header.cpusubtype != [Device cpu_subtype]) && (_originalBinary.hasMultipleARMSlices || (_originalBinary.hasARM64Slice && ([Device cpu_type]==CPU_TYPE_ARM64)))) {

        NSString* suffix = [NSString stringWithFormat:@"_%@", [Dumper readableArchFromHeader:_thinHeader]];

        swappedBinaryPath = [_originalBinary.binaryPath stringByAppendingString:suffix];
        newSinf = [_originalBinary.sinfPath.stringByDeletingPathExtension stringByAppendingString:[suffix stringByAppendingPathExtension:_originalBinary.sinfPath.pathExtension]];
        newSupp = [_originalBinary.suppPath.stringByDeletingPathExtension stringByAppendingString:[suffix stringByAppendingPathExtension:_originalBinary.suppPath.pathExtension]];

        [self swapArch];

    }


    //actual dumping

    [newFileHandle seekToFileOffset:_thinHeader.offset + _thinHeader.size];

    struct linkedit_data_command ldid; // LC_CODE_SIGNATURE load header (for resign)
    struct encryption_info_command_64 crypt; // LC_ENCRYPTION_INFO load header (for crypt*)
    struct segment_command_64 __text; // __TEXT segment

    union
    {
        struct rpath_command lc;
        char buffer[0x100];
    } rpath;

    struct super_blob *codesignblob; // codesign blob pointer
    struct code_directory directory; // codesign directory index

    directory.nCodeSlots = 0;
    BOOL foundCrypt = NO, foundSignature = NO, foundStartText = NO;
    crypt.cryptid = crypt.cryptoff = crypt.cryptsize = 0;

    uint64_t __text_start = 0;

    [[ClutchPrint sharedInstance] printDeveloper: @"64bit dumping: arch %@ offset %u", [Dumper readableArchFromHeader:_thinHeader], _thinHeader.offset];

    for (unsigned int i = 0; i < _thinHeader.header.ncmds; i++) {

        uint32_t cmd = [newFileHandle intAtOffset:newFileHandle.offsetInFile];
        uint32_t size = [newFileHandle intAtOffset:newFileHandle.offsetInFile+sizeof(uint32_t)];

        switch (cmd) {
            case LC_CODE_SIGNATURE: {
                [newFileHandle getBytes:&ldid inRange:NSMakeRange((NSUInteger)(newFileHandle.offsetInFile),sizeof(struct linkedit_data_command))];
                foundSignature = YES;

                [[ClutchPrint sharedInstance] printDeveloper: @"FOUND CODE SIGNATURE: dataoff %u | datasize %u",ldid.dataoff,ldid.datasize];

                break;
            }
            case LC_ENCRYPTION_INFO_64: {
                [newFileHandle getBytes:&crypt inRange:NSMakeRange((NSUInteger)(newFileHandle.offsetInFile),sizeof(struct encryption_info_command_64))];
                foundCrypt = YES;

                [[ClutchPrint sharedInstance] printDeveloper: @"FOUND ENCRYPTION INFO: cryptoff %u | cryptsize %u | cryptid %u",crypt.cryptoff,crypt.cryptsize,crypt.cryptid];

                break;
            }
            case LC_SEGMENT_64:
            {
                [newFileHandle getBytes:&__text inRange:NSMakeRange((NSUInteger)(newFileHandle.offsetInFile),sizeof(struct segment_command_64))];

                if (strncmp(__text.segname, "__TEXT", 6) == 0) {
                    foundStartText = YES;
                    [[ClutchPrint sharedInstance] printDeveloper: @"FOUND %s SEGMENT",__text.segname];
                    __text_start = __text.vmaddr;
                }
                break;
            }
            // case LC_RPATH:
            // {
            //     if (self.mainExecutable == NO)
            //         break;

            //     if (size > sizeof(rpath))
            //     {
            //         [[ClutchPrint sharedInstance] printError:@"LC_RPATH too large: %X", size];
            //         exit(-1);
            //     }

            //     [newFileHandle getBytes:&rpath inRange:NSMakeRange((NSUInteger)(newFileHandle.offsetInFile), size)];

            //     NSString* path;

            //     path = [[NSString alloc] initWithUTF8String:(char *)&rpath.lc + rpath.lc.path.offset];

            //     NSLog(@"RPATH1 = %@", path);

            //     if ([path hasPrefix:@"@executable_path"])
            //     {
            //         path = [path stringByReplacingOccurrencesOfString:@"@executable_path" withString:[_originalBinary.binaryPath stringByDeletingLastPathComponent]];
            //     }
            //     else
            //     {
            //         [[ClutchPrint sharedInstance] printError:@"unsupported RPATH %@", path];
            //         exit(-2);
            //     }

            //     NSLog(@"RPATH2 = %@", path);

            //     // set_rpath(path);
            //     // exit(0);

            //     self.mainExecutable = NO;

            //     break;
            // }
        }

        [newFileHandle seekToFileOffset:newFileHandle.offsetInFile + size];

        if (foundCrypt && foundSignature && foundStartText)
            break;
    }

    // we need to have all of these
    if (!foundCrypt || !foundSignature || !foundStartText) {
        [[ClutchPrint sharedInstance] printDeveloper: @"dumping binary: some load commands were not found %@ %@ %@",foundCrypt?@"YES":@"NO",foundSignature?@"YES":@"NO",foundStartText?@"YES":@"NO"];
        return NO;
    }

    [[ClutchPrint sharedInstance] printDeveloper: @"found all required load commands for %@ %@",_originalBinary,[Dumper readableArchFromHeader:_thinHeader]];

    pid_t pid; // store the process ID of the fork
    mach_port_t port; // mach port used for moving virtual memory
    kern_return_t err; // any kernel return codes
    NSUInteger begin = 0;
    void* handle;

    pid = getpid();

    // handle = dlopen(swappedBinaryPath.UTF8String, RTLD_LAZY);
    handle = loadImageFromFile(swappedBinaryPath);

    if (!handle) {
        [[ClutchPrint sharedInstance] printError:@"Failed to dlopen binary %@ %s", swappedBinaryPath, dlerror()];
        goto gotofail;
    }

    uint32_t imageCount = _dyld_image_count();
    uint32_t dyldIndex = -1;
    for (uint32_t idx = 0; idx < imageCount; idx++) {
        NSString *dyldPath = [NSString stringWithUTF8String:_dyld_get_image_name(idx)];
        if ([swappedBinaryPath isEqualToString:dyldPath]) {
            dyldIndex = idx;
            break;
        }
    }

    if (dyldIndex == -1) {
        // dlclose(handle);
        goto gotofail;
    }

    intptr_t dyldPointer = _dyld_get_image_vmaddr_slide(dyldIndex);

    port = mach_task_self();

    // pid = [self posix_spawn:swappedBinaryPath disableASLR:self.shouldDisableASLR];

    // if ((err = task_for_pid(mach_task_self(), pid, &port) != KERN_SUCCESS)) {
    //     [[ClutchPrint sharedInstance] printError:@"Could not obtain mach port, either the process is dead (codesign error?) or entitlements were not properly signed! %d", err];
    //     goto gotofail;
    // }

    codesignblob = malloc(ldid.datasize);


    //seek to ldid offset

    [newFileHandle seekToFileOffset:_thinHeader.offset + ldid.dataoff];
    [newFileHandle getBytes:codesignblob inRange:NSMakeRange((NSUInteger)(newFileHandle.offsetInFile), ldid.datasize)];

    uint32_t countBlobs = CFSwapInt32(codesignblob->count); // how many indexes?


    for (uint32_t index = 0; index < countBlobs; index++) { // is this the code directory?
        if (CFSwapInt32(codesignblob->index[index].type) == CSSLOT_CODEDIRECTORY) {
            // we'll find the hash metadata in here
            [[ClutchPrint sharedInstance] printDeveloper: @"%u %u %u", _thinHeader.offset, ldid.dataoff, codesignblob->index[index].offset];
            begin = _thinHeader.offset + ldid.dataoff + CFSwapInt32(codesignblob->index[index].offset); // store the top of the codesign directory blob
            [newFileHandle getBytes:&directory inRange:NSMakeRange(begin, sizeof(struct code_directory))]; //read the blob from its beginning
            [[ClutchPrint sharedInstance] printDeveloper: @"Found CSSLOT_CODEDIRECTORY"];
            break; //break (we don't need anything from this the superblob anymore)
        }
    }

    free(codesignblob);

    uint32_t pages = CFSwapInt32(directory.nCodeSlots); // get the amount of codeslots

    [[ClutchPrint sharedInstance] printDeveloper: @"Codesign Pages %u", pages];

    if (pages == 0) {
        [[ClutchPrint sharedInstance] printColor:ClutchPrinterColorPurple format:@"pages == 0"];
        goto gotofail;
    }

    [newFileHandle seekToFileOffset:_thinHeader.offset];

    if (NO && ((_thinHeader.header.flags & MH_PIE) && !self.shouldDisableASLR))
    {
        NSError *error = nil;
        mach_vm_address_t main_address = [ASLRDisabler slideForPID:pid error:&error];
        if(error) {
            [[ClutchPrint sharedInstance] printColor:ClutchPrinterColorPurple format:@"Failed to find address of header!"];
            goto gotofail;
        }

        [[ClutchPrint sharedInstance] printColor:ClutchPrinterColorPink format:@"ASLR slide: 0x%llx", main_address];
        __text_start = main_address;
    }

    {
        // dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);

        // dispatch_sync(queue, ^{
            dumpResult = [self
                            _dumpToFileHandle:newFileHandle
                            withDumpSize:(crypt.cryptsize + crypt.cryptoff)
                            pages:pages
                            fromPort:port
                            pid:pid
                            aslrSlide:dyldPointer + __text_start
                            codeSignature_hashOffset:CFSwapInt32(directory.hashOffset)
                            codesign_begin:(uint32_t)begin
                        ];
        // });

    }

    // dlclose(handle);

    [[ClutchPrint sharedInstance] printDeveloper:@"done dumping"];

    //done dumping, let's wait for pid

    // _kill(pid);
    [newFileHandle closeFile];
    if (![swappedBinaryPath isEqualToString:_originalBinary.binaryPath])
        [[NSFileManager defaultManager]removeItemAtPath:swappedBinaryPath error:nil];
    if (![newSinf isEqualToString:_originalBinary.sinfPath])
        [[NSFileManager defaultManager]removeItemAtPath:newSinf error:nil];
    if (![newSupp isEqualToString:_originalBinary.suppPath])
        [[NSFileManager defaultManager]removeItemAtPath:newSupp error:nil];
    if (![newSupf isEqualToString:_originalBinary.supfPath])
        [[NSFileManager defaultManager]removeItemAtPath:newSupf error:nil];

    return dumpResult;

gotofail:

    _kill(pid);
    [newFileHandle closeFile];
    if (![swappedBinaryPath isEqualToString:_originalBinary.binaryPath])
        [[NSFileManager defaultManager]removeItemAtPath:swappedBinaryPath error:nil];
    if (![newSinf isEqualToString:_originalBinary.sinfPath])
        [[NSFileManager defaultManager]removeItemAtPath:newSinf error:nil];
    if (![newSupp isEqualToString:_originalBinary.suppPath])
        [[NSFileManager defaultManager]removeItemAtPath:newSupp error:nil];
    if (![newSupf isEqualToString:_originalBinary.supfPath])
        [[NSFileManager defaultManager]removeItemAtPath:newSupf error:nil];

    return NO;
}


@end
