# Verification evidence — 2026-10-14

Environment: arm64 Mac, macOS SDK 27, Swift 6.4, CMake 4.2, Command Line Tools. Full Xcode is absent; no XCTest framework or SwiftUI macro plugin is present. The app uses the existing State wrapper and a standalone Swift check executable to support this environment.

## Completed

- Embedded llama.cpp and whisper.cpp C++ bridges compiled in Release with CPU/Accelerate. `otool -L` shows only system dylibs and Accelerate dependencies. Separate export lists hide each copy of ggml; no external model executable or HTTP inference backend is used.
- 18 initial core checks passed with zero failures: Command chord ordering/single-tap exclusion/latching/reset, intent parsing, URL/risk policy, ambiguity, contextual replies, local memories/corrections/conflicts/deletion, corruption preservation, nested/hidden/symlink/missing file search, duplicate results, folder validation, cancellation, model-output rejection, URL approval/replay/expiry, and tool arguments. Browser preference/explicit/unavailable coverage subsequently added; final result below.
- Both real model artifacts SHA256 verified. Combined storage 1,430,390,793 bytes, installed under `~/Library/Application Support/Voicey/Models` outside Git.
- `python3 scripts/native-smoke.py` passed: embedded multilingual Whisper base recognized the repository's speech sample in 0.88 seconds; embedded Qwen loaded in 1.4 seconds, produced a Figma launch intent in 3.8 seconds and a BenQ invoice reveal intent in 2.52 seconds; cancelled native inference returned no output. These timings are individual warm-cache CPU measurements, not general latency guarantees or Indian-accent acceptance.
- Initial tests found a folder-prefix off-by-one and Figma app/site collision; repaired and retested. Initial broad invoice model interpretation carried the whole utterance as a query; few-shot examples improved it to a usable BenQ invoice query. General interpretation quality remains bounded by the compact model.

## Pending at this checkpoint

Release bundle/signing, final 19-check run, and visible app smoke are underway. Actual microphone, physical-key permission and system integration manual acceptance is separate. No notarization or distribution signing claimed. See CODEX_HANDOFF.md for latest checkpoint.

## Practical limits

- CPU/Accelerate only in this build; Metal, Intel hardware, and low-memory devices have not been verified.
- Search is bounded to 80,000 entries per walk, with scoped fallback, excluding packages, symbolic links, caches, Library and dependency/build directories. It uses live metadata, with no Spotlight merge or retained incremental index. An unindexed or inaccessible file may require explicitly adding a scope. It does not promise complete-disk discovery.
- Memory is versioned atomic JSON, not SQLite; unknown versions and corrupt records are preserved and reported. Only explicit aliases/corrections and a browser preference are retained; history/automatic learning are disabled.
- Website approval is enforced; destructive tools and shell execution are unavailable. Recording can be interrupted with Speak/Finish/Cancel, but seamless acoustic barge-in while the greeting speaks is not implemented.
- Application discovery scans normal installed app directories plus registered browser handlers. Voice quality and end-of-speech accuracy require actual live checks. The app streaming downloader's pause/resume/error UX requires live network-fault QA beyond checksum-verified development downloads.
