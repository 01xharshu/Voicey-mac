import AppKit
import ApplicationServices
import VoiceyCore

/// Ephemeral semantic observations. No screen contents are written to disk.
@MainActor final class DesktopReasoning {
 let engine:LocalAIEngine,native:NativeComputerAdapter
 let ax=AccessibilityComputer()
 init(engine:LocalAIEngine,native:NativeComputerAdapter){self.engine=engine;self.native=native}
 func next(_ task:ComputerTask) async throws -> ComputerContinuation {
 try Task.checkCancellation()
 guard let front=NSWorkspace.shared.frontmostApplication,let name=front.localizedName else{return .wait("Bring the app you want me to work with to the front, then continue.")}
 let controls=try ax.controls(pid:front.processIdentifier)
 // Only selectors that uniquely address a live accessible control are offered.
 var targets:[String:AccessibleControl]=[:]
 for c in controls where c.enabled && !c.label.isEmpty {
 let candidates=[kAXIdentifierAttribute,kAXTitleAttribute,kAXDescriptionAttribute].compactMap{ax.value(c.element,$0) as? String}.filter{!$0.isEmpty && $0.count<200}
 if let selector=candidates.first(where:{candidate in controls.filter{other in [kAXIdentifierAttribute,kAXTitleAttribute,kAXDescriptionAttribute].contains{(ax.value(other.element,$0) as? String)==candidate}}.count==1}){targets[selector]=c}
 }
 let rows=targets.sorted{$0.key<$1.key}.prefix(80).map{key,c in "selector=\(key.debugDescription) role=\(c.role) value=\(String(c.value.prefix(500)).debugDescription) actions=\(c.actions.joined(separator:","))"}
 let apps=native.discovery.applications().map(\.name).sorted().joined(separator:", ")
 let history=task.steps.suffix(6).map{"\($0.title): \($0.evidence?.detail ?? "no evidence")"}.joined(separator:"\n")
 let observation="Installed applications: \(apps)\nCurrent application: \(name)\nRecent verified steps: \(history)\nControls:\n"+rows.joined(separator:"\n")
 let decision=try await engine.decide(task.originalRequest,observation:observation,desktop:true)
 try Task.checkCancellation()
 guard NSWorkspace.shared.frontmostApplication?.processIdentifier==front.processIdentifier else{return .wait("The foreground app changed during planning. Bring the target app forward and continue.")}
 var a=OperationArguments();a.application=name
 let op:ComputerOperation
 switch decision.kind {
 case "ask":return .wait(decision.explanation.isEmpty ? "What should I do next?":decision.explanation)
 case "launch":
 guard native.discovery.applications().contains(where:{$0.name==decision.query}) else{throw VoiceyError.invalid("The planner selected an unavailable application.")}
 a.application=decision.query;op = .launchApplication
 case "inspect":op = .inspectInterface
 case "fill","press":
 guard decision.destination==name,let target=targets[decision.query] else{throw VoiceyError.invalid("The planner selected a control that wasn't uniquely observed.")}
 a.label=decision.query
 if decision.kind=="fill"{
 guard ["AXTextField","AXTextArea","AXComboBox"].contains(target.role),!decision.explanation.isEmpty else{return .wait("No supported editable field was identified.")}
 a.text=decision.explanation;op = .setControlValue
 }else{
 guard target.actions.contains(kAXPressAction),!decision.explanation.isEmpty else{return .wait("That control has no supported press action or verifiable expected result.")}
 a.output=decision.explanation;op = .pressControl
 }
 case "finish":
 guard decision.destination==name,!decision.query.isEmpty,
 task.steps.contains(where:{$0.status == .verified && [.pressControl,.setControlValue,.launchApplication].contains($0.operation)}),
 controls.contains(where:{$0.value==decision.query || $0.label==decision.query}) else{return .wait("I cannot verify the requested outcome yet. What visible result should I check?")}
 return .complete(Verification(.success,"Observed in \(name): \(decision.query)"))
 default:throw VoiceyError.invalid("The local planner returned an unsupported desktop action.")
 }
 let step=ComputerStep(op,a,title:op == .launchApplication ? "Open \(a.application)":"\(op.rawValue) in \(name)",after:task.steps.last.map{[$0.id]} ?? [])
 return .steps([step])
 }
}

extension AgentOrchestrator {
 func startGeneralGoal(_ request:String) async throws {
 guard UserDefaults.standard.object(forKey:"computerUseEnabled") as? Bool != false else{throw VoiceyError.unavailable("Enable computer use in Settings.")}
 guard let app=NSWorkspace.shared.frontmostApplication,let name=app.localizedName else{throw VoiceyError.unavailable("Open the target application first.")}
 let reasoning=DesktopReasoning(engine:engine,native:nativeComputer)
 computer.continuation={task in try await reasoning.next(task)}
 var a=OperationArguments();a.application=name
 let first=ComputerStep(.inspectInterface,a,title:"Observe \(name) before planning")
 await computer.start(ComputerTask(request:request,intention:"Verify the requested result on your Mac",steps:[first]))
 }
}
