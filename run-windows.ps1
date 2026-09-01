param(
    [string] $SlangRepo = (Join-Path $PSScriptRoot "../another-slang-rt-recovery"),
    [string] $SlangBuild = "",
    [ValidateSet("Debug", "Release", "RelWithDebInfo")]
    [string] $Config = "Debug",
    [string] $Generator = "Visual Studio 17 2022",
    [ValidateSet("structural", "legacy")]
    [string] $Api = "structural",
    [switch] $Headless,
    [switch] $Benchmark,
    [string] $BenchmarkOutput = "",
    [uint32] $Warmup = 10,
    [uint32] $Iterations = 100,
    [string] $Output = "",
    [uint32] $Frames = 0
)

$ErrorActionPreference = "Stop"
$env:CMAKE_BUILD_PARALLEL_LEVEL = "8"

if (-not $SlangBuild) {
    $SlangBuild = Join-Path $SlangRepo "build"
}

$SlangRepo = (Resolve-Path $SlangRepo).Path
$SlangBuild = (Resolve-Path $SlangBuild).Path
$BuildDir = Join-Path $PSScriptRoot "build/windows"
$SlangConfigDir = Join-Path $SlangBuild $Config

& cmake.exe `
    -S $PSScriptRoot `
    -B $BuildDir `
    -G $Generator `
    -A x64 `
    "-DSLANG_REPO=$SlangRepo" `
    "-DSLANG_BUILD_CONFIG_DIR=$SlangConfigDir" `
    "-DCMAKE_C_FLAGS_INIT=/MP8" `
    "-DCMAKE_CXX_FLAGS_INIT=/MP8"
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

& cmake.exe --build $BuildDir --config $Config --target structural-rt-cornell-rhi slang-compile-benchmark --parallel 8
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$Arguments = @(
    (Join-Path $PSScriptRoot $(if ($Api -eq "legacy") { "shaders-legacy" } else { "shaders" })),
    "--backend", "d3d12",
    "--api", $Api
)
if ($Api -eq "structural") {
    $Arguments += @("--reflection-output", (Join-Path $PSScriptRoot "generated/program-layout.txt"))
}
if ($Headless) {
    $Arguments += "--headless"
}
if ($Benchmark) {
    $Arguments += @(
        "--benchmark",
        "--warmup", $Warmup,
        "--iterations", $Iterations,
        "--benchmark-output", $BenchmarkOutput
    )
}
if ($Output) {
    $Arguments += @("--output", $Output)
}
if ($Frames -ne 0) {
    $Arguments += @("--frames", $Frames)
}

$Executable = Join-Path $BuildDir "$Config/structural-rt-cornell-rhi.exe"
& $Executable @Arguments
exit $LASTEXITCODE
