#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .deps
for engine in llama whisper; do
 revision=6868a52cb337450658006ad2f9281c2eb63f1666
 if [ "$engine" = whisper ]; then revision=0c7be696371069e0baa2515ed7aa08d5a5473aa6; fi
 if [ ! -d ".deps/$engine.cpp/.git" ]; then git clone "https://github.com/ggml-org/$engine.cpp.git" ".deps/$engine.cpp"; fi
 git -C ".deps/$engine.cpp" fetch origin "$revision" --depth 1
 git -C ".deps/$engine.cpp" checkout --detach "$revision"
 cmake -S Native -B ".build/native-$engine" -DENGINE="$engine" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
 cmake --build ".build/native-$engine" -j 4
 done
