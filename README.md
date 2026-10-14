# Voicey for macOS

Voicey is a native SwiftUI/AppKit menu-bar assistant with an animated glowing companion attached to the physical notch at the top center of the active display. The default activation gesture is **Control + Option + Command (⌃⌥⌘)**. General settings also offer **left + right physical Command** and a configurable fallback, **Option–Command–Space**. Voice is recorded only when you activate it; text input works without microphone permission.

Voicey runs speech recognition, language inference and speech synthesis locally. Optional browser workflows connect to the requested external service. Computer-use features need additional setup; WhatsApp chat reading, sending and reply monitoring are still incomplete. See the setup and capability limits below before relying on those workflows.

## Build and run

Requires macOS 14+, Swift 6 toolchain with the macOS SDK, CMake 3.20+, Git, and a C++17 compiler. Full Xcode is recommended but the project also supports the installed Command Line Tools. No Electron, development server, Docker, Ollama, model server, or inference subprocess is used.

Run these commands from the repository root. The first build needs internet access to fetch the pinned native dependencies; downloading models is a separate first-use step. Node.js/npm are needed only for browser-extension development tests, and Python 3 is needed for the bridge installer and optional integration checks.

```sh
scripts/check-prerequisites.sh
scripts/build.sh
scripts/test.sh
open dist/Voicey.app
```

To build the app and create distribution archives:

```sh
scripts/package.sh
```

Build output is `dist/Voicey.app`. Packaging creates `dist/Voicey-mac.zip` and `dist/Voicey-browser-extension.zip`; these generated artifacts are excluded from Git.

The initial native dependency build downloads and pins the two source repositories. Rebuild native libraries with `scripts/build-native.sh`. The release app embeds both compiled dylibs in `Contents/Frameworks`; their independent ggml versions are symbol-isolated. Dependencies and model weights are ignored by Git. The bundle uses ad-hoc signing for local execution; it is not notarized, Developer ID signed, or approved for distribution. Keep the bundle at a stable path when granting TCC permissions; rebuilding changes ad-hoc identity and can require reapproval.

## First use

1. Open the app and use its menu-bar waveform icon. Choose Settings.
2. In Local AI, download the language and speech models or import compatible local files. The app streams partial downloads to Application Support, resumes with HTTP Range, verifies pinned SHA256 and exact sizes, and only promotes verified downloads. Models are not bundled.
3. In Voice, grant microphone permission. In General, grant Input Monitoring for the three-modifier gesture. The app opens the appropriate System Settings pages; it cannot grant permissions itself. The Carbon fallback works when the event tap is unavailable; a conflicting fallback may need a different selection.
4. Add development folders in Files. Initial scopes are Desktop, Documents and Downloads with a bounded home-directory fallback when no match is found, subject to macOS folder access. Add folders with the supported folder picker and security-scoped bookmarks.
5. Hold Control, Option and Command together. Recording starts immediately, without a spoken greeting; Speak interrupts an existing reply. Silence ends recording, or select Finish. Responses requiring a choice continue listening after Voicey's question when the session began by voice.

## Actions

Clear requests execute directly: `Launch Figma`, `Open the Tipsy Docy folder`, `Find the BenQ invoice`, `Show invoice.pdf in Finder`, `Copy hello world`, or `Create a folder called Voicey Experiments in my Documents folder`. Searches recurse through authorized scopes and return real paths. File and app opening use NSWorkspace; folders use Finder. Missing or ambiguous results produce a concise explanation or choice.

`Open YouTube in Arc` displays the complete validated URL for approval. `Correct` approves it, then uses Arc if installed. Without an explicit browser or saved preference, choose a real registered browser. Enable Remember in Browser settings to save a preference locally. The approval is single-use, bound to that URL, expires after two minutes, and is discarded on cancellation/new commands. Browser default settings never change.

Explicit commands have a deterministic fast path; broader phrasing uses embedded Qwen with grammar-constrained JSON. All intents then pass the same registry, argument and risk policy. The model has no shell access, cannot authorize itself, and cannot bypass URL approval. The computer-use engine below extends these initial tools with verified workflows, exact approved commands, ChatGPT submission, unsent Gmail drafts and schema-gated Clock alarms. Arbitrary model-generated code, unsupported deletion, overwriting and purchases remain unavailable. Existing folder names are reused only when they are compatible directories.

