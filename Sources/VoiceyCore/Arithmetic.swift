import Foundation

/// Small arithmetic language. Never evaluates shell code or arbitrary expressions.
public enum LocalArithmetic {
 public static func reply(_ input:String)->String? {
 var text=input.lowercased().trimmingCharacters(in:.whitespacesAndNewlines)
 for prefix in ["hey, ","hey ","can you tell me what is ","can you tell me what's ","could you calculate ","please calculate ","calculate ","what is ","what's ","tell me "] {
 if text.hasPrefix(prefix){text=String(text.dropFirst(prefix.count))}
 }
 text=text.trimmingCharacters(in:CharacterSet(charactersIn:" ?!"))
 let words=["zero":0,"one":1,"two":2,"three":3,"four":4,"five":5,"six":6,"seven":7,"eight":8,"nine":9,"ten":10,"eleven":11,"twelve":12,"thirteen":13,"fourteen":14,"fifteen":15,"sixteen":16,"seventeen":17,"eighteen":18,"nineteen":19,"twenty":20,"thirty":30,"forty":40,"fifty":50,"sixty":60,"seventy":70,"eighty":80,"ninety":90]
 for (phrase,symbol) in [("multiplied by","*"),("divided by","/"),("plus","+"),("minus","-"),("times","*"),("×","*"),("÷","/")] {text=text.replacingOccurrences(of:phrase,with:symbol)}
 text=text.split(separator:" ").map{words[String($0)].map(String.init) ?? String($0)}.joined(separator:" ")
 guard text.count<=160,text.contains(where:{"+*/".contains($0)}) || text.dropFirst().contains("-"),text.allSatisfy({$0.isASCII && ($0.isNumber || " .+-*/()".contains($0))}) else{return nil}
 var parser=Parser(chars:Array(text.filter{!$0.isWhitespace}))
 do{let result=try parser.expression();guard parser.index==parser.chars.count,result.isFinite else{return nil}
 return "The answer is \(String(format:"%.12g",result))."
 }catch ArithmeticError.zero{return "Division by zero doesn't have a defined result."}catch{return nil}
 }
 private enum ArithmeticError:Error {case invalid,zero}
 private struct Parser {
 let chars:[Character];var index=0
 mutating func take(_ c:Character)->Bool{if index<chars.count,chars[index]==c{index+=1;return true};return false}
 mutating func expression()throws->Double{var n=try term();while index<chars.count{if take("+"){n += try term()}else if take("-"){n -= try term()}else{break}};return n}
 mutating func term()throws->Double{var n=try factor();while index<chars.count{if take("*"){n *= try factor()}else if take("/"){let d=try factor();guard d != 0 else{throw ArithmeticError.zero};n /= d}else{break}};return n}
 mutating func factor()throws->Double{
 if take("+"){return try factor()};if take("-"){return -(try factor())}
 if take("("){let n=try expression();guard take(")") else{throw ArithmeticError.invalid};return n}
 let start=index;while index<chars.count,chars[index].isNumber || chars[index]=="."{index+=1}
 guard index>start,let n=Double(String(chars[start..<index])),n.isFinite else{throw ArithmeticError.invalid};return n
 }
 }
}
