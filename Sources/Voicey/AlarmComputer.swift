import AppKit
import ApplicationServices
import VoiceyCore

@MainActor final class AlarmComputerAdapter:ComputerAdapter {
 let descriptor=AdapterDescriptor("Clock Accessibility alarms",[.inspectAlarms,.deleteAlarms],permissions:["Accessibility"],verification:"stable Alarm- identifiers, parsed times, actual Delete alarm action, full before/after list",limitations:"Only the observed English macOS Clock schema; duplicates, changing lists and unrecognized controls stop execution. No private database access.")
 let native:NativeComputerAdapter,ax=AccessibilityComputer()
 private var baselines:[UUID:[AlarmRecord]]=[:]
 private var cancelled=false
 init(native:NativeComputerAdapter){self.native=native}
 func cancel(){cancelled=true;baselines=[:]}
 func finish(){baselines=[:]}
 func list(application:String) throws -> [(AlarmRecord,AccessibleControl)] {
 let app=try native.application(application)
 guard app.bundleID=="com.apple.clock",let running=NSRunningApplication.runningApplications(withBundleIdentifier:app.bundleID).first else{throw VoiceyError.unavailable("Only the inspected macOS Clock alarm interface is supported. Open Clock to its Alarms tab first.")}
 let controls=try ax.controls(pid:running.processIdentifier)
 let rows=controls.filter{$0.role=="AXButton" && (ax.value($0.element,kAXIdentifierAttribute) as? String ?? "").hasPrefix("Alarm-")}
 if rows.isEmpty {
 guard controls.contains(where:{$0.role=="AXRadioButton" && $0.label=="Alarms" && $0.value=="1"}) || controls.contains(where:{$0.label.localizedCaseInsensitiveContains("no alarms")}) else{throw VoiceyError.unavailable("Select the Alarms tab in Clock, then continue. No alarms changed.")}
 }
 var ids=Set<String>(),result:[(AlarmRecord,AccessibleControl)]=[]
 for row in rows {
 let id=ax.value(row.element,kAXIdentifierAttribute) as? String ?? ""
 let pieces=id.dropFirst(6).split(separator:"-",maxSplits:1)
 guard let time=pieces.first,let minutes=AlarmPolicy.time(String(time)),ids.insert(id).inserted,
 AlarmPolicy.deleteAction(row.actions) != nil else{throw VoiceyError.unavailable("Clock's alarm identifiers/actions do not match the inspected schema. No deletion will run.")}
 result.append((AlarmRecord(id:id,minutes:minutes),row))
 }
 return result
 }
 func prepare(_ step:ComputerStep) async throws -> AdapterPreparation {
 cancelled=false
 guard step.operation == .deleteAlarms else{return .ready(step)}
 guard let cutoff=step.arguments.cutoff,(0..<1440).contains(cutoff) else{throw VoiceyError.invalid("An explicit alarm cutoff including AM or PM is required.")}
 let all=try list(application:step.arguments.application).map(\.0),selected=AlarmPolicy.select(all,before:cutoff)
 var result=step;result.arguments.alarmIDs=selected.map(\.id);result.arguments.alarmTimes=selected.map(\.time);result.arguments.fingerprint=AlarmPolicy.fingerprint(all)
 baselines[step.id]=all
 return .ready(result)
 }
 func observe(_ step:ComputerStep) async throws -> Verification {
 let all=try list(application:step.arguments.application).map(\.0)
 if step.operation == .inspectAlarms{return Verification(.success,"Inspected \(all.count) alarms through the supported Clock interface")}
 if step.arguments.alarmIDs.isEmpty{return Verification(.success,"No alarms match the requested cutoff")}
 guard let baseline=baselines[step.id] else{return Verification(.unknown,"No approved alarm snapshot")}
 let selected=baseline.filter{step.arguments.alarmIDs.contains($0.id)}
 return AlarmPolicy.verify(before:baseline,selected:selected,after:all)
 }
 func execute(_ step:ComputerStep) async throws -> AdapterResult {
 if step.operation == .inspectAlarms{return .verified(try await observe(step))}
 let a=step.arguments
 guard let baseline=baselines[step.id],AlarmPolicy.fingerprint(try list(application:a.application).map(\.0))==a.fingerprint else{throw VoiceyError.unavailable("The alarm list changed after approval. Start again to review a fresh batch.")}
 let app=try native.application(a.application)
 guard let running=NSRunningApplication.runningApplications(withBundleIdentifier:app.bundleID).first else{throw VoiceyError.unavailable("Clock closed")}
 var remaining=baseline
 for id in a.alarmIDs {
 try Task.checkCancellation();guard !cancelled else{throw CancellationError()}
 let rows=try list(application:a.application)
 guard rows.map(\.0).sorted(by:{$0.id<$1.id})==remaining.sorted(by:{$0.id<$1.id}),let target=rows.first(where:{$0.0.id==id}),let action=AlarmPolicy.deleteAction(target.1.actions) else{throw VoiceyError.unavailable("Alarm state changed during the batch. Stopped with completed work preserved.")}
 try ax.assertForeground(running.processIdentifier)
 guard AXUIElementPerformAction(target.1.element,action as CFString) == .success else{throw VoiceyError.unavailable("Clock refused the approved delete action")}
 remaining.removeAll{$0.id==id}
 var verified=false
 for _ in 0..<15 {
 try Task.checkCancellation();guard !cancelled else{throw CancellationError()}
 if try list(application:a.application).map(\.0).sorted(by:{$0.id<$1.id})==remaining.sorted(by:{$0.id<$1.id}){verified=true;break}
 try await Task.sleep(nanoseconds:100_000_000)
 }
 guard verified else{throw VoiceyError.unavailable("Deletion acknowledgement unavailable. No remaining alarm was touched. Inspect Clock before retrying.")}
 }
 return .verified(try await observe(step))
 }
}
