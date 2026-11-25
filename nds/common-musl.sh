#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Shared build logic for the Andes (AndeStar V5) musl GNU toolchains.
#
# A per-configuration script next to this file sets:
#
#   TOOLCHAIN_NAME  output directory / artifact name
#   TARGET          GNU target triplet (riscv32-linux-musl or riscv64-linux-musl)
#   ARCH            -march value passed to binutils/GCC/musl
#   ABI             -mabi value
#   CPU             -mtune value
#   XLEN            32 or 64
#
# and then sources this file.
#
# Optional environment variables:
#
#   NDS_BRANCH            nds-gnu-toolchain branch or tag
#                         (default: ast-v5_2_2-release-v5)
#   NDS_REPO_URL          source repository URL
#   NDS_SRC_DIR           source checkout (default: <repo>/.sources/nds-gnu-toolchain)
#   NDS_BUILD_ROOT        build tree (default: <repo>/build)
#   NDS_OUTPUT_DIR        install root (default: <repo>/output)
#   NDS_PREFIX            override the per-toolchain install prefix
#   NDS_MAKE_JOBS         parallel make jobs (default: nproc)
#   NDS_KEEP_BUILD        0 removes each stage's build tree after install (default: 1)
#   NDS_CLEAN             1 removes the build tree and install prefix first (default: 0)
#   NDS_DOWNLOAD_PREREQ   auto|0|1, run gcc/contrib/download_prerequisites
#                         (default: auto, i.e. only when system GMP/MPFR/MPC are absent)
#   NDS_MUSL_VERSION      musl release to build (default: 1.2.5)
#   NDS_MUSL_URL          musl release tarball URL
#   NDS_MUSL_SHA256       expected tarball SHA256 (empty disables the check)
#   NDS_MUSL_SRC_DIR      extracted musl source
#                         (default: <sources>/musl-<version>)
# ---------------------------------------------------------------------------
set -euo pipefail

NDS_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${NDS_SCRIPT_DIR}/.." && pwd)"

if [ -z "${TOOLCHAIN_NAME:-}" ] || [ -z "${TARGET:-}" ] || [ -z "${ARCH:-}" ] || \
   [ -z "${ABI:-}" ] || [ -z "${CPU:-}" ] || [ -z "${XLEN:-}" ]; then
  echo "error: the build script must set TOOLCHAIN_NAME, TARGET, ARCH, ABI, CPU and XLEN" >&2
  exit 1
fi

abspath() { realpath -m -- "$1"; }

NDS_BRANCH="${NDS_BRANCH:-ast-v5_2_2-release-v5}"
NDS_REPO_URL="${NDS_REPO_URL:-https://github.com/andestech/nds-gnu-toolchain.git}"
NDS_SRC_DIR="$(abspath "${NDS_SRC_DIR:-${REPO_ROOT}/.sources/nds-gnu-toolchain}")"
NDS_BUILD_ROOT="$(abspath "${NDS_BUILD_ROOT:-${REPO_ROOT}/build}")"
NDS_OUTPUT_DIR="$(abspath "${NDS_OUTPUT_DIR:-${REPO_ROOT}/output}")"
NDS_MAKE_JOBS="${NDS_MAKE_JOBS:-$(nproc)}"
NDS_KEEP_BUILD="${NDS_KEEP_BUILD:-1}"
NDS_CLEAN="${NDS_CLEAN:-0}"
NDS_DOWNLOAD_PREREQ="${NDS_DOWNLOAD_PREREQ:-auto}"

NDS_MUSL_VERSION="${NDS_MUSL_VERSION:-1.2.5}"
NDS_MUSL_URL="${NDS_MUSL_URL:-https://musl.libc.org/releases/musl-${NDS_MUSL_VERSION}.tar.gz}"
NDS_MUSL_SHA256="${NDS_MUSL_SHA256:-a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4}"
NDS_MUSL_SRC_DIR="$(abspath "${NDS_MUSL_SRC_DIR:-$(dirname -- "${NDS_SRC_DIR}")/musl-${NDS_MUSL_VERSION}}")"
MUSL_SRC="${NDS_MUSL_SRC_DIR}"

PREFIX="$(abspath "${NDS_PREFIX:-${NDS_OUTPUT_DIR}/${TOOLCHAIN_NAME}}")"
SYSROOT="${PREFIX}/sysroot"
BUILD_DIR="${NDS_BUILD_ROOT}/${TOOLCHAIN_NAME}"