Use `Remember my AI course as /absolute/path` to save an explicit alias, or after opening a folder say `I call this folder my AI course`. Memory settings let you inspect, replace or remove aliases and explicit vocabulary corrections. Corrections apply to whole words only. Conflicting aliases are preserved until explicitly edited. This is local memory, not model training.

## Architecture and privacy

| Path | Purpose |
| --- | --- |
| `Sources/Voicey/` | macOS app, companion UI, audio, settings and native computer-use adapters |
| `Sources/VoiceyCore/` | Shared intents, policy, planning, file search, memory and communication types |
| `Sources/NativeBridge/`, `Native/` | Runtime loader and embedded llama.cpp/whisper.cpp bridges |
| `Sources/VoiceyBrowserHost/` | Browser native-messaging host |
| `Sources/VoiceyProcessRunner/` | Helper for approved command execution and process cancellation |
| `Tests/VoiceyCoreTests/` | Standalone Swift checks and isolated fixtures |
| `browser-extension/` | Chromium extension and protocol/DOM fixtures |
| `scripts/` | Build, packaging, setup and integration-check tools |
| `docs/` | Setup guides, manual QA, recorded evidence and third-party notices |
| `web/` | Static landing page |

Generated native dependency checkouts live in `.deps/`; Swift and native build output lives in `.build/`. Neither directory is source to commit.

- `VoiceyCore`: Codable typed intents; registry and input schemas; deterministic policy; URL/path validation; modifier chord state machine; dialogue replies; single-use website authorization; bounded cancellation-aware recursive file search; versioned JSON memory.
- `Voicey`: native discovery, NSWorkspace execution, actor-isolated embedded engine, streaming model manager, AVAudioEngine 16 kHz mono capture, whisper.cpp transcription, AVSpeechSynthesizer playback, event tap/Carbon hotkeys, AppKit NSPanel, animated native glow, optional text input, SwiftUI settings and companion.
- `Native`: two separately linked C++ bridges calling actual llama.cpp/whisper.cpp APIs. No HTTP inference APIs, executable backends or cloud fallback.
- `Tests`: standalone native Swift checks using temporary directories and no real application/browser actions. This avoids the missing XCTest framework in CLT.

Data lives in `~/Library/Application Support/Voicey`: `Models/assistant.gguf`, `Models/speech.bin`, and `memory.json` (version 1, atomic saves, mode 0600). Raw audio stays in RAM. Computer Use retains at most 20 summaries containing task type, timestamp, status and step counts; clear these in settings. Raw task payloads are not persisted in that history. Search does not read document contents. There are no accounts, analytics, telemetry, or remote conversation stores. Voicey inference remains local. Approved navigation, ChatGPT questions and Gmail drafts use the selected browser and transmit the requested content to the named service.

The model pair occupies about 1.43 GB. Both runtimes load lazily and release their models after two idle minutes by default. Local AI settings offer 30-second, 2-minute and 5-minute retention; shorter retention saves resident memory at the cost of reloading on the next voice/model request. Explicit parsed commands do not load the language model. CPU with Accelerate is the currently tested backend; Metal is disabled because this environment lacks Xcode's Metal toolchain. See [third-party notices](docs/THIRD_PARTY_NOTICES.md) for model licenses, exact revisions and checksums. Imported files have their magic checked and are validated by the runtime on use; arbitrary model chat templates are not guaranteed. Prefer Qwen3-compatible GGUF.

## Verification and troubleshooting

Core checks: `scripts/test.sh`. Native model checks: `python3 scripts/native-smoke.py` after models are installed. Build logs can be captured with `scripts/build.sh > /tmp/voicey-build.log 2>&1`. macOS runtime diagnostics: `log show --last 10m --predicate 'process == "Voicey"' --style compact`; Voicey does not intentionally log transcripts or audio. Inspect `codesign --verify --deep --strict dist/Voicey.app` and `otool -L dist/Voicey.app/Contents/Frameworks/*.dylib` for bundle issues.

Browser protocol fixtures run without installing npm dependencies:

```sh
npm --prefix browser-extension test
```

For isolated browser DOM fixtures, install the extension's development dependencies and Playwright Chromium, then run:

