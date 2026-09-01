#define NS_PRIVATE_IMPLEMENTATION
#define MTL_PRIVATE_IMPLEMENTATION

#include <Foundation/Foundation.hpp>
#include <Metal/Metal.hpp>
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <numeric>
#include <stdexcept>
#include <string>
#include <vector>

namespace
{

struct Case
{
    std::string name;
    std::string source;
    std::vector<double> samples;
};

struct Options
{
    std::string output;
    std::string hostLabel;
    uint32_t warmupCount = 3;
    uint32_t iterationCount = 20;
    std::vector<Case> cases;
};

std::string readTextFile(const char* path)
{
    std::ifstream stream(path, std::ios::binary);
    if (!stream)
        throw std::runtime_error(std::string("cannot open ") + path);
    return std::string(std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>());
}

Options parseOptions(int argc, char** argv)
{
    Options options;
    for (int i = 1; i < argc; ++i)
    {
        if (std::strcmp(argv[i], "--output") == 0 && i + 1 < argc)
            options.output = argv[++i];
        else if (std::strcmp(argv[i], "--host-label") == 0 && i + 1 < argc)
            options.hostLabel = argv[++i];
        else if (std::strcmp(argv[i], "--warmup") == 0 && i + 1 < argc)
            options.warmupCount = uint32_t(std::stoul(argv[++i]));
        else if (std::strcmp(argv[i], "--iterations") == 0 && i + 1 < argc)
            options.iterationCount = uint32_t(std::stoul(argv[++i]));
        else if (std::strcmp(argv[i], "--case") == 0 && i + 2 < argc)
        {
            Case value;
            value.name = argv[++i];
            value.source = readTextFile(argv[++i]);
            options.cases.push_back(std::move(value));
        }
        else
            throw std::runtime_error(std::string("unknown or incomplete argument: ") + argv[i]);
    }
    if (options.output.empty() || options.cases.empty())
        throw std::runtime_error("--output and at least one --case are required");
    if (options.iterationCount == 0)
        throw std::runtime_error("--iterations must be greater than zero");
    return options;
}

std::string errorMessage(NS::Error* error)
{
    return error && error->localizedDescription() ? error->localizedDescription()->utf8String()
                                                  : "unknown Metal error";
}

double compileOnce(MTL::Device* device, const Case& value, uint64_t nonce)
{
    // A unique comment prevents any source-hash cache from turning measured samples into lookups.
    const std::string source =
        value.source + "\n// slang-ray-tracing-perf nonce " + std::to_string(nonce) + "\n";
    auto sourceString = NS::String::string(source.c_str(), NS::UTF8StringEncoding);
    auto compileOptions = MTL::CompileOptions::alloc()->init();
    compileOptions->setLanguageVersion(MTL::LanguageVersion3_1);
    NS::Error* error = nullptr;
    const auto start = std::chrono::steady_clock::now();
    auto library = device->newLibrary(sourceString, compileOptions, &error);
    const double elapsed =
        std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    compileOptions->release();
    if (!library)
        throw std::runtime_error("compile Metal source: " + errorMessage(error));
    library->release();
    return elapsed;
}

struct Summary
{
    double median;
    double mean;
    double minimum;
    double maximum;
    double p95;
};

Summary summarize(const std::vector<double>& samples)
{
    auto sorted = samples;
    std::sort(sorted.begin(), sorted.end());
    const size_t p95Index =
        std::min(sorted.size() - 1, size_t(0.95 * double(sorted.size() - 1) + 0.5));
    return {
        sorted.size() % 2 == 0 ? (sorted[sorted.size() / 2 - 1] + sorted[sorted.size() / 2]) * 0.5
                               : sorted[sorted.size() / 2],
        std::accumulate(samples.begin(), samples.end(), 0.0) / samples.size(),
        sorted.front(),
        sorted.back(),
        sorted[p95Index],
    };
}

std::string jsonEscape(const char* value)
{
    std::string result;
    for (const char* cursor = value; *cursor; ++cursor)
    {
        if (*cursor == '\\' || *cursor == '"')
            result.push_back('\\');
        result.push_back(*cursor);
    }
    return result;
}

void writeOutput(const Options& options, MTL::Device* device)
{
    std::ofstream stream(options.output);
    if (!stream)
        throw std::runtime_error("open benchmark output");
    stream << std::fixed << std::setprecision(9);
    stream << "{\n"
           << "  \"schema\": \"slang-ray-tracing-perf-v1\",\n"
           << "  \"kind\": \"metal_downstream_compile\",\n"
           << "  \"target\": \"metal\",\n"
           << "  \"host\": \"" << jsonEscape(options.hostLabel.c_str()) << "\",\n"
           << "  \"device\": \"" << jsonEscape(device->name()->utf8String()) << "\",\n"
           << "  \"metric\": \"synchronous MTLDevice newLibrary(source) wall time\",\n"
           << "  \"unit\": \"ms\",\n"
           << "  \"warmup_count\": " << options.warmupCount << ",\n"
           << "  \"sample_count\": " << options.iterationCount << ",\n"
           << "  \"cache_control\": \"clock-seeded unique trailing source comment per sample\",\n"
           << "  \"cases\": [\n";
    for (size_t caseIndex = 0; caseIndex < options.cases.size(); ++caseIndex)
    {
        const auto& value = options.cases[caseIndex];
        const auto summary = summarize(value.samples);
        stream << "    {\"name\": \"" << jsonEscape(value.name.c_str())
               << "\", \"summary\": {\"median\": " << summary.median
               << ", \"mean\": " << summary.mean << ", \"min\": " << summary.minimum
               << ", \"max\": " << summary.maximum << ", \"p95\": " << summary.p95
               << "}, \"samples\": [";
        for (size_t sampleIndex = 0; sampleIndex < value.samples.size(); ++sampleIndex)
            stream << (sampleIndex == 0 ? "" : ", ") << value.samples[sampleIndex];
        stream << "]}" << (caseIndex + 1 == options.cases.size() ? "" : ",") << "\n";
    }
    stream << "  ]\n}\n";
}

int run(int argc, char** argv)
{
    auto options = parseOptions(argc, argv);
    auto pool = NS::AutoreleasePool::alloc()->init();
    auto device = MTL::CreateSystemDefaultDevice();
    if (!device)
        throw std::runtime_error("no Metal device is available");

    // Seed from the clock so a later invocation cannot reuse this invocation's persistent
    // compiler-cache entries. The counter still guarantees uniqueness within the process.
    uint64_t nonce = uint64_t(std::chrono::high_resolution_clock::now().time_since_epoch().count());
    for (uint32_t warmup = 0; warmup < options.warmupCount; ++warmup)
        for (const auto& value : options.cases)
            compileOnce(device, value, nonce++);
    for (uint32_t iteration = 0; iteration < options.iterationCount; ++iteration)
    {
        for (size_t offset = 0; offset < options.cases.size(); ++offset)
        {
            const size_t caseIndex = (offset + iteration) % options.cases.size();
            auto& value = options.cases[caseIndex];
            value.samples.push_back(compileOnce(device, value, nonce++));
        }
    }
    writeOutput(options, device);
    for (const auto& value : options.cases)
    {
        const auto summary = summarize(value.samples);
        std::printf(
            "metal/%s: downstream median %.3f ms, p95 %.3f ms (%u samples)\n",
            value.name.c_str(),
            summary.median,
            summary.p95,
            options.iterationCount);
    }
    device->release();
    pool->drain();
    return 0;
}

} // namespace

int main(int argc, char** argv)
{
    try
    {
        return run(argc, argv);
    }
    catch (const std::exception& error)
    {
        std::fprintf(stderr, "metal-compile-benchmark: %s\n", error.what());
        return 1;
    }
}
