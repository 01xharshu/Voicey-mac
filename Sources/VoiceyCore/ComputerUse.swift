import Foundation

public enum VerificationState: String, Codable, Sendable { case success, failure, unknown }
public struct Verification: Codable, Equatable, Sendable {
 public var state: VerificationState
 public var detail: String
 public init(_ state: VerificationState, _ detail: String) { self.state=state; self.detail=detail }
}
public enum ComputerOperation: String, Codable, CaseIterable, Sendable {
 case ensureDirectory, revealDirectory, launchApplication, navigate, inspectPage, fillPrompt, submitPrompt, gmailDraft, runCommand, inspectProject, verifyFile, inspectAlarms, deleteAlarms, inspectInterface, setControlValue, pressControl, runShortcut
}
public struct OperationArguments: Codable, Equatable, Sendable {
 public var label="",role=""
 public var cutoff:Int?
 public var alarmIDs:[String]=[],alarmTimes:[String]=[],fingerprint=""
 public var root="", components:[String]=[], application="", url="", text="", recipient="", subject="", executable="", arguments:[String]=[], output="", shortcut=""
 public init() {}
}
public enum StepStatus: String, Codable, Sendable { case pending, observing, executing, verified, failed, unknown, waiting, cancelled }
public struct ComputerStep: Codable, Identifiable, Sendable {
 public var id: UUID
 public var operation: ComputerOperation
 public var arguments: OperationArguments
 public var dependencies: [UUID]
 public var title: String
 public var precondition: String
 public var expectedResult: String
 public var verificationMethod: String
 public var status: StepStatus = .pending
 public var evidence: Verification?
 public var attempts=0
 public init(_ operation: ComputerOperation, _ arguments: OperationArguments, title: String, after: [UUID]=[]) {
 id=UUID(); self.operation=operation; self.arguments=arguments; dependencies=after; self.title=title
 precondition="All dependencies verified; target and permission revalidated by adapter"
 expectedResult=title; verificationMethod=operation.rawValue+" observation"
 }
}
public struct TaskEvent: Codable, Sendable { public let date: Date; public let step: UUID; public let status: StepStatus; public let detail: String }
public enum ComputerTaskStatus: String, Codable, Sendable { case planned, running, waiting, complete, failed, partiallyVerified, cancelled }
public struct ComputerTask: Codable, Identifiable, Sendable {
 public var id=UUID(), originalRequest: String, intention: String, requiredOutcome: String
 public var steps: [ComputerStep]
 public var unresolvedAmbiguity: String?
 public var approvedDestinations: [String]=[]
 public var status: ComputerTaskStatus = .planned
 public var history: [TaskEvent]=[]
 public var cancelled=false
 public init(request: String, intention: String, steps: [ComputerStep]) { originalRequest=request; self.intention=intention; requiredOutcome=intention; self.steps=steps }
}
public struct ComputerConfiguration: Sendable {
 public var enabled=true, previewExternalPrompts=false
 public var maxSteps=24, retries=2
 public init() {}
}
public struct AdapterDescriptor: Sendable {
 public let name: String, operations: Set<ComputerOperation>, permissions: [String], verification: String, limitations: String
 public let cancellable: Bool
 public init(_ name: String, _ operations: Set<ComputerOperation>, permissions: [String]=[], verification: String, limitations: String="", cancellable: Bool=true) {
 self.name=name; self.operations=operations; self.permissions=permissions; self.verification=verification; self.limitations=limitations; self.cancellable=cancellable
 }
}
public enum AdapterResult: Sendable {
 case verified(Verification)
 case wait(String)
}
public enum AdapterPreparation:Sendable {case ready(ComputerStep),wait(String)}
@MainActor public protocol ComputerAdapter: AnyObject {
 var descriptor: AdapterDescriptor { get }
 func prepare(_ step:ComputerStep) async throws -> AdapterPreparation
 func observe(_ step: ComputerStep) async throws -> Verification
 func execute(_ step: ComputerStep) async throws -> AdapterResult
 func cancel()
 func finish()
}
public extension ComputerAdapter {
 func prepare(_ step:ComputerStep) async throws -> AdapterPreparation{.ready(step)}
 func cancel() {}
 func finish() {} }
