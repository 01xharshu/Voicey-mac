import Foundation

public enum IntentKind: String, Codable, CaseIterable, Sendable {
 case launchApp, search, openItem, reveal, website, clipboard, createFolder, settings, remember, capabilities, computerUse, unsupported, delete, shell
}
public struct Intent: Codable, Equatable, Sendable {
 public var kind: IntentKind
 public var query: String
 public var destination: String
 public var browser: String
 public var explanation: String
 public init(_ kind: IntentKind, query: String = "", destination: String = "", browser: String = "", explanation: String = "") {
 self.kind=kind;self.query=query;self.destination=destination;self.browser=browser;self.explanation=explanation
 }
}
public enum VoiceyError: Error, LocalizedError, Equatable {
 case invalid(String), unavailable(String), cancelled
 public var errorDescription: String? {switch self {case .invalid(let s),.unavailable(let s):return s;case .cancelled:return "Cancelled."}}
}
public enum PolicyDecision: Equatable {case execute, clarify(String), confirm(String), reject(String)}
public struct ActionRiskPolicy {
 public static func evaluate(_ intent: Intent, ambiguous: Bool = false) -> PolicyDecision {
 if [.delete,.shell].contains(intent.kind) {return .reject("This version cannot delete files or execute scripts.")}
 if intent.kind == .unsupported{return .reject("I can open apps, find and open files, visit confirmed websites, copy text, create folders, and remember aliases.")}
 if ambiguous{return .clarify("Which one did you mean?")}
 if intent.kind == .website {do {return .confirm(try URLValidator.validate(intent.query).absoluteString)}catch{return .clarify("What website domain did you mean?")}}
 if intent.kind == .createFolder && intent.destination.isEmpty{return .clarify("Where should I create the folder?")}
 return .execute
 }
}
public struct URLValidator {
 public static let known = ["youtube":"https://www.youtube.com/", "google":"https://www.google.com/", "github":"https://github.com/", "notion":"https://www.notion.so/", "figma":"https://www.figma.com/", "wikipedia":"https://www.wikipedia.org/", "chatgpt":"https://chatgpt.com/", "gmail":"https://mail.google.com/"]
 public static func validate(_ raw: String) throws -> URL {
 let text=raw.trimmingCharacters(in:.whitespacesAndNewlines)
 let mapped=known[text.lowercased()] ?? text
 let normalized=mapped.contains(":") ? mapped : "https://"+mapped
 guard !mapped.contains(where: {$0.isWhitespace}), !mapped.contains("\\"),
 let c=URLComponents(string:normalized),let scheme=c.scheme?.lowercased(),["https","http"].contains(scheme),
 let host=c.host,host.contains("."),!host.hasPrefix("."),!host.hasSuffix("."),
 host.split(separator:".",omittingEmptySubsequences:false).allSatisfy({ !$0.isEmpty && !$0.hasPrefix("-") && !$0.hasSuffix("-") && $0.allSatisfy({$0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")}) }),
 c.user == nil,c.password == nil,let url=c.url else {throw VoiceyError.invalid("Use a complete HTTP or HTTPS website address.")}
 return url
 }
}
public struct CommandChord: Sendable {
 public private(set) var left=false, right=false
 private var latched=false
 public init(){}
 // Device-independent physical state supplied by CGEventSource, rather than inferring from aggregate flags.
 public mutating func update(left: Bool, right: Bool) -> Bool {
 self.left=left;self.right=right
 if !left || !right {latched=false;return false}
 if latched{return false};latched=true;return true
 }
 public mutating func reset(){left=false;right=false;latched=false}
}
public enum DialogueReply: Equatable {case approve, cancel, other, choice(String), newRequest(String)}
public struct Dialogue {
 public static func reply(_ text: String) -> DialogueReply {
 let t=text.lowercased().trimmingCharacters(in:.whitespacesAndNewlines).trimmingCharacters(in:CharacterSet(charactersIn:".!?"))
 if ["yes","correct","yes open it","open it","okay","ok","go ahead","continue","resume"].contains(t){return .approve}
 if ["no","cancel","cancel that","stop","never mind","stop. don't continue","don't continue","do not continue"].contains(t){return .cancel}
 if ["the other one","no the other one","i meant the other one","the other folder","no, the other one"].contains(t){return .other}
 if ["open ","find ","launch ","create ","copy ","show "].contains(where:t.hasPrefix){return .newRequest(text)}
 return .choice(text)
 }
}
public struct IntentParser {
 public init(){}
 public func parse(_ text: String) -> Intent? {
 let t=text.trimmingCharacters(in:.whitespacesAndNewlines),l=t.lowercased()
 if l == "cancel" || l == "cancel that" {return nil}
 if l.contains(" and ") && (l.contains("create a new page") || l.contains("create a note") || l.contains("send a message") || l.contains("write a note")){return Intent(.unsupported,explanation:"Editing content inside another app is not supported yet.")}
 if l.contains("capabilities") || l == "what can you do" {return Intent(.capabilities)}
 if l.hasPrefix("copy ") {return Intent(.clipboard,query:String(t.dropFirst(5)))}
 if l.hasPrefix("create a folder called ") || l.hasPrefix("create folder ") {
 let prefix=l.hasPrefix("create a folder called ") ? 23:14
 let rest=String(t.dropFirst(prefix))
 for separator in [" inside "," in "] {if let r=rest.range(of:separator,options:.caseInsensitive){return Intent(.createFolder,query:String(rest[..<r.lowerBound]),destination:String(rest[r.upperBound...]))}}
 return Intent(.createFolder,query:rest)
 }
 if l.hasPrefix("remember "),let range=t.range(of:" as ",options:.caseInsensitive){return Intent(.remember,query:String(t[t.index(t.startIndex,offsetBy:9)..<range.lowerBound]),destination:String(t[range.upperBound...]))}
 if l.hasPrefix("open settings"){return Intent(.settings)}
 if l.hasPrefix("delete ") || l.hasPrefix("remove file "){return Intent(.delete,query:t)}
 if l.hasPrefix("run ") || l.hasPrefix("execute "){return Intent(.shell,query:t)}
 for prefix in ["open ","launch ","find ","show ","reveal "] where l.hasPrefix(prefix) {
 var query=String(t.dropFirst(prefix.count)),browser=""
 if let r=query.range(of:" in ",options:.backwards),["safari","arc","chrome","firefox","brave","edge"].contains(String(query[r.upperBound...]).lowercased()){browser=String(query[r.upperBound...]);query=String(query[..<r.lowerBound])}
 if query.hasSuffix("."){query=String(query.dropLast())}
 if query.lowercased().hasSuffix(" app"){query=String(query.dropLast(4));return Intent(.launchApp,query:query)}
 if prefix != "launch " && ((URLValidator.known[query.lowercased()] != nil && !["figma","notion"].contains(query.lowercased())) || query.contains(".") && (query.contains("://") || !query.contains(" ") && !["blend","pdf","txt","docx","png","jpg"].contains((query as NSString).pathExtension.lowercased()))) {return Intent(.website,query:query,browser:browser)}
 if query.lowercased().contains(" dot "){query=query.replacingOccurrences(of:" dot ",with:".",options:.caseInsensitive);return Intent(.website,query:query,browser:browser)}
 if query.lowercased().hasSuffix(" in finder"){return Intent(.reveal,query:String(query.dropLast(10)))}
 if prefix == "reveal " || prefix == "show " {return Intent(.reveal,query:query)}
 if prefix == "find " {return Intent(.search,query:query)}
 if prefix == "launch " {return Intent(.launchApp,query:query)}
 return Intent(.openItem,query:query,browser:browser)
 }
 return nil
 }
}

public struct ModifierChord:Sendable {
 private var latched=false
 public init(){}
 public mutating func update(control:Bool,option:Bool,command:Bool)->Bool {
 guard control && option && command else{latched=false;return false}
 guard !latched else{return false};latched=true;return true
 }
 public mutating func reset(){latched=false}
}

public enum ActivationGesture:String,Codable,Sendable {case tripleModifiers,dualCommand}
public struct ActivationChord:Sendable {
 public let gesture:ActivationGesture
 private var modifiers=ModifierChord(),commands=CommandChord()
 public init(gesture:ActivationGesture = .tripleModifiers){self.gesture=gesture}
 public mutating func update(control:Bool,option:Bool,command:Bool,leftCommand:Bool=false,rightCommand:Bool=false)->Bool {
 switch gesture {
 case .tripleModifiers:return modifiers.update(control:control,option:option,command:command)
 case .dualCommand:return commands.update(left:leftCommand,right:rightCommand)
 }
 }
 public mutating func reset(){modifiers.reset();commands.reset()}
}
