# Extension-free Voicey acceptance contract

User requirement, October 14, 2026. This document describes required behavior,
not completed functionality. Browser extensions must not be required.

## Native execution and concurrent jobs

Observe semantic controls through macOS Accessibility. For missing controls, use
fresh ScreenCaptureKit images, local visual understanding/OCR and guarded mouse
and keyboard actions. Reobserve after each action and check foreground/window
identity. Stop when the user takes control. A click or typed command is not success.

Keep independent job state. New voice requests must not cancel earlier jobs.
Planning, local file work and read-only requests can overlap. Foreground mouse,
keyboard, clipboard and focus operations share one exclusive lease. Clarification,
approval and cancellation must belong to the selected job.

## Required live acceptance

- Next.js: “Create a Next.js project named Alex” asks for the missing parent.
  “Documents” resolves the actual directory. Check Documents/Alex before writing;
  never overwrite an existing project. Check Node availability, prepare explicit
  scaffold defaults, execute the command, verify generated package/source files,
  run the generated build and inspect its exit/result. If Terminal is used, inspect
  its actual outcome. Dependency downloads need internet; no paid API is required.
- ChatGPT to Google Docs: open the chosen existing browser, submit the requested
  research prompt, wait for a completed response, capture text and source links,
  create a Google document, transfer the response, verify title/body and saved
  state, and report its actual link. Handle sign-in, loading, partial saves and
  unsupported editors explicitly. Retries cannot duplicate prompts or documents.
  Medicine research retains sources and uncertainty, not an unsupported accuracy
  claim about generated medical text.
- Concurrent voice requests: browser research, unsent Gmail draft, alarm creation,
  Twitter notifications and WhatsApp reply inspection maintain separate jobs and
  truthful outcomes. Ask about ambiguous addresses, contacts or missing content.
  Drafting does not authorize sending. Alarm creation cannot use alarm deletion.

## Retained requirements

Activation listens first. Greetings and arithmetic produce spoken answers.
Changing facts and currency use fresh internet evidence. Michael remains the
selectable default local voice. Onboarding uses actual user speech and observed
results; canned phrases and timers cannot pass a listening test. Refresh permissions
for the actual running installed app and retain stable signing across builds.

The local editable knowledge base learns verified app/browser/project preferences.
Provide inspect, correct, disable and delete controls. Do not silently retain raw
conversations, screenshots, document/email bodies or credentials. Preferences
cannot grant authority for external submission or deletion.

## Current gaps and next work

Native app discovery, AX controls, OCR and guarded unique-text clicking exist.
Gmail currently requires the bridge; native ChatGPT checks rely on Arc scripting.
General visual planning, Google Docs transfer, Next.js scaffolding and independent
worker jobs are not implemented. WhatsApp message inspection remains unavailable.
Permissions alone do not solve these gaps. Fixtures do not prove live acceptance.

Next: finish stable signing and truthful speech onboarding; build job-scoped screen
leases and native observation/action primitives; implement extension-free browser
navigation/editor verification; Next.js scaffolding; ChatGPT response capture and
Google Docs saving; live authenticated acceptance of the remaining workflows.