public enum ComputerRisk: String, Codable, Sendable { case low, externalSubmission, consequential }
public extension ActionRiskPolicy {
 static func sensitiveExternalText(_ text:String)->Bool {
 ["password","secret","token","medical","account number","credit card","private key","social security","diagnosis","bank account"].contains{text.lowercased().contains($0)} || text.range(of:"(?:sk-[A-Za-z0-9_-]{16,}|[0-9]{12,19})",options:.regularExpression) != nil
 }
 static func risk(_ step: ComputerStep) -> ComputerRisk {
 switch step.operation { case .submitPrompt: return .externalSubmission
 case .runCommand, .runShortcut, .deleteAlarms, .pressControl: return .consequential
 default: return .low }
 }
 static func evaluate(_ step: ComputerStep, request: String, preview: Bool) -> PolicyDecision {
 let a=step.arguments
 if [.fillPrompt,.gmailDraft,.setControlValue].contains(step.operation),sensitiveExternalText(a.text) {
 return .confirm("Prepare this potentially sensitive content on \(a.url)? The website can receive text as soon as it is entered.\nRecipient: \(a.recipient)\n\(a.text)")
 }
 if step.operation == .pressControl {return .confirm("Press ‘\(a.label)’ in \(a.application)? This may change application data or submit content. Expected evidence: \(a.output.isEmpty ? "no declared outcome; result may be unknown":a.output)")}
 if step.operation == .deleteAlarms {
 if a.alarmIDs.isEmpty{return .execute}
 return .confirm("Delete exactly \(a.alarmIDs.count) alarms before the selected cutoff: \(a.alarmTimes.joined(separator:", "))? Other alarms must remain unchanged.")
 }
 if step.operation == .navigate {
 if a.url=="https://chatgpt.com/",ChatGPTGoal.parse(request) != nil{return .execute}
 return .confirm("Open this exact destination in \(a.application): \(a.url)") }
 if step.operation == .submitPrompt {
 let lower=request.lowercased()
 let explicit=ChatGPTGoal.authorizes(request,text:a.text) || lower.contains("ask ") || lower.contains("submit ") || lower.contains("send ")
 let draft=lower.contains("without submitting") || lower.contains("don't submit") || lower.contains("do not submit") || lower.contains("type only")
 if draft { return .reject("The request authorizes preparing text only.") }
 // Conservative local classification; a direct explicit prompt normally proceeds.
 let sensitive=sensitiveExternalText(a.text)
 if preview || !explicit || sensitive || !request.localizedCaseInsensitiveContains(a.text.trimmingCharacters(in:CharacterSet(charactersIn:".?!"))) {
 return .confirm("Submit this exact text to \(a.url)?\n\(a.text)") }
 }
 if step.operation == .runCommand {
 if CommandPolicy.diagnostic(a.executable, a.arguments) { return .execute }
 return .confirm("Run in \(a.root): \(CommandPolicy.display(a.executable,a.arguments))\nProject scripts can modify files or access the network.")
 }
 if step.operation == .runShortcut { return .confirm("Run the user-selected Shortcut ‘\(a.shortcut)’ with input ‘\(a.text)’? Its actions may have external effects.") }
 return .execute
 }
}
public struct PendingComputerQuestion: Sendable {
 public enum Kind: Sendable { case approval, clarification, readiness }
 public let taskID: UUID, stepID: UUID, text: String, expires: Date, kind: Kind
}
public enum ComputerContinuation:Sendable {case steps([ComputerStep]), complete(Verification), wait(String)}
@MainActor public final class ComputerUseAgent {
 public private(set) var task: ComputerTask?
 public private(set) var pending: PendingComputerQuestion?
 public var changed: ((ComputerTask?, PendingComputerQuestion?) -> Void)?
 public var configuration=ComputerConfiguration()
 public var continuation:((ComputerTask) async throws -> ComputerContinuation)?
 private var adapters: [ComputerAdapter]=[]
 private var approved: [UUID:Date]=[:]
 private var runID=UUID()
 private var advancing:UUID?
 public init() {}
 public func register(_ adapter: ComputerAdapter) { adapters.append(adapter) }
 public var capabilities: [AdapterDescriptor] { adapters.map(\.descriptor) }
 public func start(_ plan: ComputerTask) async {
 cancel(); task=plan; approved=[:]; pending=nil; runID=UUID()
 do { try validate(plan) } catch { task?.status = .failed; task?.unresolvedAmbiguity=error.localizedDescription; emit(); return }
 await advance()
 }
 public func replan(_ plan: ComputerTask) async {
 let completed=task?.steps.filter{$0.status == .verified} ?? []
 var revised=plan;revised.history=task?.history ?? []
 for i in revised.steps.indices {
 if let previous=completed.first(where:{$0.operation==revised.steps[i].operation && $0.arguments==revised.steps[i].arguments && [.ensureDirectory,.launchApplication,.revealDirectory].contains($0.operation)}) {
 // Browser effects are always reobserved under a fresh destination approval.
 revised.steps[i].status = .pending;revised.steps[i].evidence=previous.evidence
 }
 }
 await start(revised)
 }
 public func clearFinishedContext(){guard task?.status != .running,task?.status != .waiting else{return};task=nil;pending=nil;approved=[:];emit()}
 public func cancel() {
 runID=UUID(); adapters.forEach{$0.cancel()}; pending=nil; approved=[:]
 if task != nil, [.running,.waiting,.planned].contains(task!.status) {
 task?.cancelled=true; task?.status = .cancelled
 for i in task!.steps.indices where task!.steps[i].status != .verified { task?.steps[i].status = .cancelled }
 }; emit()
 }
 public func reply(_ text: String) async {
 guard let question=pending, let task, question.taskID==task.id, !task.cancelled else { return }
 guard Date()<question.expires else { self.task?.status = .failed; self.task?.unresolvedAmbiguity="The pending request expired. Start the task again."; pending=nil; emit(); return }
 if Dialogue.reply(text) == .cancel { cancel(); return }
 if question.kind == .approval {
 guard Dialogue.reply(text) == .approve else { emit(); return }
 approved[question.stepID]=Date().addingTimeInterval(120)
 }
 pending=nil; await advance()
 }
 public func validate(_ plan: ComputerTask) throws {
 guard configuration.enabled else { throw VoiceyError.unavailable("Computer use is disabled in Settings.") }
 guard !plan.steps.isEmpty, plan.steps.count<=min(64,max(1,configuration.maxSteps)) else { throw VoiceyError.invalid("Task exceeds the configured step budget.") }
 var seen=Set<UUID>()
 for step in plan.steps {
 guard !seen.contains(step.id), step.dependencies.allSatisfy({seen.contains($0)}) else { throw VoiceyError.invalid("Invalid task order or dependency.") }
 seen.insert(step.id)
 let data=try JSONEncoder().encode(step.arguments)
 guard data.count<=32768, !String(decoding:data,as:UTF8.self).contains("\\u0000") else { throw VoiceyError.invalid("Invalid operation arguments.") }
 if [.navigate,.inspectPage,.fillPrompt,.submitPrompt,.gmailDraft].contains(step.operation) {
 let url=try URLValidator.validate(step.arguments.url)
 guard url.scheme=="https",["chatgpt.com","mail.google.com"].contains(url.host),url.port==nil else { throw VoiceyError.invalid("Only approved ChatGPT and Gmail integrations are supported.") }
 if step.operation != .navigate {
 var ancestors=Set<UUID>(),queue=step.dependencies
 while let id=queue.popLast(){if ancestors.insert(id).inserted,let parent=plan.steps.first(where:{$0.id==id}){queue.append(contentsOf:parent.dependencies)}}
 guard plan.steps.contains(where:{ancestors.contains($0.id) && $0.operation == .navigate && $0.arguments.url==step.arguments.url && $0.arguments.application==step.arguments.application}) else {throw VoiceyError.invalid("A browser operation needs a preceding approved navigation.")}
 }
 if step.operation == .gmailDraft, url.host != "mail.google.com" { throw VoiceyError.invalid("Gmail origin required.") }
 if [.fillPrompt,.submitPrompt].contains(step.operation),url.host != "chatgpt.com" { throw VoiceyError.invalid("ChatGPT origin required.") }
 }
 if step.operation == .runCommand { try CommandPolicy.validate(executable:step.arguments.executable, arguments:step.arguments.arguments, original:plan.originalRequest) }
 }
 }
 private func emit() { changed?(task,pending) }
 private func record(_ index: Int, _ status: StepStatus, _ evidence: Verification) {
 guard task != nil else { return }; task!.steps[index].status=status; task!.steps[index].evidence=evidence
 task!.history.append(TaskEvent(date:Date(),step:task!.steps[index].id,status:status,detail:evidence.detail)); emit()
 }
 private func advance() async {
 guard advancing != runID, task != nil, !task!.cancelled else { return }
 let token=runID; advancing=token; defer { if advancing==token {advancing=nil} }
 task!.status = .running; emit()
 var i=0
 while true {
 if i>=task!.steps.count {
 guard token==runID,!Task.isCancelled else{return}
 guard let continuation else{break}
 do {
 let result=try await continuation(task!)
 guard token==runID,!Task.isCancelled else{return}
 switch result {
 case .steps(let additions):
 guard !additions.isEmpty else{throw VoiceyError.invalid("Planner returned no next action.")}
 var proposed=task!;proposed.steps.append(contentsOf:additions);try validate(proposed);task=proposed
 case .complete(let evidence):
 guard evidence.state == .success else{throw VoiceyError.invalid("Task completion needs successful observation evidence.")}
 task!.requiredOutcome=evidence.detail;task!.status = .complete;pending=nil;approved=[:];adapters.forEach{$0.finish()};emit();return
 case .wait(let question):
 guard let last=task!.steps.last else{throw VoiceyError.invalid("No observed task state.")}
 pending=PendingComputerQuestion(taskID:task!.id,stepID:last.id,text:question,expires:Date().addingTimeInterval(600),kind:.clarification);task!.status = .waiting;emit();return
 }
 }catch{guard token==runID else{return};task!.status = .failed;task!.unresolvedAmbiguity=error.localizedDescription;emit();return}
 }
 guard token==runID,!Task.isCancelled,task?.cancelled==false else { return }
 if task!.steps[i].status == .verified {i+=1;continue}
 var step=task!.steps[i]
 guard step.dependencies.allSatisfy({id in task!.steps.contains{$0.id==id && $0.status == .verified}}) else { task!.status = .failed; emit(); return }
 guard let adapter=adapters.first(where:{$0.descriptor.operations.contains(step.operation)}) else { record(i,.failed,Verification(.failure,"No supported adapter for \(step.operation.rawValue).")); task!.status = .failed; emit(); return }
 do {
 switch try await adapter.prepare(step) {
 case .ready(let prepared):
 guard token==runID,!Task.isCancelled else{return}
 if prepared.arguments != step.arguments{approved.removeValue(forKey:step.id)}
 step=prepared;task!.steps[i]=prepared
 case .wait(let question):
 guard token==runID else{return}
 pending=PendingComputerQuestion(taskID:task!.id,stepID:step.id,text:question,expires:Date().addingTimeInterval(600),kind:.readiness);task!.status = .waiting;record(i,.waiting,Verification(.unknown,question));return
 }
 } catch {guard token==runID else{return};record(i,.failed,Verification(.failure,error.localizedDescription));task!.status = .failed;emit();return}
 // Authorization precedes observation: observing a page itself accesses private data.
 let decision=ActionRiskPolicy.evaluate(step,request:task!.originalRequest,preview:configuration.previewExternalPrompts)
 switch decision {
 case .reject(let reason): record(i,.failed,Verification(.failure,reason)); task!.status = .failed; emit(); return
 case .confirm(let details),.clarify(let details):
 if approved[step.id].map({$0>Date()}) != true { pending=PendingComputerQuestion(taskID:task!.id,stepID:step.id,text:details,expires:Date().addingTimeInterval(120),kind:.approval); task!.status = .waiting; record(i,.waiting,Verification(.unknown,details)); return }
 default: break
 }
 let repeatable:Bool = [.ensureDirectory,.revealDirectory,.launchApplication,.navigate,.inspectPage,.fillPrompt,.inspectProject,.verifyFile,.inspectAlarms,.inspectInterface,.setControlValue].contains(step.operation)
 let limit=repeatable ? min(3,max(0,configuration.retries))+1:1
 var succeeded=false
 for _ in 0..<limit {
 guard token==runID,!Task.isCancelled else { return }
 do {
 record(i,.observing,Verification(.unknown,"Inspecting current state"))
 let before=try await adapter.observe(step)
 guard token==runID,!Task.isCancelled else { return }
 if before.state == .success { record(i,.verified,before); succeeded=true; break }
 task!.steps[i].attempts+=1; record(i,.executing,before)
 let result=try await adapter.execute(step)
 guard token==runID,!Task.isCancelled else { return }
 switch result {
 case .wait(let reason): pending=PendingComputerQuestion(taskID:task!.id,stepID:step.id,text:reason,expires:Date().addingTimeInterval(600),kind:.readiness); task!.status = .waiting; record(i,.waiting,Verification(.unknown,reason)); return
 case .verified(let initial):
 let after=initial.state == .failure ? initial:try await adapter.observe(step)
 guard token==runID,!Task.isCancelled else { return }
 if after.state == .success { record(i,.verified,after); succeeded=true }
 else { record(i,after.state == .failure ? .failed:.unknown,after) }
 }
 if succeeded { break }
 } catch is CancellationError { return }
 catch { guard token==runID else { return }; record(i,.failed,Verification(.failure,error.localizedDescription)) }
 }
 guard succeeded else { task!.status=task!.steps[i].status == .unknown ? .partiallyVerified:.failed; approved.removeValue(forKey:step.id); emit(); return }
 if step.operation == .navigate { task!.approvedDestinations.append(step.arguments.url) }
 i+=1
 }
 task!.status = .complete; pending=nil; approved=[:]; adapters.forEach{$0.finish()}; emit()
 }
}

