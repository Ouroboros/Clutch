#import "ImageLoader.h"
#import <stdio.h>
#import <substrate.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <mach-o/swap.h>
#import <mach-o/ldsyms.h>
#import <sys/stat.h>

#define MAX_MACH_O_HEADER_AND_LOAD_COMMANDS_SIZE (32*1024)

static void* gLinkContext;
static mach_header_64* (*ImageLoaderMachO_machHeader)(ImageLoaderMachO* self);
static const char* (*ImageLoader_getRealPath)(ImageLoaderMachO* self);
static ImageLoaderMachO* (*ImageLoaderMachO_instantiateFromFile)(const char* path, int fd, const uint8_t firstPages[], size_t firstPagesSize, uint64_t offsetInFat, uint64_t lenInFat, const struct stat& info, void* context);
static void (*ImageLoader_deleteImage)(ImageLoader* self);

__attribute__((noreturn)) void throwf(const char* format, ...)
{
    va_list list;
    char*   p;

    va_start(list, format);
    vasprintf(&p, format, list);
    va_end(list);

    NSLog(@"%s", p);

    const char* t = p;
    throw t;
}

int ImageLoader_Init(void* dyldBase)
{
    *(void **)&gLinkContext                         = MSFindSymbol2(dyldBase, "__ZN4dyld12gLinkContextE");
    *(void **)&ImageLoaderMachO_machHeader          = MSFindSymbol2(dyldBase, "__ZNK16ImageLoaderMachO10machHeaderEv");
    *(void **)&ImageLoader_getRealPath              = MSFindSymbol2(dyldBase, "__ZNK11ImageLoader11getRealPathEv");
    *(void **)&ImageLoaderMachO_instantiateFromFile = MSFindSymbol2(dyldBase, "__ZN16ImageLoaderMachO19instantiateFromFileEPKciPKhmyyRK4statRKN11ImageLoader11LinkContextE");
    *(void **)&ImageLoader_deleteImage              = MSFindSymbol2(dyldBase, "__ZN11ImageLoader11deleteImageEPS_");

    return 0;
}

void ImageLoader::deleteImage(ImageLoader* image)
{
    ImageLoader_deleteImage(image);
}

void ImageLoader::deleteImage()
{
    ImageLoader::deleteImage(this);
}

ImageLoaderMachO* ImageLoaderMachO::instantiateFromFile(const char* path)
{
    int             fd;
    struct stat     statbuf;
    BOOL            shortPage;
    mach_header_64* header;
    uint32_t        headerAndLoadCommandsSize;
    uint64_t        fileOffset;
    uint64_t        fileLength;
    uint8_t         firstPages[MAX_MACH_O_HEADER_AND_LOAD_COMMANDS_SIZE];

    if (stat(path, &statbuf) != 0)
    {
        throwf("lstat64 failed: %s", strerror(errno));
        return nullptr;
    }

    fd = open(path, O_RDONLY, 0);

    fileOffset = 0;
    fileLength = statbuf.st_size;

    if (fileLength < 4096)
    {
        if (pread(fd, firstPages, fileLength, 0) != (ssize_t)fileLength)
        {
            throwf("pread of short file failed: %d", errno);
        }

        shortPage = true;
    }
    else
    {
        // optimistically read only first 4KB
        if (pread(fd, firstPages, 4096, 0) != 4096)
        {
            throwf("pread of first 4K failed: %d", errno);
        }
    }

    header = (mach_header_64 *)firstPages;
    if (header->magic != MH_MAGIC_64)
    {
        throwf("MH_MAGIC_64 only");
    }

    headerAndLoadCommandsSize = sizeof(*header) + header->sizeofcmds;

    if (headerAndLoadCommandsSize > MAX_MACH_O_HEADER_AND_LOAD_COMMANDS_SIZE)
        throwf("malformed mach-o: load commands size (%u) > %u", headerAndLoadCommandsSize, MAX_MACH_O_HEADER_AND_LOAD_COMMANDS_SIZE);

    if (headerAndLoadCommandsSize > fileLength)
        throwf("malformed mach-o: load commands size (%u) > mach-o file size (%llu)", headerAndLoadCommandsSize, fileLength);

    if ( headerAndLoadCommandsSize > 4096 ) {
        // read more pages
        unsigned readAmount = headerAndLoadCommandsSize - 4096;
        if (pread(fd, &firstPages[4096], readAmount, fileOffset+4096) != readAmount)
            throwf("pread of extra load commands past 4KB failed: %d", errno);
    }

    ImageLoaderMachO* image = ImageLoaderMachO_instantiateFromFile(
                                    path,
                                    fd,
                                    firstPages,
                                    headerAndLoadCommandsSize,
                                    fileOffset,
                                    fileLength,
                                    statbuf,
                                    gLinkContext
                                );

    if (image == nullptr)
        throwf("image = %p", image);

    return image;
}

struct mach_header_64* ImageLoaderMachO::machHeader()
{
    return ImageLoaderMachO_machHeader(this);
}
