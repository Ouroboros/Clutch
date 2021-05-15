#import "ml/ml.h"

class ImageLoader
{
public:
    static void deleteImage(ImageLoader*);

public:
    void deleteImage();
};

class ImageLoaderMachO : public ImageLoader
{
public:
    static ImageLoaderMachO* instantiateFromFile(const char* path);

public:
    struct mach_header_64* machHeader();
};

int ImageLoader_Init(void* dyldBase);