GCC_SRC="${NDS_SRC_DIR}/gcc"
BINUTILS_SRC="${NDS_SRC_DIR}/binutils"
GDB_SRC="${NDS_SRC_DIR}/gdb"
KERNEL_HDR_SRC="${NDS_SRC_DIR}/linux-headers"

log()  { printf '\n==> [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

require_tools() {
  local tool
  for tool in git make tar realpath curl sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
  done
}

fetch_sources() {
  if [ -d "${NDS_SRC_DIR}/.git" ]; then
    log "Reusing sources at ${NDS_SRC_DIR}"
    local current_branch
    current_branch="$(git -C "${NDS_SRC_DIR}" rev-parse --abbrev-ref HEAD)"
    if [ "${current_branch}" != "${NDS_BRANCH}" ] && [ "${current_branch}" != "HEAD" ]; then
      warn "source checkout is on '${current_branch}', not '${NDS_BRANCH}'"
      warn "remove ${NDS_SRC_DIR} or set NDS_SRC_DIR to use another branch"
    fi
  else
    log "Cloning ${NDS_REPO_URL} (${NDS_BRANCH})"
    mkdir -p -- "$(dirname -- "${NDS_SRC_DIR}")"
    git clone --depth 1 --branch "${NDS_BRANCH}" "${NDS_REPO_URL}" "${NDS_SRC_DIR}"
  fi

  log "Updating submodules"
  git -C "${NDS_SRC_DIR}" submodule update --init --recursive --depth 1 --jobs 4

  local missing
  missing="$(git -C "${NDS_SRC_DIR}" submodule status | awk '$1 ~ /^-/ { print $2 }')"
  [ -z "${missing}" ] || die "submodules not initialized: ${missing}"

  log "Sources ready: $(git -C "${NDS_SRC_DIR}" rev-parse --short HEAD) on $(git -C "${NDS_SRC_DIR}" rev-parse --abbrev-ref HEAD)"
}

fetch_musl() {
  local tarball
  tarball="$(dirname -- "${NDS_SRC_DIR}")/musl-${NDS_MUSL_VERSION}.tar.gz"

  if [ -f "${MUSL_SRC}/Makefile" ]; then
    log "Reusing musl ${NDS_MUSL_VERSION} at ${MUSL_SRC}"
    return
  fi

  mkdir -p -- "$(dirname -- "${tarball}")"
  if [ ! -f "${tarball}" ]; then
    log "Downloading musl ${NDS_MUSL_VERSION}"
    curl -fsSL --retry 3 --retry-delay 2 -o "${tarball}.tmp" "${NDS_MUSL_URL}"
    mv -f -- "${tarball}.tmp" "${tarball}"
  fi
  if [ -n "${NDS_MUSL_SHA256}" ]; then
    printf '%s  %s\n' "${NDS_MUSL_SHA256}" "${tarball}" | sha256sum -c -
  fi

  log "Extracting musl ${NDS_MUSL_VERSION}"
  rm -rf -- "${MUSL_SRC}"
  mkdir -p -- "${MUSL_SRC}"
  tar xzf "${tarball}" -C "${MUSL_SRC}" --strip-components=1
  [ -f "${MUSL_SRC}/Makefile" ] || die "musl source extraction failed"
}

prepare_gcc_prerequisites() {
  local need=0
  if [ -d "${GCC_SRC}/gmp" ] && [ -d "${GCC_SRC}/mpfr" ] && [ -d "${GCC_SRC}/mpc" ]; then
    log "GCC prerequisites already present in the source tree"
    return
  fi

  case "${NDS_DOWNLOAD_PREREQ}" in
    1) need=1 ;;
    0) need=0 ;;
    auto)
      if printf '#include <gmp.h>\n#include <mpfr.h>\n#include <mpc.h>\n' | \
           "${CC:-cc}" -E -x c - >/dev/null 2>&1; then
        log "Using system GMP/MPFR/MPC"
      else
        need=1
      fi
      ;;
    *) die "NDS_DOWNLOAD_PREREQ must be auto, 0 or 1 (got '${NDS_DOWNLOAD_PREREQ}')" ;;
  esac

  if [ "${need}" = 1 ]; then
    log "Downloading GCC prerequisites (GMP/MPFR/MPC/ISL)"
    ( cd "${GCC_SRC}" && ./contrib/download_prerequisites )
  fi
}

prepare_dirs() {
  if [ "${NDS_CLEAN}" = 1 ]; then
    log "Removing previous build and install trees"
    rm -rf -- "${BUILD_DIR}" "${PREFIX}"
  fi
  mkdir -p -- "${BUILD_DIR}" "${NDS_OUTPUT_DIR}" "$(dirname -- "${PREFIX}")"
}

