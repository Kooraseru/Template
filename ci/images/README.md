# CI images

Each configured image has a directory here containing its Dockerfile and build
context. Add its directory name to `images.names` in `ci/config.toml` and enable
image generation. CI builds and exports the image for inspection on PRs.
Authorized publication jobs load the same exported image and push it to GHCR.

Images must build without depending on the unpublished image being built.
Select base images and tool versions appropriate to the consuming project;
use immutable digests where reproducibility requires them.
