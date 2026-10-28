#!/usr/bin/env bash
set -euo pipefail

MOPRO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOSITORY_ROOT="$(cd "$MOPRO_ROOT/.." && pwd)"
MOBILE_ROOT="$REPOSITORY_ROOT/mobile"
JNI_ROOT="$MOBILE_ROOT/android/app/src/main/jniLibs"
FRAMEWORK_ROOT="$MOBILE_ROOT/ios/Frameworks"

for artifact in \
  "$MOPRO_ROOT/assets/generic_verifier.r1cs" \
  "$MOPRO_ROOT/assets/generic_verifier_final.zkey" \
  "$MOPRO_ROOT/assets/verification_key.json"; do
  if [[ ! -f "$artifact" ]]; then
    printf 'Mopro cannot build mobile proofs. Missing circuit artifact: %s\n' "$artifact" >&2
    printf 'Build and audit the circuit-specific R1CS, proving key, and verification key first.\n' >&2
    exit 1
  fi
done

if ! command -v mopro >/dev/null 2>&1; then
  echo 'The Mopro CLI is required for a mobile build. A plain cargo build produces a host library and is not a mobile cross-build.' >&2
  exit 1
fi

cd "$MOPRO_ROOT"
mopro build --config mopro.toml

find_library() {
  local pattern="$1"
  find "$MOPRO_ROOT" "$MOBILE_ROOT" -type f -name 'libmopro_bindings.so' \
    ! -path "$JNI_ROOT/*" -print | grep -E "$pattern" | head -n 1 || true
}

declare -A ABI_PATTERNS=(
  [arm64-v8a]='/(arm64-v8a|aarch64-linux-android)/'
  [armeabi-v7a]='/(armeabi-v7a|armv7-linux-androideabi)/'
  [x86_64]='/(x86_64|x86_64-linux-android)/'
)

for abi in arm64-v8a armeabi-v7a x86_64; do
  library="$(find_library "${ABI_PATTERNS[$abi]}")"
  if [[ -z "$library" ]]; then
    printf 'Mopro did not produce libmopro_bindings.so for %s. No host library will be copied into an Android ABI folder.\n' "$abi" >&2
    exit 1
  fi
  mkdir -p "$JNI_ROOT/$abi"
  cp "$library" "$JNI_ROOT/$abi/libmopro_bindings.so"
done

framework="$(find "$MOPRO_ROOT" "$MOBILE_ROOT" -type d -name 'MoproBindings.xcframework' \
  ! -path "$FRAMEWORK_ROOT/*" -print -quit)"
if [[ -z "$framework" ]]; then
  echo 'Mopro did not produce MoproBindings.xcframework. No iOS framework was copied.' >&2
  exit 1
fi
mkdir -p "$FRAMEWORK_ROOT"
cp -R "$framework" "$FRAMEWORK_ROOT/"

echo 'Android libraries and iOS XCFramework packaged from Mopro platform outputs.'
