# Voicey 2 computer use

**Product requirement:** no browser extension should be required. The bridge setup
below describes the current transitional implementation, which does not yet meet
that requirement. See [the acceptance contract](EXTENSION_FREE_ACCEPTANCE.md).

Voicey extends the existing local assistant with typed tasks and a shared action policy.
The embedded Qwen runtime interprets broader language; deterministic workflow parsing
handles common explicit requests. Both routes produce the same validated operations.
The model cannot return executable tool code, grant permissions, or approve an action.

## Using the companion

Use the selected gesture in General settings, or Option–Command–Space. Both the
left/right physical Command gesture and the existing Control–Option–Command gesture
are supported. The glowing companion remains attached to the active display's notch.

Examples:

- `Open Finder, go to Documents, create a folder named ICICI, and create a new folder called Repo.`
- `Open ChatGPT in my Arc browser and ask it why horses exist.`
- `Go to Gmail in Arc, draft an email to harsh@example.test saying Thank you.`
- Open Terminal, run `npm run dev` in my Tipsy Docy project, and check whether the application is running.
- Run `git status --short` in /absolute/authorized/project.
- `Inspect the interface of Clock`.
- `Press "Alarms" in Clock` (a generic control action shows its precise approval).
- `Open my alarms and delete alarms before 7 AM` (only a matching supported Clock schema).

For project commands, authorize the actual project or its parent in Settings → Files.
Voicey resolves explicit aliases first, searches only authorized roots for these
workflows, and asks when multiple projects match. It never guesses a recipient's
email address. An explicit alias may map a contact name to an address; it is not
learned from unrelated browser observations.

Each task shows a concise current step and expandable details with the interpreted
request, selected app, step states and verification evidence. Cancel or say Stop to
stop remaining work. Login/consent waits are explicit: sign in yourself and say
Continue. Voicey never solves access controls. `Use Arc` or a corrected project path
at a pending task revises the remaining plan and re-observes completed reusable work.
A new unrelated command clears the previous pending approval.

## Browser extension setup

The source is `browser-extension/`, also copied into the built app at
`Contents/Resources/BrowserExtension`. It uses Manifest V3, a service worker and a
fixed semantic command vocabulary. It requests **no website access by default**.
Optional access is limited to `https://chatgpt.com/*` and
`https://mail.google.com/*`. There is no all-sites permission, cookie access,
arbitrary-JavaScript command, remote executor, or public network listener.

1. Build Voicey with `scripts/build.sh` and keep its app bundle at a stable path.
2. In Arc open its Extensions management UI (Chromium's `chrome://extensions` where
   supported). Enable Developer mode and Load unpacked. Select `browser-extension/`
   or the app's Resources/BrowserExtension folder.
3. Copy the extension's **actual ID** from the browser or extension popup. Register:

   ```sh
   python3 scripts/install-browser-bridge.py --browser arc --extension-id ACTUAL_32_LETTER_ID --app /absolute/path/Voicey.app
   ```

   The installer is also bundled at `Contents/Resources/install-browser-bridge.py`.
   Other registration choices are chrome, brave and edge; the chosen browser must
   actually be installed. The script copies the signed Swift helper and writes the
   per-user host manifest, extension identity and random IPC token. It does not
   install a daemon or launch agent. Python 3 is needed for this setup script only;
   the running bridge and app use compiled native executables.
4. In the extension popup grant **ChatGPT** and **Gmail** separately as needed, then
   choose Connect. In Voicey → Computer Use refresh the status. Socket presence is
   reported as presence, not certified health; each actual command authenticates
   and validates its response.
5. Authenticate to the selected website in the visible browser yourself. Keep the
   target tab/window visible while Voicey interacts with it.

Arc is installed on this development Mac and exposes a real `Arc.sdef` with tab URL,
loading and tab selection. Native Messaging registration compatibility has **not**
been certified in the user's installed Arc session. Two Arc-specific per-user host
locations are registered as compatibility candidates. If connection fails, use the
extension's reconnect control and inspect browser diagnostics; do not assume a
socket or successful navigation proves semantic automation. Voicey falls back to
Arc's supported URL scripting plus Accessibility when a reliable prompt is exposed.
Other browser scripting dialects are not guessed. Gmail drafting requires the bridge.

The extension reuses an existing matching tab, or creates a visible tab only after
exact destination approval. Every command checks the actual origin again. It refuses
writes if the target tab/window loses focus. It reacquires DOM elements on every
operation and does not reuse element handles across SPA changes. Existing differing
prompt text and existing Gmail compose drafts are preserved for manual review.
Supported semantic labels currently target the English ChatGPT/Gmail interfaces;
site changes or localization can require adapter updates.

## Policy and verification

