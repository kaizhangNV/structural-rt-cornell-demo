#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <numeric>
#include <slang-com-ptr.h>
#include <slang.h>
#include <stdexcept>
#include <string>
#include <vector>

using Slang::ComPtr;

namespace
{

struct Case
{
    std::string name;
    std::string searchPath;
    std::string module;
    bool experimental = false;
    std::vector<double> wallSamples;
    std::vector<double> slangSamples;
    std::vector<double> downstreamSamples;
    size_t codeSize = 0;
};

struct Entry
{
    std::string name;
    SlangStage stage;
};

struct Options
{
    std::string target;
    std::string output;
    std::string compilerLabel;
    std::string hostLabel;
    uint32_t warmupCount = 3;
    uint32_t iterationCount = 20;
    std::vector<Case> cases;
    std::vector<Entry> entries;
};

void printDiagnostics(slang::IBlob* diagnostics)
{
    if (diagnostics && diagnostics->getBufferSize())
        std::fprintf(stderr, "%s", static_cast<const char*>(diagnostics->getBufferPointer()));
}

void check(SlangResult result, slang::IBlob* diagnostics, const char* operation)
{
    printDiagnostics(diagnostics);
    if (SLANG_FAILED(result))
    {
        char message[160];
        std::snprintf(
            message,
            sizeof(message),
            "%s (SlangResult 0x%08x)",
            operation,
            unsigned(result));
        throw std::runtime_error(message);
    }
}

SlangStage parseStage(const char* value)
{
    if (std::strcmp(value, "raygeneration") == 0)
        return SLANG_STAGE_RAY_GENERATION;
    if (std::strcmp(value, "closesthit") == 0)
        return SLANG_STAGE_CLOSEST_HIT;
    if (std::strcmp(value, "anyhit") == 0)
        return SLANG_STAGE_ANY_HIT;
    if (std::strcmp(value, "intersection") == 0)
        return SLANG_STAGE_INTERSECTION;
    if (std::strcmp(value, "miss") == 0)
        return SLANG_STAGE_MISS;
    if (std::strcmp(value, "callable") == 0)
        return SLANG_STAGE_CALLABLE;
    throw std::runtime_error(std::string("unknown entry-point stage: ") + value);
}

Options parseOptions(int argc, char** argv)
{
    Options options;
    for (int i = 1; i < argc; ++i)
    {
        const auto require = [&](int count)
        {
            if (i + count >= argc)
                throw std::runtime_error(std::string("missing value after ") + argv[i]);
        };
        if (std::strcmp(argv[i], "--target") == 0)
        {
            require(1);
            options.target = argv[++i];
        }
        else if (std::strcmp(argv[i], "--output") == 0)
        {
            require(1);
            options.output = argv[++i];
        }
        else if (std::strcmp(argv[i], "--compiler-label") == 0)
        {
            require(1);
            options.compilerLabel = argv[++i];
        }
        else if (std::strcmp(argv[i], "--host-label") == 0)
        {
            require(1);
            options.hostLabel = argv[++i];
        }
        else if (std::strcmp(argv[i], "--warmup") == 0)
        {
            require(1);
            options.warmupCount = uint32_t(std::stoul(argv[++i]));
        }
        else if (std::strcmp(argv[i], "--iterations") == 0)
        {
            require(1);
            options.iterationCount = uint32_t(std::stoul(argv[++i]));
        }
        else if (std::strcmp(argv[i], "--case") == 0)
        {
            require(4);
            Case value;
            value.name = argv[++i];
            value.searchPath = argv[++i];
            value.module = argv[++i];
            const std::string mode = argv[++i];
            if (mode == "experimental")
                value.experimental = true;
            else if (mode != "standard")
                throw std::runtime_error("case mode must be 'standard' or 'experimental'");
            options.cases.push_back(std::move(value));
        }
        else if (std::strcmp(argv[i], "--entry") == 0)
        {
            require(2);
            Entry entry;
            entry.name = argv[++i];
            entry.stage = parseStage(argv[++i]);
            options.entries.push_back(std::move(entry));
        }
        else
        {
            throw std::runtime_error(std::string("unknown argument: ") + argv[i]);
        }
    }
    if (options.target != "spirv" && options.target != "dxil" && options.target != "metal")
        throw std::runtime_error("--target must be spirv, dxil, or metal");
    if (options.output.empty() || options.cases.empty() || options.entries.empty())
        throw std::runtime_error(
            "--output, at least one --case, and at least one --entry are required");
    if (options.iterationCount == 0)
        throw std::runtime_error("--iterations must be greater than zero");
    return options;
}

struct CompileResult
{
    double wallMs = 0.0;
    double slangMs = 0.0;
    double downstreamMs = 0.0;
    size_t codeSize = 0;
};

CompileResult compileOnce(
    slang::IGlobalSession* globalSession,
    const Options& options,
    const Case& benchmarkCase)
{
    slang::CompilerOptionEntry targetOptions[2] = {};
    uint32_t targetOptionCount = 0;
    targetOptions[targetOptionCount].name = slang::CompilerOptionName::Optimization;
    targetOptions[targetOptionCount].value.kind = slang::CompilerOptionValueKind::Int;
    targetOptions[targetOptionCount++].value.intValue0 = SLANG_OPTIMIZATION_LEVEL_MAXIMAL;
    if (options.target == "spirv")
    {
        targetOptions[targetOptionCount].name = slang::CompilerOptionName::EmitSpirvDirectly;
        targetOptions[targetOptionCount].value.kind = slang::CompilerOptionValueKind::Int;
        targetOptions[targetOptionCount++].value.intValue0 = 1;
    }

    slang::TargetDesc target = {};
    target.format = options.target == "spirv"  ? SLANG_SPIRV
                    : options.target == "dxil" ? SLANG_DXIL
                                               : SLANG_METAL;
    if (options.target == "spirv")
        target.profile = globalSession->findProfile("spirv_1_5");
    else if (options.target == "dxil")
        target.profile = globalSession->findProfile("lib_6_6");
    target.compilerOptionEntries = targetOptions;
    target.compilerOptionEntryCount = targetOptionCount;

    slang::CompilerOptionEntry sessionOption = {};
    if (benchmarkCase.experimental)
    {
        sessionOption.name = slang::CompilerOptionName::ExperimentalFeature;
        sessionOption.value.kind = slang::CompilerOptionValueKind::Int;
        sessionOption.value.intValue0 = 1;
    }
    const char* searchPaths[] = {benchmarkCase.searchPath.c_str()};
    slang::SessionDesc sessionDesc = {};
    sessionDesc.targets = &target;
    sessionDesc.targetCount = 1;
    sessionDesc.searchPaths = searchPaths;
    sessionDesc.searchPathCount = 1;
    sessionDesc.compilerOptionEntries = benchmarkCase.experimental ? &sessionOption : nullptr;
    sessionDesc.compilerOptionEntryCount = benchmarkCase.experimental ? 1 : 0;

    double totalBefore = 0.0;
    double downstreamBefore = 0.0;
    globalSession->getCompilerElapsedTime(&totalBefore, &downstreamBefore);
    const auto start = std::chrono::steady_clock::now();

    ComPtr<slang::ISession> session;
    check(
        globalSession->createSession(sessionDesc, session.writeRef()),
        nullptr,
        "create Slang session");
    ComPtr<slang::IBlob> diagnostics;
    ComPtr<slang::IModule> module(
        session->loadModule(benchmarkCase.module.c_str(), diagnostics.writeRef()));
    printDiagnostics(diagnostics);
    if (!module)
        throw std::runtime_error("load Slang module");

    std::vector<ComPtr<slang::IEntryPoint>> entryPoints;
    std::vector<slang::IComponentType*> components = {module};
    for (const auto& entry : options.entries)
    {
        ComPtr<slang::IEntryPoint> entryPoint;
        diagnostics.setNull();
        check(
            module->findAndCheckEntryPoint(
                entry.name.c_str(),
                entry.stage,
                entryPoint.writeRef(),
                diagnostics.writeRef()),
            diagnostics,
            entry.name.c_str());
        entryPoints.push_back(entryPoint);
        components.push_back(entryPoint);
    }

    ComPtr<slang::IComponentType> composed;
    diagnostics.setNull();
    check(
        session->createCompositeComponentType(
            components.data(),
            SlangInt(components.size()),
            composed.writeRef(),
            diagnostics.writeRef()),
        diagnostics,
        "compose program");
    ComPtr<slang::IComponentType> linked;
    diagnostics.setNull();
    check(composed->link(linked.writeRef(), diagnostics.writeRef()), diagnostics, "link program");
    size_t codeSize = 0;
    if (options.target == "dxil")
    {
        // D3D12 consumes a separate DXIL library for each ray-tracing entry point, and
        // slang-rhi obtains those libraries through getEntryPointCode(). Measure that same
        // downstream path. Whole-target DXIL extraction is not supported by every DXC/Slang
        // configuration on Windows.
        for (size_t i = 0; i < entryPoints.size(); ++i)
        {
            ComPtr<slang::IBlob> code;
            diagnostics.setNull();
            check(
                linked->getEntryPointCode(SlangInt(i), 0, code.writeRef(), diagnostics.writeRef()),
                diagnostics,
                options.entries[i].name.c_str());
            codeSize += code->getBufferSize();
        }
    }
    else
    {
        ComPtr<slang::IBlob> code;
        diagnostics.setNull();
        check(
            linked->getTargetCode(0, code.writeRef(), diagnostics.writeRef()),
            diagnostics,
            "generate target code");
        codeSize = code->getBufferSize();
    }

    const double wallMs =
        std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    double totalAfter = 0.0;
    double downstreamAfter = 0.0;
    globalSession->getCompilerElapsedTime(&totalAfter, &downstreamAfter);
    const double downstreamMs = (downstreamAfter - downstreamBefore) * 1000.0;
    if (options.target != "metal" && downstreamMs <= 0.0)
        throw std::runtime_error(
            "the requested downstream compiler did not report any elapsed time; "
            "check that its Slang plugin is built and discoverable");
    return {
        wallMs,
        std::max(0.0, wallMs - downstreamMs),
        downstreamMs,
        codeSize,
    };
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

std::string jsonEscape(const std::string& value)
{
    std::string result;
    for (const char ch : value)
    {
        if (ch == '\\' || ch == '"')
            result.push_back('\\');
        result.push_back(ch);
    }
    return result;
}

void writeArray(std::ostream& stream, const std::vector<double>& samples)
{
    stream << "[";
    for (size_t i = 0; i < samples.size(); ++i)
        stream << (i == 0 ? "" : ", ") << samples[i];
    stream << "]";
}

void writeMetric(
    std::ostream& stream,
    const char* name,
    const std::vector<double>& samples,
    bool trailingComma)
{
    const auto summary = summarize(samples);
    stream << "      \"" << name << "\": {\"summary\": {\"median\": " << summary.median
           << ", \"mean\": " << summary.mean << ", \"min\": " << summary.minimum
           << ", \"max\": " << summary.maximum << ", \"p95\": " << summary.p95
           << "}, \"samples\": ";
    writeArray(stream, samples);
    stream << "}" << (trailingComma ? "," : "") << "\n";
}

void writeOutput(const Options& options)
{
    std::ofstream stream(options.output);
    if (!stream)
        throw std::runtime_error("open benchmark output");
    stream << std::fixed << std::setprecision(9);
    stream << "{\n"
           << "  \"schema\": \"slang-ray-tracing-perf-v1\",\n"
           << "  \"kind\": \"compile\",\n"
           << "  \"target\": \"" << options.target << "\",\n"
           << "  \"compiler\": \"" << jsonEscape(options.compilerLabel) << "\",\n"
           << "  \"host\": \"" << jsonEscape(options.hostLabel) << "\",\n"
           << "  \"unit\": \"ms\",\n"
           << "  \"warmup_count\": " << options.warmupCount << ",\n"
           << "  \"sample_count\": " << options.iterationCount << ",\n"
           << "  \"measurement\": {\n"
           << "    \"total_wall_ms\": \"createSession through "
           << (options.target == "dxil" ? "all getEntryPointCode calls" : "getTargetCode")
           << "\",\n"
           << "    \"downstream_ms\": \"Slang IGlobalSession downstream timer delta\",\n"
           << "    \"slang_ms\": \"total wall time minus downstream timer delta\"\n"
           << "  },\n  \"cases\": [\n";
    for (size_t i = 0; i < options.cases.size(); ++i)
    {
        const auto& value = options.cases[i];
        stream << "    {\n"
               << "      \"name\": \"" << jsonEscape(value.name) << "\",\n"
               << "      \"code_size_bytes\": " << value.codeSize << ",\n";
        writeMetric(stream, "total_wall_ms", value.wallSamples, true);
        writeMetric(stream, "slang_ms", value.slangSamples, true);
        writeMetric(stream, "downstream_ms", value.downstreamSamples, false);
        stream << "    }" << (i + 1 == options.cases.size() ? "" : ",") << "\n";
    }
    stream << "  ]\n}\n";
}

int run(int argc, char** argv)
{
    auto options = parseOptions(argc, argv);
    SlangGlobalSessionDesc globalDesc = {};
    globalDesc.enableGLSL = false;
    ComPtr<slang::IGlobalSession> globalSession;
    check(
        slang_createGlobalSession2(&globalDesc, globalSession.writeRef()),
        nullptr,
        "create global Slang session");

    for (uint32_t warmup = 0; warmup < options.warmupCount; ++warmup)
        for (const auto& value : options.cases)
            compileOnce(globalSession, options, value);

    for (uint32_t iteration = 0; iteration < options.iterationCount; ++iteration)
    {
        for (size_t offset = 0; offset < options.cases.size(); ++offset)
        {
            // Rotate case order so persistent thermal/frequency drift does not always favor one
            // API.
            const size_t caseIndex = (offset + iteration) % options.cases.size();
            auto& value = options.cases[caseIndex];
            const auto result = compileOnce(globalSession, options, value);
            value.wallSamples.push_back(result.wallMs);
            value.slangSamples.push_back(result.slangMs);
            value.downstreamSamples.push_back(result.downstreamMs);
            value.codeSize = result.codeSize;
        }
    }
    writeOutput(options);
    for (const auto& value : options.cases)
    {
        const auto slang = summarize(value.slangSamples);
        const auto downstream = summarize(value.downstreamSamples);
        std::printf(
            "%s/%s: Slang median %.3f ms, downstream median %.3f ms (%u samples)\n",
            options.target.c_str(),
            value.name.c_str(),
            slang.median,
            downstream.median,
            options.iterationCount);
    }
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
        std::fprintf(stderr, "slang-compile-benchmark: %s\n", error.what());
        return 1;
    }
}
