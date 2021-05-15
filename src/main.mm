//
//  main.m
//  Clutch
//
//  Created by Anton Titkov on 09.02.15.
//  Copyright (c) 2015 AppAddict. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <mach-o/dyld.h>
#include <unistd.h>
#import <sys/time.h>
#import <ml/ml.h>
#import "ApplicationsManager.h"
#import "FrameworkLoader.h"
#import "ClutchPrint.h"
#import "NSTask.h"
#import "ClutchCommands.h"
#import "NSBundle+Clutch.h"
#import "Rebase64BitMachO.h"
#import "ImageLoader.h"
// #import "sha1.h"

struct timeval gStart;

extern "C" int diff_ms(struct timeval t1, struct timeval t2)
{
    return (int)((((t1.tv_sec - t2.tv_sec) * 1000000) +
                  (t1.tv_usec - t2.tv_usec)) / 1000);
}

void listApps(void);
void listApps() {
    ApplicationsManager *_manager = [[ApplicationsManager alloc] init];

    NSArray *installedApps = [_manager installedApps].allValues;
    [[ClutchPrint sharedInstance] print:@"Installed apps:"];

    NSUInteger count;
    NSString *space;
    for (Application *_app in installedApps)
    {
        count = [installedApps indexOfObject:_app] + 1;
        if (count < 10)
        {
            space = @"  ";
        }
        else if (count < 100)
        {
            space = @" ";
        }

        ClutchPrinterColor color;
        if (count % 2 == 0)
        {
            color = ClutchPrinterColorPurple;
        }
        else
        {
            color = ClutchPrinterColorPink;
        }

        [[ClutchPrint sharedInstance] printColor:color format:@"%d: %@%@ <%@>", count, space, _app.displayName, _app.bundleIdentifier];
    }
}

id NSBundle_bundleIdentifier(id self, SEL cmd)
{
    return @"tv.danmaku.bilianime";
}

intptr_t getDyldBase()
{
    /*
        dyld
            init_func
                getDyldBase
    */

    intptr_t pagesize = getpagesize();

    void *returnAddress[] =
    {
        __builtin_return_address(1),
        __builtin_return_address(2),
        __builtin_return_address(3),
        __builtin_return_address(4),
        __builtin_return_address(5),
    };

    for (int i = 0; i != sizeof(returnAddress) / sizeof(*returnAddress); i++)
    {
        intptr_t base = (intptr_t)returnAddress[i];

        base &= ~(pagesize - 1);

        DbgLog(@"%p -> %p", (void *)base, &_mh_execute_header);

        for (;;)
        {
            switch (*(uint32_t *)base)
            {
                case MH_MAGIC:
                case MH_CIGAM:
                case MH_MAGIC_64:
                case MH_CIGAM_64:
                case FAT_MAGIC:
                case FAT_CIGAM:
                    break;

                default:
                    base -= pagesize;
                    continue;
            }

            if (base == (intptr_t)&_mh_execute_header)
                break;

            return base;
        }
    }

    return 0;
}

intptr_t dyldBase = getDyldBase();

