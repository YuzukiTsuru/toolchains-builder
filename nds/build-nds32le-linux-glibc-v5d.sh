#!/usr/bin/env bash
# Andes GNU Toolchain 5.2.2 — riscv32, rv32imafdc + Andes extensions, ilp32d.
set -euo pipefail

TOOLCHAIN_NAME=nds32le-linux-glibc-v5d
TARGET=riscv32-linux
ARCH=rv32imafdcxandes
ABI=ilp32d
CPU=andes-25-series
XLEN=32

# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"
