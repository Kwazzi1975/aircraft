#!/usr/bin/env bash
# Host toolchain for Cloud Agents. The pinned ghcr.io/flybywiresim/dev-env image
# is private and expects Docker; this script installs the same compiler family
# directly so login shells can build and test without it.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  clang \
  cmake \
  curl \
  git \
  lld \
  pkg-config \
  python3 \
  rsync \
  xz-utils

if ! command -v wasm-opt >/dev/null 2>&1 || ! wasm-opt --version 2>/dev/null | grep -q 'version 130'; then
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/binaryen.tar.gz" \
    "https://github.com/WebAssembly/binaryen/releases/download/version_130/binaryen-version_130-x86_64-linux.tar.gz"
  tar -xzf "$tmp/binaryen.tar.gz" -C "$tmp"
  sudo install -m 755 "$tmp"/binaryen-version_130/bin/* /usr/local/bin/
  rm -rf "$tmp"
fi

if ! command -v wasm-ld >/dev/null 2>&1; then
  wasm_ld="$(command -v wasm-ld-18 || true)"
  if [[ -n "$wasm_ld" ]]; then
    sudo ln -sfn "$wasm_ld" /usr/local/bin/wasm-ld
  fi
fi

if ! command -v node >/dev/null 2>&1 || ! node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 22 ? 0 : 1)'; then
  curl -fsSL "https://nodejs.org/dist/v22.23.4/node-v22.23.4-linux-x64.tar.xz" \
    | sudo tar -xJ -C /usr/local --strip-components=1 --no-same-owner
fi

# Login shells do not load nvm, so pnpm must live on the default PATH.
if [[ ! -x /usr/local/bin/pnpm ]] || [[ "$(/usr/local/bin/pnpm -v)" != "10.33.4" ]]; then
  tmp="$(mktemp)"
  curl -fsSL -o "$tmp" "https://github.com/pnpm/pnpm/releases/download/v10.33.4/pnpm-linux-x64"
  sudo install -m 755 "$tmp" /usr/local/bin/pnpm
  rm -f "$tmp"
fi

if ! command -v rustup >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs \
    | sh -s -- -y --default-toolchain none --profile minimal
  for bin in rustup cargo rustc rustdoc rustfmt cargo-clippy rust-analyzer; do
    if [[ -x "$HOME/.cargo/bin/$bin" ]]; then
      sudo ln -sfn "$HOME/.cargo/bin/$bin" "/usr/local/bin/$bin"
    fi
  done
fi

# rust-toolchain.toml selects 1.96.0, rust-analyzer, and wasm32-wasip1.
rustup show
rustup component add rustfmt clippy
rustup target add wasm32-wasip1

/usr/local/bin/pnpm install --frozen-lockfile
cargo fetch