```sh
npm --prefix browser-extension install
cd browser-extension
npx playwright install chromium
npm run test:dom
cd ..
```

These fixtures use intercepted pages and do not submit to real accounts. After building the app, `python3 scripts/test-browser-host.py` checks native-host IPC with synthetic messages. Live browser setup, permissions and account workflows require the separate [Computer Use QA checklist](docs/COMPUTER_USE_QA.md). Recorded evidence describes the version and environment tested; it is not a guarantee for every checkout or Mac.

If model loading fails, free RAM, unload models, import the documented format, or redownload. A corrupt memory document is preserved and reported; move `memory.json` aside to recover, preserving it for inspection. Folder access errors require an authorized scope. Missing browser/app launches return actual API errors. Cancel stops audio, clears pending actions, aborts native computation, and invalidates late results. It cannot undo a macOS launch already dispatched.

See [manual QA](docs/MANUAL_QA.md), [verification evidence](docs/VERIFICATION.md), and `CODEX_HANDOFF.md` for current limitations. Live microphone quality, physical keyboard permissions, multi-display behavior and distribution signing require separate verification; compilation alone is not their acceptance.

## Landing page

The static, responsive website lives in `web/`. Preview it with `python3 -m http.server 8080 --directory web`; open http://localhost:8080 . It includes the actual GitHub repository link, implemented features, local-processing details, the Control+Option+Command shortcut, and build limitations.

## Communication foundation (Voicey 3 work in progress)

Communication settings show the installed WhatsApp adapter, Accessibility status,
notification permission, privacy preferences, and saved-watch cancellation/deletion.
`Open WhatsApp` uses macOS application launching. The current adapter **does not yet
read chats, count real messages, compose/send replies, or activate reply monitoring**.
The browser bridge currently supports ChatGPT/Gmail only, with no verified WhatsApp integration. Those WhatsApp requests return an
explicit limitation instead of fabricated results. Notification permission can be
requested, but no real reply-arrived notifications are generated yet.

The shared core includes exact-name contact resolution with ambiguity handling,
incoming/outgoing/unknown direction, half-open time intervals using the local
calendar, stable-ID deduplication, explicit incomplete-history reporting, recipient-
bound reply policy and outgoing-submission evidence checks. Identifier-free repeated
messages are retained and labeled uncertain rather than incorrectly collapsed.
Persisted one-time watch metadata supports matching, cancellation and expiration;
restored waiting watches pause with a gap notice. Saved deadlines are checked every 30 seconds while Voicey runs and can emit
permission-gated timeout notifications. This is infrastructure, not a working
background reply observer. No transcript or screenshot is stored. Metadata lives
in `~/Library/Application Support/Voicey/communication-watches.json` with private
file permissions. Clear it from Communication settings.

Exact dictated replies require an unambiguous verified conversation and explicit
send authorization. Drafts stay drafts; generated/contextual replies require review.
The native adapter currently refuses all composer operations. Reasoning remains
local; any future authorized send through WhatsApp reaches WhatsApp and its recipient.

Run `scripts/test.sh` for isolated core fixtures. See
[manual communication verification](docs/COMMUNICATION_QA.md) for the separate,
user-authorized real-session checklist and remaining implementation requirements.

## Computer use (Voicey 2)

The existing orchestrator now runs typed, dependent tasks through observe → act → verify, with per-step evidence, bounded recovery, scoped approvals, cancellation and remaining-plan corrections. Finder workflows create or reuse exact nested directories through native filesystem APIs. ChatGPT and unsent Gmail workflows use the local MV3/native-messaging bridge, with an Arc scripting/Accessibility fallback for supported prompt controls. Commands must be copied from the user's exact backticks and pass the centralized policy; actual process state and exit status are captured. Project running status uses cwd/listener evidence and remains unknown when evidence is insufficient. Clock alarm operations require a live matching AX schema and one reviewed destructive batch. Generic native controls have semantic and guarded screenshot/OCR adapters.

See [Computer Use setup, architecture and limitations](docs/COMPUTER_USE.md) and the [automated/manual integration checklist](docs/COMPUTER_USE_QA.md). Browser extension installation, per-site access, Automation and user login are setup steps; a build does not certify a real-account workflow. No automated test submits to a real account or deletes the user's alarms.


