# Realistic local voice research — 2026-10-14

User rejected Rishi Enhanced as robotic. That listening judgment supersedes the earlier mechanical speech PASS. No neural voice is yet wired into Voicey’s actual reply pipeline.

## Recommendation

Kokoro-82M v1.0, initially Heart (`af_heart`) and Bella (`af_bella`). Model weights Apache 2.0. The author rates Heart A and Bella A-; those are author ratings, not independent proof of user-perceived naturalness. Michael supplies a male US option and Emma a female UK option.

## Actual local previews

Generated all four WAVs from the same synthetic greeting on this Mac. Native sherpa-onnx 1.13.8 runtime, CPU provider, two threads; Kokoro v1.0 fp32 conversion. No website synthesis, paid API, cloned private voice, or account required. Runtime command-line executable is used only for this research; it is not integrated or redistributed in Voicey.

| Voice | Generation seconds including process/model startup | Audio seconds |
| --- | ---: | ---: |
| Heart | 4.22 | 8.3 |
| Bella | 4.92 | 8.23 |
| Michael | 4.69 | 9.36 |
| Emma | 4.92 | 8.77 |

24 kHz mono 16-bit WAV. Embedded Whisper independently transcribed the generated clips; all were non-silent and included project/browser/listening key phrases. This checks content and signal, not subjective voice quality. JSON evidence is beside the WAVs.

## Other candidates

- Chatterbox: MIT repository; current official family includes Turbo 350M, Nano 110M and Multilingual V3 500M. Expressive speech and paralinguistic tags are advertised, with a Mac MPS example. Not downloaded or benchmarked in this session.
- Pocket TTS: 100M CPU model with streaming. Official developers report about 200 ms first-chunk latency and six times real-time on M4 MacBook Air; not measured here. Code MIT, current official model card CC BY 4.0 and gated contact-sharing access. Voice references have their own licenses. Not an account-free download path by default.

## Integration findings

Swift/MLX Kokoro ports exist but their package manifests can pull MLX even when offering CoreML. This workspace has Command Line Tools only and previously could not build custom Metal kernels. FluidAudio provides a native CoreML route; verify the exact pinned version, voice support, full model dependency licenses, offline cache behavior, punctuation handling, short-reply quality and cancellation before shipping. Its v0.15.2 seven-stage ANE variant supports only Heart for English; do not advertise arbitrary voices on that conversion. Newer multi-voice backend needs separate verification. sherpa-onnx model package includes eSpeak data, so bundled native-runtime/phonemizer licensing must be audited before redistribution; model Apache license alone is not the entire dependency license.

## Primary sources

- https://huggingface.co/hexgrad/Kokoro-82M
- https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md
- https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html
- https://github.com/k2-fsa/sherpa-onnx/releases/tag/v1.13.8
- https://github.com/resemble-ai/chatterbox
- https://github.com/kyutai-labs/pocket-tts
- https://huggingface.co/kyutai/pocket-tts
- https://github.com/FluidInference/FluidAudio
- https://raw.githubusercontent.com/FluidInference/FluidAudio/v0.15.2/Documentation/TTS/KokoroAne.md

## Download provenance

- runtime.tar.bz2: 20314448 bytes, observed SHA256 `b10e5c7e2c30ea03de9c442655d14860d9edc475c6251d58a8f5f06e913a1d56`. This is the downloaded artifact hash, not an independently authenticated upstream checksum.
- kokoro.tar.bz2: 349906910 bytes, observed SHA256 `c5f7e2d2caf082bc1d20fb70334a61d99d20b484500aad32e7cf84c128ea3298`. This is the downloaded artifact hash, not an independently authenticated upstream checksum.
