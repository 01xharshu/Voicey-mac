# Computer-use verification

Automated tests use temporary directories and intercepted browser pages. They never
modify the user's Documents, send a real ChatGPT/Gmail message, or delete real alarms.
See CODEX_HANDOFF.md for exact run logs and current acceptance status.

## Reproduce automated checks

```sh
scripts/test.sh
scripts/build.sh
# Actual macOS Process/NSWorkspace/filesystem checks; no microphone or account action:
dist/Voicey.app/Contents/MacOS/Voicey --computer-self-test
# Optional read-only schema check of already-open Clock:
dist/Voicey.app/Contents/MacOS/Voicey --computer-self-test --inspect-clock-schema
# Optional actual embedded language-model planning smoke (models installed):
dist/Voicey.app/Contents/MacOS/Voicey --computer-self-test --model-plan-check
python3 scripts/test-browser-host.py .build/release/VoiceyBrowserHost
node --test browser-extension/tests/protocol.test.js
npm --prefix browser-extension install
npx --prefix browser-extension playwright install chromium --only-shell
node browser-extension/tests/dom.test.cjs
codesign --verify --deep --strict dist/Voicey.app
```

The standalone executable runner is used because this CLT installation lacks XCTest.
The app self-test needs a real .app bundle because the concurrently integrated
notification subsystem uses UserNotifications (an unbundled Swift executable is not
an adequate app-launch environment). Test fixtures are independent of model weights.
The model smoke is a separate real-inference check, not part of deterministic tests.

Coverage includes:

- Ordered dependencies, invalid/cyclic order, bounded steps/retries, cancellation,
  failure/unknown states, context-bound yes/continue, authentication waits and
  no repeated uncertain submissions/deletions.
- Missing/existing ICICI and Repo, incompatible files at either path, unauthorized
  roots, symlinks, unavailable paths, repeated runs with exact final path.
- Command provenance/tokenization/policy, captured real exit status/output,
  long-running/cancelled processes, actual installed Arc discovery and unknown
  project status without evidence.
- Schema/origin/extension-ID validation, per-user socket permissions, authentication,
  actual native framing, correlated replies, app disconnect → browser cancellation.
- Intercepted Chromium DOM: semantic prompt discovery/fill, replaced elements,
  acknowledgement, login wall, existing differing input, unsent Gmail draft with
  exact recipient/body, saved signal, zero Send clicks, existing compose protection,
  unauthorized origin rejection.
- Alarm time conversion including midnight/noon, AM/PM ambiguity, exact matching,
  unrelated alarm preservation, custom action-name shape, batch approval and no
  retry after an uncertain destructive result. All destructive alarm tests use
  mocks only.

## Manual real-Mac checklist (not certified by unit tests)

1. **Preservation:** exercise existing app launch/search, URL chooser, local aliases,
   model import/download, microphone, offline recognition/TTS and both selectable
   activation gestures. Confirm the fallback hotkey and below-notch companion on
   each display. Run with networking disconnected after installing models.
2. **Filesystem:** use an expressly disposable authorized directory; run the nested
   ICICI/Repo workflow three times with missing, partly present and fully present
   folders. Inspect exact paths in Finder. Replace one target with a file in that
   disposable root and confirm the conflict preserves it. Remove permission during
   a task; no subsequent dependent action may run.
3. **Bridge:** load the actual extension in the installed Arc version and register
   its real ID. Grant one website at a time; verify denied sites stay denied. Check
   connected status by an authenticated command, not socket presence alone. Test
   disconnect/reconnect, browser close and navigation to an unapproved origin.
4. **ChatGPT:** first use a non-sensitive disposable question. Approve the exact URL.
   Test Arc already running and existing matching tab reuse. Verify login/consent
   waits, fresh prompt discovery after SPA change, exact field text and user-message
   acknowledgement. Test preview on/off, sensitive/transformed text previews,
   cancellation before submission and focus stolen before input. An uncertain send
   must stop, never automatically click Send again. A real external submission
   should be performed only when the human has explicitly authorized that test.
5. **Gmail:** use an explicitly provided test recipient. Confirm names without an
   address clarify instead of inventing one. Create a disposable draft; inspect
   recipient, subject/body and Saved to Drafts. Confirm it stays unsent. Open an
   existing draft and ensure another run stops instead of overwriting it. Test
   localization, delayed saved state, login and lost focus. No Gmail send operation
   is exposed.
6. **Commands/projects:** authorize a disposable project with known test scripts.
   Run exact `git status --short`, a failing command, an approved finite build,
   and `npm run dev`. Inspect exit/output evidence, cwd and actual listener.
   Request dev again: a verified equivalent process should be reused; uncertain
   existing listeners must pause rather than duplicate. Cancel while the process
   is active and verify ordinary child processes terminate. Complete a server-start
   workflow, then run another task and ensure that completed server remains running.
   Check an idle project: report unknown when no evidence establishes running/stopped.
7. **Native/visual:** inspect a named app; fill a unique reversible test field and
   verify its value. Test duplicate labels, target window replacement, permission
   denial, moved windows, user input and focus loss. With explicit approval press
   a harmless test control and verify a declared visible result. Confirm stale
   screenshots cannot be clicked and screenshot bytes never reach disk/history.
8. **Clock:** first inspect the version-specific accessible schema read-only. For
   destructive testing the human must explicitly create/name disposable test alarms;
   never use existing real alarms as test data. Cover before-seven AM/PM, zero
   matches, duplicate IDs, list changes after approval, partial batch interruption
   and one summary approval. Check every unaffected alarm remains identical.
   If custom action names or UI structure differ, expect a clear blocked result.
9. **Shortcuts:** select an explicitly authorized disposable no-input Shortcut.
   Verify discovery, one approval, cancellation/errors and honest unknown outcome
   if only an exit code is available. Do not run unknown system/user Shortcuts.
10. **Privacy/settings:** disable computer use, change step budget/retry count,
    enable prompt preview and turn narration off. Verify task details/cancel and
    clear summaries. Inspect saved summaries: no prompt/mail contents, screenshots,
    recipients, output or raw audio. Confirm approvals expire and cannot carry to
    a different task or a changed destructive batch.

## Known acceptance boundaries

A successful build and fixtures do not certify current real-account ChatGPT/Gmail
DOMs, Arc's Native Messaging registration behavior, microphone quality, TCC grants,
Clock deletion or every native app's controls. UI/site version mismatches deliberately
return partial/unknown/unavailable. Full Xcode is not installed; SwiftPM CLT builds
and ad-hoc signing work. Distribution signing/notarization remains separate.
