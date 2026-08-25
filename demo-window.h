#pragma once

#define GLFW_INCLUDE_NONE
#if defined(__APPLE__)
#define GLFW_EXPOSE_NATIVE_COCOA
#elif defined(_WIN32)
#define GLFW_EXPOSE_NATIVE_WIN32
#else
#define GLFW_EXPOSE_NATIVE_X11
#endif
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <stdexcept>

#if defined(None)
#undef None
#endif
#if defined(Bool)
#undef Bool
#endif

struct WindowInput
{
    bool forward;
    bool backward;
    bool left;
    bool right;
    bool down;
    bool up;
    float mouseDeltaX;
    float mouseDeltaY;
};

class DemoWindow
{
public:
    DemoWindow(const char* title, uint32_t width, uint32_t height)
    {
        glfwSetErrorCallback(
            [](int, const char* description)
            {
                if (description)
                    std::fprintf(stderr, "GLFW: %s\n", description);
            });
        if (!glfwInit())
            throw std::runtime_error("initialize GLFW");
        glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
        m_window = glfwCreateWindow(int(width), int(height), title, nullptr, nullptr);
        if (!m_window)
        {
            glfwTerminate();
            throw std::runtime_error("create GLFW window");
        }
    }

    ~DemoWindow()
    {
        if (m_window)
            glfwDestroyWindow(m_window);
        glfwTerminate();
    }

    bool poll(WindowInput& input)
    {
        glfwPollEvents();
        if (glfwGetKey(m_window, GLFW_KEY_ESCAPE) == GLFW_PRESS)
            glfwSetWindowShouldClose(m_window, GLFW_TRUE);

        input = {};
        input.forward = glfwGetKey(m_window, GLFW_KEY_W) == GLFW_PRESS;
        input.backward = glfwGetKey(m_window, GLFW_KEY_S) == GLFW_PRESS;
        input.left = glfwGetKey(m_window, GLFW_KEY_A) == GLFW_PRESS;
        input.right = glfwGetKey(m_window, GLFW_KEY_D) == GLFW_PRESS;
        input.down = glfwGetKey(m_window, GLFW_KEY_Q) == GLFW_PRESS;
        input.up = glfwGetKey(m_window, GLFW_KEY_E) == GLFW_PRESS;

        double mouseX = 0.0;
        double mouseY = 0.0;
        glfwGetCursorPos(m_window, &mouseX, &mouseY);
        const bool dragging = glfwGetMouseButton(m_window, GLFW_MOUSE_BUTTON_LEFT) == GLFW_PRESS;
        if (dragging && m_dragging)
        {
            input.mouseDeltaX = float(mouseX - m_lastMouseX);
            input.mouseDeltaY = float(mouseY - m_lastMouseY);
        }
        m_dragging = dragging;
        m_lastMouseX = mouseX;
        m_lastMouseY = mouseY;
        return !glfwWindowShouldClose(m_window);
    }

    void getFramebufferSize(uint32_t& width, uint32_t& height) const
    {
        int framebufferWidth = 0;
        int framebufferHeight = 0;
        glfwGetFramebufferSize(m_window, &framebufferWidth, &framebufferHeight);
        width = uint32_t(std::max(framebufferWidth, 0));
        height = uint32_t(std::max(framebufferHeight, 0));
    }

#if defined(__APPLE__)
    void* nativeWindow() const { return glfwGetCocoaWindow(m_window); }
#elif defined(_WIN32)
    void* nativeWindow() const { return glfwGetWin32Window(m_window); }
#else
    void* nativeDisplay() const { return glfwGetX11Display(); }
    uint32_t nativeWindow() const { return uint32_t(glfwGetX11Window(m_window)); }
#endif

private:
    GLFWwindow* m_window = nullptr;
    bool m_dragging = false;
    double m_lastMouseX = 0.0;
    double m_lastMouseY = 0.0;
};