Low-risk filesystem/app/search/status operations run directly when unambiguous.
Every website workflow requires approval of the exact destination. A direct request
to ask an unchanged, non-sensitive question normally authorizes submission. Enable
**Preview external prompts before submitting** to require an additional exact-text
preview. Transformed/ambiguous prompts and detected sensitive content require
approval. Sensitive content is also checked before filling because a website can
receive text before Send is clicked. Local keyword/credential detection is
conservative; it is not a comprehensive data-loss-prevention classifier.

Gmail has no send operation. Voicey creates an unsent draft and checks actual
recipient, subject, body and a saved-draft indicator. If the current site does not
expose a reliable saved signal, the result is partial/unknown. It does not claim
that merely filling a compose window saved a draft.

Commands must originate in the user's exact backticks and pass executable/argument,
working-directory and policy checks. The allowlist includes pwd, git, make, python3,
echo, swift and three fixed npm workflows through env (run dev, test, run build).
There is no shell-expansion/pipeline/redirection interface. Clear pwd/git-status
checks run directly. Project scripts/other commands require one exact approval;
approval is not inferred from model output. Unsupported executables, including
privileged/destructive shell tools, are rejected. Explicit Terminal requests show
a Terminal session for the project; actual execution is controlled natively for
exit status, bounded output capture and cancellation. They do not run the same
command a second time in Terminal.

Development status uses actual process cwd and TCP listener evidence from lsof;
no port is invented. No matching evidence means **unknown**, since a process may
run remotely, without a listener, or with another cwd. A matching existing server
is reused. A successfully completed workflow leaves its intentionally started
server running. User cancellation during the task terminates the controlled
process group, including ordinary children. Deliberately detached/daemonized
processes are outside that cancellation guarantee. A live process/listener alone
is not reported as an HTTP/application health check.

Clock support reads actual accessible rows with unique stable identifiers, explicit
AM/PM times and a supported delete action. Ambiguous before-7-AM/PM sets prompt once.
The proposed count and times are confirmed as a single batch. The adapter checks the
whole list again after approval, reacquires each row, and verifies each deletion and
all unaffected alarms. Duplicate IDs, new modals, localization, schema changes,
missing permissions or uncertain results stop the batch. No private alarm database
is accessed. Real alarm deletion is not part of automated testing.

Generic native interface inspection/filling/pressing uses a target application PID,
unique semantic AX labels/identifiers and supported actions. Generic button presses
require explicit approval; successful AX invocation alone is not completion. A
user-declared expected visible result or exact resulting field value is checked.
When semantic controls are unavailable, ScreenCaptureKit captures only the front
target window, Vision recognizes text locally, and a unique explicit control may
be clicked from a fresh observation. Focus, window identity, observation age and
manual input are checked. Visual-only web prompt entry is not enabled because OCR
cannot reliably prove an editor's identity or a submitted message's author.

Shortcuts are discovered through `/usr/bin/shortcuts list` and exact-name selected,
then approved once. The initial adapter supports no-input Shortcuts only. Exit zero
without a dedicated outcome verifier yields unknown, not a fabricated success.

## Task state and privacy

`ComputerTask` contains ordered/dependent operations, preconditions, outcome and
verification descriptions, validated arguments, actual attempts/evidence, a bounded
step/retry policy, approval context and cancellation state. The executor observes
before acting, skips goals already met, then verifies again. Dependency failures
stop later steps. Low-risk operations may be re-observed/retried within the budget;
submissions, Gmail creation, generic button presses, commands and alarm deletion are
not automatically replayed after an uncertain result. Approval is task/step scoped,
expires, and is invalidated if a prepared destructive batch changes.

Operational task state remains in memory, distinct from explicit long-term aliases.
Only task type, time, status and verified/total counts are retained in a bounded list
of 20 local summaries; clear them in Computer Use. Screenshots, raw recordings,
mail contents, complete browser pages and command output are not persisted in these
summaries. Dismissing the companion clears completed task context.

Voicey's inference and OCR remain local. **Opening a website and entering or
submitting a ChatGPT question or Gmail draft transmits information through that
website's existing browser session.** These explicitly requested browser actions
are not offline/private-to-the-Mac operations. Voicey does not export passwords,
cookies or authentication tokens and never sends browser contents to its own cloud
AI service. Observed page/app/terminal content is data, never authority to change
tools, approvals or privacy policy.

The Native Messaging host checks the exact extension origin, installed browser
parent executable (or its bundled helper), strict command shape, request correlation
and actual result origin. Local IPC uses Unix sockets and getpeereid user checks,
mode-0700 storage, mode-0600 configuration/socket files and an installation-generated
token. Cancelling disconnects the socket and asks the extension to stop pending work.
Already-dispatched irreversible actions cannot be undone; the executor does not
retry uncertain external actions. A user with unrestricted access to the same
account remains within the local trust boundary.

Reference: Chrome's [Native Messaging specification](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)
and [permissions documentation](https://developer.chrome.com/docs/extensions/develop/concepts/declare-permissions).
