# Adapted from https://github.com/m2Giles/m2os/blob/main/Justfile

repo_user := "hal7df"
repo_name := "borealos"
images := "([" + repo_name + "]='" + repo_name + "' [" + repo_name + "-nvidia]='" + repo_name + "-nvidia' [" + repo_name + "-nvidia-open]=" + repo_name + "-nvidia-open)"
image_desc := "Custom lightweight build of Aurora Linux targeted at power users"

artifact_dir := "./out"
selinux := env("BUILD_SELINUX", "true")
bib_image := env("BIB_IMAGE", "quay.io/centos-bootc/bootc-image-builder:latest")
chunkah_digest := "sha256:ff8b8b466a942ec6000445d4001fc661e2fc5a952ad9ee29b4de9ab09d1d1708"
chunkah := "quay.io/coreos/chunkah@" + chunkah_digest

bootc_mount_options := if selinux == "true" { "-v /var/lib/containers:/var/lib/containers:Z -v /etc/containers:/etc/containers:Z -v /sys/fs/selinux:/sys/fs/selinux --security-opt label=type:unconfined_t" } else { "-v /var/lib/containers:/var/lib/containers -v /etc/containers:/etc/containers" }

export SUDOIF := if `id -u` == "0" { "" } else { "sudo" }
export PODMAN := if path_exists("/usr/bin/podman") == "true" { env("PODMAN", "/usr/bin/podman") } else if path_exists("/usr/bin/docker") == "true" { env("PODMAN", "/usr/bin/docker") } else { env("PODMAN", "exit 1") }

[private]
default:
    @just --list

# Validate Justfile
[group('Just')]
lint:
    #!/usr/bin/env bash
    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile

[group('Just')]
lint-fix:
    #!/usr/bin/env bash
    echo "Fixing syntax: Justfile"
    just --unstable --fmt -f Justfile

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
build image=repo_name $SOURCE_TAG="stable" $DEST_TAG="stable":
    #!/usr/bin/env bash
    set -euxo pipefail

    # Validate that the user provided a valid image
    declare -A ALL_IMAGES={{ images }}
    TARGET_IMAGE="${ALL_IMAGES[{{ image }}]-}"
    if [[ -z "$TARGET_IMAGE" ]]; then
        echo "No such image {{ image }}."
        exit 1
    fi

    BUILD_ARGS=()
    SOURCE_IMAGE="${TARGET_IMAGE/{{ repo_name }}/aurora-dx}"

    # Determine the Fedora version of upstream
    skopeo inspect "docker://ghcr.io/ublue-os/${SOURCE_IMAGE}:${SOURCE_TAG}" > "/tmp/inspect-{{ image }}.json"
    FEDORA_VERSION="$(jq -r '.Labels["ostree.linux"]' < "/tmp/inspect-{{ image }}.json" | grep -oP 'fc\K[0-9]+')"

    # Determine if the tag we're trying to build exists already
    TAG_BASE="${FEDORA_VERSION}.$(date +%Y%m%d)"
    EXISTING_TAGS="$(skopeo list-tags "docker://ghcr.io/{{ repo_user }}/{{ image }}" | jq -r ".Tags | map(select(startswith(\"${DEST_TAG}-${TAG_BASE}\")))[]")"

    TAGN=1
    TARGET_TAG="${DEST_TAG}-${TAG_BASE}.${TAGN}"

    while printf '%s\n' "$EXISTING_TAGS" | grep -q "$TARGET_TAG"; do
        TAGN=$((TAGN + 1))
        TARGET_TAG="${DEST_TAG}-${TAG_BASE}.${TAGN}"
    done

    IMAGE_VERSION="${TAG_BASE}.${TAGN}"
    TARGET_TAG="${TARGET_TAG}-unopt"

    BUILD_ARGS+=("--file" "Containerfile")
    BUILD_ARGS+=("--label" "org.opencontainers.image.title={{ image }}")
    BUILD_ARGS+=("--label" "org.opencontainers.image.version=${IMAGE_VERSION}")
    BUILD_ARGS+=("--label" "org.opencontainers.image.revision=$(git rev-parse HEAD))")
    BUILD_ARGS+=("--label" "org.opencontainers.image.description={{ image_desc }}")
    BUILD_ARGS+=("--label" "ostree.linux=$(jq -r '.Labels["ostree.linux"]' < /tmp/inspect-{{ image }}.json)")
    BUILD_ARGS+=("--build-arg" "SOURCE_IMAGE=$SOURCE_IMAGE")
    BUILD_ARGS+=("--build-arg" "SOURCE_TAG=$SOURCE_TAG")
    BUILD_ARGS+=("--build-arg" "TARGET_IMAGE=$TARGET_IMAGE")
    BUILD_ARGS+=("--build-arg" "TARGET_RELEASE_TYPE=$DEST_TAG")
    BUILD_ARGS+=("--build-arg" "VERSION=${IMAGE_VERSION}")
    BUILD_ARGS+=("--tag" "localhost/$TARGET_IMAGE:$TARGET_TAG")

    if [[ "${PODMAN}" =~ docker && "${TERM}" == "dumb" ]]; then
        BUILD_ARGS+=("--progress" "plain")
    elif [[ "${PODMAN}" =~ podman && "$UID" -ne 0 ]]; then
        BUILD_ARGS+=("--security-opt" "label=disable")
    fi

    ${PODMAN} pull "ghcr.io/ublue-os/${SOURCE_IMAGE}:${SOURCE_TAG}"
    ${PODMAN} build "${BUILD_ARGS[@]}"

    just rechunk "$TARGET_IMAGE" "$TARGET_TAG" "$DEST_TAG"

