import Foundation

public struct Conversation: Codable, Equatable, Identifiable, Sendable {
 public let id:String
 public let name:String
 public var detail:String = ""
 public var isGroup:Bool = false
 public init(id:String,name:String,detail:String="",isGroup:Bool=false){self.id=id;self.name=name;self.detail=detail;self.isGroup=isGroup}
}
public enum ContactResolution:Equatable {case found(Conversation), ambiguous([Conversation]), missing}
public enum ContactResolver {
 public static func resolve(_ name:String,in chats:[Conversation])->ContactResolution {
 let matches=chats.filter{$0.name.compare(name.trimmingCharacters(in:.whitespacesAndNewlines),options:[.caseInsensitive,.diacriticInsensitive]) == .orderedSame}
 if matches.count==1{return .found(matches[0])};return matches.isEmpty ? .missing:.ambiguous(matches)
 }
}
public struct ChatMessage:Codable,Equatable,Sendable {
 public enum Direction:String,Codable,Sendable {case incoming,outgoing,unknown}
 public let id:String?
 public let conversationID:String
 public let text:String?
 public let date:Date?
 public let direction:Direction
 public let unread:Bool?
 public init(id:String?=nil,conversationID:String,text:String?,date:Date?,direction:Direction,unread:Bool?=nil){self.id=id;self.conversationID=conversationID;self.text=text;self.date=date;self.direction=direction;self.unread=unread}
}
public struct ChatSnapshot:Sendable {
 public let conversation:Conversation
 public let messages:[ChatMessage]
 public let verifiedInterval:DateInterval?
 public init(conversation:Conversation,messages:[ChatMessage],verifiedInterval:DateInterval?=nil){self.conversation=conversation;self.messages=messages;self.verifiedInterval=verifiedInterval}
}
public enum CountScope {case unread, visible, interval(DateInterval)}
public struct MessageCount:Equatable {public let count:Int;public let exact:Bool;public let limitation:String}
public enum MessageCounter {
 public static func count(_ snapshot:ChatSnapshot,scope:CountScope)->MessageCount {
 var seen=Set<String>();var uncertain=false
 let incoming=snapshot.messages.filter {m in
 guard m.conversationID==snapshot.conversation.id else{return false}
 if m.direction == .unknown{uncertain=true};guard m.direction == .incoming else{return false}
 // Only stable provider IDs justify collapsing identical messages. Repeated text can be real.
 if let id=m.id {return seen.insert(id).inserted};uncertain=true;return true
 }
 var exact=false
 let selected=incoming.filter{m in switch scope {
 case .visible:return true
 case .unread:if m.unread == nil{uncertain=true};return m.unread == true
 case .interval(let interval):guard let date=m.date else{uncertain=true;return false};return date>=interval.start && date<interval.end
 }}
 switch scope {case .visible:exact = !uncertain
 case .unread:exact=false
 case .interval(let interval):exact = !uncertain && snapshot.verifiedInterval.map{$0.start<=interval.start && $0.end>=interval.end} == true}
 return MessageCount(count:selected.count,exact:exact,limitation:exact ? "Verified requested records.":"Available records only; missing history, timestamps, direction or stable identifiers can prevent an exact total.")
 }
 public static func today(now:Date,calendar:Calendar = .current)->DateInterval {let start=calendar.startOfDay(for:now);return DateInterval(start:start,end:calendar.date(byAdding:.day,value:1,to:start)!)}
}
public enum ReplyMode:Sendable {case exact,draft,contextual}
public struct ReplyProposal:Equatable,Sendable {
 public let conversationID:String;public let text:String;public let mode:ReplyMode;public let sensitive:Bool
 public init(conversationID:String,text:String,mode:ReplyMode,sensitive:Bool=false){self.conversationID=conversationID;self.text=text;self.mode=mode;self.sensitive=sensitive}
}
public enum MessagingPolicy {
 public static func evaluate(_ reply:ReplyProposal,verifiedConversation:String?,explicitSend:Bool,reviewed:Bool=false)->PolicyDecision {
 guard !reply.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return .clarify("What should the message say?")}
 guard verifiedConversation==reply.conversationID else{return .clarify("Verify the intended conversation first.")}
 if reply.mode == .draft{return .execute}
 if reply.sensitive && !reviewed{return .confirm(reply.text)}
 if reply.mode == .contextual && !reviewed{return .confirm(reply.text)}
 return explicitSend || reviewed ? .execute:.clarify("Send this message or save a draft?")
 }
 public static func verifiedSubmission(_ proposal:ReplyProposal,in snapshot:ChatSnapshot,after:Date)->Bool {
 snapshot.conversation.id==proposal.conversationID && snapshot.messages.contains{$0.conversationID==proposal.conversationID && $0.direction == .outgoing && $0.text==proposal.text && ($0.date.map{$0>=after} ?? false)}
 }
}
@MainActor public protocol MessagingAdapter {
 var limitation:String {get}
 func conversations() async throws->[Conversation]
 func open(_ conversation:Conversation) async throws
 func inspect(_ conversation:Conversation) async throws->ChatSnapshot
 func compose(_ reply:ReplyProposal) async throws
 func send(_ reply:ReplyProposal) async throws->ChatSnapshot
}
public struct ReplyWatch:Codable,Equatable,Identifiable,Sendable {
 public enum Status:String,Codable,Sendable {case waiting,paused,triggered,cancelled,timedOut}
 public let id:UUID;public let conversation:Conversation;public let created:Date;public let expires:Date
 public let referenceDate:Date?;public var status:Status;public var speak:Bool;public var preview:Bool
 public var seenIDs:Set<String>;public var gap:String?
 public init(conversation:Conversation,created:Date=Date(),expires:Date,referenceDate:Date?=nil,speak:Bool=false,preview:Bool=false){id=UUID();self.conversation=conversation;self.created=created;self.expires=expires;self.referenceDate=referenceDate;status = .waiting;self.speak=speak;self.preview=preview;seenIDs=[]}
 public mutating func observe(_ message:ChatMessage,now:Date)->Bool {
 guard status == .waiting,now<expires,message.conversationID==conversation.id,message.direction == .incoming,let date=message.date,date>max(created,referenceDate ?? created),let id=message.id,!seenIDs.contains(id) else{return false}
 seenIDs.insert(id);status = .triggered;return true
 }
 public mutating func timeout(now:Date)->Bool {guard [.waiting,.paused].contains(status),now>=expires else{return false};status = .timedOut;return true}
}
public final class CommunicationStore {
 public private(set) var watches:[ReplyWatch]
 private let url:URL
 public init(url:URL)throws {self.url=url;if FileManager.default.fileExists(atPath:url.path){watches=try JSONDecoder().decode([ReplyWatch].self,from:Data(contentsOf:url))}else{watches=[]}}
 public func update(_ watches:[ReplyWatch])throws {let data=try JSONEncoder().encode(watches);try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try data.write(to:url,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path);self.watches=watches}
 public func cancelAll()throws {var values=watches;for i in values.indices where [.waiting,.paused].contains(values[i].status){values[i].status = .cancelled};try update(values)}
 public func clear()throws {try update([])}
}

