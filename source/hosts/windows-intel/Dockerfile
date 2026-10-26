# Host-owned Windows cross-compilation environment.
# llvm-mingw supplies both x86-64 and AArch64 Windows targets.
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl xz-utils && rm -rf /var/lib/apt/lists/*
RUN curl --fail --location --retry 3 https://github.com/mstorsjo/llvm-mingw/releases/download/20240619/llvm-mingw-20240619-ucrt-ubuntu-20.04-x86_64.tar.xz -o /tmp/toolchain.tar.xz \
    && mkdir -p /opt/llvm-mingw \
    && tar -xJf /tmp/toolchain.tar.xz -C /opt/llvm-mingw --strip-components=1 \
    && rm /tmp/toolchain.tar.xz
ENV PATH="/opt/llvm-mingw/bin:${PATH}"
WORKDIR /workspace
