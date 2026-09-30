#pragma once

#include "scene.h"
#include <cstring>
#include <stdexcept>
#include <string>

namespace cornell
{
struct RenderSettings
{
    uint32_t samples = 64;
    uint32_t bounces = 8;
    uint32_t aoSamples = 8;
    uint32_t seed = 1;
    float exposure = 1.0f;
    float aoRadius = 0.5f;
    uint32_t viewMode = 0; // beauty, AO, direct lighting
    uint32_t sphereMode = 0; // glass, diffuse, none
    uint32_t width = kImageWidth;
    uint32_t height = kImageHeight;

    void apply(FrameData& frame, uint32_t samplesPerFrame, uint32_t sampleOffset) const
    {
        frame.samplesPerFrame = samplesPerFrame;
        frame.sampleOffset = sampleOffset;
        frame.maxBounces = bounces;
        frame.viewMode = viewMode;
        frame.exposure = exposure;
        frame.aoRadius = aoRadius;
        frame.aoSamples = aoSamples;
        frame.seed = seed;
    }
};

// Both hosts use this parser so deterministic comparisons use identical settings.
inline bool parseRenderArgument(int argc, char** argv, int& index, RenderSettings& settings)
{
    const std::string option = argv[index];
    if (option != "--samples" && option != "--bounces" && option != "--ao-samples" &&
        option != "--seed" && option != "--width" && option != "--height" &&
        option != "--exposure" && option != "--ao-radius" && option != "--view" &&
        option != "--sphere")
        return false;
    if (++index >= argc)
        throw std::runtime_error(option + " requires a value");
    const std::string value = argv[index];
    const auto integer = [&](uint32_t minimum, uint32_t maximum)
    {
        if (value.empty() || value.find_first_not_of("0123456789") != std::string::npos)
            throw std::runtime_error(option + " requires an unsigned integer");
        const auto number = std::stoull(value);
        if (number < minimum || number > maximum)
            throw std::runtime_error(option + " must be in [" + std::to_string(minimum) + ", " + std::to_string(maximum) + "]");
        return uint32_t(number);
    };
    const auto positiveFloat = [&]()
    {
        size_t end = 0;
        const float number = std::stof(value, &end);
        if (end != value.size() || !std::isfinite(number) || number <= 0 || number > 1000)
            throw std::runtime_error(option + " must be finite and in (0, 1000]");
        return number;
    };
    if (option == "--samples") settings.samples = integer(1, 65536);
    else if (option == "--bounces") settings.bounces = integer(1, 64);
    else if (option == "--ao-samples") settings.aoSamples = integer(1, 256);
    else if (option == "--seed") settings.seed = integer(0, UINT32_MAX);
    else if (option == "--width") settings.width = integer(1, 4096);
    else if (option == "--height") settings.height = integer(1, 4096);
    else if (option == "--exposure") settings.exposure = positiveFloat();
    else if (option == "--ao-radius") settings.aoRadius = positiveFloat();
    else if (option == "--view")
    {
        if (value == "beauty") settings.viewMode = 0;
        else if (value == "ao") settings.viewMode = 1;
        else if (value == "direct") settings.viewMode = 2;
        else throw std::runtime_error("--view must be beauty, ao, or direct");
    }
    else if (option == "--sphere")
    {
        if (value == "glass") settings.sphereMode = 0;
        else if (value == "diffuse") settings.sphereMode = 1;
        else if (value == "none") settings.sphereMode = 2;
        else throw std::runtime_error("--sphere must be glass, diffuse, or none");
    }
    return true;
}
} // namespace cornell