public enum CommandPolicy {
 public static func display(_ exe: String, _ args: [String]) -> String { ([exe]+args).map{ $0.contains(" ") ? "'"+$0.replacingOccurrences(of:"'",with:"'\\''")+"'":$0 }.joined(separator:" ") }
 public static func diagnostic(_ exe: String,_ args: [String]) -> Bool {
 if exe == "/bin/pwd" { return args.isEmpty }
 if exe == "/usr/bin/git" { return args == ["status","--short"] || args == ["status"] }
 return false
 }
 public static func validate(executable: String, arguments: [String], original: String) throws {
 let allowed=["/bin/pwd","/usr/bin/git","/usr/bin/make","/usr/bin/python3","/usr/bin/env","/bin/echo","/usr/bin/swift"]
 guard allowed.contains(executable),arguments.count<40,!arguments.contains(where:{$0.contains("\0") || $0.count>4096}) else { throw VoiceyError.invalid("Command executable or arguments are unsupported.") }
 // Commands must be copied from user-authored backticks, never invented by the model.
 let quoted=original.components(separatedBy:"`")
 let expected = executable == "/usr/bin/env" ? arguments : [URL(fileURLWithPath:executable).lastPathComponent]+arguments
 let explicit=quoted.enumerated().contains{index,text in index%2==1 && ((try? tokenize(text)) == expected || (try? tokenize(text)) == [executable]+arguments)}
 guard explicit else { throw VoiceyError.invalid("Provide the exact command in backticks. Voicey does not execute model-generated commands.") }
 if executable == "/usr/bin/env" {
 guard arguments == ["npm","run","dev"] || arguments == ["npm","test"] || arguments == ["npm","run","build"] else { throw VoiceyError.invalid("Only npm run dev, npm test, and npm run build are supported through env.") }
 }
 }
 public static func tokenize(_ text: String) throws -> [String] {
 var parts:[String]=[],part="",quote:Character?,escaped=false
 for c in text {
 if escaped { part.append(c); escaped=false; continue }
 if c == "\\" { escaped=true; continue }
 if let q=quote { if c==q {quote=nil}else{part.append(c)}; continue }
 if c=="'" || c=="\"" { quote=c; continue }
 if c.isWhitespace { if !part.isEmpty {parts.append(part);part=""};continue }
 guard !";&|><`$\n\r".contains(c) else { throw VoiceyError.invalid("Shell expansion, pipelines, and redirection are unsupported. Use a single executable and arguments.") }
 part.append(c)
 }
 guard quote==nil,!escaped else {throw VoiceyError.invalid("Unclosed command quoting.")}
 if !part.isEmpty {parts.append(part)}
 guard !parts.isEmpty else {throw VoiceyError.invalid("Missing command.")};return parts
 }
}
