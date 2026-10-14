# CI images

`catalogue.json` declares 24 Linux image variants, with runner architecture,
immutable base-image digest, packages, toolchain profile, and tool probes.
Select variants using `images.names` in `ci/config.toml`.

| Environment | Architectures | Profiles |
| --- | --- | --- |
| Alpine 3.24.2 | x86_64, ARM64 | GCC, Clang, Rust |
| Debian 13 | x86_64, ARM64 | GCC, Clang, Rust, MinGW |
| Ubuntu 24.04 | x86_64, ARM64 | GCC, Clang |
| Fedora 44 | x86_64, ARM64 | GCC, Clang |
| Arch rolling | x86_64 | GCC, Clang |

Arch's official base image has no ARM64 variant. Windows and macOS targets use
native runners, with no Windows or macOS Docker image implied.

Distribution Dockerfiles live under `linux/<distribution>/`; profile Dockerfiles
live under `toolchains/<profile>/`. Each job builds its distribution layer and
then its toolchain layer locally. It does not need a prepublished template image.
`install.sh` executes the distribution package manager using declared packages.

CI exports `image.tar`, `image.json`, and the actual installed package inventory
in `versions.txt`. Build jobs download the selected image and execute within it.
Publication jobs load that same artifact and push it to the current repository's
GHCR namespace using the automatic workflow token.

Base images are pinned by digest. Package repositories still change, especially
Arch rolling; the inventory records what was installed rather than claiming
immutable package versions. Consumers needing exact package reproduction should
use snapshot repositories or pinned package artifacts.

The workflow runs Lune on the job runner, outside the build image. Images supply
the selected compilation environment; Alpine does not assume a glibc Lune binary
will run inside its musl container.
