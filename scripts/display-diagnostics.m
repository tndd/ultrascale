#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>
// 読み取り専用。出力変更API・映像取得APIは呼ばない。
int main(void) { @autoreleasepool {
 void *lib = dlopen("/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/IOMobileFramebuffer", RTLD_LAZY);
 int (*openFB)(io_service_t,mach_port_t,uint32_t,void **) = dlsym(lib,"IOMobileFramebufferOpen");
 int (*getMode)(void *,uint32_t *,uint32_t *) = dlsym(lib,"IOMobileFramebufferGetDigitalOutMode");
 if(!openFB || !getMode) return 2;
 io_iterator_t iterator=0; if(IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOMobileFramebufferShim"),&iterator)) return 3;
 int failures=0, found=0;
 io_service_t service;
 while((service=IOIteratorNext(iterator))) {
  uint64_t registryID=0; IORegistryEntryGetRegistryEntryID(service,&registryID);
  CFTypeRef attrs=IORegistryEntryCreateCFProperty(service,CFSTR("DisplayAttributes"),kCFAllocatorDefault,0);
  if(attrs) {
   found++;
   void *connection=NULL; int opened=openFB(service,mach_task_self(),0,&connection);
   uint32_t timing=0,color=0; int read=opened ? opened : getMode(connection,&color,&timing);
   if(read)failures++;
   printf("registry=%llu open=0x%x read=0x%x timing=%u color=%u\n",registryID,opened,read,timing,color);
   if(!read){
    CFTypeRef modes=IORegistryEntryCreateCFProperty(service,CFSTR("ColorElements"),kCFAllocatorDefault,0);
    if(modes && CFGetTypeID(modes)==CFArrayGetTypeID()) for(NSDictionary *m in (__bridge NSArray*)modes) if([m[@"ID"] unsignedIntValue]==color)
     printf("current Depth=%s PixelEncoding=%s DynamicRange=%s Colorimetry=%s\n",[m[@"Depth"] description].UTF8String,[m[@"PixelEncoding"] description].UTF8String,[m[@"DynamicRange"] description].UTF8String,[m[@"Colorimetry"] description].UTF8String);
    if(modes)CFRelease(modes);
   }
   CFRelease(attrs);
  }
  IOObjectRelease(service);
 }
 IOObjectRelease(iterator);
 return failures || !found ? 1:0;
} }