[private]
rechunk image=repo_name $tag="stable-unopt" prevTag="stable":
    #!/usr/bin/env bash
    set -euxo pipefail
    ID="$(${PODMAN} images --filter reference=localhost/{{ image }}:{{ tag }} --format "'{{ '{{.ID}}' }}'")"

    if [[ -z "$ID" ]]; then
        echo "Image could not be found for rechunking. Run 'just build {{ image }}' to create the unoptimized image."
        exit 1
    fi

    # Set metadata for the image
    OUT_TAG="${tag/%-unopt/}"
    CHUNKAH_CONFIG_STR=$(${PODMAN} inspect "{{ image }}:${tag}")
    export CHUNKAH_CONFIG_STR

    # Rechunk the image
    ${PODMAN} run --rm --mount=type=image,src="{{ image }}:${tag}",target=/chunkah \
        -e CHUNKAH_CONFIG_STR \
        "{{ chunkah }}" build \
        --verbose \
        --compressed \
        --max-layers 128 \
        --prune /sysroot/ \
        --label ostree.commit- \
        --label ostree.final-diffid- \
        --tag "{{ image }}:$OUT_TAG" | ${PODMAN} load

    # Remove the unoptimized image
    ${PODMAN} rmi "{{ image }}:${tag}"

[group('Image')]
load-image image=repo_name:
    #!/usr/bin/env bash
    set -euxo pipefail

    LOAD_IMAGE_REF="oci:${PWD}/{{ image }}"

    # Workaround uppercase letters in path (e.g. ~/Documents/...)
    if printf '%s' "$LOAD_IMAGE_REF" | egrep -o '[A-Z]' >/dev/null; then
        ln -s "$PWD" "/tmp/{{ image }}_work"
        LOAD_IMAGE_REF="oci:/tmp/{{ image }}_work/{{ image }}"
    fi

    LOAD_IMAGE="$(${PODMAN} pull "$LOAD_IMAGE_REF")"
    LOAD_IMAGE_VERSION="$(${PODMAN} inspect "$LOAD_IMAGE" | jq -r '.[]["Config"]["Labels"]["org.opencontainers.image.version"]')"
    LOAD_IMAGE_VERSION_SYMBOLIC="$(printf '%s' "$LOAD_IMAGE_VERSION" | sed 's/-[[:digit:]]\+\.[[:digit:]]\+$//')"

    ${PODMAN} untag "${LOAD_IMAGE}"
    ${PODMAN} tag "${LOAD_IMAGE}" "localhost/{{ image }}:$LOAD_IMAGE_VERSION"
    ${PODMAN} tag "${LOAD_IMAGE}" "localhost/{{ image }}:$LOAD_IMAGE_VERSION_SYMBOLIC"
    ${PODMAN} images

    if [[ "$LOAD_IMAGE_REF" == "oci:/tmp/{{ image }}_work/{{ image }}" && -L /tmp/{{ image }}_work ]]; then
        rm -f /tmp/{{ image }}_work
    fi
    rm -rf "{{ image }}/"

