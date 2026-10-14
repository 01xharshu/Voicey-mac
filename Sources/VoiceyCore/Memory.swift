import Foundation
public struct MemoryEntry: Codable, Identifiable, Equatable, Sendable {
 public var id: UUID
 public var phrase: String
 public var target: String
 public var category: String
 public var updated: Date
 public init(phrase:String,target:String,category:String="alias"){id=UUID();self.phrase=phrase;self.target=target;self.category=category;updated=Date()}
}
public struct MemoryDocument: Codable, Sendable {
 public var version=1
 public var entries:[MemoryEntry]=[]
 public var preferredBrowser:String?
 public init(){}
}
public final class LocalMemoryStore {
 public let url: URL
 public private(set) var document:MemoryDocument
 public init(url:URL) throws {
 self.url=url
 if FileManager.default.fileExists(atPath:url.path) {
 do {document=try JSONDecoder().decode(MemoryDocument.self,from:Data(contentsOf:url));guard document.version==1 else{throw VoiceyError.invalid("Memory format is newer than this app. Original file preserved.")}}catch{throw VoiceyError.invalid("Cannot read local memory. Original file preserved; move it aside to recover.")}
 } else {document=MemoryDocument()}
 }
 public func save() throws {try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try JSONEncoder().encode(document).write(to:url,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)}
 public func remember(_ entry:MemoryEntry,replace:Bool=false) throws {
 if let index=document.entries.firstIndex(where:{$0.phrase.lowercased()==entry.phrase.lowercased() && $0.category==entry.category}) {
 guard replace || document.entries[index].target==entry.target else{throw VoiceyError.invalid("That phrase already has a different memory. Edit the existing memory in Settings.")};document.entries[index]=entry
 } else {document.entries.append(entry)}
 try save()
 }
 public func remove(_ id:UUID) throws {document.entries.removeAll{$0.id==id};try save()}
 public func clear() throws {document.entries=[];document.preferredBrowser=nil;try save()}
 public func browser(_ id:String?) throws{document.preferredBrowser=id;try save()}
 public func alias(_ phrase:String) -> String? {document.entries.first{$0.category=="alias" && $0.phrase.caseInsensitiveCompare(phrase) == .orderedSame}?.target}
 public func corrected(_ text:String)->String {
 // Only explicit corrections, whole word boundaries; never infer replacements from unrelated files.
 var result=text
 for entry in document.entries where entry.category=="correction" {
 let pattern="(?i)(?<![\\p{L}\\p{N}])"+NSRegularExpression.escapedPattern(for:entry.phrase)+"(?![\\p{L}\\p{N}])"
 if let regex=try? NSRegularExpression(pattern:pattern){result=regex.stringByReplacingMatches(in:result,range:NSRange(result.startIndex...,in:result),withTemplate:NSRegularExpression.escapedTemplate(for:entry.target))}
 }
 return result
 }
}