public struct CommunicationAlert:Equatable,Sendable {
 public let id:String;public let title:String;public let body:String;public let conversationID:String;public let speak:Bool
}
public enum WatchProcessor {
 // Persist returned watch states before publishing alerts. No transcripts enter the store.
 public static func process(_ watches:[ReplyWatch],messages:[ChatMessage],now:Date,connected:Bool)->(watches:[ReplyWatch],alerts:[CommunicationAlert]) {
 var updated=watches;var alerts:[CommunicationAlert]=[]
 for index in updated.indices {
 if !connected && updated[index].status == .waiting {updated[index].status = .paused;updated[index].gap="Observation unavailable; messages during this gap are not verified."}
 if updated[index].timeout(now:now) {
 alerts.append(CommunicationAlert(id:updated[index].id.uuidString+"-timeout",title:"Reply deadline reached",body:"No verified reply from \(updated[index].conversation.name) before the deadline. Observation gaps may apply.",conversationID:updated[index].conversation.id,speak:updated[index].speak));continue
 }
 guard connected,updated[index].status == .waiting else{continue}
 for message in messages where updated[index].observe(message,now:now) {
 let watch=updated[index]
 alerts.append(CommunicationAlert(id:watch.id.uuidString+"-reply",title:"\(watch.conversation.name) replied",body:watch.preview ? (message.text ?? "A new incoming message was observed."):"A new incoming message was observed.",conversationID:watch.conversation.id,speak:watch.speak))
 break
 }
 }
 return (updated,alerts)
 }
}
public extension ActionRiskPolicy {
 static func evaluateMessage(_ reply:ReplyProposal,verifiedConversation:String?,explicitSend:Bool,reviewed:Bool=false)->PolicyDecision {
 MessagingPolicy.evaluate(reply,verifiedConversation:verifiedConversation,explicitSend:explicitSend,reviewed:reviewed)
 }
}
