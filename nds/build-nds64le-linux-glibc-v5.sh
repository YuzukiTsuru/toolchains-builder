#!/usr/bin/env bash
# Andes GNU Toolchain 5.2.2 — riscv64, rv64imac + Andes extensions, lp64.
set -euo pipefail

TOOLCHAIN_NAME=nds64le-linux-glibc-v5
TARGET=riscv64-linux
ARCH=rv64imacxandes
ABI=lp64
CPU=andes-25-series
XLEN=64

# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"
