#!/usr/bin/env bash
set -euo pipefail

toolchain=$(realpath -m "${1:?toolchain directory is required}")
repository=$(cd "$(dirname "$0")/.." && pwd)
bootstrap=$(go env GOROOT)
if [ ! -x "$toolchain/bin/go" ]; then
  archive="$RUNNER_TEMP/go1.27.3.src.tar.gz"
  curl -fsSL --retry 3 https://go.dev/dl/go1.27.3.src.tar.gz -o "$archive"
  echo "6e7749035cf360f06b2575d162ea79df9fda8ef671889e5c375f8e50777f26bb  $archive" | sha256sum --check
  mkdir -p "$toolchain"
  tar -xzf "$archive" --strip-components=1 -C "$toolchain"
  test "$(head -n 1 "$toolchain/VERSION")" = go1.27.3
  git -C "$toolchain" apply --check "$repository/.github/ohos-go1.27.patch"
  git -C "$toolchain" apply "$repository/.github/ohos-go1.27.patch"
  (cd "$toolchain/src" && env -u GOROOT GOROOT_BOOTSTRAP="$bootstrap" GOTOOLCHAIN=local ./make.bash)
fi
export GOROOT="$toolchain" GOTOOLCHAIN=local
"$toolchain/bin/go" version
"$toolchain/bin/go" tool dist list | grep -Fx openharmony/arm64
"$toolchain/bin/go" test cmd/internal/obj/arm64 cmd/internal/objabi internal/platform

compiler="${OHOS_NDK_HOME:?OHOS_NDK_HOME is required}/native/llvm/bin/aarch64-unknown-linux-ohos-clang"
if [ ! -x "$compiler" ]; then
  cat > "$compiler" <<'EOF'
#!/bin/sh
exec "$(dirname "$0")/clang" --target=aarch64-linux-ohos --sysroot="$(dirname "$0")/../../sysroot" -D__MUSL__ "$@"
EOF
  chmod +x "$compiler"
fi
printf 'GOROOT=%s\nGOTOOLCHAIN=local\n' "$toolchain" >> "$GITHUB_ENV"
printf '%s/bin\n' "$toolchain" >> "$GITHUB_PATH"
