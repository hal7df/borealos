# Adapted from https://github.com/m2Giles/m2os/blob/main/Justfile

repo_user := "hal7df"
repo_name := "borealos"
images := "([" + repo_name + "]='" + repo_name \
    + "' [" + repo_name + "-nvidia]='" + repo_name + "-nvidia')"
image_desc := "Custom lightweight build of Aurora Linux targeted at power users"

export SUDOIF := if `id -u` == "0" { "" } else { "sudo" }
export SET_X := if `id -u` == "0" { "1" } else { env('SET_X', '') }
export PODMAN := if path_exists("/usr/bin/podman") == "true" { env("PODMAN", "/usr/bin/podman") } else { if path_exists("/usr/bin/docker") == "true" { env("PODMAN", "/usr/bin/docker") } else { env("PODMAN", "exit 1") }}

[private]
default:
    @just --list

# Validate Justfile
[group('Just')]
check:
    #!/usr/bin/env bash
    echo "Checking syntax: Justfile"
    just --fmt --check -f Justfile

[group('Just')]
fix:
    #!/usr/bin/env bash
    echo "Fixing syntax: Justfile"
    just --fmt -f Justfile

[group('Utility')]
clean:
    #!/usr/bin/env bash
    set -eux

    rm -f output*.env changelog*.md version.txt previous.manifest.json
    rm -f /tmp/{{ repo_name }}_*
    rm -rf build/

    if ls | grep '{{ repo_name }}*' >/dev/null; then
        ${SUDOIF} find {{ repo_name }}* -delete
    fi

[group('Image')]
build image=repo_name tag="stable":
    #!/usr/bin/env bash
    set ${SET_X:+-x} -euo pipefail
    
    # Validate that the user provided a valid image
    declare -A ALL_IMAGES={{ images }}
    TARGET_IMAGE="${ALL_IMAGES[{{ image }}]-}"
    if [[ -z "$TARGET_IMAGE" ]]; then
        echo "No such image {{ image }}."
        exit 1
    fi

    BUILD_ARGS=()
    SOURCE_IMAGE="${TARGET_IMAGE/{{ repo_name }}/aurora-dx}"
    SOURCE_TAG="{{ tag }}"
    skopeo inspect "docker://ghcr.io/ublue-os/${SOURCE_IMAGE}:${SOURCE_TAG}" > "/tmp/inspect-{{ image }}.json"
    FEDORA_VERSION="$(jq -r '.Labels["ostree.linux"]' < "/tmp/inspect-{{ image }}.json" | grep -oP 'fc\K[0-9]+')"
    TARGET_TAG="$SOURCE_TAG-$FEDORA_VERSION.$(date +%Y%m%d)-unopt"

    BUILD_ARGS+=("--file" "Containerfile")
    BUILD_ARGS+=("--label" "org.opencontainers.image.title={{ image }}")
    BUILD_ARGS+=("--label" "org.opencontainers.image.version=$TARGET_TAG")
    BUILD_ARGS+=("--label" "org.opencontainers.image.description={{ image_desc }}")
    BUILD_ARGS+=("--label" "ostree.linux=$(jq -r '.Labels["ostree.linux"]' < /tmp/inspect-{{ image }}.json)")
    BUILD_ARGS+=("--build-arg" "SOURCE_IMAGE=$SOURCE_IMAGE")
    BUILD_ARGS+=("--build-arg" "SOURCE_TAG=$SOURCE_TAG")
    BUILD_ARGS+=("--build-arg" "TARGET_IMAGE=$TARGET_IMAGE")
    BUILD_ARGS+=("--tag" "localhost/$TARGET_IMAGE:$TARGET_TAG")

    if [[ "${PODMAN}" =~ docker && "${TERM}" == "dumb" ]]; then
        BUILD_ARGS+=("--progress" "plain")
    fi

    ${PODMAN} pull "ghcr.io/ublue-os/${SOURCE_IMAGE}:${SOURCE_TAG}"
    ${PODMAN} build "${BUILD_ARGS[@]}"

    just rechunk "$TARGET_IMAGE" "$TARGET_TAG" "{{ tag }}"