cleanup_stage() {
  if [ "${NDS_KEEP_BUILD}" != 1 ]; then
    rm -rf -- "$1"
  fi
}

build_binutils() {
  log "Stage 1/6: binutils"
  mkdir -p -- "${BUILD_DIR}/binutils"
  (
    cd "${BUILD_DIR}/binutils"
    "${BINUTILS_SRC}/configure" \
      --target="${TARGET}" --prefix="${PREFIX}" --with-arch="${ARCH}" \
      --with-curses --disable-nls --disable-tui --with-python=no --with-lzma=no \
      --with-expat=yes --with-guile=no --enable-plugins --disable-werror \
      --enable-deterministic-archives --disable-gdb --disable-sim \
      --with-sysroot="${SYSROOT}"
    make -j"${NDS_MAKE_JOBS}" all
    make install
  )
  cleanup_stage "${BUILD_DIR}/binutils"
}

install_linux_headers() {
  log "Stage 2/6: Linux UAPI headers"
  mkdir -p -- "${SYSROOT}/usr"
  cp -a -- "${KERNEL_HDR_SRC}/include" "${SYSROOT}/usr/"
}

build_bootstrap_gcc() {
  log "Stage 3/6: bootstrap GCC"
  mkdir -p -- "${BUILD_DIR}/bootstrap-gcc"
  (
    cd "${BUILD_DIR}/bootstrap-gcc"
    "${GCC_SRC}/configure" \
      --target="${TARGET}" --prefix="${PREFIX}" \
      --with-arch="${ARCH}" --with-abi="${ABI}" --with-tune="${CPU}" \
      --without-headers --disable-shared --disable-threads \
      --enable-tls --enable-languages=c --disable-libatomic \
      --disable-libmudflap --disable-libssp --disable-libquadmath \
      --disable-libgomp --disable-nls --disable-bootstrap \
      --disable-werror --disable-multilib \
      --enable-gp-insn-relax-default=yes \
      --enable-checking=release \
      CFLAGS_FOR_TARGET="-O2 -g -mstrict-align" \
      CXXFLAGS_FOR_TARGET="-O2 -g -mstrict-align"
    make -j"${NDS_MAKE_JOBS}" inhibit-libc=true all-gcc
    make inhibit-libc=true install-gcc
    make -j"${NDS_MAKE_JOBS}" inhibit-libc=true all-target-libgcc
    make inhibit-libc=true install-target-libgcc
  )
  cleanup_stage "${BUILD_DIR}/bootstrap-gcc"
}

build_musl() {
  log "Stage 4/6: musl ${NDS_MUSL_VERSION}"
  mkdir -p -- "${BUILD_DIR}/musl"
  (
    cd "${BUILD_DIR}/musl"
    CC="${PREFIX}/bin/${TARGET}-gcc" \
    AR="${PREFIX}/bin/${TARGET}-ar" \
    RANLIB="${PREFIX}/bin/${TARGET}-ranlib" \
    CFLAGS="-O2 -g" \
    "${MUSL_SRC}/configure" \
      --host="${TARGET}" --prefix=/usr --libdir=/lib \
      --disable-gcc-wrapper --enable-shared --enable-static
    make -j"${NDS_MAKE_JOBS}"
    make DESTDIR="${SYSROOT}" install-libs install-headers
  )
  [ -f "${SYSROOT}/lib/libc.so" ] || die "musl libc.so was not installed"

  local sub=""
  case "${ABI}" in
    ilp32|lp64) sub="-sf" ;;
    ilp32f|lp64f) sub="-sp" ;;
    ilp32d|lp64d) sub="" ;;
  esac
  ln -sf libc.so "${SYSROOT}/lib/ld-musl-riscv${XLEN}${sub}.so.1"
  cleanup_stage "${BUILD_DIR}/musl"
}

build_final_gcc() {
  log "Stage 5/6: final GCC"
  mkdir -p -- "${BUILD_DIR}/final-gcc"
  (
    cd "${BUILD_DIR}/final-gcc"
    "${GCC_SRC}/configure" \
      --target="${TARGET}" --prefix="${PREFIX}" \
      --with-arch="${ARCH}" --with-abi="${ABI}" --with-tune="${CPU}" \
      --with-sysroot="${SYSROOT}" \
      --disable-nls --enable-languages=c,c++ --enable-lto \
      --enable-gp-insn-relax-default=yes \
      --disable-werror --disable-multilib \
      --enable-shared --enable-tls --disable-bootstrap \
      --disable-libmudflap --disable-libssp --disable-libquadmath \
      --disable-libsanitizer \
      --enable-checking=release \
      CFLAGS_FOR_TARGET="-O2 -g -mstrict-align" \
      CXXFLAGS_FOR_TARGET="-O2 -g -mstrict-align"
    make -j"${NDS_MAKE_JOBS}" all
    make install
  )
  cleanup_stage "${BUILD_DIR}/final-gcc"
}

