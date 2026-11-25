# toolchains-builder

Build scripts and CI for prebuilt RISC-V GNU toolchains.

Each vendor/toolchain family lives in its own directory and produces a
self-contained, relocatable toolchain tree plus a CI artifact:

```
nds/        Andes (AndeStar V5) GNU toolchains
build/      build trees (generated)
output/     installed toolchains (generated)
.sources/   upstream source checkouts (generated)
```

## Andes GNU toolchain 5.2.2 (glibc)

The scripts build the `ast-v5_2_2-release-v5` branch of
[andestech/nds-gnu-toolchain](https://github.com/andestech/nds-gnu-toolchain):

| Script | Target | `-march` | ABI | XLEN |
| --- | --- | --- | --- | --- |
| `nds/build-nds32le-linux-glibc-v5.sh` | riscv32-linux | rv32imacxandes | ilp32 | 32 |
| `nds/build-nds32le-linux-glibc-v5d.sh` | riscv32-linux | rv32imafdcxandes | ilp32d | 32 |
| `nds/build-nds64le-linux-glibc-v5.sh` | riscv64-linux | rv64imacxandes | lp64 | 64 |
| `nds/build-nds64le-linux-glibc-v5d.sh` | riscv64-linux | rv64imafdcxandes | lp64d | 64 |

Component versions in this release: GCC 10.4, binutils 2.38, glibc 2.35,
GDB 12, Linux 5.4 UAPI headers.

### Requirements

Ubuntu 22.04 (GCC 11) is the tested host. Newer hosts may compile the
toolchain sources with stricter defaults; if you hit that, build inside an
Ubuntu 22.04 container.

```sh
sudo apt-get install -y --no-install-recommends \
  autoconf automake bc bison bzip2 flex gawk gperf git \
  libexpat1-dev libgmp-dev libmpc-dev libmpfr-dev libncurses-dev \
  libtool m4 patchutils python3 texinfo wget zlib1g-dev zstd
```

### Build

```sh
./nds/build-nds32le-linux-glibc-v5d.sh
```

The script clones the upstream repository and its submodules into
`.sources/nds-gnu-toolchain` on first run, builds binutils, a bootstrap GCC,
glibc, the final GCC and GDB, then installs to
`output/<toolchain-name>/` and links a test program to verify the sysroot.

The installed tree is relocatable: GCC records its sysroot relative to the
install prefix and passes the relocated path to the linker, so the whole
`output/<toolchain-name>/` directory can be moved or tarred and extracted
anywhere.

### Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `NDS_BRANCH` | `ast-v5_2_2-release-v5` | upstream branch or tag |
| `NDS_REPO_URL` | `https://github.com/andestech/nds-gnu-toolchain.git` | source repository |
| `NDS_SRC_DIR` | `.sources/nds-gnu-toolchain` | source checkout |
| `NDS_BUILD_ROOT` | `build` | build trees |
| `NDS_OUTPUT_DIR` | `output` | install root |
| `NDS_PREFIX` | `output/<toolchain-name>` | override install prefix |
| `NDS_MAKE_JOBS` | `nproc` | parallel make jobs |
| `NDS_KEEP_BUILD` | `1` | `0` deletes each stage's build tree after install |
| `NDS_CLEAN` | `0` | `1` deletes the build tree and prefix first |
| `NDS_DOWNLOAD_PREREQ` | `auto` | `auto`/`0`/`1`: use system GMP/MPFR/MPC or download them |

Example:

```sh
NDS_BRANCH=ast-v5_2_2-release-v5 \
NDS_MAKE_JOBS=8 \
NDS_KEEP_BUILD=0 \
./nds/build-nds32le-linux-glibc-v5d.sh
```

### CI

`.github/workflows/nds-toolchain.yml` builds
`nds32le-linux-glibc-v5d` by default in a matrix on `ubuntu-22.04` (the other
scripts stay available and can be selected manually). It runs on pushes that
touch `nds/`, on pull requests, and on manual dispatch:

- `branch`: upstream branch or tag to build (default
  `ast-v5_2_2-release-v5`)
- `toolchains`: space-separated subset, e.g.
  `nds32le-linux-glibc-v5d` or `nds64le-linux-glibc-v5d`
  (empty builds `nds32le-linux-glibc-v5d`)

Each job uploads a `zstd` tarball and its SHA-256 as an artifact. Pushing a
tag named `nds-*` additionally attaches all tarballs to a GitHub release.

Locally the same commands can be reproduced outside Actions; the scripts do
not depend on any CI-specific tooling.

### Adding another toolchain

Create a new script that sets `TOOLCHAIN_NAME`, `TARGET`, `ARCH`, `ABI`,
`CPU`, `XLEN` and sources `common.sh`. A musl toolchain, for example, will
mostly change the library stage and the target triple. The CI workflow
discovers every `nds/build-*.sh` automatically; add the new name to the
`default` list in the prepare job if it should build on every push.
