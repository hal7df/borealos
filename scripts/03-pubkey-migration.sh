#!/bin/bash

set -euxo pipefail

mkdir -p /etc/pki/containers
ln -s /usr/lib/pki/containers/borealos.pub /etc/pki/containers/borealos.pub