[private]
rechunk image=repo_name $tag="stable-unopt" prevTag="stable":
    #!/usr/bin/env bash
    set -xeuo pipefail
    ID="$(${PODMAN} images --filter reference=localhost/{{ image }}:{{ tag }} --format "'{{ '{{.ID}}' }}'")"

    if [[ -z "$ID" ]]; then
        echo "Image could not be found for rechunking. Run 'just build {{ image }}' to create the unoptimized image."
        exit 1
    fi
    
    # Set metadata for the image
    OUT_NAME="{{ image }}"
    OUT_VERSION="${tag/%-unopt/}"
    OUT_VERSION_SYMBOLIC="$(printf '%s' "$OUT_VERSION" | sed 's/-[[:digit:]]\+\.[[:digit:]]\+$//')"
    LABELS="
        org.opencontainers.image.title={{ image }}
        org.opencontainers.image.revision=$(git rev-parse HEAD)
        org.opencontainers.image.version=$OUT_VERSION
        org.opencontainers.image.description={{ image_desc }}
        ostree.linux=$(${PODMAN} inspect localhost/{{ image }}:{{ tag }} | jq -r '.[]["Config"]["Labels"]["ostree.linux"]')"

    if [[ "${UID}" -gt "0" && ! ${PODMAN} =~ docker ]]; then
        ${PODMAN} save localhost/{{ image }}:{{ tag }} | ${SUDOIF} ${PODMAN} load
    fi

    # Mount the image in an accessible container filesystem
    CREF="$(${SUDOIF} ${PODMAN} create localhost/{{ image }}:{{ tag }} bash)"
    MOUNT="$(${SUDOIF} ${PODMAN} mount $CREF)"
    FEDORA_VERSION="$(${SUDOIF} ${PODMAN} inspect $CREF | jq -r '.[]["Config"]["Labels"]["ostree.linux"]' | grep -oP 'fc\K[0-9]+')"

    # Prepare the image for rechunking
    ${SUDOIF} ${PODMAN} run --rm \
        --security-opt label=disable \
        --volume "$MOUNT:/var/tree" \
        --env TREE=/var/tree \
        --user 0:0 \
        ghcr.io/hhd-dev/rechunk:latest \
        /sources/rechunk/1_prune.sh
    ${SUDOIF} ${PODMAN} run --rm \
        --security-opt label=disable \
        --volume "$MOUNT:/var/tree" \
        --volume "{{ image }}_{{ tag }}_cache_ostree:/var/ostree" \
        --env TREE=/var/tree \
        --env REPO=/var/ostree/repo \
        --env RESET_TIMESTAMP=1 \
        --user 0:0 \
        ghcr.io/hhd-dev/rechunk:latest \
        /sources/rechunk/2_create.sh

    # Unmount the temporary container, and remove both the container and the
    # unoptimized images
    ${SUDOIF} ${PODMAN} unmount "$CREF"
    ${SUDOIF} ${PODMAN} rm "$CREF"
    if [[ "${UID}" -gt "0" ]]; then
        ${SUDOIF} ${PODMAN} rmi localhost/{{ image }}:{{ tag }}
    fi
    ${PODMAN} rmi localhost/{{ image }}:{{ tag }}

    # Rechunk the image
    ${SUDOIF} ${PODMAN} run --rm \
        --pull=newer \
        --security-opt label=disable \
        --volume "$PWD:/workspace" \
        --volume "$PWD:/var/git" \
        --volume "{{ image }}_{{ tag }}_cache_ostree:/var/ostree" \
        --env REPO=/var/ostree/repo \
        --env PREV_REF=ghcr.io/{{ repo_user }}/{{ image }}:{{ prevTag }} \
        --env LABELS="$LABELS" \
        --env OUT_NAME="$OUT_NAME" \
        --env VERSION="$OUT_VERSION" \
        --env OUT_REF="oci:$OUT_NAME" \
        --env GIT_DIR="/var/git" \
        --user 0:0 \
        ghcr.io/hhd-dev/rechunk:latest \
        /sources/rechunk/3_chunk.sh

    # Clean up rechunk output
    ${SUDOIF} find "$OUT_NAME" -type d -exec chmod 0755 {} \; || true
    ${SUDOIF} find "$OUT_NAME"* -type f -exec chmod 0644 {} \; || true

    if [[ "${UID}" -gt "0" ]]; then
        ${SUDOIF} chown -R ${UID}:${GROUPS} "${PWD}"
    elif [[ "${UID}" == "0" && -n "${SUDO_USER:-}" ]]; then
        ${SUDOIF} chown -R ${SUDO_UID}:${SUDO_GID} "${PWD}"
    fi

    ${SUDOIF} ${PODMAN} volume rm {{ image }}_{{ tag }}_cache_ostree

    # Load the rechunked image back into Podman
    OUT_IMAGE_REF="oci:${PWD}/{{ image }}"

    # Workaround upper-case letters in path (e.g. ~/Documents/...)
    if printf '%s' "$OUT_IMAGE_REF" | egrep -o '[A-Z]' >/dev/null; then
        ln -s "$PWD" "/tmp/${OUT_NAME}_${OUT_VERSION}"
        OUT_IMAGE_REF="oci:/tmp/${OUT_NAME}_${OUT_VERSION}/${OUT_NAME}"
    fi

    OUT_IMAGE="$(${PODMAN} pull "$OUT_IMAGE_REF")"
    ${PODMAN} untag "${OUT_IMAGE}"
    ${PODMAN} tag "${OUT_IMAGE}" "localhost/{{ image }}:$OUT_VERSION"
    ${PODMAN} tag "${OUT_IMAGE}" "localhost/{{ image }}:$OUT_VERSION_SYMBOLIC"
    ${PODMAN} images
    rm -rf "{{ image }}"

    if [[ "$OUT_IMAGE_REF" == "oci:/tmp/${OUT_NAME}_${OUT_VERSION}/${OUT_NAME}" && -L /tmp/${OUT_NAME}_${OUT_VERSION} ]]; then
        rm -f /tmp/${OUT_NAME}_${OUT_VERSION}
    fi

