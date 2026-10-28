# ==============================================================================
# Circuit Compilation & Setup Script for Windows PowerShell
# ==============================================================================
# Usage: ./compile_circuit.ps1 [-CircuitName circuit_name]
#   Defaults to the generic multi-predicate engine (generic_verifier).
#   Pass -CircuitName age_verifier to build the legacy single-purpose circuit.

param(
    [string]$CircuitName = "generic_verifier"
)

$ErrorActionPreference = "Stop"

$BuildDir = Join-Path $PSScriptRoot "..\build"
$MoproAssetsDir = Join-Path $PSScriptRoot "..\..\mopro\assets"
$MobileAssetsDir = Join-Path $PSScriptRoot "..\..\mobile\assets"
$PtauFile = Join-Path $BuildDir "powersOfTau28_hez_final_12.ptau"

Write-Host "=== [1/6] Creating build directories ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
New-Item -ItemType Directory -Force -Path $MoproAssetsDir | Out-Null
New-Item -ItemType Directory -Force -Path $MobileAssetsDir | Out-Null

Write-Host "=== [2/6] Compiling Circom Circuit ===" -ForegroundColor Cyan
$CircuitSrc = Join-Path $PSScriptRoot "..\src\$CircuitName.circom"
circom $CircuitSrc --r1cs --wasm --sym -o $BuildDir

Write-Host "=== [3/6] Acquiring BN254 Powers of Tau ceremony file ===" -ForegroundColor Cyan
if (-not (Test-Path $PtauFile)) {
    Write-Host "Local PTAU file not found. Generating local Powers of Tau (pot12) using SnarkJS..." -ForegroundColor Yellow
    $Pot12_0 = Join-Path $BuildDir "pot12_0000.ptau"
    $Pot12_1 = Join-Path $BuildDir "pot12_0001.ptau"

    npx snarkjs powersoftau new bn128 12 $Pot12_0 -v
    "local entropy contribution" | npx snarkjs powersoftau contribute $Pot12_0 $Pot12_1 --name="Local Contributor" -v
    npx snarkjs powersoftau prepare phase2 $Pot12_1 $PtauFile -v

    # Clean up intermediate pot files
    Remove-Item $Pot12_0 -ErrorAction SilentlyContinue
    Remove-Item $Pot12_1 -ErrorAction SilentlyContinue
    Write-Host "Successfully generated local PTAU file: $PtauFile" -ForegroundColor Green
} else {
    Write-Host "Using existing PTAU file: $PtauFile" -ForegroundColor Green
}

Write-Host "=== [4/6] Generating Initial Groth16 zkey ===" -ForegroundColor Cyan
$R1csFile = Join-Path $BuildDir "$CircuitName.r1cs"
$InitZkey = Join-Path $BuildDir "${CircuitName}_0000.zkey"
npx snarkjs groth16 setup $R1csFile $PtauFile $InitZkey

Write-Host "=== [5/6] Contributing Entropy for Phase 2 ===" -ForegroundColor Cyan
$FinalZkey = Join-Path $BuildDir "${CircuitName}_final.zkey"
"zk-MatchID Phase 2 random beacon" | npx snarkjs zkey contribute $InitZkey $FinalZkey --name="zk-MatchID Contributor" -v

Write-Host "=== [6/6] Exporting Verification Key JSON ===" -ForegroundColor Cyan
$VKey = Join-Path $BuildDir "verification_key.json"
npx snarkjs zkey export verificationkey $FinalZkey $VKey
Copy-Item $VKey -Destination (Join-Path $MobileAssetsDir "verification_key.json") -Force

Write-Host "=== Copying assets to Mopro engine assets directory ===" -ForegroundColor Cyan
Copy-Item $R1csFile -Destination $MoproAssetsDir -Force
Copy-Item $FinalZkey -Destination $MoproAssetsDir -Force
Copy-Item $VKey -Destination $MoproAssetsDir -Force

# Copy the JS/WASM directory containing generic_verifier.wasm
$WasmDir = Join-Path $BuildDir "${CircuitName}_js"
$WasmFile = Join-Path $WasmDir "$CircuitName.wasm"

if (Test-Path $WasmFile) {
    Copy-Item $WasmFile -Destination $MoproAssetsDir -Force
    Write-Host "Copied $CircuitName.wasm to $MoproAssetsDir" -ForegroundColor Green
} else {
    Write-Error "Could not find WASM file at $WasmFile"
}
