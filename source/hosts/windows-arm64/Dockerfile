# Host-owned Windows cross-compilation environment.
# Select a toolchain archive for the native Docker host architecture.
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl xz-utils && rm -rf /var/lib/apt/lists/*
ARG TARGETARCH
RUN case "$TARGETARCH" in \
        amd64) TOOLCHAIN_ARCH=x86_64 ;; \
        arm64) TOOLCHAIN_ARCH=aarch64 ;; \
        *) echo "Unsupported Docker build architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac \
    && curl --fail --location --retry 3 "https://github.com/mstorsjo/llvm-mingw/releases/download/20240619/llvm-mingw-20240619-ucrt-ubuntu-20.04-${TOOLCHAIN_ARCH}.tar.xz" -o /tmp/toolchain.tar.xz \
    && mkdir -p /opt/llvm-mingw \
    && tar -xJf /tmp/toolchain.tar.xz -C /opt/llvm-mingw --strip-components=1 \
    && rm /tmp/toolchain.tar.xz
ENV PATH="/opt/llvm-mingw/bin:${PATH}"
WORKDIR /workspace
COPY source/main.c /workspace/source/main.c
