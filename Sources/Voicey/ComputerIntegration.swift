import AppKit
import VoiceyCore

extension AgentOrchestrator {
 func configureComputer() {
 computer.register(interfaceComputer);computer.register(filesystemComputer);computer.register(alarmComputer);computer.register(nativeComputer);computer.register(browserComputer)
 computer.changed = { [weak self] task,question in
 guard let self else{return}
 self.computerTask=task
 guard let task else{return}
 if let question {
 self.setComputerPending(question)
 return
 }
 if case .computer=self.pending {self.pending=nil}
 switch task.status {
 case .running,.planned:
 self.state = .executing
 self.message=task.steps.first(where:{![.verified,.pending].contains($0.status)})?.title ?? "Inspecting your Mac…"
 case .complete:
 self.activeWorkflow=nil
 self.saveTaskSummary(task)
 let detail=task.steps.last?.evidence?.detail ?? task.requiredOutcome
 self.report("Done. \(detail)",speak:UserDefaults.standard.object(forKey:"computerNarration") as? Bool != false)
 case .failed,.partiallyVerified:
 self.saveTaskSummary(task)
 let done=task.steps.filter{$0.status == .verified}.count
 let detail=task.unresolvedAmbiguity ?? task.steps.last(where:{$0.evidence != nil})?.evidence?.detail ?? "Verification unavailable"
 self.report("\(done)/\(task.steps.count) steps verified. \(detail)",state:.error)
 case .cancelled:break
 case .waiting:break
 }
 }
 }
 func saveTaskSummary(_ task:ComputerTask) {
 guard !summarizedTasks.contains(task.id) else{return};summarizedTasks.insert(task.id)
 let formatter=DateFormatter();formatter.dateStyle = .short;formatter.timeStyle = .short
 let summary="\(formatter.string(from:Date())) · \(task.steps.first?.operation.rawValue ?? "task") · \(task.status.rawValue) · \(task.steps.filter{$0.status == .verified}.count)/\(task.steps.count) verified"
 recentComputerTasks=Array(([summary]+recentComputerTasks).prefix(20))
 UserDefaults.standard.set(recentComputerTasks,forKey:"computerTaskSummaries")
 }
 func clearComputerHistory(){recentComputerTasks=[];UserDefaults.standard.removeObject(forKey:"computerTaskSummaries")}
 func prepareWorkflow(_ request:WorkflowRequest,original:String) async {
 var w=request
 computer.continuation=nil
 var config=ComputerConfiguration()
 config.enabled=UserDefaults.standard.object(forKey:"computerUseEnabled") as? Bool != false
 config.previewExternalPrompts=UserDefaults.standard.bool(forKey:"previewExternalPrompts")
 let budget=UserDefaults.standard.integer(forKey:"computerStepBudget"),retry=UserDefaults.standard.object(forKey:"computerRetries") as? Int ?? 2
 config.maxSteps=budget==0 ? 24:budget;config.retries=retry;computer.configuration=config
 guard config.enabled else{report("Computer use is disabled in Settings.",state:.error);return}
 if [.chatGPT,.gmailDraft].contains(w.kind) {
 if w.browser.isEmpty {
 if let saved=memory?.document.preferredBrowser,let app=discovery.browsers().first(where:{$0.bundleID==saved}){w.browser=app.name}
 else {askWorkflow(w,field:"browser",original:original,question:"Which browser? Installed: \(discovery.browsers().map(\.name).joined(separator:", ")).");return}
 }
 if discovery.browsers().filter({$0.name.caseInsensitiveCompare(w.browser) == .orderedSame || ($0.name=="Google Chrome" && w.browser.lowercased()=="chrome")}).isEmpty {
 askWorkflow(w,field:"browser",original:original,question:"\(w.browser) isn't available. Choose an installed browser: \(discovery.browsers().map(\.name).joined(separator:", ")).");return
 }
 if let app=discovery.browsers().first(where:{$0.name.caseInsensitiveCompare(w.browser) == .orderedSame || ($0.name=="Google Chrome" && w.browser.lowercased()=="chrome")}){w.browser=app.name}
 if w.kind == .gmailDraft,!WorkflowPlanner.validEmail(w.recipient) {
 if let address=memory?.alias(w.recipient),WorkflowPlanner.validEmail(address){w.recipient=address}
 else {askWorkflow(w,field:"recipient",original:original,question:"What is \(w.recipient.isEmpty ? "the recipient's":w.recipient+"'s") exact email address? Nothing will be sent.");return}
 }
 if w.text.isEmpty {
 if w.kind == .gmailDraft && (original.lowercased().contains("thank-you") || original.lowercased().contains("thank you")){w.text="Thank you.";w.subject="Thank you"}
 else {askWorkflow(w,field:"text",original:original,question:"What exact text should I prepare?");return}
 }
 }
 if w.kind == .alarms {
 if w.application.isEmpty {
 let apps=discovery.applications().filter{$0.bundleID=="com.apple.clock" || $0.name.lowercased().contains("alarm")}
 guard apps.count==1 else{askWorkflow(w,field:"alarmApp",original:original,question:"Which alarm app? Discovered: \(apps.map(\.name).joined(separator:", ")).");return}
 w.application=apps[0].name
 }
 if w.cutoff==nil {
 do {
 let options=try AlarmPolicy.cutoffs(w.text.isEmpty ? original:w.text)
 if options.count==1{w.cutoff=options[0]}
 else {
 if let app=try? nativeComputer.application(w.application){try await discovery.launch(app)}
 let alarms=try alarmComputer.list(application:w.application).map(\.0)
 if AlarmPolicy.select(alarms,before:options[0])==AlarmPolicy.select(alarms,before:options[1]){w.cutoff=options[0]}
 else{askWorkflow(w,field:"alarmCutoff",original:original,question:"Does that mean before \(AlarmRecord(id:"am",minutes:options[0]).time) or before \(AlarmRecord(id:"pm",minutes:options[1]).time)? No alarms have been changed.");return}
 }
 }catch{askWorkflow(w,field:"alarmCutoff",original:original,question:"Open the supported app to Alarms, then give the cutoff with AM or PM. \(error.localizedDescription)");return}
 }
 }
 let scopes=searchScopes()
 filesystemComputer.filesystem=AuthorizedFilesystem(roots:scopes);nativeComputer.filesystem=AuthorizedFilesystem(roots:scopes)
 if [.folders,.command,.projectStatus].contains(w.kind) {
 if w.root.isEmpty {askWorkflow(w,field:"root",original:original,question:"Which authorized parent or project folder should I use?");return}
 let raw=memory?.alias(w.root) ?? w.root
 let common:[String:FileManager.SearchPathDirectory]=["documents":.documentDirectory,"desktop":.desktopDirectory,"downloads":.downloadsDirectory]
 let name=raw.lowercased().replacingOccurrences(of:"my ",with:"").replacingOccurrences(of:" folder",with:"")
 if let directory=common[name],let url=FileManager.default.urls(for:directory,in:.userDomainMask).first{w.root=url.path}
 else if raw.hasPrefix("/") || raw.hasPrefix("~/"){w.root=(raw as NSString).expandingTildeInPath}
 else {
 do {
 let results=try await Task.detached{try FileSearchService().search(raw,scopes:scopes).filter(\.directory)}.value
 try Task.checkCancellation()
 guard results.count==1 || FileSearchService.unambiguous(results) else {
 askWorkflow(w,field:"root",original:original,question:results.isEmpty ? "No authorized project matched \(raw). Enter its absolute path or add its parent in Settings → Files.":"Which project path?\n"+results.prefix(5).map{$0.url.path}.joined(separator:"\n"));return
 }
 w.root=results[0].url.path
 }catch{report(error.localizedDescription,state:.error);return}
 }
 }
 do {try Task.checkCancellation();let plan=try WorkflowPlanner.plan(w,original:original);activeWorkflow=(w,original);if revisingWorkflow{revisingWorkflow=false;await computer.replan(plan)}else{await computer.start(plan)}}catch{if !Task.isCancelled{report(error.localizedDescription,state:.error)}}
 }
 func receiveWorkflowAnswer(_ answer:String,request:WorkflowRequest,field:String,original:String) {
 var w=request
 switch field {case "browser":w.browser=answer.replacingOccurrences(of:"Use ",with:"",options:.caseInsensitive)
 case "root":w.root=answer
 case "recipient":w.recipient=answer
 case "text":w.text=answer
 case "alarmApp":w.application=answer
 case "alarmCutoff":w.text=answer;w.cutoff=nil
 default:return}
 pending=nil
 runWorkflow(w,original:original)
 }
}
