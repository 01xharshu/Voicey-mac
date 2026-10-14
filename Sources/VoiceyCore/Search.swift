import Foundation
public struct SearchResult: Identifiable, Equatable, Sendable {
 public var id:String{url.path}
 public let url:URL
 public let score:Int
 public let directory:Bool
 public init(url:URL,score:Int,directory:Bool){self.url=url;self.score=score;self.directory=directory}
}
public struct FileSearchService: Sendable {
 public init(){}
 public static func terms(_ query:String)->[String] {
 let ignored=Set(["my","the","a","folder","file","project","please","all","from","today","yesterday","i","was","working","on"])
 return query.lowercased().split(whereSeparator:{!$0.isLetter && !$0.isNumber}).map(String.init).filter{!ignored.contains($0)}
 }
 public static func score(_ query:String,url:URL)->Int {
 let name=url.deletingPathExtension().lastPathComponent.lowercased(),q=query.lowercased(),terms=terms(query)
 if name==q || url.lastPathComponent.lowercased()==q{return 100}
 let normalized=terms.joined(separator:" ")
 let normalizedName=name.split(whereSeparator:{!$0.isLetter && !$0.isNumber}).joined(separator:" ")
 if !normalized.isEmpty && name==normalized{return 96}
 if !normalized.isEmpty && normalizedName.contains(normalized){return 88}
 if terms.isEmpty{return 0}
 let matches=terms.filter{url.path.lowercased().contains($0)}.count
 if matches==terms.count{return 70 + (terms.allSatisfy{name.contains($0)} ? 12:0)}
 return 0
 }
 public func search(_ query:String,scopes:[URL],hidden:Bool=false,limit:Int=40,maxEntries:Int=80000) throws -> [SearchResult] {
 var results:[SearchResult]=[],seen=Set<String>(),visited=0
 let keys:Set<URLResourceKey>=[.isDirectoryKey,.isSymbolicLinkKey,.isPackageKey,.contentModificationDateKey]
 let excluded=Set(["Library","node_modules",".git",".build",".deps","Caches","DerivedData"])
 let lower=query.lowercased(),calendar=Calendar.current
 let dateOffset=lower.contains("yesterday") ? -1:0
 let dated=lower.contains("today") || lower.contains("yesterday")
 let requestedDate=calendar.date(byAdding:.day,value:dateOffset,to:Date())!
 for scope in scopes {
 try Task.checkCancellation()
 let root=scope.resolvingSymlinksInPath()
 guard FileManager.default.fileExists(atPath:root.path) else{continue}
 let options:FileManager.DirectoryEnumerationOptions=hidden ? [.skipsPackageDescendants]:[.skipsPackageDescendants,.skipsHiddenFiles]
 guard let enumerator=FileManager.default.enumerator(at:root,includingPropertiesForKeys:Array(keys),options:options,errorHandler:{_,_ in true}) else{continue}
 for case let url as URL in enumerator {
 try Task.checkCancellation();visited+=1;if visited>maxEntries{break}
 guard let attrs=try? url.resourceValues(forKeys:keys) else{continue}
 if attrs.isSymbolicLink==true{enumerator.skipDescendants();continue}
 if excluded.contains(url.lastPathComponent) || attrs.isPackage==true {enumerator.skipDescendants();if attrs.isDirectory==true{continue}}
 if !seen.insert(url.path).inserted{continue}
 if dated {guard let date=attrs.contentModificationDate,calendar.isDate(date,inSameDayAs:requestedDate) else{continue}}
 if lower.contains("folder") && attrs.isDirectory != true {continue}
 if lower.contains("blender") && url.pathExtension.lowercased() != "blend" && attrs.isDirectory != true{continue}
 let effective=lower.contains("blender") ? lower.replacingOccurrences(of:"blender",with:""):query
 var score=Self.score(effective,url:url)
 if lower.contains("blender") && url.pathExtension.lowercased()=="blend" {score=max(score,80)}
 if lower.contains("screenshot") && url.lastPathComponent.lowercased().contains("screenshot"){score=max(score,85)}
 if score>0{results.append(SearchResult(url:url,score:score,directory:attrs.isDirectory==true))}
 }
 if visited>maxEntries{break}
 }
 return Array(results.sorted{$0.score==$1.score ? $0.url.path<$1.url.path:$0.score>$1.score}.prefix(limit))
 }
 public static func unambiguous(_ results:[SearchResult])->Bool {
 guard let first=results.first,first.score>=85 else{return false}
 return results.count==1 || first.score-results[1].score>=12
 }
}
public struct PathValidator {
 public static func existing(_ path:String) throws -> URL {
 guard path.hasPrefix("/") || path.hasPrefix("~/") else{throw VoiceyError.invalid("An absolute local path is required.")}
 let url=URL(fileURLWithPath:(path as NSString).expandingTildeInPath).standardizedFileURL
 guard FileManager.default.fileExists(atPath:url.path) else{throw VoiceyError.unavailable("That saved path no longer exists.")};return url
 }
 public static func folder(name:String,parent:URL) throws -> URL {
 guard !name.isEmpty,name.count<256,!name.contains("/"),!name.contains(":"),!name.contains("\0"),name != ".",name != ".." else{throw VoiceyError.invalid("Choose a simple folder name without a slash or colon.")}
 var isDirectory:ObjCBool=false
 guard FileManager.default.fileExists(atPath:parent.path,isDirectory:&isDirectory),isDirectory.boolValue else{throw VoiceyError.invalid("The destination must be an existing folder.")}
 let target=parent.appendingPathComponent(name,isDirectory:true)
 guard !FileManager.default.fileExists(atPath:target.path) else{throw VoiceyError.invalid("An item with that name already exists; nothing was overwritten.")};return target
 }
}