# Build ISO
[group('ISO')]
build-iso image=repo_name tag="stable" ghcr="0" clean="0":
    #!/bin/bash
    set -euxo pipefail

    # Validate that the user provided a valid image
    declare -A ALL_IMAGES={{ images }}
    TARGET_IMAGE="${ALL_IMAGES[{{ image }}]-}"
    if [[ -z "$TARGET_IMAGE" ]]; then
        echo "No such image {{ image }}."
        exit 1
    fi

    # Verify the ISO builder image
    just verify-container "build-container-installer" "ghcr.io/jasonn3" "https://raw.githubusercontent.com/JasonN3/build-container-installer/refs/heads/main/cosign.pub"

    # Set up build directory structure
    mkdir -p build/{flatpak-refs,output,bin}
    FLATPAK_REFS_DIR="build/flatpak-refs"
    FLATPAK_REFS_DIR_ABS="$(realpath ${FLATPAK_REFS_DIR})"

    # Build from GHCR or localhost
    if [[ "{{ ghcr }}" == "1" ]]; then
        IMAGE_REGISTRY="ghcr.io/{{ repo_user }}"
        IMAGE_FULL="$IMAGE_REGISTRY/{{ image }}:{{ tag }}"

        # Verify the downloaded container
        just verify-container "{{ image }}:{{ tag }}" "${IMAGE_REGISTRY}" "https://raw.githubusercontent.com/{{ repo_user }}/{{ repo_name }}/refs/heads/main/cosign.pub"
    else
        IMAGE_REGISTRY="localhost"
        IMAGE_FULL="$IMAGE_REGISTRY/{{ image }}:{{ tag }}"
        ID=$(${PODMAN} images --filter "reference=${IMAGE_FULL}" --format "'{{ '{{.ID}}' }}'")

        if [[ -z "$ID" ]]; then
            just build {{ image }} {{ tag }}
        fi
    fi

    # Remove ISO files if they already exist
    if ls build/output | grep '{{ image }}-{{ tag }}.iso'; then
        rm -f "build/output/{{ image }}-{{ tag }}.iso"*
    fi

    # Load image into rootful podman
    if [[ "${UID}" -gt "0" && ! ${PODMAN} =~ docker ]]; then
        if [[ "{{ ghcr }}" == "0" ]]; then
            ${PODMAN} save "$IMAGE_FULL" | ${SUDOIF} ${PODMAN} load
        else
            ${SUDOIF} ${PODMAN} pull "$IMAGE_FULL"
        fi
    fi

    # Build preinstalled flatpak list
    curl -Lo "${FLATPAK_REFS_DIR_ABS}/flatpaks-src.txt" "https://raw.githubusercontent.com/ublue-os/aurora/refs/heads/main/aurora_flatpaks/flatpaks"
    curl -L "https://raw.githubusercontent.com/ublue-os/aurora/refs/heads/main/dx_flatpaks/flatpaks" >> "${FLATPAK_REFS_DIR_ABS}/flatpaks-src.txt"

    jq -r .flatpak.include[] packages.json >> "${FLATPAK_REFS_DIR_ABS}/flatpaks-src.txt"
    jq -r .flatpak.exclude[] packages.json | grep -vf - "${FLATPAK_REFS_DIR_ABS}/flatpaks-src.txt" > "${FLATPAK_REFS_DIR_ABS}/flatpaks.txt"
    rm -f "${FLATPAK_REFS_DIR_ABS}/flatpaks-src.txt"

    # Resolve flatpak dependencies
    cat > "build/bin/install-flatpaks.sh" <<EOF
    mkdir -p /flatpak/{flatpak,triggers}
    mkdir -p /var/tmp
    chmod -R 1777 /var/tmp
    flatpak config --system --set languages "*"
    flatpak remote-add --system flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak install --system -y flathub \$(cat /output/flatpaks.txt)
    ostree refs --repo=\${FLATPAK_SYSTEM_DIR}/repo | grep '^deploy/' | grep -v 'org\.freedesktop\.Platform\.openh264' | sed 's/^deploy\///g' > /output/flatpaks-with-deps
    EOF
    chmod 755 "build/bin/install-flatpaks.sh"

    ${SUDOIF} ${PODMAN} run --rm --privileged \
        --entrypoint /bin/bash \
        -e FLATPAK_SYSTEM_DIR=/flatpak/flatpak \
        -e FLATPAK_TRIGGERS_DIR=/flatpak/triggers \
        -v ${FLATPAK_REFS_DIR_ABS}:/output \
        -v "${PWD}/build/bin/install-flatpaks.sh:/install-flatpaks.sh" \
        ${IMAGE_FULL} /install-flatpaks.sh

    # Pull the Fedora version from the image
    VERSION="$(${SUDOIF} ${PODMAN} inspect ${IMAGE_FULL} | jq -r '.[]["Config"]["Labels"]["ostree.linux"]' | grep -oP 'fc\K[0-9]+')"

    # Clean up if requested
    if [[ "{{ ghcr }}" == "1" && "{{ clean }}" == "1" ]]; then
        ${SUDOIF} ${PODMAN} rmi "${IMAGE_FULL}"
    fi

    # Prepare ISO builder arguments
    ISO_BUILD_ARGS=(--volume "${PWD}:/work")
    if [[ "{{ ghcr }}" == "0" ]]; then
        ISO_BUILD_ARGS+=(--volume "/var/lib/containers/storage:/var/lib/containers/storage")
    fi
    ISO_BUILD_ARGS+=(ghcr.io/jasonn3/build-container-installer:latest)
    ISO_BUILD_ARGS+=(ARCH="x86_64")
    ISO_BUILD_ARGS+=(ENROLLMENT_PASSWORD="universalblue")
    ISO_BUILD_ARGS+=(FLATPAK_REMOTE_REFS_DIR="/work/${FLATPAK_REFS_DIR}")
    ISO_BUILD_ARGS+=(IMAGE_NAME="{{ image }}")
    ISO_BUILD_ARGS+=(IMAGE_REPO="${IMAGE_REGISTRY}")
    ISO_BUILD_ARGS+=(IMAGE_SIGNED="true")
    if [[ "{{ ghcr }}" == "0" ]]; then
        ISO_BUILD_ARGS+=(IMAGE_SRC="containers-storage:${IMAGE_FULL}")
    fi
    ISO_BUILD_ARGS+=(IMAGE_TAG="{{ tag }}")
    ISO_BUILD_ARGS+=(ISO_NAME="/work/build/output/{{ image }}-{{ tag }}.iso")
    ISO_BUILD_ARGS+=(SECURE_BOOT_KEY_URL="https://github.com/ublue-os/akmods/raw/main/certs/public_key.der")
    ISO_BUILD_ARGS+=(VARIANT="Kinoite")
    ISO_BUILD_ARGS+=(VERSION="${VERSION}")
    ISO_BUILD_ARGS+=(WEB_UI="false")

    ${SUDOIF} ${PODMAN} run --rm --privileged --pull=newer --security-opt label=disable "${ISO_BUILD_ARGS[@]}"
    mv build/output/{{ image }}-{{ tag }}.iso-CHECKSUM build/output/{{ image }}-{{ tag }}.iso.sha256
    
    if [[ "${UID}" -gt "0" ]]; then
        ${SUDOIF} chown -R ${UID}:${GROUPS} "${PWD}"
        ${SUDOIF} ${PODMAN} rmi "${IMAGE_FULL}"
    elif [[ "${UID}" == "0" && -n "${SUDO_USER:-}" ]]; then
        ${SUDOIF} chown -R ${SUDO_UID}:${SUDO_GID} "${PWD}"
    fi

