#import "ml/ml.h"
#import "Rebase64BitMachO.h"
#import <sys/stat.h>
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import <sys/mman.h>
#import "ImageLoader.h"

// #define DbgLog NSLog

extern "C" void set_rpath(NSString* path)
{
    const char*             rpath;
    int                     rpath_len;
    uint8_t                 p[0x100];
    struct rpath_command*   lc;
    struct mach_header_64*  header;
    uint32_t                ncmds;
    uint32_t                cmdsize;

    header = (struct mach_header_64 *)_dyld_get_image_header(0);

    rpath = path.UTF8String;
    rpath_len = path.length;

    lc = (rpath_command *)p;

    cmdsize = sizeof(*lc) + rpath_len + 1;
    cmdsize = (cmdsize + 8) & ~7;

    lc->cmd = LC_RPATH;
    lc->cmdsize = cmdsize;
    lc->path.offset = sizeof(*lc);
    memcpy(lc + 1, rpath, rpath_len + 1);

    WriteProcessMemory(mach_task_self(), (uint8_t *)(header + 1) + header->sizeofcmds, lc, cmdsize);

    struct mach_header_64 hdr = *header;

    hdr.ncmds++;
    hdr.sizeofcmds += cmdsize;

    WriteProcessMemory(mach_task_self(), header, &hdr, sizeof(hdr));
}

extern "C" void* loadImageFromFile(NSString* path)
{
    ImageLoaderMachO* image = ImageLoaderMachO::instantiateFromFile(path.UTF8String);
    return image->machHeader();
}

uintptr_t ImageLoaderMachO_assignSegmentAddresses_Start;
uintptr_t ImageLoaderMachO_assignSegmentAddresses_End;

mach_header_64* (*ImageLoaderMachO_machHeader)(void* self);
const char* (*ImageLoader_getRealPath)(void* self);

BOOL callerIsAssignSegmentAddresses(void* caller)
{
    return (uintptr_t)caller > ImageLoaderMachO_assignSegmentAddresses_Start && (uintptr_t)caller < ImageLoaderMachO_assignSegmentAddresses_End;
}

MSHook(uintptr_t, ImageLoaderMachO_segSize, void* self, uint segIndex)
{
    uintptr_t size;
    BOOL fuckit;

    fuckit = callerIsAssignSegmentAddresses(__builtin_return_address(0));
    size = _ImageLoaderMachO_segSize(self, segIndex);

    if (fuckit)
    {
        if (segIndex == 0 && size == 0x100000000)
            size = 0;

        DbgLog(@"segSize %p @ %d", (void *)size, segIndex);
    }

    return size;
}

MSHook(uintptr_t, ImageLoaderMachO_segPreferredLoadAddress, void* self, uint segIndex)
{
    uintptr_t addr;
    BOOL fuckit;

    fuckit = callerIsAssignSegmentAddresses(__builtin_return_address(0));
    addr = _ImageLoaderMachO_segPreferredLoadAddress(self, segIndex);

    if (fuckit)
    {
        if (segIndex == 0 && addr == 0 && _ImageLoaderMachO_segSize(self, 0) == 0x100000000)
            addr = _ImageLoaderMachO_segPreferredLoadAddress(self, segIndex + 1);

        DbgLog(@"load addr %p @ %d", (void *)addr, segIndex);
    }

    return addr;
}

MSHook(uintptr_t, ImageLoaderMachO_reserveAnAddressRange, void* self, size_t length, void* context)
{
    uintptr_t base;

    DbgLog(@"address range = %p", (void *)length);

    return _ImageLoaderMachO_reserveAnAddressRange(self, length, context);

    // write code here may cause exception handler corrupt
}

// void find_syms_raw(const void *hdr, intptr_t * slide, const char ** names, void ** syms, size_t nsyms);

// void* MSFindSymbol2(MSImageRef image, const char* symbol)
// {
//     return MSFindSymbol2(image, symbol);

//     const char* names[] = { symbol };
//     void *syms[countof(names)];
//     intptr_t dyld_slide = -1;

//     find_syms_raw(image, &dyld_slide, names, syms, countof(names));

//     return syms[0];
// }

