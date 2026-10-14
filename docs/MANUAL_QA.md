# Voicey manual QA

Use a stable app location. These are manual acceptance checks, not automatically passed results.

- [ ] Launch the bundle, verify one menu-bar item and one companion; quit cleans up recording and monitoring.
- [ ] Allow Input Monitoring, relaunch. Any single modifier or two-modifier combination/separate taps never activate. Any Control/Option/Command press order activates once. Hold all three, release one, repress; rapid repeats and missed releases never leave a latched assistant. No unrelated keys logged. Denied permission shows a working fallback.
- [ ] Change fallback to Option–Command–V; check conflict handling. Test on built-in and external keyboards.
- [ ] Grant/deny microphone, test text before grants; missing mic produces a useful recovery message.
- [ ] Hear greeting, interrupt with Speak, and verify no greeting is recognized as an instruction. Record English and Indian-accent English, Hindi, silence, background noise. Verify silence end, Finish, timeout, Cancel, transcript correction/retry, and voice yes/browser replies.
- [ ] Test reduced motion, dark/light, keyboard Tab/Return/Escape, VoiceOver, screen changes, fullscreen apps. Companion stays on active screen, text accepts focus, repeated activation never creates another panel.
- [ ] Launch a real installed app and reveal its bundle; missing/duplicate names clarify. Failed native launches never report success.
- [ ] In a disposable folder, search nested exact/partial/hidden/date/type queries. Check two equal folders show names and paths. Add a protected scope through picker. Missing access is actionable. Symlink loops do not hang; Cancel prevents later actions.
- [ ] Create a new empty folder at an explicit destination without confirmation; reject traversal, unavailable parents and an existing name without modifying data.
- [ ] Copy text and verify clipboard. No shell, deletion or overwrite tool executes.
- [ ] Open YouTube in Arc: URL is shown before any navigation; Cancel/No prevents navigation. Correct uses Arc. Unavailable Arc asks another browser. Saved browser works; override uses Safari; default browser stays unchanged. Expiry and unrelated requests invalidate previous approval.
- [ ] Save an alias, restart, use it; delete it and verify it is not reused. Edit a conflict explicitly. Move its target, verify missing path error. Correction applies to whole words, never automatically invents vocabulary. Corrupt/newer memory is preserved.
- [ ] Cancel a model download and resume it; test wrong checksum, disconnect, unavailable storage, manual incompatible model, import/remove while models loaded. No cloud fallback occurs. Disconnect internet and verify ordinary local actions, recognition and language reasoning.
- [ ] Use native model smoke script and inspect RAM/latency during repeated commands. Test a compatible Intel Mac separately. Verify launch at login on a stable signed app location.
- [ ] For distribution: Developer ID sign/notarize independently; current bundle is ad-hoc signed only.