# Build ISO
[group('Boot Media')]
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
    cp flatpaks.txt "${FLATPAK_REFS_DIR_ABS}/flatpaks.txt"

    # Build from GHCR or localhost
    if [[ "{{ ghcr }}" == "1" ]]; then
        IMAGE_REGISTRY="ghcr.io/{{ repo_user }}"
        IMAGE_FULL="$IMAGE_REGISTRY/{{ image }}:{{ tag }}"

        # Verify the downloaded container
        just verify-container "{{ image }}:{{ tag }}" "${IMAGE_REGISTRY}" "https://raw.githubusercontent.com/{{ repo_user }}/{{ repo_name }}/refs/heads/main/conf/usr/lib/pki/containers/borealos.pub"
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

[group("Boot Media")]
disk-image $image=repo_name $tag="-detect" $base_dir=artifact_dir $filesystem="ext4":
    #!/usr/bin/env bash
    set -euxo pipefail

    if [[ ! -d "${base_dir}" ]]; then
        mkdir -p "${base_dir}"
    fi

    if [[ "${PODMAN}" =~ podman ]]; then
        image="localhost/${image}"
    fi

    if [[ "$tag" == "-detect" ]]; then
        tag="$(${PODMAN} image ls -f "reference=${image}" --format '{{{{.Tag}}' | head -1)"
    fi

    # make sure the image actually exists
    if [[ -z "$tag" ]] || ! ${PODMAN} image ls --format '{{{{.Repository}}:{{{{.Tag}}' | grep -q "${image}:${tag}"; then
        just build "${image#localhost/}"
        just load-image "${image#localhost/}"

        if [[ -z "$tag" ]]; then
            tag="$(${PODMAN} image ls -f "reference=${image}" --format '{{{{.Tag}}' | head -1)"
        fi
    fi

    # we need to load the image into rootful podman
    if [[ "${PODMAN}" =~ podman ]] && ! ${SUDOIF} ${PODMAN} image ls --format '{{{{ .Repository }}:{{{{ .Tag }}' | grep -q "${image}:${tag}"; then
        ${PODMAN} save "localhost/${image}:${tag}" | ${SUDOIF} ${PODMAN} load
    fi

    ARGS=(--type qcow2)
    ARGS+=(--rootfs ext4)
    ARGS+=(--use-librepo=True)

    ${SUDOIF} ${PODMAN} run -it --rm \
        --privileged \
        --pull=newer \
        --net=host \
        --security-opt label=type:unconfined_t \
        -v "${PWD}/image.toml:/config.toml:ro" \
        -v "${base_dir}:/output" \
        -v "/var/lib/containers/storage:/var/lib/containers/storage" \
        "{{ bib_image }}" \
        "${ARGS[@]}" \
        "${image}:${tag}"

    sudo chown -R $USER:$USER "$base_dir"

# Run generated bootable disk image in an ephemeral VM
[group("Utility")]
run-vm $image=repo_name $tag="stable" $base_dir=artifact_dir $filesystem="ext4":
    #!/usr/bin/env bash
    set -euxo pipefail

    IMAGE_FILE="${base_dir}/qcow2/disk.qcow2"

    if [[ ! -e "$IMAGE_FILE" ]]; then
        just disk-image "$image" "$tag" "$base_dir" "$filesystem"
    fi

    # Determine available port to use
    PORT=8006
    while grep -q ":${PORT}" <<< $(ss -tunalp); do
        PORT=$(( PORT + 1 ))
    done
    echo "Using port: ${PORT}"
    echo "Connect via browser: http://localhost:${PORT}"

    # Construct VM run arguments
    RUN_ARGS=()
    RUN_ARGS+=(--rm --privileged)
    RUN_ARGS+=(--pull=newer)
    RUN_ARGS+=(--publish "127.0.0.1:${PORT}:8006")
    RUN_ARGS+=(--env "CPU_CORES=4")
    RUN_ARGS+=(--env "RAM_SIZE=4G")
    RUN_ARGS+=(--env "DISK_SIZE=64G")
    RUN_ARGS+=(--env "TPM=Y")
    RUN_ARGS+=(--env "GPU=Y")
    RUN_ARGS+=(--device=/dev/kvm)

    RUN_ARGS+=(--volume "${IMAGE_FILE}:/boot.qcow2")
    RUN_ARGS+=(ghcr.io/qemus/qemu)

    # Run the VM and open the browser to connect
    (sleep 5 && xdg-open "http://localhost:${PORT}") &
    ${PODMAN} run "${RUN_ARGS[@]}"

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
    podman image ls --filter reference='{{ image }}' --format "{{ '{{.Tag}}' }}"
