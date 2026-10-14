import Foundation

public enum WorkflowKind: String, Codable, Sendable { case folders, chatGPT, gmailDraft, command, projectStatus, alarms, shortcut, interface }
public struct WorkflowRequest: Codable, Sendable {
 public var kind: WorkflowKind
 public var root="", folders:[String]=[], browser="", text="", recipient="", subject="", command="", output="", application="", shortcut=""
 public var label="",action="",expected=""
 public var cutoff:Int?
 public var submit=false
 public init(_ kind: WorkflowKind) { self.kind=kind }
}
public enum WorkflowPlanner {
 private static func captures(_ pattern: String, _ text: String) -> [String]? {
 guard let re=try? NSRegularExpression(pattern:pattern,options:[.caseInsensitive]), let m=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else{return nil}
 return (1..<m.numberOfRanges).map{Range(m.range(at:$0),in:text).map{String(text[$0])} ?? ""}
 }
 public static func parse(_ raw: String) -> WorkflowRequest? {
 if let goal=ChatGPTGoal.parse(raw){return goal}
 let l=raw.lowercased()
 if let r=captures("(?:click|press) \"([^\"]+)\" in (.+?)(?: and verify \"([^\"]+)\")?$",raw){var w=WorkflowRequest(.interface);w.action="press";w.label=r[0];w.application=r[1];w.expected=r[2];return w}
 if let r=captures("inspect (?:the )?(?:interface|windows) (?:of|in) (.+)$",raw){var w=WorkflowRequest(.interface);w.action="inspect";w.application=r[0];return w}
 if l.contains("chatgpt"),let c=captures("(?:ask (?:it |chatgpt )?|(?:type|submit) (?:the question )?)(.+?)[.!]?$",raw) {
 var w=WorkflowRequest(.chatGPT);w.text=c[0];w.submit=l.contains("ask ") || l.contains("submit ")
 if l.contains("without submitting") || l.contains("don't submit") || l.contains("do not submit") {w.submit=false;w.text=w.text.replacingOccurrences(of:" without submitting",with:"")}
 if let b=captures("(?:in (?:my )?|open |use )(Arc|Safari|Chrome|Brave|Edge|Firefox)(?: browser)?",raw){w.browser=b[0]}
 return w
 }
 if l.contains("gmail"),l.contains("draft") {
 var w=WorkflowRequest(.gmailDraft)
 if let r=captures("(?:email |message )?to (.+?)(?:,| saying | with | and |$)",raw){w.recipient=r[0]}
 if let r=captures("(?:saying|body:)\\s*[\"‘]?(.+?)[\"’]?$",raw){w.text=r[0]}
 if let b=captures("(?:in |use )(Arc|Safari|Chrome|Brave|Edge|Firefox)",raw){w.browser=b[0]}
 return w
 }
 if l.contains("alarm") {var w=WorkflowRequest(.alarms);w.text=raw;return w}
 if l.contains("shortcut"),let r=captures("(?:run|invoke) (?:the )?shortcut (?:called )?[\"‘]?(.+?)[\"’]?$",raw){var w=WorkflowRequest(.shortcut);w.shortcut=r[0];return w}
 if l.contains("run ") || l.contains("execute "),let c=captures("`([^`]+)`",raw){
 var w=WorkflowRequest(.command);w.command=c[0];w.application=l.contains("terminal") ? "Terminal":""
 if let r=captures(" in (?:my )?(.+?)(?: project|,| and |$)",raw){w.root=r[0]}
 if let r=captures("(?:whether|if|that) `([^`]+)` (?:was |is )?(?:created|exists)",raw){w.output=r[0]}
 return w
 }
 if l.contains("project"),(l.contains("running") || l.contains("stopped")) {
 var w=WorkflowRequest(.projectStatus)
 if let r=captures("(?:my |the |in )([^,]+?) project",raw){w.root=r[0]}
 w.application=l.contains("codex") ? "Codex":"";return w
 }
 if l.contains("folder") || l.contains("finder") {
 let pattern="(?:create|make) (?:a |new |a new )?(?:folder|directory)(?: (?:named|called))? [\"‘]?([\\w.-]+)[\"’]?"
 if let re=try? NSRegularExpression(pattern:pattern,options:.caseInsensitive) {
 let matches=re.matches(in:raw,range:NSRange(raw.startIndex...,in:raw))
 var names=matches.compactMap{Range($0.range(at:1),in:raw).map{String(raw[$0])}}.map{$0.hasSuffix(".") ? String($0.dropLast()):$0}
 // ‘check if ICICI exists ... create it ... folder called Repo’
 if let r=captures("check (?:if|whether) ([\\w.-]+) exists",raw),names.first != r[0]{names.insert(r[0],at:0)}
 if names.isEmpty,let r=captures("create (?:an? )?([\\w.-]+) folder",raw){names=r}
 if !names.isEmpty {
 var w=WorkflowRequest(.folders);w.folders=names;w.application=l.contains("finder") ? "Finder":""
 if let root=captures("(?:in|inside|go to) (?:my )?(Documents|Desktop|Downloads)",raw){w.root=root[0]}
 else if let root=captures("(?:in|inside) (`[^`]+`|/[^,]+?)(?:,| and |$)",raw){w.root=root[0].trimmingCharacters(in:CharacterSet(charactersIn:"`"))}
 return w
 }
 }
 }
 return nil
 }
 public static func plan(_ w: WorkflowRequest, original: String) throws -> ComputerTask {
 var steps:[ComputerStep]=[]
 func append(_ op:ComputerOperation,_ a:OperationArguments,_ title:String){steps.append(ComputerStep(op,a,title:title,after:steps.last.map{[$0.id]} ?? []))}
 var a=OperationArguments();a.root=w.root;a.application=w.application;a.text=w.text
 switch w.kind {
 case .folders:
 guard !w.root.isEmpty,!w.folders.isEmpty else{throw VoiceyError.invalid("Which parent folder should contain these folders?")}
 for name in w.folders {
 guard !name.isEmpty,name != ".",name != "..",!name.contains("/"),!name.contains(":"),!name.contains("\0") else{throw VoiceyError.invalid("Invalid folder name.")}
 a.components.append(name);append(.ensureDirectory,a,"Ensure \(name) exists")
 }
 if w.application == "Finder" {append(.revealDirectory,a,"Open the final folder in Finder")}
 case .chatGPT,.gmailDraft:
 guard !w.browser.isEmpty else{throw VoiceyError.invalid("Which installed browser should I use?")}
 a.application=w.browser;a.url=w.kind == .chatGPT ? "https://chatgpt.com/":"https://mail.google.com/"
 a.recipient=w.recipient;a.subject=w.subject
 append(.launchApplication,a,"Open \(w.browser)");append(.navigate,a,"Open \(a.url)");append(.inspectPage,a,"Wait for the authenticated interface")
 guard !w.text.isEmpty else{throw VoiceyError.invalid("What exact text should I prepare?")}
 if w.kind == .gmailDraft {
 guard validEmail(w.recipient) else{throw VoiceyError.invalid("What is the recipient's email address? I won't invent an address for \(w.recipient).")}
 append(.gmailDraft,a,"Create and verify an unsent Gmail draft")
 } else {
 append(.fillPrompt,a,"Prepare the exact question")
 if w.submit {append(.submitPrompt,a,"Submit and verify the question")}
 }
 case .command:
 guard !w.root.isEmpty else{throw VoiceyError.invalid("Which authorized project folder should run the command?")}
 var parts=try CommandPolicy.tokenize(w.command);let executable=parts.removeFirst()
 let map=["pwd":"/bin/pwd","git":"/usr/bin/git","make":"/usr/bin/make","python3":"/usr/bin/python3","echo":"/bin/echo","swift":"/usr/bin/swift"]
 if executable=="npm"{a.executable="/usr/bin/env";a.arguments=["npm"]+parts}else{a.executable=map[executable] ?? executable;a.arguments=parts}
 try CommandPolicy.validate(executable:a.executable,arguments:a.arguments,original:original)
 append(.runCommand,a,"Run the exact requested command")
 if !w.output.isEmpty {a.output=w.output;append(.verifyFile,a,"Verify \(w.output)")}
 if parts == ["run","dev"] {append(.inspectProject,a,"Inspect the development process")}
 case .projectStatus:
 guard !w.root.isEmpty else{throw VoiceyError.invalid("Which project folder should I inspect?")}
 if !w.application.isEmpty {append(.launchApplication,a,"Open \(w.application)")}
 append(.inspectProject,a,"Inspect actual project process and listener evidence")
 case .alarms:
 a.application=w.application;a.cutoff=w.cutoff
 append(.launchApplication,a,"Open the selected alarm app")
 append(.inspectAlarms,a,"Inspect the supported alarm list")
 append(.deleteAlarms,a,"Remove only the approved matching alarms")
 case .interface:
 guard !w.application.isEmpty,["inspect","fill","press"].contains(w.action) else{throw VoiceyError.invalid("Name the application and a supported inspect, fill, or press action.")}
 a.label=w.label;a.text=w.text;a.output=w.expected
 append(.launchApplication,a,"Open \(w.application)")
 if w.action=="inspect"{append(.inspectInterface,a,"Inspect the application's current windows and controls")}
 else {
 guard !w.label.isEmpty,original.localizedCaseInsensitiveContains(w.label) else{throw VoiceyError.invalid("Name the exact control to interact with.")}
 append(w.action=="fill" ? .setControlValue:.pressControl,a,"\(w.action) \(w.label) in \(w.application)")
 }
 case .shortcut:
 guard !w.shortcut.isEmpty else{throw VoiceyError.invalid("Which Shortcut should I run?")};a.shortcut=w.shortcut;append(.runShortcut,a,"Run and verify the selected Shortcut")
 }
 return ComputerTask(request:original,intention:steps.last?.title ?? original,steps:steps)
 }
 public static func validEmail(_ value:String)->Bool {value.range(of:"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)+$",options:.regularExpression) != nil && value.count<=254}
}
