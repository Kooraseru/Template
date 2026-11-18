FROM node:24-bookworm
WORKDIR /tools
COPY dependencies ./dependencies
COPY .github/workflows/bootstrap.yml .github/workflows/bootstrap.yml
RUN node dependencies/packages/core/dependencyLoader/index.ts --exec luau.lute --version
ENV PATH="/tools/dependencies/managed/bin/lute:${PATH}"
