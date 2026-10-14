#!/bin/bash
set -euo pipefail
sw_vers
uname -m
swift --version
xcrun --show-sdk-path
cmake --version
git --version
clang --version
