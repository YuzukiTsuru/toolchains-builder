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

## Andes GNU toolchain 5.2.2 (glibc / musl)

The scripts build the `ast-v5_2_2-release-v5` branch of
[andestech/nds-gnu-toolchain](https://github.com/andestech/nds-gnu-toolchain):

| Script | Target | `-march` | ABI | XLEN |
| --- | --- | --- | --- | --- |
| `nds/build-nds32le-linux-glibc-v5.sh` | riscv32-linux | rv32imacxandes | ilp32 | 32 |
| `nds/build-nds32le-linux-glibc-v5d.sh` | riscv32-linux | rv32imafdcxandes | ilp32d | 32 |
| `nds/build-nds32le-linux-musl-v5d.sh` | riscv32-linux-musl | rv32imafdcxandes | ilp32d | 32 |
| `nds/build-nds64le-linux-glibc-v5.sh` | riscv64-linux | rv64imacxandes | lp64 | 64 |
| `nds/build-nds64le-linux-glibc-v5d.sh` | riscv64-linux | rv64imafdcxandes | lp64d | 64 |

Component versions in this release: GCC 10.4, binutils 2.38, glibc 2.35,
GDB 12, Linux 5.4 UAPI headers. The musl toolchain uses musl 1.2.4 plus the
Andes patch in `nds/patches/musl-1.2.4-andes.patch`, which adds riscv32
support and carries the vendor bug fixes.

### Requirements

Ubuntu 22.04 (GCC 11) is the tested host. Newer hosts may compile the
toolchain sources with stricter defaults; if you hit that, build inside an
Ubuntu 22.04 container.

```sh
sudo apt-get install -y --no-install-recommends \
  autoconf automake bc bison bzip2 curl flex gawk gperf git \
  libexpat1-dev libgmp-dev libmpc-dev libmpfr-dev libncurses-dev \
  libtool m4 patch patchutils python3 texinfo wget zlib1g-dev zstd
```

### Build

```sh
./nds/build-nds32le-linux-glibc-v5d.sh
```

The musl variant uses the same workflow:

```sh
./nds/build-nds32le-linux-musl-v5d.sh
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
| `NDS_MUSL_VERSION` | `1.2.4` | musl release used by the musl scripts |
| `NDS_MUSL_URL` | musl.libc.org release URL | musl source tarball |
| `NDS_MUSL_SHA256` | built-in 1.2.4 hash | expected tarball SHA256 (empty disables the check) |
| `NDS_MUSL_SRC_DIR` | `.sources/musl-<version>` | extracted musl source |
| `NDS_MUSL_PATCH` | `nds/patches/musl-<version>-andes.patch` | patch applied after extraction (empty disables) |

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
  `nds32le-linux-glibc-v5d` or `nds32le-linux-musl-v5d`
  (empty builds `nds32le-linux-glibc-v5d`)
- `release_tag`: release to publish (default `nds-latest`; empty = build
  artifacts only)

Each job uploads a `zstd` tarball, its SHA-256 and a small metadata JSON as
workflow artifacts.

### Releases and manifest

Manual runs publish to the rolling `nds-latest` release by default; pushing
a tag named `nds-*` publishes to that tag instead. A run that builds several
toolchains publishes them together; separate runs publishing to the same tag
merge their entries by toolchain name, so glibc and musl can be published
incrementally.

Every release contains:

- `<toolchain>-<branch>.tar.zst` and `.sha256`
- `<toolchain>.json` metadata
- `manifest.json` listing every toolchain in the release

Stable manifest URL:

```
https://github.com/<owner>/<repo>/releases/download/nds-latest/manifest.json
```

Since `nds-latest` is marked as the latest release, this also works:

```
https://github.com/<owner>/<repo>/releases/latest/download/manifest.json
```

The manifest contains the release tag, upstream branch, generation time and
one entry per toolchain with target/arch/ABI/libc, source commit, file name,
SHA-256, byte size and direct download URL:

```json
{
  "schema": 1,
  "generated_at": "2026-11-25T12:00:00Z",
  "release": {
    "tag": "nds-latest",
    "url": "https://github.com/<owner>/<repo>/releases/tag/nds-latest",
    "manifest_url": "https://github.com/<owner>/<repo>/releases/download/nds-latest/manifest.json"
  },
  "upstream": {
    "repository": "https://github.com/andestech/nds-gnu-toolchain",
    "branch": "ast-v5_2_2-release-v5"
  },
  "toolchains": [
    {
      "name": "nds32le-linux-glibc-v5d",
      "target": "riscv32-linux",
      "arch": "rv32imafdcxandes",
      "abi": "ilp32d",
      "libc": "glibc 2.35",
      "branch": "ast-v5_2_2-release-v5",
      "commit": "f73a8e2d655081707cdf0d9acd37d048987307ee",
      "file": "nds32le-linux-glibc-v5d-ast-v5_2_2-release-v5.tar.zst",
      "sha256": "...",
      "size": 462000000,
      "url": "https://github.com/<owner>/<repo>/releases/download/nds-latest/nds32le-linux-glibc-v5d-ast-v5_2_2-release-v5.tar.zst"
    }
  ]
}
```

Locally the same commands can be reproduced outside Actions; the scripts do
not depend on any CI-specific tooling.

### Adding another toolchain

Create a new script that sets `TOOLCHAIN_NAME`, `TARGET`, `ARCH`, `ABI`,
`CPU`, `XLEN` and sources `common.sh`. A musl toolchain, for example, will
mostly change the library stage and the target triple. The CI workflow
discovers every `nds/build-*.sh` automatically; add the new name to the
`default` list in the prepare job if it should build on every push.