int main2(int argc, const char * argv[])
{
    CLUTCH_UNUSED(argc);
    CLUTCH_UNUSED(argv);

    fuckPageZero((void *)dyldBase);

    // return 0;

    ImageLoader_Init((void *)dyldBase);

    // ImageLoaderMachO* image = ImageLoaderMachO::instantiateFromFile("/var/containers/Bundle/Application/1E2A84D5-CBA5-4CB6-A05F-8C11861F2590/Aweme.app/Aweme");

    // NSLog(@"addr = %p", image->machHeader());

    // return 0;

    // [NSBundle mainBundle].clutchBID = @"com.ouroboros.clutch";

    [[ClutchPrint sharedInstance] setVerboseLevel:ClutchPrinterVerboseLevelFull];
    // [[ClutchPrint sharedInstance] print:@"------------------- main %@ --------------------------", [NSBundle mainBundle].bundleIdentifier];

    @autoreleasepool
    {
        if (getuid() != 0) { // Clutch needs to be root user to run
            [[ClutchPrint sharedInstance] print:@"Clutch needs to be run as the root user, please change user and rerun."];

            return 0;
        }

        if (SYSTEM_VERSION_LESS_THAN(NSFoundationVersionNumber_iOS_8_0))
        {
            [[ClutchPrint sharedInstance] print:@"You need iOS 8.0+ to use Clutch %@", CLUTCH_VERSION];

            return 0;
        }

        [[ClutchPrint sharedInstance] setColorLevel:ClutchPrinterColorLevelFull];
        [[ClutchPrint sharedInstance] setVerboseLevel:ClutchPrinterVerboseLevelNone];

        BOOL dumpedFramework = NO;
        BOOL successfullyDumpedFramework = NO;
        NSString *_selectedBundleID;

        NSArray *arguments = [[NSProcessInfo processInfo] arguments];

        ClutchCommands *commands = [[ClutchCommands alloc] initWithArguments:arguments];

        NSArray *values;

        if (commands.commands)
        {
            for (ClutchCommand *command in commands.commands)
            {
                // Switch flags
                switch (command.flag) {
                    case ClutchCommandFlagArgumentRequired:
                    {
                        values = commands.values;
                    }
                    default:
                        break;
                }

                // Switch optionals
                switch (command.option)
                {
                    case ClutchCommandOptionNoColor:
                        [[ClutchPrint sharedInstance] setColorLevel:ClutchPrinterColorLevelNone];
                        break;
                    case ClutchCommandOptionVerbose:
                        [[ClutchPrint sharedInstance] setVerboseLevel:ClutchPrinterVerboseLevelFull];
                        break;
                    default:
                        break;
                }

                switch (command.option) {
                    case ClutchCommandOptionNone:
                    {
                        [[ClutchPrint sharedInstance] print:@"%@", commands.helpString];
                        break;
                    }
                    case ClutchCommandOptionFrameworkDump:
                    {
                        NSArray *args = [NSProcessInfo processInfo].arguments;

                        if (([args[1] isEqualToString:@"--fmwk-dump"] || [args[1] isEqualToString:@"-f"]) && (args.count == 13))
                        {
                            FrameworkLoader *fmwk = [FrameworkLoader new];

                            fmwk.binPath = args[2];
                            fmwk.dumpPath = args[3];
                            fmwk.pages = [args[4] intValue];
                            fmwk.ncmds = [args[5] intValue];
                            fmwk.offset = [args[6] intValue];
                            fmwk.bID = args[7];
                            fmwk.hashOffset = [args[8] intValue];
                            fmwk.codesign_begin = [args[9] intValue];
                            fmwk.cryptsize = [args[10] intValue];
                            fmwk.cryptoff = [args[11] intValue];
                            fmwk.cryptlc_offset = [args[12] intValue];
                            fmwk.dumpSize = fmwk.cryptoff + fmwk.cryptsize;


                            BOOL result = successfullyDumpedFramework = [fmwk dumpBinary];

                            if (result)
                            {
                                [[ClutchPrint sharedInstance] printColor:ClutchPrinterColorPurple format:@"Successfully dumped framework %@!", fmwk.binPath.lastPathComponent];

                                // exit(0);
                                return 0;
                            }
                            else {
                                [[ClutchPrint sharedInstance] printColor:ClutchPrinterColorPurple format:@"Failed to dump framework %@ :(", fmwk.binPath.lastPathComponent];
                                // exit(1);
                                return 1;
                            }

                        }
                        else if (args.count != 13)
                        {
                            [[ClutchPrint sharedInstance] printError:@"Incorrect amount of arguments - see source if you're using this."];
                        }

                        break;
                    }
                    case ClutchCommandOptionBinaryDump:
                    case ClutchCommandOptionDump:
                    {
                        NSDictionary *_installedApps = [[[ApplicationsManager alloc] init] _allCachedApplications];
                        NSArray* _installedArray = _installedApps.allValues;

                        for (NSString* selection in values)
                        {
                            NSUInteger key;
                            Application *_selectedApp;

                            if (!(key = (NSUInteger)selection.integerValue))
                            {
                                [[ClutchPrint sharedInstance] printDeveloper:@"using bundle identifier"];
                                if (_installedApps[selection] == nil)
                                {
                                    [[ClutchPrint sharedInstance] print:@"Couldn't find installed app with bundle identifier: %@",_selectedBundleID];
                                    return 1;
                                }
                                else
                                {
                                    _selectedApp = _installedApps[selection];
                                }
                            }
                            else
                            {
                                [[ClutchPrint sharedInstance] printDeveloper:@"using number"];
                                key = key - 1;

                                if (key > [_installedArray count])
                                {
                                    [[ClutchPrint sharedInstance] print:@"Couldn't find app with corresponding number!?!"];
                                    return 1;
                                }
                                _selectedApp = [_installedArray objectAtIndex:key];

                            }

                            if (!_selectedApp)
                            {
                                [[ClutchPrint sharedInstance] print:@"Couldn't find installed app"];
                                return 1;
                            }

                            [[ClutchPrint sharedInstance] printVerbose:@"Now dumping %@", _selectedApp.bundleIdentifier];

                            if (_selectedApp.hasAppleWatchApp)
                            {
                                [[ClutchPrint sharedInstance] print:@"%@ contains watchOS 2 compatible application. It's not possible to dump watchOS 2 apps with Clutch %@ at this moment.",_selectedApp.bundleIdentifier,CLUTCH_VERSION];
                            }

                            // gAppPath = [_selectedApp.bundlePath stringByDeletingLastPathComponent];
                            _dyld_objc_notify_register(
                                [] (unsigned count, const char* const paths[], const struct mach_header* const mh[]) {},
                                [] (const char* path, const struct mach_header* mh) {},
                                [] (const char* path, const struct mach_header* mh) {}
                            );

                            gettimeofday(&gStart, NULL);
                            if (![_selectedApp dumpToDirectoryURL:nil onlyBinaries:command.option == ClutchCommandOptionBinaryDump]) {
                                return 1;
                            }
                        }
                        break;
                    }
                    case ClutchCommandOptionPrintInstalled:
                    {
                        listApps();
                        break;
                    }
                    case ClutchCommandOptionClean:
                    {
                        [[NSFileManager defaultManager]removeItemAtPath:@"/var/tmp/clutch" error:nil];
                        [[NSFileManager defaultManager]createDirectoryAtPath:@"/var/tmp/clutch" withIntermediateDirectories:YES attributes:nil error:nil];
                        break;
                    }
                    case ClutchCommandOptionVersion:
                    {
                        [[ClutchPrint sharedInstance] print:CLUTCH_VERSION];
                        break;
                    }
                    case ClutchCommandOptionHelp:
                    {
                        [[ClutchPrint sharedInstance] print:@"%@", commands.helpString];
                        break;
                    }
                    default:
                        // no command found.
                        break;
                }
            }
        }

        if (dumpedFramework) {
            fclose(stdin);
            fclose(stdout);
            fclose(stderr);

            if (successfullyDumpedFramework) {
                return 0;
            }
            return 1;
        }
    }

	return 0;
}

int main(int argc, const char * argv[])
{
    _exit(main2(argc, argv));
}

extern "C" void sha1(uint8_t *hash, uint8_t *data, size_t size)
{
    // SHA1Context context;
    // SHA1Reset(&context);
    // SHA1Input(&context, data, (unsigned)size);
    // SHA1Result(&context, hash);

    CC_SHA1(data, size, hash);
}

extern "C" void exit_with_errno (int err, const char *prefix)
{
    if (err)
    {
        fprintf (stderr,
                 "%s%s",
                 prefix ? prefix : "",
                 strerror(err));
        fclose(stdout);
        fclose(stderr);
        exit (err);
    }
}

extern "C" void _kill(pid_t pid)
{
    dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        int result;
        waitpid(pid, &result, 0);
        waitpid(pid, &result, 0);
        kill(pid, SIGKILL); //just in case;
    });

    kill(pid, SIGCONT);
    kill(pid, SIGKILL);
}
