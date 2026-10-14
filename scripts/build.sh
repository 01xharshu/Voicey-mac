#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -f .build/native-llama/libvoicey_llama.dylib ] || [ ! -f .build/native-whisper/libvoicey_whisper.dylib ]; then scripts/build-native.sh; fi
python3 scripts/prepare-neural-speech.py
swift build -c release
mkdir -p dist .build/runtimes
voicey_stage=$(mktemp -d "$PWD/.build/voicey-bundle.XXXXXX")
voicey_app="$voicey_stage/Voicey.app"
mkdir -p "$voicey_app/Contents/"{MacOS,Frameworks,Resources}
cp .build/release/Voicey "$voicey_app/Contents/MacOS/Voicey"
cp .build/release/VoiceyProcessRunner "$voicey_app/Contents/MacOS/VoiceyProcessRunner"
python3 scripts/local-signing.py "$voicey_app/Contents/MacOS/VoiceyProcessRunner" local.voicey.processrunner
cp .build/release/VoiceyBrowserHost "$voicey_app/Contents/MacOS/VoiceyBrowserHost"
cp -R browser-extension "$voicey_app/Contents/Resources/BrowserExtension"
python3 scripts/local-signing.py "$voicey_app/Contents/MacOS/VoiceyBrowserHost" local.voicey.browserhost
cp .build/native-llama/libvoicey_llama.dylib .build/native-whisper/libvoicey_whisper.dylib "$voicey_app/Contents/Frameworks/"
cp .deps/sherpa-onnx/sherpa-onnx-v1.13.8-osx-arm64-shared/lib/{libsherpa-onnx-c-api,libonnxruntime}.dylib "$voicey_app/Contents/Frameworks/"
install_name_tool -change @rpath/libonnxruntime.dylib @loader_path/libonnxruntime.dylib "$voicey_app/Contents/Frameworks/libsherpa-onnx-c-api.dylib"
cp -R .deps/sherpa-onnx/kokoro-multi-lang-v1_0 "$voicey_app/Contents/Resources/Kokoro"
cp .deps/sherpa-onnx/licenses/*.txt "$voicey_app/Contents/Resources/"
cp "$voicey_app/Contents/Frameworks/"*.dylib .build/runtimes/
cp docs/Info.plist "$voicey_app/Contents/Info.plist"
cp scripts/install-browser-bridge.py "$voicey_app/Contents/Resources/install-browser-bridge.py"
cp docs/COMPUTER_USE.md "$voicey_app/Contents/Resources/COMPUTER_USE.md"
cp docs/THIRD_PARTY_NOTICES.md "$voicey_app/Contents/Resources/"
cp .deps/llama.cpp/LICENSE "$voicey_app/Contents/Resources/llama-LICENSE.txt"
cp .deps/whisper.cpp/LICENSE "$voicey_app/Contents/Resources/whisper-LICENSE.txt"
cp .deps/llama.cpp/LICENSE "$voicey_app/Contents/Resources/ggml-LICENSE.txt"
for library in "$voicey_app/Contents/Frameworks/"*.dylib; do python3 scripts/local-signing.py "$library" "local.voicey.runtime.$(basename "$library" .dylib)"; done
python3 scripts/local-signing.py "$voicey_app" local.voicey.mac
codesign --verify --deep --strict "$voicey_app"
# Preserve the previous bundle's inode so a running instance is never overwritten.
if [ -d dist/Voicey.app ]; then mv dist/Voicey.app "$voicey_stage/previous-Voicey.app"; fi
mv "$voicey_app" dist/Voicey.app
printf 'Built %s/dist/Voicey.app\n' "$PWD"
