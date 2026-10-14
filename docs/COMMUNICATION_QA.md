# Communication integration verification

Current status: foundation only; real WhatsApp reading/sending/monitoring blocked.
Environment inspected 2026-10-14: WhatsApp installed with bundle ID
net.whatsapp.WhatsApp. `sdef` exposes no scripting dictionary. A read-only
AX inspection was trusted and initially returned zero windows for the running application.
After normal app activation, one window exposed chat navigation buttons and headings.
The session is linked; message direction/timestamps and safe composer identity remain
unverified. Only bounded control metadata was inspected; no transcript was saved.
No private database, keys, cookies, or account protocols were accessed.

## Required native adapter work

1. With the user's normal linked session open, inspect bounded AX roles for the
   selected chat. Establish stable conversation identity, group indicators, direction,
   timestamps, unread state, message identity, composer and submitted-message evidence.
2. If AX does not expose these reliably, retain unavailable capabilities. An authorized
   browser bridge requires a separately implemented extension and selected session;
   there is no bridge in this version. No universal notification-reading API is assumed.
3. Connect adapter operations through the registry and central action policy, implement
   local structured planning and contextual model replies with bounded relevant input.
4. Wire reliable observation to watch persistence, permission-aware native notification
   delivery/actions, optional local speech, deadlines and disconnection recovery. The controller now checks persisted deadlines every 30 seconds and delivers
   permission-gated timeout notifications, but no live watch can be created until
   conversation observation is verified.

## Manual checks (never ordinary automated tests)

- Authorize a test contact/session; link/login normally and grant Voicey Accessibility.
- Open an existing exact contact; exercise duplicate names and a similarly named group.
- Compare observed last messages/direction/time with WhatsApp itself.
- Check unread, today, explicit range and partial/older-history counts separately.
- Prepare an exact draft without submission. Then explicitly authorize a test send;
  verify a new outgoing message in that exact chat, without claiming delivery/read.
- Generate a contextual draft locally and review before send. Verify ambiguous and
  sensitive requests stop before composing/submitting.
- Establish a one-time watch, hide the window and receive a test reply; verify one native
  notification, privacy preview toggle, speech toggle and open-chat action.
- Exercise unrelated messages, repeated observations, cancellation, timeout, permission
  denial, app exit/restart and integration loss. Ensure gaps and unavailable observation
  never display active monitoring. Clear all metadata from settings.

Automated fixtures cover core contact ambiguity, count boundaries/completeness,
direction, stable-ID duplicates, uncertain identifier-free messages, reply authorization,
submission evidence, watch matching/stop/deduplication, persistence, cancellation and
pure expiration transitions. They do not certify native UI operations, notification
errors, live observation recovery, or full natural-language workflows.
