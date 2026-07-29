#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Build and package a modern curl-impersonate bundle for Lightpanda.

Usage:
  scripts/build-curl-impersonate.sh --source <curl-impersonate> [options]

Options:
  --source DIR       curl-impersonate source checkout. Required unless
                     CURL_IMPERSONATE_SOURCE is set.
  --output DIR       Package output directory. Default: .curl-impersonate
  --build-dir DIR    CMake build directory. Default: .curl-impersonate-build
  --target NAME      Required browser target. Default: chrome136
  --jobs N           Parallel build jobs. Default: host CPU count
  --check            Only validate tools, source layout, and target support.
  -h, --help         Show this help.

The source must be the active CMake-based curl-impersonate fork that carries
modern targets such as chrome136/chrome145/chrome146. The legacy lwthiker
0.6.x layout tops out at chrome116 and is intentionally rejected for managed
Chimera production profiles.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

host_jobs() {
  if have nproc; then
    nproc
  elif have sysctl; then
    sysctl -n hw.ncpu
  else
    printf '4\n'
  fi
}

canonical_path() {
  local raw="$1"
  local parent
  local base

  parent="$(dirname "$raw")"
  base="$(basename "$raw")"
  if [[ -d "$parent" ]]; then
    printf '%s/%s\n' "$(cd "$parent" && pwd)" "$base"
  elif [[ "$raw" = /* ]]; then
    printf '%s\n' "$raw"
  else
    printf '%s/%s\n' "$(pwd)" "$raw"
  fi
}

display_path() {
  local raw="$1"

  if [[ "$raw" == "$REPO_ROOT"/* ]]; then
    printf '.%s\n' "${raw#"$REPO_ROOT"}"
  else
    printf '%s\n' "$raw"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SOURCE="${CURL_IMPERSONATE_SOURCE:-}"
OUTPUT="$REPO_ROOT/.curl-impersonate"
BUILD_DIR="$REPO_ROOT/.curl-impersonate-build"
TARGET="${CURL_IMPERSONATE_TARGET:-chrome136}"
JOBS="${JOBS:-$(host_jobs)}"
CHECK_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || die "--source requires a directory"
      SOURCE="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || die "--output requires a directory"
      OUTPUT="$2"
      shift 2
      ;;
    --build-dir)
      [[ $# -ge 2 ]] || die "--build-dir requires a directory"
      BUILD_DIR="$2"
      shift 2
      ;;
    --target)
      [[ $# -ge 2 ]] || die "--target requires a browser target"
      TARGET="$2"
      shift 2
      ;;
    --jobs)
      [[ $# -ge 2 ]] || die "--jobs requires a number"
      JOBS="$2"
      shift 2
      ;;
    --check)
      CHECK_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$SOURCE" ]] || die "missing --source <curl-impersonate>"
[[ "$JOBS" =~ ^[0-9]+$ ]] || die "--jobs must be a positive integer"
[[ "$JOBS" -gt 0 ]] || die "--jobs must be a positive integer"

SOURCE="$(cd "$SOURCE" && pwd)" || die "source directory not found: $SOURCE"
OUTPUT="$(canonical_path "$OUTPUT")"
BUILD_DIR="$(canonical_path "$BUILD_DIR")"

for tool in cmake ninja autoconf automake patch unzip curl go nm rsync perl python3 git; do
  have "$tool" || die "missing required tool: $tool"
done

if have gmake; then
  MAKE_TOOL="gmake"
elif have make; then
  MAKE_TOOL="make"
else
  die "missing required tool: gmake or make"
fi

if ! have glibtoolize && ! have libtoolize; then
  die "missing required GNU libtoolize tool: install libtool"
fi

[[ -f "$SOURCE/CMakeLists.txt" ]] || die "source is not the CMake superbuild layout: $SOURCE"
[[ -f "$SOURCE/patches/curl.patch" ]] || die "source is missing patches/curl.patch"
[[ ! -d "$SOURCE/chrome/patches" ]] ||
  die "legacy lwthiker layout detected; use lexiforest/curl-impersonate for modern Chimera targets"
[[ -x "$SOURCE/bin/curl_$TARGET" || -f "$SOURCE/bin/curl_$TARGET" ]] ||
  grep -q "\"$TARGET\"" "$SOURCE/patches/curl.patch" ||
  die "curl-impersonate source does not advertise target '$TARGET'"

LOCK_FILE="$REPO_ROOT/curl-impersonate.lock.json"
[[ -f "$LOCK_FILE" ]] || die "missing tracked source contract: $LOCK_FILE"
python3 "$SCRIPT_DIR/curl_impersonate_receipt.py" source \
  --lock "$LOCK_FILE" \
  --source "$SOURCE" \
  --target "$TARGET"

printf 'curl-impersonate source name: %s\n' "$(basename "$SOURCE")"
printf 'required target: %s\n' "$TARGET"
printf 'output: %s\n' "$(display_path "$OUTPUT")"
printf 'build dir: %s\n' "$(display_path "$BUILD_DIR")"
printf 'jobs: %s\n' "$JOBS"
printf 'make: %s\n' "$MAKE_TOOL"

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  printf 'preflight ok\n'
  exit 0
fi

if [[ -f "$BUILD_DIR/CMakeCache.txt" ]]; then
  rm -rf "$BUILD_DIR"
fi

WORK_SOURCE="$BUILD_DIR/source"
CMAKE_BUILD_DIR="$BUILD_DIR/cmake"
rm -rf "$WORK_SOURCE"
mkdir -p "$WORK_SOURCE"
rsync -a --delete --exclude '.git/' "$SOURCE/" "$WORK_SOURCE/"

if [[ "$(uname -s)" == "Darwin" ]]; then
  cmakelists="$WORK_SOURCE/CMakeLists.txt"
  perl -0pi -e 's/set\(_curl_idn_flags -DUSE_APPLE_IDN=ON -DUSE_LIBIDN2=OFF\)/set(_curl_idn_flags -DUSE_APPLE_IDN=OFF -DUSE_LIBIDN2=OFF)/' "$cmakelists"
  grep -q 'set(_curl_idn_flags -DUSE_APPLE_IDN=OFF -DUSE_LIBIDN2=OFF)' "$cmakelists" ||
    die "failed to disable Apple IDN in curl-impersonate source copy"
fi

cmake -S "$WORK_SOURCE" -B "$CMAKE_BUILD_DIR" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$CMAKE_BUILD_DIR/install" \
  -DUSE_LIBIDN2=OFF \
  -DCURL_CA_BUNDLE=auto

cmake --build "$CMAKE_BUILD_DIR" --target install-all --parallel "$JOBS"

DEPS_INSTALL="$CMAKE_BUILD_DIR/deps/install"
PREFIX="$CMAKE_BUILD_DIR/install"

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/lib" "$OUTPUT/include" "$OUTPUT/bin" "$OUTPUT/share"

curl_lib="$(find "$PREFIX/lib" -maxdepth 1 -type f -name 'libcurl-impersonate*.a' | sort | head -1)"
[[ -n "$curl_lib" ]] || die "missing libcurl-impersonate static archive in $PREFIX/lib"
cp "$curl_lib" "$OUTPUT/lib/libcurl-impersonate.a"

[[ -d "$PREFIX/include/curl" ]] || die "missing curl headers in $PREFIX/include"
cp -R "$PREFIX/include/curl" "$OUTPUT/include/"

for lib in \
  libssl.a \
  libcrypto.a \
  libnghttp2.a \
  libnghttp3.a \
  libngtcp2.a \
  libngtcp2_crypto_boringssl.a \
  libbrotlicommon.a \
  libbrotlidec.a \
  libbrotlienc.a \
  libz.a \
  libzstd.a
do
  [[ -f "$DEPS_INSTALL/lib/$lib" ]] || die "missing dependency library: $DEPS_INSTALL/lib/$lib"
  cp "$DEPS_INSTALL/lib/$lib" "$OUTPUT/lib/"
done

cp -R "$DEPS_INSTALL/include/." "$OUTPUT/include/"

if [[ -x "$PREFIX/bin/curl-impersonate" ]]; then
  cp "$PREFIX/bin/curl-impersonate" "$OUTPUT/bin/"
fi
if [[ -f "$PREFIX/bin/curl_$TARGET" ]]; then
  cp "$PREFIX/bin/curl_$TARGET" "$OUTPUT/bin/"
fi
[[ -f "$OUTPUT/bin/curl_$TARGET" && -x "$OUTPUT/bin/curl_$TARGET" ]] ||
  die "missing executable runtime wrapper: $OUTPUT/bin/curl_$TARGET"

python3 "$SCRIPT_DIR/curl_impersonate_receipt.py" write \
  --lock "$LOCK_FILE" \
  --source "$SOURCE" \
  --package "$OUTPUT" \
  --target "$TARGET"

nm_output="$(nm -g "$OUTPUT/lib/libcurl-impersonate.a")"
grep -Eq '(^|[[:space:]])_?curl_easy_impersonate([[:space:]]|$)' <<<"$nm_output" ||
  die "libcurl-impersonate.a does not export curl_easy_impersonate"

if [[ -x "$OUTPUT/bin/curl-impersonate" ]]; then
  version="$("$OUTPUT/bin/curl-impersonate" -V)"
  grep -q 'BoringSSL' <<<"$version" || die "curl-impersonate binary is missing BoringSSL"
  grep -q 'nghttp2' <<<"$version" || die "curl-impersonate binary is missing nghttp2"
  grep -q 'brotli' <<<"$version" || die "curl-impersonate binary is missing brotli"
  grep -q 'zstd' <<<"$version" || die "curl-impersonate binary is missing zstd"
  ! grep -q 'AppleIDN' <<<"$version" || die "curl-impersonate binary unexpectedly depends on Apple IDN"
fi

printf 'packaged curl-impersonate bundle:\n'
while IFS= read -r path; do
  display_path "$path"
done < <(find "$OUTPUT" -maxdepth 3 -type f | sort)
