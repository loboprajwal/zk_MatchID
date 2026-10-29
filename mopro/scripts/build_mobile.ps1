$ErrorActionPreference = 'Stop'

$MoproRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$RepositoryRoot = (Resolve-Path (Join-Path $MoproRoot '..')).Path
$MobileRoot = Join-Path $RepositoryRoot 'mobile'
$JniRoot = Join-Path $MobileRoot 'android\app\src\main\jniLibs'
$FrameworkRoot = Join-Path $MobileRoot 'ios\Frameworks'

$RequiredArtifacts = @(
    (Join-Path $MoproRoot 'assets\generic_verifier.r1cs'),
    (Join-Path $MoproRoot 'assets\generic_verifier_final.zkey'),
    (Join-Path $MoproRoot 'assets\verification_key.json')
)
$MissingArtifacts = $RequiredArtifacts | Where-Object { -not (Test-Path -LiteralPath $_) }
if ($MissingArtifacts.Count -gt 0) {
    throw "Mopro cannot build mobile proofs. Missing circuit artifacts: $($MissingArtifacts -join ', '). Build and audit the circuit-specific R1CS, proving key, and verification key first."
}

if (-not (Get-Command mopro -ErrorAction SilentlyContinue)) {
    throw 'The Mopro CLI is required for a mobile build. A plain cargo build produces a host library and is not a mobile cross-build.'
}

Push-Location $MoproRoot
try {
    & mopro build --config mopro.toml
    if ($LASTEXITCODE -ne 0) {
        throw "Mopro build failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}

$Libraries = Get-ChildItem -LiteralPath $MoproRoot, $MobileRoot -Recurse -File -Filter 'libmopro_bindings.so' -ErrorAction SilentlyContinue
$AbiPatterns = @{
    'arm64-v8a' = '[\\/](arm64-v8a|aarch64-linux-android)[\\/]'
    'armeabi-v7a' = '[\\/](armeabi-v7a|armv7-linux-androideabi)[\\/]'
    'x86_64' = '[\\/](x86_64|x86_64-linux-android)[\\/]'
}

foreach ($Abi in $AbiPatterns.Keys) {
    $Library = $Libraries |
        Where-Object { $_.FullName -match $AbiPatterns[$Abi] } |
        Where-Object { $_.FullName -notlike "$JniRoot\*" } |
        Select-Object -First 1
    if ($null -eq $Library) {
        throw "Mopro did not produce libmopro_bindings.so for $Abi. No host library will be copied into an Android ABI folder."
    }
    $Destination = Join-Path (Join-Path $JniRoot $Abi) 'libmopro_bindings.so'
    New-Item -ItemType Directory -Force -Path (Split-Path $Destination) | Out-Null
    Copy-Item -LiteralPath $Library.FullName -Destination $Destination -Force
}

$Framework = Get-ChildItem -LiteralPath $MoproRoot, $MobileRoot -Recurse -Directory -Filter 'MoproBindings.xcframework' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notlike "$FrameworkRoot\*" } |
    Select-Object -First 1
if ($null -eq $Framework) {
    throw 'Mopro did not produce MoproBindings.xcframework. No iOS framework was copied.'
}
New-Item -ItemType Directory -Force -Path $FrameworkRoot | Out-Null
Copy-Item -LiteralPath $Framework.FullName -Destination $FrameworkRoot -Recurse -Force

Write-Host 'Android libraries and iOS XCFramework packaged from Mopro platform outputs.' -ForegroundColor Green
