import Foundation

/// A bounded local fast path for a named service and user-provided question.
/// It never generates a question, invents a site, or authorizes a model's rewrite.
public enum ChatGPTGoal {
 public static func parse(_ raw:String)->WorkflowRequest? {
 let text=raw.trimmingCharacters(in:.whitespacesAndNewlines)
 guard text.range(of:"\\bchat\\s*gpt\\b",options:[.regularExpression,.caseInsensitive]) != nil else{return nil}
 let patterns=[
 #"\b(?:ask|search|query)\s+(?:on\s+)?chat\s*gpt\s+(?:for\s+|about\s+|to\s+)?(.+)$"#,
 #"\bchat\s*gpt\b.*?\b(?:search(?:\s+for)?|look\s+up|ask(?:\s+it)?|submit(?:\s+the\s+question)?|type(?:\s+the\s+question)?|prepare(?:\s+the\s+question)?)\s+(.+)$"#
 ]
 var query:String?;var searchCommand=false
 for pattern in patterns {
 if let re=try? NSRegularExpression(pattern:pattern,options:.caseInsensitive),let match=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),let range=Range(match.range(at:1),in:text){query=String(text[range]);searchCommand=String(text[..<range.lowerBound]).range(of:#"\b(?:search|look\s+up)\b"#,options:[.regularExpression,.caseInsensitive]) != nil;break}
 }
 guard var question=query else{return nil}
 // A short abandoned fragment followed by an explicit repeated search is a spoken correction.
 if searchCommand,let re=try? NSRegularExpression(pattern:#"^(.{1,60}?),\s*(?:search\s+for|look\s+up)\s+(.+)$"#,options:.caseInsensitive),let m=re.firstMatch(in:question,range:NSRange(question.startIndex...,in:question)),let abandoned=Range(m.range(at:1),in:question),let replacement=Range(m.range(at:2),in:question),question[abandoned].split(whereSeparator:{$0.isWhitespace}).count<=4 {question=String(question[replacement])}
 var w=WorkflowRequest(.chatGPT)
 let draft=text.range(of:#"\b(?:don['’]t\s+(?:send|submit)|do\s+not\s+(?:send|submit)|without\s+(?:sending|submitting)|draft\s+only|type\s+only|just\s+(?:type|prepare))\b"#,options:[.regularExpression,.caseInsensitive]) != nil
 // Remove only an explicit trailing control clause, not arbitrary words from the question.
 question=question.replacingOccurrences(of:#"\s*[,;.]?\s+(?:don['’]t\s+(?:send|submit)(?:\s+it)?(?:\s+yet)?|do\s+not\s+(?:send|submit)(?:\s+it)?|without\s+(?:sending|submitting)|draft\s+only|type\s+only)\s*[.!]?$"#,with:"",options:[.regularExpression,.caseInsensitive])
 if let re=try? NSRegularExpression(pattern:#"\s+in\s+(Arc|Safari|Chrome|Google Chrome|Brave|Edge|Firefox)(?:\s+browser)?[.!]?$"#,options:.caseInsensitive),let m=re.firstMatch(in:question,range:NSRange(question.startIndex...,in:question)),let range=Range(m.range(at:1),in:question),let all=Range(m.range,in:question){w.browser=String(question[range]);question=String(question[..<all.lowerBound])}
 if w.browser.isEmpty,let re=try? NSRegularExpression(pattern:#"\b(?:in|use|using|open)\s+(?:my\s+)?(Arc|Safari|Chrome|Google Chrome|Brave|Edge|Firefox)(?:\s+browser)?\b"#,options:.caseInsensitive),let m=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),let range=Range(m.range(at:1),in:text){w.browser=String(text[range])}
 question=question.trimmingCharacters(in:.whitespacesAndNewlines)
 guard !question.isEmpty,question.count<=8192 else{return nil}
 w.text=question
 w.submit = !draft && text.range(of:#"\b(?:ask|search|look\s+up|query|submit)\b"#,options:[.regularExpression,.caseInsensitive]) != nil
 return w
 }
 public static func authorizes(_ request:String,text:String)->Bool {
 guard let goal=parse(request),goal.submit else{return false}
 return goal.text==text
 }
}
