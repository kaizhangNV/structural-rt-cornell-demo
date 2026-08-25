#pragma once

// GLFW owns the NSWindow. This bridge only installs the Metal-cpp layer on its
// content view.
void attachMetalLayerToWindow(void *nsWindow, void *metalLayer);