# Verify Container with cosign
[group('Utility')]
verify-container container="" registry="ghcr.io/ublue-os" $key="":
    #!/bin/bash
    set -euxo pipefail

    # Set up cosign
    COSIGN="$(command -v cosign || true)"
    if [[ -z "$COSIGN" ]]; then
        mkdir -p "${PWD}/build/bin"
        COSIGN_CONTAINER_ID="$(${PODMAN} create cgr.dev/chainguard/cosign:latest bash)"
        ${PODMAN} cp "${COSIGN_CONTAINER_ID}:/usr/bin/cosign" "${PWD}/build/bin/cosign"
        ${PODMAN} container rm -f "${COSIGN_CONTAINER_ID}"
        COSIGN="${PWD}/build/bin/cosign"
    fi

    if [[ -z "${key:-}" && "{{ registry }}" == "ghcr.io/ublue-os" ]]; then
        key="https://raw.githubusercontent.com/ublue-os/main/main/cosign.pub"
    fi

    if ! $COSIGN verify --key "${key}" "{{ registry }}/{{ container }}" >/dev/null; then
        echo "Verification of {{ registry }}/{{ container }} failed. Please ensure the container's public key is correct."
        exit 1
    fi

[group('Image')]
list-tags image=repo_name:
    #!/usr/bin/env bash
    podman image ls --filter reference='{{ image }}' --format "'{{ '{{.Tag}}' }}'"
