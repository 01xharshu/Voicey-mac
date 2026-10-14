import Foundation
public enum BrowserOperation:String,Codable,Sendable {case inspect,navigate,fillPrompt,submitPrompt,gmailDraft,cancel}
public struct BrowserCommand:Codable,Sendable {
 public var version=1,id=UUID().uuidString,operation:BrowserOperation,url:String,text="",recipient="",subject=""
 public init(_ operation:BrowserOperation,url:String){self.operation=operation;self.url=url}
 public func validate()throws {
 guard version==1,UUID(uuidString:id) != nil,text.count<=16000,subject.count<=500,recipient.count<=254 else{throw VoiceyError.invalid("Invalid browser command schema")}
 let target=try URLValidator.validate(url)
 guard target.scheme=="https",target.port==nil,["chatgpt.com","mail.google.com"].contains(target.host) else{throw VoiceyError.invalid("Unauthorized browser origin")}
 if [.fillPrompt,.submitPrompt].contains(operation),target.host != "chatgpt.com"{throw VoiceyError.invalid("Wrong prompt origin")}
 if operation == .gmailDraft {guard target.host=="mail.google.com",WorkflowPlanner.validEmail(recipient),!text.isEmpty else{throw VoiceyError.invalid("Invalid Gmail draft arguments")}}
 }
}
public struct BrowserReply:Codable,Sendable {
 public var version:Int,id:String,ok:Bool,url:String,state:String,detail:String
 public var prompt:String?,submitted:Bool?,draftSaved:Bool?,recipient:String?,body:String?
 public init(id:String,ok:Bool,url:String,state:String,detail:String){version=1;self.id=id;self.ok=ok;self.url=url;self.state=state;self.detail=detail}
 public func validate(for command:BrowserCommand)throws {
 guard version==1,id==command.id,detail.count<=4096,let expected=URL(string:command.url),let actual=URL(string:url),actual.scheme=="https",actual.host==expected.host,actual.port==nil else{throw VoiceyError.invalid("Browser returned a mismatched request or destination")}
 }
}
public struct BrowserEnvelope:Codable {public let token:String;public let command:BrowserCommand;public init(token:String,command:BrowserCommand){self.token=token;self.command=command}}
