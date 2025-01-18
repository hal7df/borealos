## 1. BUILD ARGS
# These allow changing the produced image by passing different build args to adjust
# the source from which your image is built.
# Build args can be provided on the commandline when building locally with:
#   podman build -f Containerfile --build-arg FEDORA_VERSION=40 -t local-image

# SOURCE_IMAGE arg can be anything from ublue upstream which matches your desired version:
# See list here: https://github.com/orgs/ublue-os/packages?repo_name=main
# - "silverblue"
# - "kinoite"
# - "sericea"
# - "onyx"
# - "lazurite"
# - "vauxite"
# - "base"
#
#  "aurora", "bazzite", "bluefin" or "ucore" may also be used but have different suffixes.
ARG SOURCE_IMAGE="aurora-dx"

## SOURCE_TAG arg must be a version built for the specific image: eg, 39, 40, gts, latest
ARG SOURCE_TAG="stable"

### 2. SOURCE IMAGE
## this is a standard Containerfile FROM using the build ARGs above to select the right upstream image
FROM ghcr.io/ublue-os/${SOURCE_IMAGE}:${SOURCE_TAG}

ARG TARGET_IMAGE="borealos"
ARG SOURCE_TAG="stable"

### 3. MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

COPY build-files/ /tmp/build-files/
COPY just/ /tmp/just/
COPY packages.json /tmp/packages.json
COPY cosign.pub /tmp/cosign.pub

RUN mkdir -p /var/lib/alternatives && \
    /tmp/build-files/build.sh && \
    ostree container commit
## NOTES:
# - /var/lib/alternatives is required to prevent failure with some RPM installs
# - All RUN commands must end with ostree container commit
#   see: https://coreos.github.io/rpm-ostree/container/#using-ostree-container-commit
