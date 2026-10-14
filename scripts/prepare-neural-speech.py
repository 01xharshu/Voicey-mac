#!/usr/bin/env python3
"""Prepare pinned on-device Kokoro assets. No speech or inference subprocess."""
import hashlib, pathlib, tarfile, urllib.request
root = pathlib.Path(__file__).resolve().parent.parent
cache = root / '.deps/sherpa-onnx'
cache.mkdir(parents=True, exist_ok=True)
artifacts = [
 ('runtime.tar.bz2', 'https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/sherpa-onnx-v1.13.8-osx-arm64-shared.tar.bz2', 'b10e5c7e2c30ea03de9c442655d14860d9edc475c6251d58a8f5f06e913a1d56'),
 ('kokoro.tar.bz2', 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2', 'c5f7e2d2caf082bc1d20fb70334a61d99d20b484500aad32e7cf84c128ea3298'),
]
for name, url, expected in artifacts:
 path = cache / name
 if not path.exists():
  partial = path.with_suffix(path.suffix + '.partial')
  print('Downloading', name, flush=True)
  with urllib.request.urlopen(url, timeout=60) as response, partial.open('wb') as output:
   while chunk := response.read(1024 * 1024): output.write(chunk)
  partial.replace(path)
 digest = hashlib.sha256()
 with path.open('rb') as source:
  for chunk in iter(lambda: source.read(1024 * 1024), b''): digest.update(chunk)
 if digest.hexdigest() != expected: raise RuntimeError('Pinned neural asset checksum mismatch: ' + name)
 directory = cache / ('sherpa-onnx-v1.13.8-osx-arm64-shared' if name == 'runtime.tar.bz2' else 'kokoro-multi-lang-v1_0')
 if not directory.exists():
  with tarfile.open(path) as archive: archive.extractall(cache, filter='data')
licenses = {
 'sherpa-onnx-LICENSE.txt': 'https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/v1.13.8/LICENSE',
 'onnxruntime-LICENSE.txt': 'https://raw.githubusercontent.com/microsoft/onnxruntime/v1.28.2/LICENSE',
 'espeak-ng-COPYING.txt': 'https://raw.githubusercontent.com/csukuangfj/espeak-ng/ed530aa113046142eb5115cf2fc9157854d0ffe1/COPYING',
 'piper-phonemize-LICENSE.txt': 'https://raw.githubusercontent.com/csukuangfj/piper-phonemize/f3ff95afc03640bc1399e113e83361192a2fafb4/LICENSE.md',
}
license_dir = cache / 'licenses'
license_dir.mkdir(exist_ok=True)
for name, url in licenses.items():
 path = license_dir / name
 if not path.exists():
  with urllib.request.urlopen(url, timeout=30) as response: path.write_bytes(response.read())
print('Verified neural runtime and Kokoro voice assets', flush=True)