int fuckPageZero(void* dyldBase)
{
    void* ImageLoaderMachO_assignSegmentAddresses;
    // void* ImageLoaderMachO_reserveAnAddressRange;
    void* ImageLoaderMachO_segPreferredLoadAddress;
    void* ImageLoaderMachO_segSize;
    void* ImageLoaderMachO_doModInitFunctions;
    void* dyld_notifySingle;

    DbgLog(@"dyldBase = %p", (void *)dyldBase);

    // sleep(5);

    ImageLoaderMachO_assignSegmentAddresses     = MSFindSymbol2(dyldBase, "__ZN16ImageLoaderMachO22assignSegmentAddressesERKN11ImageLoader11LinkContextE");
    // ImageLoaderMachO_reserveAnAddressRange      = MSFindSymbol2(dyldBase, "__ZN16ImageLoaderMachO21reserveAnAddressRangeEmRKN11ImageLoader11LinkContextE");
    ImageLoaderMachO_segPreferredLoadAddress    = MSFindSymbol2(dyldBase, "__ZNK16ImageLoaderMachO23segPreferredLoadAddressEj");
    ImageLoaderMachO_segSize                    = MSFindSymbol2(dyldBase, "__ZNK16ImageLoaderMachO7segSizeEj");
    ImageLoaderMachO_doModInitFunctions         = MSFindSymbol2(dyldBase, "__ZN16ImageLoaderMachO18doModInitFunctionsERKN11ImageLoader11LinkContextE");
    dyld_notifySingle                           = MSFindSymbol2(dyldBase, "__ZN4dyldL12notifySingleE17dyld_image_statesPK11ImageLoaderPNS1_21InitializerTimingListE");

    *(void **)&ImageLoaderMachO_machHeader      = MSFindSymbol2(dyldBase, "__ZNK16ImageLoaderMachO10machHeaderEv");
    *(void **)&ImageLoader_getRealPath          = MSFindSymbol2(dyldBase, "__ZNK11ImageLoader11getRealPathEv");

    ImageLoaderMachO_assignSegmentAddresses_Start = (uintptr_t)ImageLoaderMachO_assignSegmentAddresses;
    ImageLoaderMachO_assignSegmentAddresses_End = ImageLoaderMachO_assignSegmentAddresses_Start;
    for (;;ImageLoaderMachO_assignSegmentAddresses_End += 4)
    {
        if (*(uint32_t *)ImageLoaderMachO_assignSegmentAddresses_End == 0xD65F03C0)     // ret
            break;
    }

    DbgLog(@"ImageLoaderMachO::assignSegmentAddresses       = %p", ImageLoaderMachO_assignSegmentAddresses);
    // DbgLog(@"ImageLoaderMachO::reserveAnAddressRange        = %p", ImageLoaderMachO_reserveAnAddressRange);
    DbgLog(@"ImageLoaderMachO::segPreferredLoadAddress      = %p", ImageLoaderMachO_segPreferredLoadAddress);
    DbgLog(@"ImageLoaderMachO::segSize                      = %p", ImageLoaderMachO_segSize);
    DbgLog(@"ImageLoaderMachO_assignSegmentAddresses_Start  = %p", (void *)ImageLoaderMachO_assignSegmentAddresses_Start);
    DbgLog(@"ImageLoaderMachO_assignSegmentAddresses_End    = %p", (void *)ImageLoaderMachO_assignSegmentAddresses_End);

    DbgLog(@"ImageLoaderMachO::doModInitFunctions           = %p", (void *)ImageLoaderMachO_doModInitFunctions);
    DbgLog(@"dyld::notifySingle                             = %p", (void *)dyld_notifySingle);

    // MSHookFunction(ImageLoaderMachO_assignSegmentAddresses,     MSHake2(ImageLoaderMachO_assignSegmentAddresses));
    MSHookFunction(ImageLoaderMachO_segPreferredLoadAddress,    MSHake2(ImageLoaderMachO_segPreferredLoadAddress));
    MSHookFunction(ImageLoaderMachO_segSize,                    MSHake2(ImageLoaderMachO_segSize));
    // MSHookFunction(ImageLoaderMachO_doModInitFunctions,         MSHake2(ImageLoaderMachO_doModInitFunctions));
    // MSHookFunction(dyld_notifySingle,                           MSHake2(dyld_notifySingle));

    // MSHookFunction(MSFindSymbol2(dyldBase, "__ZN11ImageLoader9setMappedERKNS_11LinkContextE"),   MSHake2(ImageLoader_setMapped));

    // MSHookFunction(ImageLoaderMachO_reserveAnAddressRange,      MSHake2(ImageLoaderMachO_reserveAnAddressRange));

    return 0;
}
