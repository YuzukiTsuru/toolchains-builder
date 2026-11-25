#!/usr/bin/env bash
# Andes GNU Toolchain 5.2.2 — riscv64, rv64imafdc + Andes extensions, lp64d.
set -euo pipefail

TOOLCHAIN_NAME=nds64le-linux-glibc-v5d
TARGET=riscv64-linux
ARCH=rv64imafdcxandes
ABI=lp64d
CPU=andes-25-series
XLEN=64

# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"
