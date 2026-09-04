#!/usr/bin/env bash
set -euo pipefail
mkdir -p build
odin build src -out:build/shen-joy
