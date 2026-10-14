import AppKit
import ApplicationServices
import VoiceyCore

@MainActor final class InterfaceComputerAdapter:ComputerAdapter {
 let descriptor=AdapterDescriptor("Semantic native controls and guarded visual fallback",[.inspectInterface,.setControlValue,.pressControl],permissions:["Accessibility","Screen Recording only for visual fallback"],verification:"reacquired unique AX controls, exact field value or user-declared expected visible text",limitations:"All generic button actions require approval; unknown outcomes stop without automatic replay. Visual fill unsupported.")
 let native:NativeComputerAdapter,ax=AccessibilityComputer(),visual=VisualComputer()
 private var touched=Set<UUID>()
 init(native:NativeComputerAdapter){self.native=native}
 func cancel(){visual.cancel();touched=[]}
 func finish(){touched=[]}
 private func process(_ name:String)throws->pid_t {
 let app=try native.application(name)
 guard let running=NSRunningApplication.runningApplications(withBundleIdentifier:app.bundleID).first else{throw VoiceyError.unavailable("Target application closed")}
 return running.processIdentifier
 }
 private func matches(_ controls:[AccessibleControl],label:String)->[AccessibleControl] {
 controls.filter{c in c.enabled && [kAXTitleAttribute,kAXDescriptionAttribute,kAXIdentifierAttribute].contains{(ax.value(c.element,$0) as? String)?.caseInsensitiveCompare(label) == .orderedSame}}
 }
 func observe(_ step:ComputerStep) async throws -> Verification {
 let pid=try process(step.arguments.application)
 if ax.available {
 let controls=try ax.controls(pid:pid)
 if step.operation == .inspectInterface {return Verification(controls.isEmpty ? .unknown:.success,"Observed \(controls.count) accessible elements in the selected application; no contents persisted")}
 let targets=matches(controls,label:step.arguments.label)
 if step.operation == .setControlValue {return Verification(targets.count==1 && targets[0].value==step.arguments.text ? .success:.failure,"Compared the identified field's actual value")}
 if touched.contains(step.id),!step.arguments.output.isEmpty {
 let expected=controls.contains{$0.value==step.arguments.output || $0.label==step.arguments.output}
 return Verification(expected ? .success:.unknown,"Checked user-declared expected visible text: \(step.arguments.output)")
 }
 }
 if touched.contains(step.id),visual.available,!step.arguments.output.isEmpty {
 let observation=try await visual.capture(pid:pid)
 return Verification(observation.text.contains{$0.text==step.arguments.output} ? .success:.unknown,"Fresh local OCR checked the user-declared result")
 }
 return Verification(.unknown,"No verified semantic outcome yet")
 }
 func execute(_ step:ComputerStep) async throws -> AdapterResult {
 let pid=try process(step.arguments.application);try ax.assertForeground(pid)
 if ax.available {
 let controls=try ax.controls(pid:pid),targets=matches(controls,label:step.arguments.label)
 if step.operation == .inspectInterface{return .verified(try await observe(step))}
 if targets.count==1 {
 if step.operation == .setControlValue {try ax.fill(targets[0],text:step.arguments.text,pid:pid)}
 else {try ax.press(targets[0],pid:pid);touched.insert(step.id)}
 return .verified(try await observe(step))
 }
 if targets.count>1{throw VoiceyError.invalid("Multiple controls have that label; use a stable unique identifier instead.")}
 }
 if step.operation == .pressControl,visual.available {
 let observation=try await visual.capture(pid:pid);try Task.checkCancellation()
 try visual.click(text:step.arguments.label,in:observation);touched.insert(step.id)
 return .verified(try await observe(step))
 }
 throw VoiceyError.unavailable("No reliable accessible control is available. Enable the needed permission or use a supported application adapter.")
 }
}
