import Foundation
var failures=0
func fail(_ message:String="",file:StaticString=#filePath,line:UInt=#line){failures+=1;print("FAIL \(file):\(line) \(message)")}
func expectTrue(_ value:@autoclosure() throws->Bool,_ message:String="",file:StaticString=#filePath,line:UInt=#line) {do{if try !value(){fail(message,file:file,line:line)}}catch{fail(error.localizedDescription,file:file,line:line)}}
func expectFalse(_ value:@autoclosure() throws->Bool,_ message:String="",file:StaticString=#filePath,line:UInt=#line) {do{if try value(){fail(message,file:file,line:line)}}catch{fail(error.localizedDescription,file:file,line:line)}}
func expectEqual<T:Equatable>(_ a:@autoclosure() throws->T,_ b:@autoclosure() throws->T,file:StaticString=#filePath,line:UInt=#line) {do{let actual=try a();let expected=try b();if actual != expected{fail("Actual: \(actual); expected: \(expected)",file:file,line:line)}}catch{fail(error.localizedDescription,file:file,line:line)}}
func expectNil<T>(_ value:T?,file:StaticString=#filePath,line:UInt=#line){if value != nil{fail("Expected nil",file:file,line:line)}}
func expectThrows<T>(_ value:@autoclosure() throws->T,_ message:String="",file:StaticString=#filePath,line:UInt=#line){do{_ = try value();fail("Expected error "+message,file:file,line:line)}catch{}}
@main struct CheckRunner {@MainActor static func main() async {
 let tests=CoreTests()
tests.testCommandChordEitherOrderAndLatch(); print("CHECK testCommandChordEitherOrderAndLatch");tests.cleanup()
tests.testSingleAndSequentialTaps(); print("CHECK testSingleAndSequentialTaps");tests.cleanup()
tests.testSafePolicy(); print("CHECK testSafePolicy");tests.cleanup()
tests.testAmbiguityAndDestination(); print("CHECK testAmbiguityAndDestination");tests.cleanup()
tests.testWebsiteAlwaysConfirmation(); print("CHECK testWebsiteAlwaysConfirmation");tests.cleanup()
tests.testUnsupportedAndDestructiveFailClosed(); print("CHECK testUnsupportedAndDestructiveFailClosed");tests.cleanup()
tests.testURLSchemesAndMalformed(); print("CHECK testURLSchemesAndMalformed");tests.cleanup()
tests.testIntentExamples(); print("CHECK testIntentExamples");tests.cleanup()
tests.testContextReplies(); print("CHECK testContextReplies");tests.cleanup()
do{try tests.testMemoryAliasesCorrectionsConflictDeletion(); print("CHECK testMemoryAliasesCorrectionsConflictDeletion")}catch{fail(error.localizedDescription)};tests.cleanup()
do{try tests.testCorruptMemoryPreserved(); print("CHECK testCorruptMemoryPreserved")}catch{fail(error.localizedDescription)};tests.cleanup()
do{try tests.testNestedHiddenSymlinkAndMissingSearch(); print("CHECK testNestedHiddenSymlinkAndMissingSearch")}catch{fail(error.localizedDescription)};tests.cleanup()
do{try tests.testEqualMatchesClarify(); print("CHECK testEqualMatchesClarify")}catch{fail(error.localizedDescription)};tests.cleanup()
do{try tests.testPathAndFolderValidation(); print("CHECK testPathAndFolderValidation")}catch{fail(error.localizedDescription)};tests.cleanup()
do{try await tests.testSearchCancellation(); print("CHECK testSearchCancellation")}catch{fail(error.localizedDescription)};tests.cleanup()
tests.testMalformedModelIntentRejected(); print("CHECK testMalformedModelIntentRejected");tests.cleanup()
do{try tests.testWebsiteAuthorizationCancellationExpiryAndReplay(); print("CHECK testWebsiteAuthorizationCancellationExpiryAndReplay")}catch{fail(error.localizedDescription)};tests.cleanup()
tests.testToolArgumentValidation(); print("CHECK testToolArgumentValidation");tests.cleanup()
tests.testBrowserExplicitPreferenceAndUnavailable();print("CHECK browser choice");
tests.testThreeModifierActivation();print("CHECK three modifier activation");
tests.testSpeechPunctuationAndSpokenDomain();print("CHECK speech punctuation");
tests.testUnsupportedCompoundAppEditing();print("CHECK unsupported compound editing");
conversationChecks()
neuralVoiceChecks()
await ComputerTests.run()
tests.testPersistedGestureModes();print("CHECK selected activation gesture");
do{try communicationChecks();try await smartAgentChecks();try await adaptiveComputerChecks()}catch{fail(error.localizedDescription)}
print("Completed legacy checks, computer-use scenarios, communication and smart-agent fixtures; \(failures) failures");if failures>0{exit(1)}
}}
