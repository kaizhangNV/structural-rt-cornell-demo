param(
    [string] $SlangRepo = (Join-Path $PSScriptRoot "../another-slang-rt-recovery"),
    [string] $SlangBuild = "",
    [ValidateSet("Debug", "Release", "RelWithDebInfo")]
    [string] $Config = "Release",
    [string] $Generator = "Visual Studio 17 2022",
    [string] $ResultsDir = (Join-Path $PSScriptRoot "perf-results/windows"),
    [string] $HostLabel = "",
    [uint32] $Warmup = 5,
    [uint32] $Iterations = 50
)

$ErrorActionPreference = "Stop"
$env:CMAKE_BUILD_PARALLEL_LEVEL = "8"
$env:CL_MPCount = "8"

if (-not $SlangBuild) {
    $SlangBuild = Join-Path $SlangRepo "build"
}
$SlangRepo = (Resolve-Path $SlangRepo).Path
$SlangBuild = (Resolve-Path $SlangBuild).Path
New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null
$ResultsDir = (Resolve-Path $ResultsDir).Path
if (-not $HostLabel) {
    $ProcessorNames = (Get-CimInstance Win32_Processor | Select-Object -ExpandProperty Name) -join ", "
    $HostLabel = "$([System.Environment]::OSVersion.VersionString); $ProcessorNames"
}

& (Join-Path $PSScriptRoot "run-windows.ps1") `
    -SlangRepo $SlangRepo `
    -SlangBuild $SlangBuild `
    -Config $Config `
    -Generator $Generator `
    -Api structural `
    -Headless `
    -Output (Join-Path $ResultsDir "cornell-structural.ppm")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $PSScriptRoot "run-windows.ps1") `
    -SlangRepo $SlangRepo `
    -SlangBuild $SlangBuild `
    -Config $Config `
    -Generator $Generator `
    -Api legacy `
    -Headless `
    -Output (Join-Path $ResultsDir "cornell-legacy.ppm")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$StructuralHash = (Get-FileHash (Join-Path $ResultsDir "cornell-structural.ppm") -Algorithm SHA256).Hash
$LegacyHash = (Get-FileHash (Join-Path $ResultsDir "cornell-legacy.ppm") -Algorithm SHA256).Hash
if ($StructuralHash -ne $LegacyHash) {
    throw "structural and legacy renders differ"
}

$BuildDir = Join-Path $PSScriptRoot "build/windows"
$Compiler = Join-Path $BuildDir "$Config/slang-compile-benchmark.exe"
$SavedErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$SlangVersionLines = & (Join-Path $SlangBuild "$Config/bin/slangc.exe") -version 2>&1
$SlangVersionExitCode = $LASTEXITCODE
$ErrorActionPreference = $SavedErrorActionPreference
if ($SlangVersionExitCode -ne 0) { exit $SlangVersionExitCode }
$SlangVersion = (($SlangVersionLines | ForEach-Object { $_.ToString() }) | Out-String).Trim()
$SlangCommit = ((& git.exe -C $SlangRepo rev-parse --short=12 HEAD) | Out-String).Trim()
$CommonCompilerArguments = @(
    "--target", "dxil",
    "--output", (Join-Path $ResultsDir "compile-dxil.json"),
    "--compiler-label", "$SlangVersion; source $SlangCommit",
    "--host-label", $HostLabel,
    "--warmup", $Warmup,
    "--iterations", $Iterations,
    "--case", "structural", (Join-Path $PSScriptRoot "shaders"), "rt_pipeline", "experimental",
    "--case", "legacy", (Join-Path $PSScriptRoot "shaders-legacy"), "rt_pipeline", "standard",
    "--entry", "RayGeneration", "raygeneration",
    "--entry", "PrimaryClosestHit", "closesthit",
    "--entry", "ShadowClosestHit", "closesthit",
    "--entry", "PrimaryMiss", "miss",
    "--entry", "ShadowMiss", "miss"
)
& $Compiler @CommonCompilerArguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

foreach ($Api in @("structural", "legacy")) {
    & (Join-Path $PSScriptRoot "run-windows.ps1") `
        -SlangRepo $SlangRepo `
        -SlangBuild $SlangBuild `
        -Config $Config `
        -Generator $Generator `
        -Api $Api `
        -Benchmark `
        -BenchmarkOutput (Join-Path $ResultsDir "runtime-d3d12-$Api.json") `
        -Warmup $Warmup `
        -Iterations $Iterations
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Get-ChildItem $ResultsDir -Filter "*.json" | Sort-Object Name | ForEach-Object {
    Write-Output "PERF_RESULT_BEGIN $($_.Name)"
    Get-Content $_.FullName
    Write-Output "PERF_RESULT_END $($_.Name)"
}
