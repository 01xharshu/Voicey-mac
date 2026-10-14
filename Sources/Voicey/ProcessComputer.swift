import AppKit
import VoiceyCore

struct ProcessEvidence {let exit:Int32?,running:Bool,output:String,pid:pid_t}
@MainActor final class ControlledProcesses {
 private var released:[Process]=[]
 private var active:[UUID:Process]=[:],results:[UUID:ProcessEvidence]=[:]
 func finish(){released = released.filter{$0.isRunning}+active.values.filter{$0.isRunning};active=[:]}
 private func terminate(_ p:Process){
 let pid=p.processIdentifier
 _ = kill(-pid,SIGTERM);if p.isRunning{p.terminate()}
 Task{try? await Task.sleep(nanoseconds:1_000_000_000);if p.isRunning{_ = kill(-pid,SIGKILL);_ = kill(pid,SIGKILL)}}
 }
 func cancel(){for p in active.values where p.isRunning{terminate(p)};active=[:];results=[:]}

 func result(_ id:UUID)->ProcessEvidence? {
 if let p=active[id],p.isRunning {return ProcessEvidence(exit:nil,running:true,output:"Process remains active",pid:p.processIdentifier)}
 return results[id]
 }
 func run(id:UUID,executable:String,args:[String],directory:URL,timeout:Double=30,longRunning:Bool=false) async throws -> ProcessEvidence {
 try Task.checkCancellation()
 let p=Process(),pipe=Pipe()
 let runner=URL(fileURLWithPath:CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("VoiceyProcessRunner")
 guard FileManager.default.isExecutableFile(atPath:runner.path) else{throw VoiceyError.unavailable("The controlled process helper is missing; rebuild Voicey.")}
 p.executableURL=runner;p.arguments=[executable]+args;p.currentDirectoryURL=directory
 p.environment=["PATH":"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin","HOME":NSHomeDirectory(),"LANG":"en_US.UTF-8"]
 p.standardOutput=pipe;p.standardError=pipe
 let buffer=ProcessOutput()
 pipe.fileHandleForReading.readabilityHandler={handle in let data=handle.availableData;if !data.isEmpty{buffer.append(data)}}
 try p.run();active[id]=p
 let start=Date()
 do {
 while p.isRunning {
 try Task.checkCancellation()
 if Date().timeIntervalSince(start)>(longRunning ? 3:timeout) {
 if longRunning {let r=ProcessEvidence(exit:nil,running:true,output:buffer.text,pid:p.processIdentifier);results[id]=r;return r}
 terminate(p);throw VoiceyError.unavailable("The command exceeded its time limit and was stopped.")
 }
 try await Task.sleep(nanoseconds:100_000_000)
 }
 } catch {if p.isRunning{terminate(p)};pipe.fileHandleForReading.readabilityHandler=nil;throw error}
 pipe.fileHandleForReading.readabilityHandler=nil
 buffer.append(pipe.fileHandleForReading.readDataToEndOfFile())
 let result=ProcessEvidence(exit:p.terminationStatus,running:false,output:buffer.text,pid:p.processIdentifier);results[id]=result;active[id]=nil
 return result
 }
}
private final class ProcessOutput:@unchecked Sendable {
 private let lock=NSLock();private var data=Data()
 func append(_ d:Data){lock.lock();defer{lock.unlock()};if data.count<16384{data.append(d.prefix(16384-data.count))}}
 var text:String{lock.lock();defer{lock.unlock()};return String(decoding:data,as:UTF8.self)}
}
@MainActor final class NativeComputerAdapter:ComputerAdapter {
 let descriptor=AdapterDescriptor("macOS native and controlled processes",[.revealDirectory,.launchApplication,.runCommand,.inspectProject,.inspectAlarms,.runShortcut],permissions:["filesystem scopes","Automation for visible Terminal/Shortcuts"],verification:"NSWorkspace result, running applications, exit status, lsof cwd and TCP listeners",limitations:"Clock deletion unavailable without a reliable supported alarm interface; project with no process evidence is unknown")
 let discovery:ApplicationDiscoveryService,processes=ControlledProcesses(),ax=AccessibilityComputer()
 var filesystem:AuthorizedFilesystem
 private var opened=Set<UUID>(),commands:[UUID:Verification]=[:],projectEvidence:[UUID:Verification]=[:]
 init(discovery:ApplicationDiscoveryService,roots:[URL]){self.discovery=discovery;filesystem=AuthorizedFilesystem(roots:roots)}
 func cancel(){processes.cancel()}
 func finish(){processes.finish();commands=[:];projectEvidence=[:]}
 func application(_ name:String)throws->InstalledApp {let apps=discovery.matches(name);guard apps.count==1 else{throw VoiceyError.unavailable(apps.isEmpty ? "\(name) isn't installed. Available browsers: \(discovery.browsers().map(\.name).joined(separator:", ")). Choose an alternative explicitly.":"Multiple applications match \(name). Use the exact app name.")};return apps[0]}
 func observe(_ step:ComputerStep) async throws -> Verification {
 let a=step.arguments
 switch step.operation {
 case .launchApplication:
 let app=try application(a.application)
 return Verification(NSRunningApplication.runningApplications(withBundleIdentifier:app.bundleID).contains(where:{$0.isActive}) ? .success:.failure,"\(app.name) running state")
 case .revealDirectory: _ = try filesystem.directory(root:a.root,components:a.components,create:false);return Verification(opened.contains(step.id) ? .success:.unknown,"Native Finder open accepted")
 case .runCommand:
 if let r=processes.result(step.id){return Verification(r.running || r.exit==0 ? .success:.failure,r.running ? "Process \(r.pid) remains active; this alone doesn't establish server health.":"Exit status \(r.exit ?? -1). \(r.output.suffix(2000))")}
 return commands[step.id] ?? Verification(.unknown,"Command has not run")
 case .inspectProject:return projectEvidence[step.id] ?? Verification(.unknown,"Project has not been inspected")
 case .runShortcut:return commands[step.id] ?? Verification(.unknown,"Shortcut has not run")
 case .inspectAlarms:return Verification(.unknown,"Alarm interface discovery required")
 default:return Verification(.unknown,"Unsupported native observation")
 }
 }
 func execute(_ step:ComputerStep) async throws -> AdapterResult {
 let a=step.arguments
 switch step.operation {
 case .launchApplication:
 let app=try application(a.application)
 if let running=NSRunningApplication.runningApplications(withBundleIdentifier:app.bundleID).first{running.activate()}else{try await discovery.launch(app)}
 for _ in 0..<50 {try Task.checkCancellation();if !(NSRunningApplication.runningApplications(withBundleIdentifier:app.bundleID).isEmpty){return .verified(try await observe(step))};try await Task.sleep(nanoseconds:100_000_000)}
 throw VoiceyError.unavailable("The application did not become ready.")
 case .revealDirectory:
 let url=try filesystem.directory(root:a.root,components:a.components,create:false)
 guard NSWorkspace.shared.open(url) else{throw VoiceyError.unavailable("Finder did not accept the folder open.")};opened.insert(step.id);return .verified(try await observe(step))
 case .runCommand:
 let root=try filesystem.authorize(a.root)
 // Check actual processes with the exact project cwd before starting a dev server.
 if a.arguments == ["npm","run","dev"] {
 if let running=try await project(root,developmentCommandOnly:true),running.state == .success{commands[step.id]=running;return .verified(running)}
 if let existing=try await project(root){return .wait("A project listener already exists, but it isn't verified as npm run dev. Inspect it before continuing to avoid duplicates. \(existing.detail)")}
 }
 if a.application == "Terminal" {
 let terminal=try application("Terminal");try await discovery.launch(terminal)
 // Present the actual project; execution remains controlled for exit/cancel evidence.
 let script="tell application id \"com.apple.Terminal\"\nactivate\ndo script " + AppleScripting.literal("cd "+AppleScripting.shellQuote(root.path)+"; printf '%s\\n' 'Voicey runs the approved command in its controlled process. See Voicey task details for status.'") + "\nend tell"
 _ = try await AppleScripting.run(script)
 }
 let r=try await processes.run(id:step.id,executable:a.executable,args:a.arguments,directory:root,timeout:30,longRunning:a.arguments == ["npm","run","dev"])
 return .verified(Verification(r.running || r.exit==0 ? .success:.failure,r.running ? "Command is still running":"Exit \(r.exit ?? -1)"))
 case .inspectProject:
 let root=try filesystem.authorize(a.root)
 if !a.application.isEmpty {
 let app=try application(a.application)
 try await withCheckedThrowingContinuation{(c:CheckedContinuation<Void,Error>) in NSWorkspace.shared.open([root],withApplicationAt:app.url,configuration:NSWorkspace.OpenConfiguration()){_,error in if let error{c.resume(throwing:error)}else{c.resume()}}}
 }
 let evidence=try await project(root) ?? Verification(.unknown,"No matching process/listener evidence for \(root.path). Status is unknown; a remote or externally managed project may still be running.")
 projectEvidence[step.id]=evidence;return .verified(evidence)
 case .runShortcut:
 let list=try await processes.run(id:UUID(),executable:"/usr/bin/shortcuts",args:["list"],directory:URL(fileURLWithPath:NSHomeDirectory()))
 guard list.exit==0,list.output.split(separator:"\n").map(String.init).contains(a.shortcut) else{throw VoiceyError.unavailable("The exact Shortcut wasn't found.")}
 guard a.text.isEmpty else{throw VoiceyError.invalid("This adapter supports Shortcuts without input only; add a dedicated validated input adapter first.")}
 let r=try await processes.run(id:step.id,executable:"/usr/bin/shortcuts",args:["run",a.shortcut],directory:URL(fileURLWithPath:NSHomeDirectory()))
 let evidence=Verification(r.exit==0 ? .unknown:.failure,r.exit==0 ? "Shortcut completed, but its effect cannot be verified without a dedicated outcome adapter.":"Shortcut failed: \(r.output)")
 commands[step.id]=evidence;return .verified(evidence)
 case .inspectAlarms:
 let apps=discovery.applications().filter{$0.bundleID=="com.apple.clock" || $0.name.lowercased().contains("alarm")}
 guard !apps.isEmpty else{throw VoiceyError.unavailable("No alarm application was discovered. Select an installed app or an explicitly authorized Shortcut.")}
 let names=apps.map(\.name).joined(separator:", ")
 throw VoiceyError.unavailable("Discovered \(names). No verified alarm-list/delete integration is available. No alarms were changed. Use the alarm app directly or a named, explicitly authorized Shortcut.")
 default:throw VoiceyError.invalid("Unsupported native operation")
 }
 }
 private func project(_ root:URL,developmentCommandOnly:Bool=false) async throws -> Verification? {
 let r=try await processes.run(id:UUID(),executable:"/usr/sbin/lsof",args:["-a","-d","cwd","-Fpn","+D",root.path],directory:root,timeout:5)
 let lines=r.output.split(separator:"\n");var pid:String?,matches:[String]=[]
 for line in lines {if line.hasPrefix("p"){pid=String(line.dropFirst())};if line=="n"+root.path,let pid{matches.append(pid)}}
 var developmentPIDs=Set<String>()
 if developmentCommandOnly {
 for pid in matches.prefix(32) {
 let command=try await processes.run(id:UUID(),executable:"/bin/ps",args:["-p",pid,"-o","args="],directory:root,timeout:3)
 if command.output.range(of:"(?:^|/)npm run dev(?:\\s|$)",options:.regularExpression) != nil{developmentPIDs.insert(pid)}
 }
 if developmentPIDs.isEmpty{return nil}
 }
 for pid in matches.prefix(32) {
 if developmentCommandOnly {
 var candidate=pid,belongs=false
 for _ in 0..<16 {
 if developmentPIDs.contains(candidate){belongs=true;break}
 let parent=try await processes.run(id:UUID(),executable:"/bin/ps",args:["-p",candidate,"-o","ppid="],directory:root,timeout:3)
 let next=parent.output.trimmingCharacters(in:.whitespacesAndNewlines)
 guard Int(next) != nil,next != "1",next != candidate else{break};candidate=next
 }
 if !belongs{continue}
 }
 let listen=try await processes.run(id:UUID(),executable:"/usr/sbin/lsof",args:["-a","-p",pid,"-iTCP","-sTCP:LISTEN","-Fn"],directory:root,timeout:5)
 let addresses=listen.output.split(separator:"\n").filter{$0.hasPrefix("n")}.map{String($0.dropFirst())}
 if !addresses.isEmpty{return Verification(.success,"Project process \(pid) has cwd \(root.path) and TCP listeners: \(addresses.joined(separator:", ")). Application health not inferred.")}
 }
 return nil
 }
}
@MainActor enum AppleScripting {
 static func literal(_ text:String)->String{"\""+text.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"").replacingOccurrences(of:"\n",with:"\\n")+"\""}
 static func shellQuote(_ text:String)->String{"'"+text.replacingOccurrences(of:"'",with:"'\\''")+"'"}
 static func run(_ source:String) async throws -> String {
 // osascript only executes fixed application adapter templates, never model code.
 let process=ControlledProcesses()
 let result=try await withTaskCancellationHandler(operation:{try await process.run(id:UUID(),executable:"/usr/bin/osascript",args:["-e",source],directory:URL(fileURLWithPath:NSHomeDirectory()),timeout:8)},onCancel:{Task{@MainActor in process.cancel()}})
 guard result.exit==0 else{throw VoiceyError.unavailable("Automation failed or was denied: \(result.output.prefix(500))")};return result.output.trimmingCharacters(in:.whitespacesAndNewlines)
 }
}
