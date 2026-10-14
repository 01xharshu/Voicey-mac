import Foundation
import VoiceyCore

@MainActor final class MockComputerAdapter:ComputerAdapter {
 let descriptor=AdapterDescriptor("test adapter",Set(ComputerOperation.allCases),verification:"test-double state")
 var executed:[UUID]=[],done=Set<UUID>(),failure=false,unknown=false,waiting=false,transient=0
 var onExecute:((ComputerStep)->Void)?
 func observe(_ step:ComputerStep) async throws -> Verification {Verification(done.contains(step.id) ? .success:unknown ? .unknown:.failure,"mock observed")}
 func execute(_ step:ComputerStep) async throws -> AdapterResult {
 executed.append(step.id);onExecute?(step)
 if waiting {return .wait("Sign in, then continue")}
 if transient>0{transient-=1;throw VoiceyError.unavailable("Changed state")}
 if !failure && !unknown{done.insert(step.id)}
 return .verified(Verification(failure ? .failure:unknown ? .unknown:.success,"mock executed"))
 }
}
@MainActor enum ComputerTests {
 static var count=0
 static func check(_ name:String,_ block:() async throws->Void) async {do{try await block();print("CHECK \(name)")}catch{fail("\(name): \(error.localizedDescription)")};count+=1}
 static func temp()throws->URL{let u=FileManager.default.temporaryDirectory.appendingPathComponent("voicey2-"+UUID().uuidString);try FileManager.default.createDirectory(at:u,withIntermediateDirectories:true);return u.resolvingSymlinksInPath()}
 static func folderPlan(_ root:URL)throws->ComputerTask{var w=WorkflowRequest(.folders);w.root=root.path;w.folders=["ICICI","Repo"];return try WorkflowPlanner.plan(w,original:"Create ICICI and Repo")}
 static func engine(_ adapter:ComputerAdapter)->ComputerUseAgent{let a=ComputerUseAgent();a.register(adapter);return a}
 static func two()->ComputerTask{var a=OperationArguments();a.root="/test";let first=ComputerStep(.ensureDirectory,a,title:"first");let second=ComputerStep(.ensureDirectory,a,title:"second",after:[first.id]);return ComputerTask(request:"create folders",intention:"test",steps:[first,second])}
 static func run() async {
 await check("plan order and dependency enforcement") {
 let m=MockComputerAdapter(),e=engine(m),p=two();await e.start(p);expectEqual(m.executed,p.steps.map(\.id));expectEqual(e.task?.status,.complete)
 var invalid=p;invalid.steps.reverse();expectThrows(try e.validate(invalid))
 }
 for state in [0,1,2] {
 await check("filesystem ICICI/Repo existing state \(state)") {
 let root=try temp();defer{try? FileManager.default.removeItem(at:root)}
 if state>0 {try FileManager.default.createDirectory(at:root.appendingPathComponent(state==2 ? "ICICI/Repo":"ICICI"),withIntermediateDirectories:true)}
 let e=engine(FilesystemComputerAdapter(roots:[root]))
 await e.start(try folderPlan(root));expectEqual(e.task?.status,.complete)
 await e.start(try folderPlan(root));expectEqual(e.task?.status,.complete)
 expectEqual(try FileManager.default.contentsOfDirectory(atPath:root.path),["ICICI"])
 expectEqual(try FileManager.default.contentsOfDirectory(atPath:root.appendingPathComponent("ICICI").path),["Repo"])
 expectTrue(FileManager.default.fileExists(atPath:root.appendingPathComponent("ICICI/Repo").path))
 }
 }
 for conflict in ["ICICI","ICICI/Repo"] {
 await check("incompatible object \(conflict) preserved") {
 let root=try temp();defer{try? FileManager.default.removeItem(at:root)}
 if conflict.contains("/"){try FileManager.default.createDirectory(at:root.appendingPathComponent("ICICI"),withIntermediateDirectories:false)}
 try Data("unchanged".utf8).write(to:root.appendingPathComponent(conflict))
 let e=engine(FilesystemComputerAdapter(roots:[root]));await e.start(try folderPlan(root));expectEqual(e.task?.status,.failed)
 expectEqual(try String(contentsOf:root.appendingPathComponent(conflict),encoding:.utf8),"unchanged")
 }
 }
 await check("symlink and unauthorized parent rejected") {
 let root=try temp(),outside=try temp();defer{try? FileManager.default.removeItem(at:root);try? FileManager.default.removeItem(at:outside)}
 try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("ICICI"),withDestinationURL:outside)
 let fs=AuthorizedFilesystem(roots:[root]);expectThrows(try fs.directory(root:root.path,components:["ICICI","Repo"],create:true));expectThrows(try fs.authorize(outside.path));expectFalse(FileManager.default.fileExists(atPath:outside.appendingPathComponent("Repo").path))
 }
 await check("unavailable path fails and does not run dependent steps") {
 let root=try temp(),p=try folderPlan(root);try FileManager.default.removeItem(at:root)
 let e=engine(FilesystemComputerAdapter(roots:[root]));await e.start(p);expectEqual(e.task?.status,.failed);expectEqual(e.task?.steps[1].attempts,0)
 }
 await check("recover from changed state without repeating complete steps") {
 let m=MockComputerAdapter();m.transient=1;let e=engine(m),p=two();await e.start(p);expectEqual(e.task?.status,.complete);expectEqual(m.executed.filter{$0==p.steps[0].id}.count,2);expectEqual(m.executed.filter{$0==p.steps[1].id}.count,1)
 }
 await check("cancellation prevents remaining steps") {
 let m=MockComputerAdapter(),e=engine(m);m.onExecute={_ in e.cancel()};await e.start(two());expectEqual(m.executed.count,1);expectEqual(e.task?.status,.cancelled)
 }
 await check("failure never reports success") {let m=MockComputerAdapter();m.failure=true;let e=engine(m);await e.start(two());expectEqual(e.task?.status,.failed);expectEqual(m.executed.count,3)}
 await check("unknown verification remains partial") {let m=MockComputerAdapter();m.unknown=true;let e=engine(m);await e.start(two());expectEqual(e.task?.status,.partiallyVerified)}
 await check("bounded task-step budget") {let e=ComputerUseAgent();e.configuration.maxSteps=1;expectThrows(try e.validate(two()))}
 await check("website and external preview policy enforced") {
 var a=OperationArguments();a.url="https://chatgpt.com/";a.application="Arc";a.text="why horses exist"
 let s=ComputerStep(.submitPrompt,a,title:"ask")
 expectEqual(ActionRiskPolicy.evaluate(s,request:"Open ChatGPT and ask it why horses exist",preview:false),.execute)
 if case .confirm=ActionRiskPolicy.evaluate(s,request:"Open ChatGPT and ask it why horses exist",preview:true){}else{fail("Preview must require approval")}
 if case .confirm=ActionRiskPolicy.evaluate(s,request:"Ask another question",preview:false){}else{fail("Transformed text must be previewed")}
 if case .reject=ActionRiskPolicy.evaluate(s,request:"type only without submitting",preview:false){}else{fail("Draft must not submit")}
 }
 await check("browser operation cannot bypass destination approval") {
 var a=OperationArguments();a.url="https://chatgpt.com/";a.application="Arc"
 let e=ComputerUseAgent(),p=ComputerTask(request:"ask",intention:"ask",steps:[ComputerStep(.submitPrompt,a,title:"submit")]);expectThrows(try e.validate(p))
 }
 await check("approved workflow pause uses existing context and cancel cannot resume") {
 let m=MockComputerAdapter(),e=engine(m);var w=WorkflowRequest(.chatGPT);w.browser="Arc";w.text="why horses exist";w.submit=true
 let p=try WorkflowPlanner.plan(w,original:"Open the website in Arc and ask it why horses exist")
 await e.start(p);expectEqual(e.task?.status,.waiting);expectEqual(m.executed.count,1)
 await e.reply("yes");expectEqual(e.task?.status,.complete);expectEqual(m.executed.count,5)
 await e.start(p);e.cancel();let before=m.executed.count;await e.reply("continue");expectEqual(m.executed.count,before)
 }
 await check("authentication wait preserves completed steps") {
 let m=MockComputerAdapter(),e=engine(m);m.waiting=true;await e.start(two());expectEqual(e.task?.status,.waiting);m.waiting=false;await e.reply("continue");expectEqual(e.task?.status,.complete)
 }
 await check("uncertain submission is never retried") {
 let m=MockComputerAdapter(),e=engine(m);var w=WorkflowRequest(.chatGPT);w.browser="Arc";w.text="why horses exist";w.submit=true
 let p=try WorkflowPlanner.plan(w,original:"Ask it why horses exist");m.onExecute={step in if step.operation == .submitPrompt{m.unknown=true}}
 await e.start(p);await e.reply("yes");expectEqual(e.task?.status,.partiallyVerified);expectEqual(m.executed.filter{$0==p.steps.last!.id}.count,1)
 }
 await check("exact explicit command validation") {
 try CommandPolicy.validate(executable:"/usr/bin/git",arguments:["status"],original:"Run `git status` in my project")
 try CommandPolicy.validate(executable:"/usr/bin/env",arguments:["npm","run","dev"],original:"Run `npm run dev` in my project")
 expectThrows(try CommandPolicy.validate(executable:"/bin/rm",arguments:["-rf","/"],original:"Run `rm -rf /`"))
 expectThrows(try CommandPolicy.validate(executable:"/usr/bin/git",arguments:["status"],original:"Inspect my project"))
 expectThrows(try CommandPolicy.tokenize("echo hello; rm file"))
 expectEqual(try CommandPolicy.tokenize("echo 'hello world'"),["echo","hello world"])
 }
 await check("command policy requires approval for scripts") {
 var a=OperationArguments();a.executable="/usr/bin/env";a.arguments=["npm","run","dev"];a.root="/project"
 if case .confirm=ActionRiskPolicy.evaluate(ComputerStep(.runCommand,a,title:"run"),request:"run",preview:false){}else{fail("Project scripts require approval")}
 a.executable="/bin/pwd";a.arguments=[];expectEqual(ActionRiskPolicy.evaluate(ComputerStep(.runCommand,a,title:"run"),request:"run",preview:false),.execute)
 }
 await check("browser schema unauthorized origins and replies rejected") {
 var c=BrowserCommand(.inspect,url:"https://chatgpt.com/");try c.validate()
 c.url="https://chatgpt.com.evil.test/";expectThrows(try c.validate());c.url="https://chatgpt.com/"
 var reply=BrowserReply(id:c.id,ok:true,url:"https://mail.google.com/",state:"ready",detail:"test");expectThrows(try reply.validate(for:c));reply.url=c.url;reply.id=UUID().uuidString;expectThrows(try reply.validate(for:c))
 }
 await check("Gmail exact recipient and draft-only plan") {
 var w=WorkflowRequest(.gmailDraft);w.browser="Arc";w.recipient="Harsh Mishra";w.text="Thank you."
 expectThrows(try WorkflowPlanner.plan(w,original:"Draft a thank-you email"));w.recipient="harsh@example.test"
 let p=try WorkflowPlanner.plan(w,original:"Draft a thank-you email");expectEqual(p.steps.last?.operation,.gmailDraft);expectFalse(p.steps.contains{$0.operation == .submitPrompt});expectEqual(p.steps.last?.arguments.recipient,w.recipient)
 }
 await check("workflow natural-language examples") {
 let one=WorkflowPlanner.parse("Open Finder, go to Documents, create a folder named ICICI, and if it exists, get into it and create a new folder called Repo.")
 expectEqual(one?.folders,["ICICI","Repo"]);expectEqual(one?.root,"Documents")
 let two=WorkflowPlanner.parse("Open Finder, go to Documents, check if ICICI exists, open it if it does, create it if it doesn't, and create a folder called Repo inside it.");expectEqual(two?.folders,["ICICI","Repo"])
 let chat=WorkflowPlanner.parse("Open ChatGPT in my Arc browser and ask it why horses exist.");expectEqual(chat?.browser,"Arc");expectEqual(chat?.text,"why horses exist.");expectEqual(chat?.submit,true)
 let terminal=WorkflowPlanner.parse("Open Terminal, run `npm run dev` in my Tipsy Docy project, and then check whether the application is running.");expectEqual(terminal?.root,"Tipsy Docy");expectEqual(terminal?.command,"npm run dev")
 }
 await check("unsupported alarms produce no fake success") {
 let e=ComputerUseAgent();await e.start(try WorkflowPlanner.plan(WorkflowRequest(.alarms),original:"Delete alarms before seven"));expectEqual(e.task?.status,.failed)
 }
 await check("alarm AM/PM parsing and exact selection") {
 expectEqual(AlarmPolicy.deleteAction(["AXPress","Name:Delete alarm\nTarget:0x0\nSelector:(null)"]),"Name:Delete alarm\nTarget:0x0\nSelector:(null)");expectNil(AlarmPolicy.deleteAction(["Name:Toggle alarm\nTarget:0x0"]));
 expectEqual(AlarmPolicy.time("6:30AM"),390);expectEqual(AlarmPolicy.time("12:00AM"),0);expectEqual(AlarmPolicy.time("12:00PM"),720)
 expectEqual(try AlarmPolicy.cutoffs("before seven"),[420,1140]);expectEqual(try AlarmPolicy.cutoffs("before 7 PM"),[1140])
 expectNil(AlarmPolicy.time("25:99AM"))
 let alarms=[AlarmRecord(id:"early",minutes:390),AlarmRecord(id:"equal",minutes:420),AlarmRecord(id:"late",minutes:1200)]
 expectEqual(AlarmPolicy.select(alarms,before:420).map(\.id),["early"])
 expectEqual(AlarmPolicy.verify(before:alarms,selected:[alarms[0]],after:Array(alarms.dropFirst())).state,.success)
 expectEqual(AlarmPolicy.verify(before:alarms,selected:[alarms[0]],after:[]).state,.failure)
 }
 await check("alarm batch approval precedes destructive execution") {
 let m=MockComputerAdapter(),e=engine(m);var a=OperationArguments();a.alarmIDs=["one","two"];a.alarmTimes=["5:00 AM","6:00 AM"];a.cutoff=420
 let step=ComputerStep(.deleteAlarms,a,title:"delete selected")
 await e.start(ComputerTask(request:"Delete alarms before 7 AM",intention:"delete selected",steps:[step]))
 expectEqual(m.executed.count,0);expectEqual(e.pending?.kind,.approval)
 await e.reply("yes");expectEqual(m.executed.count,1);expectEqual(e.task?.status,.complete)
 }
 await check("uncertain alarm deletion is not retried") {
 let m=MockComputerAdapter(),e=engine(m);m.unknown=true;var a=OperationArguments();a.alarmIDs=["one"];a.alarmTimes=["6:00 AM"]
 await e.start(ComputerTask(request:"Delete selected alarm",intention:"delete",steps:[ComputerStep(.deleteAlarms,a,title:"delete")]))
 await e.reply("yes");expectEqual(m.executed.count,1);expectEqual(e.task?.status,.partiallyVerified)
 }
 print("Completed \(count) computer-use scenarios")
 }
}
