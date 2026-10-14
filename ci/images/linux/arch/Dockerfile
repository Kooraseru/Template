ARG BASE_IMAGE
FROM ${BASE_IMAGE}
ARG PACKAGES
COPY install.sh /usr/local/bin/install-ci-packages
RUN sh /usr/local/bin/install-ci-packages ${PACKAGES}
WORKDIR /workspace
