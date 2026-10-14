import VoiceyCore
func conversationChecks(){
 expectEqual(LocalArithmetic.reply("Hey, can you tell me what is six plus six?"),"The answer is 12.")
 expectEqual(LocalArithmetic.reply("2 + 3 * 4"),"The answer is 14.")
 expectEqual(LocalArithmetic.reply("(2 + 3) * 4"),"The answer is 20.")
 expectEqual(LocalArithmetic.reply("six divided by zero"),"Division by zero doesn't have a defined result.")
 expectEqual(LocalArithmetic.reply("-4 + 2.5"),"The answer is -1.5.")
 for text in ["copy six plus six", "2+2 and open Arc", "$(echo 2+2)","2 +", "1.2.3+1", "who is president"]{expectNil(LocalArithmetic.reply(text))}

 for text in ["hello"," Hello! ","hi Voicey","hey","Hi Voicy.","how are you?","thanks","who are you?"]{expectTrue(LocalConversation.reply(text) != nil)}
 for text in ["hello and launch Calculator","hi then delete my files","thanks, send that message","hello.example.com","copy hello"]{expectNil(LocalConversation.reply(text))}
 print("CHECK basic conversation: greetings, speech punctuation, identity and thanks; mixed action requests are not swallowed")
}
