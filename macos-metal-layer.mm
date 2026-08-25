#include "macos-metal-layer.h"

#import <AppKit/AppKit.h>
#import <QuartzCore/CAMetalLayer.h>

void attachMetalLayerToWindow(void* nsWindow, void* metalLayer)
{
    NSWindow* window = (__bridge NSWindow*)nsWindow;
    NSView* view = [window contentView];
    [view setWantsLayer:YES];
    [view setLayer:(__bridge CAMetalLayer*)metalLayer];
}
