import AppKit
import SwiftUI
import AVFoundation
import NativeBridge
import VoiceyCore

enum AssistantState:String {case idle,greeting,listening,transcribing,thinking,executing,clarification,confirmation,browser,results,success,error,missing}
enum PendingAction {
 case website(URL,String),browser(URL),files(Intent,[SearchResult]),apps(Intent,[InstalledApp]),destination(Intent),computer,workflow(WorkflowRequest,String,String)
}
@MainActor final class AgentOrchestrator:ObservableObject {
 @Published var state:AssistantState = .idle
 @Published var message="Hold Control + Option + Command."
 @Published var transcript=""
 @Published var input=""
 @Published var level:Float=0
 @Published private(set) var shortcutActivations=0
 private var microphoneTest:((String)->Void)?
 @Published var pending:PendingAction?
 @Published var results:[SearchResult]=[]
 @Published var apps:[InstalledApp]=[]
 @Published var modelProgress:Double=0
 @Published var downloading=false
 @Published var modelStatus="Models are installed separately and stay on this Mac."
 @Published var memories:[MemoryEntry]=[]
 @Published var memoryError:String?
 @Published var computerTask:ComputerTask?
 @Published var recentComputerTasks:[String]=UserDefaults.standard.stringArray(forKey:"computerTaskSummaries") ?? []
 let computer=ComputerUseAgent()
 lazy var filesystemComputer=FilesystemComputerAdapter(roots:[])
 lazy var nativeComputer=NativeComputerAdapter(discovery:discovery,roots:[])
 lazy var interfaceComputer=InterfaceComputerAdapter(native:nativeComputer)
 lazy var alarmComputer=AlarmComputerAdapter(native:nativeComputer)
 lazy var browserComputer=BrowserComputerAdapter(native:nativeComputer)
 var summarizedTasks=Set<UUID>()
 var activeWorkflow:(WorkflowRequest,String)?
 var revisingWorkflow=false
 let communication=CommunicationController()
 let discovery=ApplicationDiscoveryService(),engine=LocalAIEngine(),audio=AudioCaptureService(),tts=SpeechSynthesisService(),hotkey=HotkeyManager()
 var memory:LocalMemoryStore?
 var showPanel:(()->Void)?,hidePanel:(()->Void)?
 private var websiteAuthorization=WebsiteAuthorization()
 private let registry=ToolRegistry()
 private var work:Task<Void,Never>?,downloadWork:Task<Void,Never>?,generation=UUID()
 private var pendingExpiry:Date?,lastResults:[SearchResult]=[],lastIntent:Intent?,lastItem:URL?
 private var scopeAccess:[URL]=[]
 private var idleTimer:Timer?
 private var voiceSession=false
 init(){do{memory=try LocalMemoryStore(url:supportDirectory.appendingPathComponent("memory.json"));memories=memory!.document.entries}catch{memoryError=error.localizedDescription}
 configureComputer()
 hotkey.activate={[weak self] in self?.activate(fromShortcut:true)}
 }
 func start(){hotkey.start()}
 func stop(){cancel();hotkey.stop()}
 func report(_ text:String,state:AssistantState = .success,speak:Bool=true){message=text;self.state=state;if speak && UserDefaults.standard.object(forKey:"spokenResponses") as? Bool != false {tts.speak(text,voice:UserDefaults.standard.string(forKey:"voiceID"),rate:speechRate){[weak self] in guard let self,self.voiceSession,self.pending != nil,[.clarification,.confirmation,.browser,.results].contains(self.state) else{return};self.listen()}};scheduleDismiss()}
 var speechRate:Float{let r=UserDefaults.standard.float(forKey:"speechRate");return r==0 ? AVSpeechUtteranceDefaultSpeechRate:r}
 func activate(fromShortcut:Bool=false){
 if fromShortcut{shortcutActivations+=1}
 NotificationCenter.default.post(name:Notification.Name("VoiceyVoiceInput"),object:nil)
 guard ![.listening,.thinking,.transcribing,.executing].contains(state) else{return}
 // Activation always listens first. Spoken replies follow a captured request.
 listen()
 }
 func prepareMicrophoneTest(_ result:@escaping(String)->Void){cancel();hidePanel?();microphoneTest=result}
 func startMicrophoneTest(_ result:@escaping(String)->Void){prepareMicrophoneTest(result);listen()}
 func listen(){if computer.task?.status == .running{computer.cancel()}
 NotificationCenter.default.post(name:Notification.Name("VoiceyVoiceInput"),object:nil);voiceSession=true;tts.stop();idleTimer?.invalidate();if microphoneTest==nil{showPanel?()}
 work?.cancel();generation=UUID();vy_cancel(0)
 work=Task{let granted=await AVCaptureDevice.requestAccess(for:.audio);guard !Task.isCancelled else{return};guard granted else{report("Microphone access is off. Use text or enable it in System Settings.",state:.missing,speak:false);return}
 do{let timeout=UserDefaults.standard.double(forKey:"listenTimeout");try audio.start(timeout:timeout==0 ? 20:timeout,level:{[weak self] in self?.level=$0},finished:{[weak self] in self?.recognize($0)});state = .listening;message="Listening…"}catch{report(error.localizedDescription,state:.error,speak:false)}
 }
 }
 func finishListening(){let samples=audio.stop();recognize(samples)}
 private func recognize(_ samples:[Float]){
 guard !samples.isEmpty else{report("No audio captured. Try again or type a command.",state:.error,speak:microphoneTest==nil);return}
 state = .transcribing;message="Transcribing on your Mac…";vy_cancel(0);let token=generation
 work=Task{do{let hints=memories.map{$0.phrase+", "+$0.target}.joined(separator:", ")
 let text=try await engine.transcribe(samples,language:UserDefaults.standard.string(forKey:"language") ?? "en",vocabulary:String(hints.prefix(2000)))
 guard generation==token,!Task.isCancelled else{return};transcript=memory?.corrected(text) ?? text
 if let test=microphoneTest{microphoneTest=nil;voiceSession=false;report("Microphone test transcribed successfully.",speak:false);test(transcript);return}
 if UserDefaults.standard.bool(forKey:"reviewTranscript"){input=transcript;report("Review the transcript, then press Send.",state:.clarification,speak:false)}else{submit(transcript)}
 }catch{if generation==token && !Task.isCancelled{report(error.localizedDescription,state:.error,speak:microphoneTest==nil)}}}
 }
 func cancel(){microphoneTest=nil;computer.cancel();voiceSession=false;websiteAuthorization.clear();generation=UUID();work?.cancel();work=nil;vy_cancel(1);audio.stop();tts.stop();pending=nil;pendingExpiry=nil;results=[];apps=[];state = .idle;message="Cancelled.";idleTimer?.invalidate()}
 func dismiss(){cancel();computer.clearFinishedContext();computerTask=nil;activeWorkflow=nil;hidePanel?()}
 private func scheduleDismiss(){idleTimer?.invalidate();guard pending==nil,state == .success else{return};let seconds=UserDefaults.standard.double(forKey:"idleDismissal");idleTimer=Timer.scheduledTimer(withTimeInterval:seconds==0 ? 12:seconds,repeats:false){[weak self] _ in Task{@MainActor in self?.dismiss()}}}
 private func setPending(_ value:PendingAction){pending=value;pendingExpiry=Date().addingTimeInterval(120);idleTimer?.invalidate()}
 func submitInput(){voiceSession=false;let text=input;input="";submit(text)}
 func submit(_ raw:String){let text=raw.trimmingCharacters(in:.whitespacesAndNewlines);guard !text.isEmpty else{return}
 microphoneTest=nil;showPanel?();tts.stop();audio.stop();idleTimer?.invalidate()
 if pendingExpiry.map({$0<Date()})==true{pending=nil;pendingExpiry=nil}
 let reply=Dialogue.reply(text)
 if reply == .cancel{cancel();return}
 if let response=LocalArithmetic.reply(text) ?? LocalConversation.reply(text){
 cancel();websiteAuthorization.clear();pending=nil;transcript=text;report(response);return
 }
 if case .computer=pending {
 if let (request,original)=activeWorkflow,text.lowercased().hasPrefix("use ") || text.lowercased().hasPrefix("no, i meant ") || text.lowercased().hasPrefix("try ") {
 let answer=text.replacingOccurrences(of:"use ",with:"",options:.caseInsensitive).replacingOccurrences(of:"no, i meant ",with:"",options:.caseInsensitive).replacingOccurrences(of:"try ",with:"",options:.caseInsensitive)
 var revised=request
 if [.chatGPT,.gmailDraft].contains(request.kind){revised.browser=answer}else{revised.root=answer}
 revisingWorkflow=true;pending=nil;work?.cancel();work=Task{await prepareWorkflow(revised,original:original+". Correction: "+text)};return
 }
 work?.cancel();work=Task{await computer.reply(text)};return
 }
 if case .workflow(let request,let field,let original)=pending {
 if case .newRequest=reply {pending=nil} else {receiveWorkflowAnswer(text,request:request,field:field,original:original);return}
 }
 if reply == .other,let intent=lastIntent,!lastResults.isEmpty{pending=nil;results=lastResults.filter{$0.url != lastItem};setPending(.files(intent,results));report("Which alternative did you mean?",state:.clarification);return}
 if let pending {
 let correction=text.lowercased().replacingOccurrences(of:"actually, ",with:"").replacingOccurrences(of:"actually ",with:"").replacingOccurrences(of:"use ",with:"")
 if case .website(let url,_)=pending,let browser=discovery.browsers().first(where:{$0.name.caseInsensitiveCompare(correction) == .orderedSame}){setPending(.website(url,browser.name));report("Use \(browser.name). Open this website? \(url.absoluteString)",state:.confirmation);return}
 switch (pending,reply) {
 case (.website(_,let requested),.approve):do{let url=try websiteAuthorization.approve();self.pending=nil;chooseBrowser(url,requested:requested)}catch{self.pending=nil;report(error.localizedDescription,state:.error)};return
 case (.browser(let url),.choice(let name)):
 let matches=discovery.browsers().filter{$0.name.localizedCaseInsensitiveContains(name)};if matches.count==1{openWebsite(url,browser:matches[0]);return};report("Choose an installed browser from the list.",state:.browser);return
 case (.files(let intent,let choices),.choice(let answer)):
 let matches=choices.filter{$0.url.path.localizedCaseInsensitiveContains(answer.replacingOccurrences(of:"the one in ",with:""))};if matches.count==1{selectFile(matches[0],intent:intent);return};report("Select the matching path below.",state:.clarification);return
 case (.apps(let intent,let choices),.choice(let answer)):
 if let app=choices.first(where:{$0.name.caseInsensitiveCompare(answer) == .orderedSame}){selectApp(app,intent:intent);return};report("Select an application below.",state:.clarification);return
 case (.destination(var intent),.choice(let answer)):intent.destination=answer;self.pending=nil;run(intent);return
 case (_, .newRequest):self.pending=nil;self.pendingExpiry=nil
 default:self.pending=nil;self.pendingExpiry=nil
 }
 }
 computer.cancel();activeWorkflow=nil;revisingWorkflow=false;websiteAuthorization.clear();transcript=text;work?.cancel();generation=UUID();let token=generation;vy_cancel(0);results=[];apps=[]
 state = .thinking;message="Understanding your request…"
 work=Task {
 do{
 if let result=await communication.handle(text){report(result,state:communication.blocked ? .missing:.success);return}
 let corrected=memory?.corrected(text) ?? text
 if corrected.lowercased().hasPrefix("i call this folder "),let lastItem{
 let phrase=String(corrected.dropFirst(19));try memory?.remember(MemoryEntry(phrase:phrase,target:lastItem.path));memories=memory?.document.entries ?? [];report("Remembered \(phrase) for \(lastItem.lastPathComponent).");return
 }
 if let workflow=WorkflowPlanner.parse(corrected) {
 await prepareWorkflow(workflow,original:corrected);return
 }
 var intent:Intent
 // Deterministic parsing accelerates explicit commands; embedded model handles broader language.
 if let parsed=IntentParser().parse(corrected), !corrected.lowercased().contains(" and "), !corrected.lowercased().contains(" then "){intent=parsed}else{
 let context="Aliases: "+memories.filter{$0.category=="alias"}.map{$0.phrase+" = "+$0.target}.joined(separator:"; ")+". Current project: "+(lastItem?.path ?? "none")
 if let workflow=try await engine.planWorkflow(corrected,context:context) {
 guard generation==token,!Task.isCancelled else{return}
 await prepareWorkflow(workflow,original:corrected);return
 }
 let decision=try await engine.decide(corrected,observation:context,desktop:false)
 guard generation==token,!Task.isCancelled else{return}
 switch decision.kind {
 case "answer":report(decision.explanation);return
 case "ask":report(decision.explanation,state:.clarification);return
 case "task":try await startGeneralGoal(corrected);return
 default:break
 }
 intent=try await engine.interpret(corrected,context:context)
 }
 guard generation==token,!Task.isCancelled else{return}
 await execute(intent,token:token)
 }catch{if generation==token && !Task.isCancelled{report(error.localizedDescription,state:.error)}}
 }
 }
 func setComputerPending(_ question:PendingComputerQuestion){
 setPending(.computer);pendingExpiry=question.expires
 report(question.text,state:question.kind == .approval ? .confirmation:.clarification)
 }
 func askWorkflow(_ request:WorkflowRequest,field:String,original:String,question:String){setPending(.workflow(request,field,original));report(question,state:.clarification)}
 func runWorkflow(_ request:WorkflowRequest,original:String){work?.cancel();computer.cancel();generation=UUID();work=Task{await prepareWorkflow(request,original:original)}}
 private func run(_ intent:Intent){work?.cancel();generation=UUID();let token=generation;vy_cancel(0);work=Task{await execute(intent,token:token)}}
 private func execute(_ original:Intent,token:UUID) async {
 var intent=original
 if let target=memory?.alias(intent.query){intent.query=target;if (try? URLValidator.validate(target)) != nil{intent.kind = .website}}
 if case .reject(let reason)=ActionRiskPolicy.evaluate(intent){report(intent.kind == .unsupported && !intent.explanation.isEmpty ? intent.explanation:reason,state:.error);return}
 do{try registry.validate(intent)}catch{report(error.localizedDescription,state:.error);return}
 switch ActionRiskPolicy.evaluate(intent) {
 case .reject(let reason):report(intent.explanation.isEmpty ? reason:intent.explanation,state:.error);return
 case .clarify(let question):if intent.kind == .createFolder{setPending(.destination(intent))};report(question,state:.clarification);return
 case .confirm(let destination):guard let url=try? websiteAuthorization.propose(destination) else{return};setPending(.website(url,intent.browser));report("Open this website? \(url.absoluteString)",state:.confirmation);return
 case .execute:break
 }
 guard generation==token,!Task.isCancelled else{return};state = .executing;message="Working on your Mac…"
 do {
 switch intent.kind {
 case .capabilities:report("I can launch apps, find and open files or folders, reveal items in Finder, open confirmed websites in your chosen browser, copy text, create folders, and save local aliases.")
 case .settings:AppDelegate.current?.settings();report("Opened Voicey settings.")
 case .clipboard:guard !intent.query.isEmpty else{throw VoiceyError.invalid("What text should I copy?")};NSPasteboard.general.clearContents();guard NSPasteboard.general.setString(intent.query,forType:.string) else{throw VoiceyError.unavailable("Clipboard write failed.")};report("Copied to the clipboard.")
 case .remember:
 guard let memory else{throw VoiceyError.unavailable(memoryError ?? "Memory unavailable.")}
 let target=try PathValidator.existing(intent.destination);try memory.remember(MemoryEntry(phrase:intent.query,target:target.path));memories=memory.document.entries;report("Remembered \(intent.query) locally.")
 case .createFolder:
 var w=WorkflowRequest(.folders);w.root=intent.destination;w.folders=[intent.query]
 await prepareWorkflow(w,original:transcript)
 case .launchApp,.openItem,.search,.reveal:
 if !intent.query.hasPrefix("/") && !intent.query.hasPrefix("~/"),intent.kind != .search {
 let candidates=discovery.matches(intent.query)
 if candidates.count==1{try await performApp(candidates[0],intent:intent);return}
 if candidates.count>1{apps=candidates;setPending(.apps(intent,candidates));report("Which application?",state:.clarification);return}
 }
 if intent.query.hasPrefix("/") || intent.query.hasPrefix("~/"){
 let url=try PathValidator.existing(intent.query);try openItem(url,intent:intent);return
 }
 let scopes=searchScopes(),hidden=UserDefaults.standard.bool(forKey:"hiddenFiles"),query=intent.query
 let search=Task.detached(priority:.userInitiated){let service=FileSearchService();let initial=try service.search(query,scopes:scopes,hidden:hidden)
 if !initial.isEmpty{return initial}
 return try service.search(query,scopes:[URL(fileURLWithPath:NSHomeDirectory())],hidden:hidden)}
 let found=try await withTaskCancellationHandler(operation:{try await search.value},onCancel:{search.cancel()})
 guard generation==token,!Task.isCancelled else{return}
 guard !found.isEmpty else{throw VoiceyError.unavailable("No accessible match found. Add a search folder in Settings or use a more specific name.")}
 lastResults=found;lastIntent=intent
 if intent.kind == .search{results=found;setPending(.files(intent,found));report("Found \(found.count) matching items. Select one to reveal it.",state:.results)}
 else if FileSearchService.unambiguous(found){try openItem(found[0].url,intent:intent)}else{results=found;setPending(.files(intent,found));report("Which item did you mean?",state:.clarification)}
 default:throw VoiceyError.invalid("That operation is unavailable.")
 }
 }catch{if generation==token && !Task.isCancelled{report(error.localizedDescription,state:.error)}}
 }
 private func resolveParent(_ raw:String)throws->URL {
 let q=raw.lowercased().replacingOccurrences(of:"my ",with:"").replacingOccurrences(of:" folder",with:"")
 if ["documents","desktop","downloads"].contains(q){return URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent(q.capitalized)}
 if q=="project",let lastItem{var d:ObjCBool=false;if FileManager.default.fileExists(atPath:lastItem.path,isDirectory:&d),d.boolValue{return lastItem}}
 return try PathValidator.existing(memory?.alias(raw) ?? raw)
 }
 private func openItem(_ url:URL,intent:Intent)throws {
 let validated=try PathValidator.existing(url.path)
 if intent.kind == .reveal || intent.kind == .search{NSWorkspace.shared.activateFileViewerSelecting([validated]);report("Revealed \(validated.lastPathComponent) in Finder.")}
 else{guard NSWorkspace.shared.open(validated) else{throw VoiceyError.unavailable("macOS could not open that item.")};report("Opened \(validated.lastPathComponent).")}
 lastItem=validated;pending=nil;pendingExpiry=nil
 }
 private func performApp(_ app:InstalledApp,intent:Intent) async throws {
 if intent.kind == .reveal{NSWorkspace.shared.activateFileViewerSelecting([app.url]);report("Revealed \(app.name) in Finder.")}
 else{try await discovery.launch(app);try Task.checkCancellation();report("Opened \(app.name).")};pending=nil
 }
 func selectFile(_ result:SearchResult,intent:Intent){pending=nil;pendingExpiry=nil;do{try openItem(result.url,intent:intent)}catch{report(error.localizedDescription,state:.error)}}
 func selectApp(_ app:InstalledApp,intent:Intent){pending=nil;generation=UUID();let token=generation;work=Task{do{try await performApp(app,intent:intent)}catch{if generation==token{report(error.localizedDescription,state:.error)}}}}
 func approveWebsite(){submit("yes")}
 func changeWebsite(){websiteAuthorization.clear();pending=nil;report("Type or say the corrected website address.",state:.clarification);input="open "}
 private func chooseBrowser(_ url:URL,requested:String){
 let installed=discovery.browsers()
 let resolution=BrowserPolicy.resolve(installed:installed.map{AvailableBrowser(id:$0.bundleID,name:$0.name)},explicit:requested,saved:memory?.document.preferredBrowser)
 switch resolution {
 case .selected(let id):if let browser=installed.first(where:{$0.bundleID==id}){openWebsite(url,browser:browser)}
 case .none:websiteAuthorization.clear();report("No installed browser was found.",state:.error)
 case .choose(let unavailable):apps=installed;setPending(.browser(url));report(unavailable ? "That browser is unavailable. Choose another.":"Which browser?",state:.browser)
 }
 }
 func openWebsite(_ url:URL,browser:InstalledApp){
 // Entry reachable only from an approved URL or a pending browser chooser for that same URL.
 pending=nil;pendingExpiry=nil;generation=UUID();let token=generation
 work=Task{do{let validated=try URLValidator.validate(url.absoluteString);try websiteAuthorization.consume(validated);guard generation==token,!Task.isCancelled else{return};try await discovery.website(validated,browser:browser);guard generation==token,!Task.isCancelled else{return}
 if UserDefaults.standard.bool(forKey:"rememberBrowser"){try memory?.browser(browser.bundleID)};report("Opened \(validated.host ?? "website") in \(browser.name).")
 }catch{if generation==token && !Task.isCancelled{report(error.localizedDescription,state:.error)}}}
 }
 func searchScopes()->[URL]{
 scopeAccess.forEach{$0.stopAccessingSecurityScopedResource()};scopeAccess=[]
 var scopes=["Desktop","Documents","Downloads"].map{URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent($0)}
 let bookmarks=UserDefaults.standard.array(forKey:"folderBookmarks") as? [Data] ?? []
 for data in bookmarks{var stale=false;if let url=try? URL(resolvingBookmarkData:data,options:.withSecurityScope,bookmarkDataIsStale:&stale),!stale{if url.startAccessingSecurityScopedResource(){scopeAccess.append(url)};scopes.append(url)}}
 return scopes
 }
 func addScope(){let p=NSOpenPanel();p.canChooseDirectories=true;p.canChooseFiles=false;p.allowsMultipleSelection=false
 if p.runModal() == .OK,let url=p.url,let data=try? url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil){var all=UserDefaults.standard.array(forKey:"folderBookmarks") as? [Data] ?? [];all.append(data);UserDefaults.standard.set(all,forKey:"folderBookmarks");objectWillChange.send()}}
 func downloadModels(){guard !downloading else{return};downloading=true;modelProgress=0
 downloadWork=Task{do{for artifact in [ModelArtifact.llm,.speech]{modelStatus="Downloading \(artifact.name)…";let download=ModelDownload(artifact:artifact,directory:supportDirectory.appendingPathComponent("Models")){[weak self] progress in Task{@MainActor in self?.modelProgress=progress}};try await download.run()};modelStatus="Both models verified and ready for offline use."}catch{modelStatus=error.localizedDescription};downloading=false}
 }
 func cancelDownload(){downloadWork?.cancel()}
 func importModel(_ artifact:ModelArtifact){guard !downloading else{return};let p=NSOpenPanel();p.canChooseDirectories=false
 if p.runModal() == .OK,let url=p.url{downloading=true;downloadWork=Task{await engine.unload();do{let destination=supportDirectory.appendingPathComponent("Models/"+artifact.filename);let magic=try FileHandle(forReadingFrom:url);let header=try magic.read(upToCount:4);try magic.close()
 guard header==(artifact.filename.hasSuffix("gguf") ? Data("GGUF".utf8):Data([0x6c,0x6d,0x67,0x67])) else{throw VoiceyError.invalid("Incompatible model header.")}
 try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
 let staging=destination.appendingPathExtension("importing");try? FileManager.default.removeItem(at:staging)
 try await Task.detached{try FileManager.default.copyItem(at:url,to:staging)}.value
 if FileManager.default.fileExists(atPath:destination.path){_ = try FileManager.default.replaceItemAt(destination,withItemAt:staging)}else{try FileManager.default.moveItem(at:staging,to:destination)}
 modelStatus="Imported \(url.lastPathComponent). Compatibility will be checked by the native runtime on use."
 }catch{modelStatus=error.localizedDescription};downloading=false}}
 }
 func removeModels(){cancel();Task{await engine.unload();do{try FileManager.default.removeItem(at:supportDirectory.appendingPathComponent("Models"));modelStatus="Models removed."}catch{modelStatus=error.localizedDescription}}}
 func saveMemory(phrase:String,target:String,category:String){do{guard let memory else{throw VoiceyError.unavailable(memoryError ?? "Memory unavailable")};guard !phrase.isEmpty,!target.isEmpty else{throw VoiceyError.invalid("Both memory fields are required.")};try memory.remember(MemoryEntry(phrase:phrase,target:target,category:category));memories=memory.document.entries}catch{memoryError=error.localizedDescription}}
 func removeMemory(_ entry:MemoryEntry){do{try memory?.remove(entry.id);memories=memory?.document.entries ?? []}catch{memoryError=error.localizedDescription}}
}
