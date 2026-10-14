#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build.sh
ditto -c -k --sequesterRsrc --keepParent dist/Voicey.app dist/Voicey-mac.zip

ditto -c -k --keepParent browser-extension dist/Voicey-browser-extension.zip
