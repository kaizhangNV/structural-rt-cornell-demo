#include "program-schema-reflection.h"

#include <slang-com-ptr.h>
#include <slang.h>

#include <algorithm>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

using Slang::ComPtr;

namespace
{

struct StageDesc
{
    std::string sourceName;
    std::string entryPointName;
    SlangStage stage = SLANG_STAGE_NONE;
};

void printDiagnostics(slang::IBlob* diagnostics)
{
    if (!diagnostics || !diagnostics->getBufferPointer() || diagnostics->getBufferSize() == 0)
        return;
    std::cerr.write(
        static_cast<const char*>(diagnostics->getBufferPointer()),
        std::streamsize(diagnostics->getBufferSize()));
    if (static_cast<const char*>(diagnostics->getBufferPointer())
            [diagnostics->getBufferSize() - 1] != '\n')
        std::cerr << '\n';
}

void checkResult(SlangResult result, slang::IBlob* diagnostics, const char* operation)
{
    printDiagnostics(diagnostics);
    if (SLANG_FAILED(result))
        throw std::runtime_error(operation);
}

void addStage(
    std::vector<StageDesc>& stages,
    const ReflectedStage& reflectedStage,
    SlangStage stage)
{
    if (reflectedStage.sourceName.empty())
        return;

    auto existing = std::find_if(
        stages.begin(),
        stages.end(),
        [&](const StageDesc& value)
        {
            return value.sourceName == reflectedStage.sourceName && value.stage == stage;
        });
    if (existing != stages.end())
    {
        if (!existing->entryPointName.empty() && !reflectedStage.entryPointName.empty() &&
            existing->entryPointName != reflectedStage.entryPointName)
            throw std::runtime_error(
                "one structural source stage reflects multiple target entry-point names");
        if (existing->entryPointName.empty())
            existing->entryPointName = reflectedStage.entryPointName;
        return;
    }
    stages.push_back({reflectedStage.sourceName, reflectedStage.entryPointName, stage});
}

std::vector<StageDesc> collectStages(const ReflectedProgramSchema& schema)
{
    std::vector<StageDesc> stages;
    for (const auto& payload : schema.payloads)
    {
        for (const auto& group : payload.hitGroups)
        {
            addStage(stages, group.closestHit, SLANG_STAGE_CLOSEST_HIT);
            addStage(stages, group.anyHit, SLANG_STAGE_ANY_HIT);
            addStage(stages, group.intersection, SLANG_STAGE_INTERSECTION);
        }
        for (const auto& shader : payload.missShaders)
            addStage(stages, shader.stage, SLANG_STAGE_MISS);
    }
    for (const auto& shader : schema.callableShaders)
        addStage(stages, shader.stage, SLANG_STAGE_CALLABLE);
    return stages;
}

std::string writeBlob(const char* path, slang::IBlob* blob)
{
    if (!blob)
        throw std::runtime_error("Metal code generation returned no output blob");
    std::ofstream stream(path, std::ios::binary);
    if (!stream)
        throw std::runtime_error(std::string("open Metal output: ") + path);
    std::string text(
        static_cast<const char*>(blob->getBufferPointer()),
        blob->getBufferSize());
    while (!text.empty() && (text.back() == '\n' || text.back() == '\r'))
        text.pop_back();
    text.push_back('\n');
    stream.write(text.data(), std::streamsize(text.size()));
    if (!stream)
        throw std::runtime_error(std::string("write Metal output: ") + path);
    return text;
}

} // namespace

