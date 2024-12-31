#!/bin/bash
# Borrowed (and modified) from https://github.com/m2Giles/m2os/blob/main/signing.sh

set -euxo pipefail

mkdir -p {,/usr}/etc/containers/registries.d/
mkdir -p {,/usr}/etc/pki/containers

if [[ ! -f /usr/etc/containers/policy.json ]]; then
    echo '{"transports":{"docker":{}}}' > /usr/etc/containers/policy.json
fi

cat > /etc/containers/policy.json <<< "$(jq '.transports.docker |=. + {
    "ghcr.io/hal7df/borealos": [{
        "type": "sigstoreSigned",
        "keyPath": "/etc/pki/containers/borealos.pub",
        "signedIdentity": {
            "type": "matchRepository"
        }
    }],
    "ghcr.io/hal7df/borealos-nvidia": [{
        "type": "sigstoreSigned",
        "keyPath": "/etc/pki/containers/borealos.pub",
        "signedIdentity": {
            "type": "matchRepository"
        }
    }
]}' </usr/etc/containers/policy.json)"

cp /tmp/cosign.pub /etc/pki/containers/borealos.pub
tee /etc/containers/registries.d/borealos.yaml <<EOF
docker:
    ghcr.io/hal7df/borealos:
        use-sigstore-attachments: true
    ghcr.io/hal7df/borealos-nvidia:
        use-sigstore-attachments: true
EOF

cp {,/usr}/etc/containers/policy.json
cp {,/usr}/etc/pki/containers/borealos.pub