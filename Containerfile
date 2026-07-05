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
ARG TARGET_RELEASE_TYPE="stable"
ARG VERSION="dev-build"

### 3. MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

# Copy in static files
COPY conf/ /

# Run modifications
RUN --mount=type=tmpfs,dst=/var/log \
    --mount=type=bind,src=scripts/,dst=/tmp/scripts/ \
    --mount=type=bind,src=just/,dst=/tmp/just/ \
    --mount=type=bind,src=packages.json,dst=/tmp/packages.json \
    --mount=type=bind,src=flatpaks.txt,dst=/tmp/flatpaks.txt \
    export SCRIPTS_DIR="/tmp/scripts"; \
    export JUSTFILES="/tmp/just"; \
    export FLATPAK_LIST="/tmp/flatpaks.txt"; \
    "${SCRIPTS_DIR}/build.sh"

# Lint image and apply bootc label
RUN bootc container lint
LABEL containers.bootc=1

# Add static metadata
LABEL org.opencontainers.image.title="${TARGET_IMAGE}"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.description="Custom lightweight build of Aurora Linux targeted at power users"
LABEL org.opencontainers.image.url="https://github.com/hal7df/borealos"
LABEL org.opencontainers.image.source="https://raw.githubusercontent.com/hal7df/borealos/refs/heads/main/Containerfile"
LABEL org.opencontainers.image.vendor="hal7df"

LABEL io.artifacthub.package.maintainers="[{\"name\":\"hal7df\",\"email\":\"hal7df@gmail.com\"}]"
LABEL io.artifacthub.package.readme-url="https://raw.githubusercontent.com/hal7df/borealos/refs/heads/main/README.md"
