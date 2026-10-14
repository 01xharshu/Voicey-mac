import Foundation
public struct ToolDefinition:Sendable {
 public let kind:IntentKind
 public let required:[String]
 public let output:String
}
public struct ToolRegistry:Sendable {
 public let definitions:[IntentKind:ToolDefinition]
 public init(){
 var definitions:[IntentKind:ToolDefinition]=[:]
 for kind in [IntentKind.launchApp,.search,.openItem,.reveal,.website,.clipboard,.createFolder,.settings,.remember,.capabilities]{definitions[kind]=ToolDefinition(kind:kind,required:[.settings,.capabilities].contains(kind) ? []:["query"],output:"native execution result or actionable error")}
 self.definitions=definitions
 }
 public func validate(_ intent:Intent)throws {
 guard let definition=definitions[intent.kind] else{throw VoiceyError.invalid("This tool is unavailable. Shell execution and deletion are not enabled.")}
 for value in [intent.query,intent.destination,intent.browser,intent.explanation]{guard value.count<=8192,!value.contains("\0") else{throw VoiceyError.invalid("Invalid tool arguments.")}}
 if definition.required.contains("query") && intent.query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty{throw VoiceyError.invalid("A search name, destination or text is required.")}
 }
}
// A one-use approval bound to a complete URL, cleared on cancellation or a new request.
public struct WebsiteAuthorization:Sendable {
 private var proposed:URL?,approved:URL?,expires:Date?
 public init(){}
 public mutating func propose(_ raw:String,now:Date=Date()) throws -> URL {
 clear();let url=try URLValidator.validate(raw);proposed=url;expires=now.addingTimeInterval(120);return url
 }
 public mutating func approve(now:Date=Date())throws->URL {
 guard let url=proposed,let expires,now<expires else{clear();throw VoiceyError.invalid("Website confirmation expired. Please request the website again.")}
 proposed=nil;approved=url;return url
 }
 public mutating func consume(_ url:URL,now:Date=Date())throws {
 guard approved==url,let expires,now<expires else{clear();throw VoiceyError.invalid("Approve this website's complete URL before opening it.")};clear()
 }
 public mutating func clear(){proposed=nil;approved=nil;expires=nil}
}
public struct AvailableBrowser:Equatable,Sendable {
 public let id:String,name:String
 public init(id:String,name:String){self.id=id;self.name=name}
}
public enum BrowserResolution:Equatable {case selected(String),choose(explicitUnavailable:Bool),none}
public struct BrowserPolicy {
 public static func resolve(installed:[AvailableBrowser],explicit:String,saved:String?)->BrowserResolution {
 guard !installed.isEmpty else{return .none}
 let requested=explicit.isEmpty ? saved:explicit
 if let requested,!requested.isEmpty {
 if let match=installed.first(where:{$0.id==requested || $0.name.caseInsensitiveCompare(requested) == .orderedSame || ($0.name=="Google Chrome" && requested.lowercased()=="chrome") || ($0.name=="Microsoft Edge" && requested.lowercased()=="edge")}){return .selected(match.id)}
 return .choose(explicitUnavailable:true)
 }
 return .choose(explicitUnavailable:false)
 }
}
