#!/bin/bash
set -e

# ==============================================================================
# Circuit Compilation & Setup Script for zk-MatchID
# ==============================================================================
# Usage: ./compile_circuit.sh [circuit_name]
#   Defaults to the generic multi-predicate engine (generic_verifier).
#   Pass e.g. `age_verifier` to build the legacy single-purpose circuit.

CIRCUIT_NAME="${1:-generic_verifier}"
BUILD_DIR="./build"
MOPRO_ASSETS_DIR="../mopro/assets"
MOBILE_ASSETS_DIR="../mobile/assets"
PTAU_URL="https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_12.ptau"
PTAU_FILE="$BUILD_DIR/powersOfTau28_hez_final_12.ptau"

echo "=== [1/6] Creating build directory ==="
mkdir -p "$BUILD_DIR"
mkdir -p "$MOPRO_ASSETS_DIR"
mkdir -p "$MOBILE_ASSETS_DIR"

echo "=== [2/6] Compiling Circom Circuit ==="
circom src/${CIRCUIT_NAME}.circom --r1cs --wasm --sym -o "$BUILD_DIR"

echo "=== [3/6] Acquiring BN254 Powers of Tau ceremony file ==="
if [ ! -f "$PTAU_FILE" ]; then
    echo "Downloading Powers of Tau file (degree 12)..."
    curl -L -o "$PTAU_FILE" "$PTAU_URL"
else
    echo "Using existing PTAU file: $PTAU_FILE"
fi

echo "=== [4/6] Generating Initial Groth16 zkey ==="
npx snarkjs groth16 setup "$BUILD_DIR/${CIRCUIT_NAME}.r1cs" "$PTAU_FILE" "$BUILD_DIR/${CIRCUIT_NAME}_0000.zkey"

echo "=== [5/6] Contributing Entropy for Phase 2 ==="
echo "zk-MatchID Phase 2 random beacon" | npx snarkjs zkey contribute "$BUILD_DIR/${CIRCUIT_NAME}_0000.zkey" "$BUILD_DIR/${CIRCUIT_NAME}_final.zkey" --name="zk-MatchID Contributor" -v

echo "=== [6/6] Exporting Verification Key JSON ==="
npx snarkjs zkey export verification_key "$BUILD_DIR/${CIRCUIT_NAME}_final.zkey" "$BUILD_DIR/verification_key.json"
cp "$BUILD_DIR/verification_key.json" "$MOBILE_ASSETS_DIR/verification_key.json"

echo "=== Copying assets to Mopro engine assets directory ==="
cp "$BUILD_DIR/${CIRCUIT_NAME}.r1cs" "$MOPRO_ASSETS_DIR/"
cp "$BUILD_DIR/${CIRCUIT_NAME}_final.zkey" "$MOPRO_ASSETS_DIR/"
cp "$BUILD_DIR/verification_key.json" "$MOPRO_ASSETS_DIR/"
cp "$BUILD_DIR/${CIRCUIT_NAME}_js/${CIRCUIT_NAME}.wasm" "$MOPRO_ASSETS_DIR/${CIRCUIT_NAME}.wasm"

echo ">>> Circuit compilation and Groth16 ceremony setup completed successfully!"
