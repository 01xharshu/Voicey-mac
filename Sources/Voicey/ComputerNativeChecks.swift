import AppKit
import ApplicationServices
import VoiceyCore

@MainActor enum ComputerNativeChecks {
 static func run() async -> Int32 {
 var failures=0,count=0
 func check(_ value:Bool,_ name:String){count+=1;if value{print("PASS \(name)")}else{failures+=1;print("FAIL \(name)")}}
 let root=FileManager.default.temporaryDirectory.appendingPathComponent("voicey-native-"+UUID().uuidString)
 do {
 try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
 let processes=ControlledProcesses()
 let echo=try await processes.run(id:UUID(),executable:"/bin/echo",args:["Voicey exact output"],directory:root)
 check(echo.exit==0 && echo.output.contains("Voicey exact output"),"real process output and exit status")
 let bad=try await processes.run(id:UUID(),executable:"/usr/bin/false",args:[],directory:root)
 check(bad.exit != 0 && !bad.running,"failed command exit is captured")
 let id=UUID();let live=try await processes.run(id:id,executable:"/bin/sleep",args:["10"],directory:root,longRunning:true)
 check(live.running && live.exit==nil,"long-running process distinct from completed")
 processes.cancel();try await Task.sleep(nanoseconds:200_000_000)
 check(kill(live.pid,0) != 0,"cancellation terminates controlled process")
 let job=Task{try await processes.run(id:UUID(),executable:"/bin/sleep",args:["10"],directory:root)}
 try await Task.sleep(nanoseconds:100_000_000);job.cancel()
 do{_ = try await job.value;check(false,"Task cancellation interrupts process")}catch{check(true,"Task cancellation interrupts process")}
 let discovery=ApplicationDiscoveryService()
 check(discovery.applications().contains{$0.bundleID=="company.thebrowser.Browser"},"installed Arc discovery on this Mac")
 let native=NativeComputerAdapter(discovery:discovery,roots:[root]),engine=ComputerUseAgent()
 engine.register(FilesystemComputerAdapter(roots:[root]));engine.register(native)
 var w=WorkflowRequest(.folders);w.root=root.path;w.folders=["ICICI","Repo"]
 if CommandLine.arguments.contains("--show-finder"){w.application="Finder"}
 await engine.start(try WorkflowPlanner.plan(w,original:"Create folders"))
 check(engine.task?.status == .complete,"actual integrated native filesystem workflow")
 var a=OperationArguments();a.root=root.path
 let project=ComputerStep(.inspectProject,a,title:"inspect")
 let r=try await native.execute(project)
 if case .verified(let v)=r{check(v.state == .unknown,"no process evidence reports unknown")}else{check(false,"project result")}
 check(native.descriptor.operations.contains(.runCommand),"native registry contains process adapter")
 if CommandLine.arguments.contains("--dev-server-check") {
 try Data("{\"scripts\":{\"dev\":\"node server.js\"}}".utf8).write(to:root.appendingPathComponent("package.json"))
 try Data("require('http').createServer((q,s)=>s.end('voicey fixture')).listen(0,'127.0.0.1');".utf8).write(to:root.appendingPathComponent("server.js"))
 var command=OperationArguments();command.root=root.path;command.executable="/usr/bin/env";command.arguments=["npm","run","dev"]
 let first=ComputerStep(.runCommand,command,title:"run fixture server")
 if case .verified(let evidence)=try await native.execute(first){check(evidence.state == .success,"actual npm dev fixture starts")}else{check(false,"dev fixture starts")}
 let probe=ComputerStep(.inspectProject,command,title:"inspect fixture server")
 if case .verified(let evidence)=try await native.execute(probe){check(evidence.state == .success,"actual cwd and TCP listener evidence")}else{check(false,"dev fixture inspection")}
 let second=ComputerStep(.runCommand,command,title:"reuse fixture server")
 if case .verified(let evidence)=try await native.execute(second){check(evidence.state == .success && native.processes.result(second.id)==nil,"equivalent npm server reused without starting another process")}else{check(false,"equivalent dev fixture reused")}
 native.cancel()
 }

 if CommandLine.arguments.contains("--inspect-clock-schema") {
 do{let alarms=try AlarmComputerAdapter(native:native).list(application:"Clock");print("CLOCK_SCHEMA supported rows=\(alarms.count), all unique IDs and Delete alarm actions; no alarm mutated")}catch{
 print("CLOCK_SCHEMA unavailable: \(error.localizedDescription)")
 if let app=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.clock").first {
 let ax=AccessibilityComputer();let controls=(try? ax.controls(pid:app.processIdentifier)) ?? []
 for c in controls where c.role=="AXButton" && (ax.value(c.element,kAXIdentifierAttribute) as? String ?? "").hasPrefix("Alarm-"){print("CLOCK_ACTION_NAMES \(c.actions)")}
 }
 }
 }
 if CommandLine.arguments.contains("--model-idle-check") {
 let model=LocalAIEngine(idleSeconds:30)
 check(!(await model.hasResidentModels),"model starts unloaded")
 let result=try await model.interpret("Please launch Figma for me.",context:"No aliases")
 check(result.kind == .launchApp && result.query=="Figma","actual embedded model inference")
 check(await model.hasResidentModels,"model resident after inference")
 print("MODEL_IDLE_CHECK waiting 32 seconds for automatic release, pid=\(getpid())");fflush(stdout)
 try await Task.sleep(nanoseconds:32_000_000_000)
 check(!(await model.hasResidentModels),"automatic idle timer releases actual native model")
 }
 if CommandLine.arguments.contains("--model-plan-check") {
 let model=LocalAIEngine()
 let plan=try await model.planWorkflow("Please make sure a folder named ICICI exists under Documents, with Repo nested inside, and show it in Finder.",context:"No aliases")
 print("SYNTHETIC_MODEL_PLAN \(String(data:try JSONEncoder().encode(plan),encoding:.utf8) ?? "none")")
 check(plan?.kind == .folders && plan?.folders == ["ICICI","Repo"],"embedded local model returns typed nested folder plan")
 await model.unload()
 }
 print("READINESS Accessibility=\(AXIsProcessTrusted()) ScreenCapture=\(CGPreflightScreenCaptureAccess()) (no permission request)")
 } catch {failures+=1;print("FAIL native checks: \(error.localizedDescription)")}
 print("Native checks: \(count), failures: \(failures)")
 return failures==0 ? 0:1
 }
}
