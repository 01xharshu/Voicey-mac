import Foundation
public enum LocalConversation {
 public static func reply(_ text:String)->String? {
 let normalized=text.lowercased().trimmingCharacters(in:.whitespacesAndNewlines.union(.punctuationCharacters)).split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
 switch normalized {
 case "hello","hi","hey","hello voicey","hi voicey","hey voicey","hello voicy","hi voicy":return "Hi! I'm Voicey. What would you like to do?"
 case "good morning","good afternoon","good evening":return "Hello! What can I help you with?"
 case "how are you","how are you doing":return "I'm ready to help. What's on your mind?"
 case "thank you","thanks","thanks voicey":return "You're welcome!"
 case "who are you","what is your name","what's your name":return "I'm Voicey, your local Mac assistant. I can help you with apps, files and supported computer tasks."
 default:return nil
 }
 }
}