build_gdb() {
  log "Stage 6/6: GDB"
  mkdir -p -- "${BUILD_DIR}/gdb"
  (
    cd "${BUILD_DIR}/gdb"
    "${GDB_SRC}/configure" \
      --target="${TARGET}" --prefix="${PREFIX}" --with-arch="${ARCH}" \
      --with-curses --disable-nls --enable-tui --with-python=no \
      --with-lzma=no --with-expat=yes --with-guile=no \
      --disable-werror --disable-sim \
      --disable-binutils --disable-ld --disable-gas --disable-gprof \
      CFLAGS="-std=gnu99"
    make -j"${NDS_MAKE_JOBS}" all
    make install
  )
  cleanup_stage "${BUILD_DIR}/gdb"
}

install_target_libs() {
  log "Installing target libraries into the sysroot"
  mkdir -p -- "${SYSROOT}/lib"
  cp -a -- "${PREFIX}/${TARGET}/lib/." "${SYSROOT}/lib/"
}

write_toolchain_info() {
  {
    echo "toolchain: ${TOOLCHAIN_NAME}"
    echo "source: ${NDS_REPO_URL}"
    echo "branch: ${NDS_BRANCH}"
    echo "commit: $(git -C "${NDS_SRC_DIR}" rev-parse HEAD)"
    echo "target: ${TARGET}"
    echo "arch: ${ARCH}"
    echo "abi: ${ABI}"
    echo "cpu: ${CPU}"
    echo "libc: musl ${NDS_MUSL_VERSION}"
    echo "built: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "host: $(uname -srm)"
  } > "${PREFIX}/toolchain-info.txt"
}

verify_toolchain() {
  log "Verifying toolchain"
  local gcc="${PREFIX}/bin/${TARGET}-gcc"
  local gxx="${PREFIX}/bin/${TARGET}-g++"
  local gdb="${PREFIX}/bin/${TARGET}-gdb"
  [ -x "${gcc}" ] || die "missing compiler: ${gcc}"
  [ -x "${gxx}" ] || die "missing compiler: ${gxx}"
  [ -x "${gdb}" ] || die "missing debugger: ${gdb}"

  "${gcc}" --version | head -n 1
  "${gdb}" --version | head -n 1
  log "gcc sysroot: $("${gcc}" -print-sysroot)"

  local tmpdir
  tmpdir="$(mktemp -d)"
  printf 'int main(void) { return 0; }\n' > "${tmpdir}/hello.c"
  "${gcc}" "${tmpdir}/hello.c" -o "${tmpdir}/hello"
  file "${tmpdir}/hello" || true

  cat > "${tmpdir}/hello.cc" <<'EOF'
#include <iostream>
int main() { std::cout << "hello" << std::endl; return 0; }
EOF
  "${gxx}" "${tmpdir}/hello.cc" -o "${tmpdir}/hello-cxx"
  file "${tmpdir}/hello-cxx" || true

  rm -rf -- "${tmpdir}"
}

main() {
  local started=${SECONDS}

  log "Building ${TOOLCHAIN_NAME}"
  log "  target=${TARGET}  arch=${ARCH}  abi=${ABI}  cpu=${CPU}"
  log "  source=${NDS_REPO_URL} (${NDS_BRANCH})"
  log "  prefix=${PREFIX}"
  log "  jobs=${NDS_MAKE_JOBS}"

  require_tools
  fetch_sources
  fetch_musl
  prepare_gcc_prerequisites
  prepare_dirs

  export PATH="${PREFIX}/bin:${PATH}"

  build_binutils
  install_linux_headers
  build_bootstrap_gcc
  build_musl
  build_final_gcc
  build_gdb
  install_target_libs
  write_toolchain_info
  verify_toolchain

  log "Done: ${TOOLCHAIN_NAME} in $((SECONDS - started))s"
  log "Toolchain: ${PREFIX}"
  if [ "${NDS_KEEP_BUILD}" = 1 ]; then
    log "Build tree: ${BUILD_DIR}"
  fi
}

main "$@"
