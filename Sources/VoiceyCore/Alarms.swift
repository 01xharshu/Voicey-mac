import Foundation
public struct AlarmRecord:Codable,Equatable,Sendable {
 public let id:String,minutes:Int
 public init(id:String,minutes:Int){self.id=id;self.minutes=minutes}
 public var time:String{let hour=minutes/60;return String(format:"%d:%02d %@",hour%12==0 ? 12:hour%12,minutes%60,hour>=12 ? "PM":"AM")}
}
public enum AlarmPolicy {
 public static func deleteAction(_ actions:[String])->String? {
 actions.first{$0.caseInsensitiveCompare("Delete alarm") == .orderedSame || $0.components(separatedBy:"\n").first?.caseInsensitiveCompare("Name:Delete alarm") == .orderedSame}
 }
 public static func time(_ text:String)->Int? {
 let compact=text.uppercased().replacingOccurrences(of:" ",with:"")
 guard let re=try? NSRegularExpression(pattern:"^(1[0-2]|[1-9]):([0-5][0-9])(AM|PM)$"),let m=re.firstMatch(in:compact,range:NSRange(compact.startIndex...,in:compact)) else{return nil}
 func group(_ n:Int)->String{String(compact[Range(m.range(at:n),in:compact)!])}
 guard let hour=Int(group(1)),let minute=Int(group(2)) else{return nil}
 return (hour%12+(group(3)=="PM" ? 12:0))*60+minute
 }
 public static func cutoffs(_ text:String)throws->[Int] {
 var value=text.lowercased()
 for (word,number) in [("twelve","12"),("eleven","11"),("ten","10"),("nine","9"),("eight","8"),("seven","7"),("six","6"),("five","5"),("four","4"),("three","3"),("two","2"),("one","1")] {value=value.replacingOccurrences(of:word,with:number)}
 value=value.replacingOccurrences(of:"in the morning",with:"am").replacingOccurrences(of:"in the evening",with:"pm").replacingOccurrences(of:"in the afternoon",with:"pm")
 guard let re=try? NSRegularExpression(pattern:"(?:before\\s+)?(1[0-2]|[1-9])(?::([0-5][0-9]))?\\s*(am|pm)?\\b"),let m=re.firstMatch(in:value,range:NSRange(value.startIndex...,in:value)) else{throw VoiceyError.invalid("What time should the alarm cutoff use? Include AM or PM.")}
 func group(_ n:Int)->String{Range(m.range(at:n),in:value).map{String(value[$0])} ?? ""}
 let hour=Int(group(1))!,minute=Int(group(2)) ?? 0,base=hour%12*60+minute
 return group(3)=="am" ? [base]:group(3)=="pm" ? [base+720]:[base,base+720]
 }
 public static func select(_ alarms:[AlarmRecord],before:Int)->[AlarmRecord]{alarms.filter{$0.minutes<before}.sorted{$0.id<$1.id}}
 public static func fingerprint(_ alarms:[AlarmRecord])->String {alarms.sorted{$0.id<$1.id}.map{"\($0.id)=\($0.minutes)"}.joined(separator:"\n")}
 public static func verify(before:[AlarmRecord],selected:[AlarmRecord],after:[AlarmRecord])->Verification {
 let expected=before.filter{alarm in !selected.contains(where:{$0.id==alarm.id})}.sorted{$0.id<$1.id}
 return Verification(after.sorted{$0.id<$1.id}==expected ? .success:.failure,"Alarm list compared with the approved batch; unrelated alarms must remain unchanged")
 }
}