## Natural ChatGPT requests and lightweight operation

Say “Go to ChatGPT and search for the last five prime ministers of India.” Voicey
extracts the question locally, resolves your chosen or saved browser, opens the
fixed ChatGPT destination, checks interface readiness, fills the exact question,
and verifies that a submitted user message appears. Short repeated search fragments
such as “search for top, search for the last five…” use the corrected query. It does
not assert that ChatGPT performed a live web search or that its eventual answer is
correct; the verified outcome is question submission. Say “without submitting” to
prepare only. Direct, non-sensitive questions authorize the fixed navigation and
exact submission; enable external-prompt preview in Computer Use to review every
question. Sensitive or changed text still requires review.

Setup: enable Computer Use; grant Input Monitoring for the Control+Option+Command
shortcut and Microphone for voice. Select the triple-modifier gesture in General.
For reliable browser semantics, install the bundled BrowserExtension in a supported
Chromium browser, register its exact extension ID with
`scripts/install-browser-bridge.py`, grant ChatGPT access in the extension popup and
Connect. Arc is installed on this development Mac; its native-messaging compatibility
must be verified after connection. Arc Automation plus Accessibility is an alternative
only when the actual interface exposes a unique prompt and trustworthy origin.
Complete ChatGPT login normally. Missing controls or permissions pause with a real
blocker. See [Computer Use setup](docs/COMPUTER_USE.md).

The agent uses one serial task executor with local planning, app-specific adapters
and verification at each step. It does not run a swarm of models in the background.
Tasks have bounded step/retry counts; uncertain submissions are not repeated.
Keyboard activation uses event notifications with a one-second recovery check;
models load on demand and unload after idle time. No continuous screen recording
or background language inference is used. Model inference can still consume CPU/RAM
while active; this version does not promise a measured system-wide performance level.

### Voice and first-run testing

Michael is the default Kokoro neural voice. Settings → Voice offers Michael, Heart, Bella, Emma and an optional macOS voice. The neural model/runtime are included in the app; speech runs in-process, entirely offline, with no Python, inference server, subscription or API key. The app occupies about 426 MB and its ZIP about 342 MB because these voice assets are included. Hindi replies use an installed Hindi macOS voice. The neural model loads on demand and releases after one idle minute.

Holding Control + Option + Command starts listening immediately. Voicey speaks only after receiving a request; there is no activation greeting. Press Speak to interrupt an existing reply. Recording and local transcription precede reasoning and verified actions.

On first launch the native Test Voicey walkthrough opens. You can repeat it from the menu or Settings → General → Test Voicey. It checks speaker playback with your listening confirmation, microphone transcription without running commands, physical shortcut activation reaching recording, a natural-language request interpreted by the actual local model, and Calculator launched through the normal command route. Unfinished or skipped checks remain Not tested. Completing onboarding does not certify untested features. Microphone/Input Monitoring permissions are requested only through user-initiated controls or voice activation.

Settings use a native sidebar and grouped forms in a resizable window. Advanced integration details are kept in disclosure sections. The below-notch companion and outside-click dismissal remain available.

Native neural speech verification: `dist/Voicey.app/Contents/MacOS/Voicey --neural-speech-self-test`. This produces synthetic preview audio in the system temporary folder, renders four actual voices in-process, checks cancellation/unloading and briefly plays Michael through the same service as normal replies. Run this from a packaged .app; unbundled Swift executables cannot use macOS notification APIs initialized by the app. Dependency licenses are in docs/THIRD_PARTY_NOTICES.md and the bundle Resources.

### Development permission recovery

Use the installed copy at `~/Applications/Voicey.app`. Settings refreshes live permission checks while visible and when Voicey becomes active. General offers Allow Keyboard Monitoring; Computer Use offers Allow Accessibility and Allow Screen Recording, Check Again and Restart. If an old Voicey entry remains enabled but the new app fails its runtime checks, remove that stale entry and add the current installed app in macOS Privacy & Security. Ad-hoc development signatures identify a specific build, so recompilation can invalidate prior grants; this build must remain unchanged during testing. No signing identity is configured in this workspace.

Basic greetings, thanks and identity questions use a direct local response path, without model loading. Test Voicey includes a normal-path Say Hello conversation check. Compact onboarding is optional and can be reopened from General.