int main(int argc, char** argv)
{
    if (argc != 7 && argc != 8)
    {
        std::cerr << "usage: " << argv[0]
                  << " <shader-dir> <module> <raygen> <schema> <metal-output>"
                     " <manifest-output> [compiler-source-revision]\n";
        return 2;
    }

    const char* shaderDirectory = argv[1];
    const char* moduleName = argv[2];
    const char* rayGenerationName = argv[3];
    const char* schemaName = argv[4];
    const char* metalOutputPath = argv[5];
    const char* manifestOutputPath = argv[6];
    const char* compilerSourceRevision = argc == 8 ? argv[7] : "";

    try
    {
        ComPtr<slang::IGlobalSession> globalSession;
        checkResult(
            slang_createGlobalSession(SLANG_API_VERSION, globalSession.writeRef()),
            nullptr,
            "create Slang global session");

        slang::CompilerOptionEntry experimentalOption = {};
        experimentalOption.name = slang::CompilerOptionName::ExperimentalFeature;
        experimentalOption.value.kind = slang::CompilerOptionValueKind::Int;
        experimentalOption.value.intValue0 = 1;

        slang::TargetDesc target = {};
        target.format = SLANG_METAL;
        const auto metal31 = globalSession->findCapability("metallib_3_1");
        if (metal31 == SLANG_CAPABILITY_UNKNOWN)
            throw std::runtime_error("find Metal 3.1 target capability");
        slang::CompilerOptionEntry targetCapability = {};
        targetCapability.name = slang::CompilerOptionName::Capability;
        targetCapability.value.kind = slang::CompilerOptionValueKind::Int;
        targetCapability.value.intValue0 = int32_t(metal31);
        target.compilerOptionEntries = &targetCapability;
        target.compilerOptionEntryCount = 1;

        const char* searchPaths[] = {shaderDirectory};
        slang::SessionDesc sessionDesc = {};
        sessionDesc.targets = &target;
        sessionDesc.targetCount = 1;
        sessionDesc.searchPaths = searchPaths;
        sessionDesc.searchPathCount = 1;
        sessionDesc.compilerOptionEntries = &experimentalOption;
        sessionDesc.compilerOptionEntryCount = 1;

        ComPtr<slang::ISession> session;
        checkResult(
            globalSession->createSession(sessionDesc, session.writeRef()),
            nullptr,
            "create Metal Slang session");

        ComPtr<slang::IBlob> diagnostics;
        ComPtr<slang::IModule> module(
            session->loadModule(moduleName, diagnostics.writeRef()));
        printDiagnostics(diagnostics);
        if (!module)
            throw std::runtime_error(std::string("load Slang module: ") + moduleName);

        diagnostics.setNull();
        auto preliminaryLayout = module->getLayout(0, diagnostics.writeRef());
        printDiagnostics(diagnostics);
        if (!preliminaryLayout)
            throw std::runtime_error("reflect preliminary Slang module layout");
        auto preliminarySchema = reflectProgramSchema(preliminaryLayout, schemaName);
        auto stages = collectStages(preliminarySchema);

        std::vector<ComPtr<slang::IComponentType>> selectedEntryPoints;
        std::vector<slang::IComponentType*> components;
        components.push_back(module);

        diagnostics.setNull();
        ComPtr<slang::IEntryPoint> rayGeneration;
        auto result = module->findAndCheckEntryPoint(
            rayGenerationName,
            SLANG_STAGE_RAY_GENERATION,
            rayGeneration.writeRef(),
            diagnostics.writeRef());
        checkResult(result, diagnostics, "find ray-generation entry point");
        selectedEntryPoints.push_back(ComPtr<slang::IComponentType>(rayGeneration.get()));
        components.push_back(rayGeneration);

        for (const auto& stage : stages)
        {
            diagnostics.setNull();
            ComPtr<slang::IEntryPoint> sourceEntryPoint;
            result = module->findAndCheckEntryPoint(
                stage.sourceName.c_str(),
                stage.stage,
                sourceEntryPoint.writeRef(),
                diagnostics.writeRef());
            checkResult(result, diagnostics, stage.sourceName.c_str());

            ComPtr<slang::IComponentType> selectedEntryPoint(sourceEntryPoint.get());
            if (!stage.entryPointName.empty())
            {
                selectedEntryPoint.setNull();
                result = sourceEntryPoint->renameEntryPoint(
                    stage.entryPointName.c_str(), selectedEntryPoint.writeRef());
                checkResult(result, nullptr, "rename structural stage entry point");
            }
            selectedEntryPoints.push_back(selectedEntryPoint);
            components.push_back(selectedEntryPoint);
        }

        diagnostics.setNull();
        ComPtr<slang::IComponentType> composedProgram;
        result = session->createCompositeComponentType(
            components.data(),
            SlangInt(components.size()),
            composedProgram.writeRef(),
            diagnostics.writeRef());
        checkResult(result, diagnostics, "compose Metal shader program");

        diagnostics.setNull();
        ComPtr<slang::IComponentType> linkedProgram;
        result = composedProgram->link(linkedProgram.writeRef(), diagnostics.writeRef());
        checkResult(result, diagnostics, "link Metal shader program");

        diagnostics.setNull();
        ComPtr<slang::IBlob> metalCode;
        result = linkedProgram->getEntryPointCode(
            0, 0, metalCode.writeRef(), diagnostics.writeRef());
        checkResult(result, diagnostics, "generate Metal ray-generation code");

        diagnostics.setNull();
        auto linkedLayout = linkedProgram->getLayout(0, diagnostics.writeRef());
        printDiagnostics(diagnostics);
        if (!linkedLayout)
            throw std::runtime_error("reflect linked Metal program layout");
        auto reflectedSchema = reflectProgramSchema(linkedLayout, schemaName);
        reflectedSchema.compilerBuildTag = globalSession->getBuildTagString();
        reflectedSchema.compilerSourceRevision = compilerSourceRevision;

        diagnostics.setNull();
        ComPtr<slang::IMetadata> targetMetadata;
        result = linkedProgram->getTargetMetadata(
            0, targetMetadata.writeRef(), diagnostics.writeRef());
        checkResult(result, diagnostics, "read Metal target metadata");
        if (!targetMetadata)
            throw std::runtime_error("Metal code generation returned no target metadata");
        auto structuralMetadata = static_cast<slang::IStructuralRayTracingMetadata*>(
            targetMetadata->castAs(slang::IStructuralRayTracingMetadata::getTypeGuid()));
        applyMetalTargetMetadata(reflectedSchema, structuralMetadata);

        const auto writtenMetalSource = writeBlob(metalOutputPath, metalCode);
        reflectedSchema.metalSourceByteCount = writtenMetalSource.size();
        reflectedSchema.metalSourceFnv1a64 =
            computeFnv1a64(writtenMetalSource.data(), writtenMetalSource.size());
        writeReflectedProgramSchema(manifestOutputPath, reflectedSchema);
        return 0;
    }
    catch (const std::exception& error)
    {
        std::cerr << "metal artifact generation failed: " << error.what() << '\n';
        return 1;
    }
}
