import Foundation
import VoiceyCore
final class CoreTests {
 var teardown:[()->Void]=[]
 func addTeardownBlock(_ block:@escaping()->Void){teardown.append(block)}
 func cleanup(){teardown.forEach{$0()};teardown=[]}
 func testCommandChordEitherOrderAndLatch(){
 for leftFirst in [true,false]{var c=CommandChord();expectFalse(c.update(left:leftFirst,right:!leftFirst));expectTrue(c.update(left:true,right:true));expectFalse(c.update(left:true,right:true));expectFalse(c.update(left:false,right:true));expectTrue(c.update(left:true,right:true));c.reset();expectFalse(c.left);expectFalse(c.right)}
 }
 func testSingleAndSequentialTaps(){var c=CommandChord();for _ in 0..<5{expectFalse(c.update(left:true,right:false));expectFalse(c.update(left:false,right:false));expectFalse(c.update(left:false,right:true));expectFalse(c.update(left:false,right:false))}}
 func testSafePolicy(){for kind in [IntentKind.launchApp,.search,.openItem,.reveal,.clipboard,.remember,.capabilities]{expectEqual(ActionRiskPolicy.evaluate(Intent(kind,query:"x")),.execute)};expectEqual(ActionRiskPolicy.evaluate(Intent(.createFolder,query:"Assets",destination:"Documents")),.execute)}
 func testAmbiguityAndDestination(){expectEqual(ActionRiskPolicy.evaluate(Intent(.openItem),ambiguous:true),.clarify("Which one did you mean?"));if case .clarify=ActionRiskPolicy.evaluate(Intent(.createFolder)){ }else{fail()}}
 func testWebsiteAlwaysConfirmation(){expectEqual(ActionRiskPolicy.evaluate(Intent(.website,query:"youtube",browser:"Arc")),.confirm("https://www.youtube.com/"))}
 func testUnsupportedAndDestructiveFailClosed(){for kind in [IntentKind.delete,.shell,.unsupported]{if case .reject=ActionRiskPolicy.evaluate(Intent(kind)){ }else{fail("Must fail closed")}}}
 func testURLSchemesAndMalformed(){for value in ["javascript:alert(1)","file:///tmp/foo","ftp://example.com","https://user:pass@example.com","https://ex ample.com","https://.com","https://example..com","https://-bad.com","https://example.com\\@evil.com","notawwebsite","https://example.com\n"]{if value.hasSuffix("\n"){continue};expectThrows(try URLValidator.validate(value),value)};expectEqual(try URLValidator.validate("example.com").host,"example.com");expectEqual(try URLValidator.validate("http://example.com/path?q=a").scheme,"http")}
 func testIntentExamples(){let p=IntentParser();expectEqual(p.parse("Launch Figma")?.kind,.launchApp);expectEqual(p.parse("Show invoice.pdf in Finder")?.kind,.reveal);expectEqual(p.parse("Find my Notion Masterclass folder")?.kind,.search);expectEqual(p.parse("Open YouTube in Arc"),Intent(.website,query:"YouTube",browser:"Arc"));let folder=p.parse("Create a folder called Voicey Experiments in my Documents folder");expectEqual(folder?.query,"Voicey Experiments");expectEqual(folder?.destination,"my Documents folder");expectEqual(p.parse("Copy hello world")?.query,"hello world");expectNil(p.parse("please organize everything magically"))}
 func testContextReplies(){expectEqual(Dialogue.reply("Correct."),.approve);expectEqual(Dialogue.reply("cancel that"),.cancel);expectEqual(Dialogue.reply("Arc"),.choice("Arc"));expectEqual(Dialogue.reply("No, the other one"),.other);expectEqual(Dialogue.reply("Open Safari"),.newRequest("Open Safari"))}
 func temporary()throws->URL{let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);addTeardownBlock{try? FileManager.default.removeItem(at:url)};return url}
 func testMemoryAliasesCorrectionsConflictDeletion()throws{let root=try temporary(),url=root.appendingPathComponent("memory.json"),store=try LocalMemoryStore(url:url);let e=MemoryEntry(phrase:"my AI course",target:"/Documents/AI");try store.remember(e);try store.remember(MemoryEntry(phrase:"Tipsy Docky",target:"Tipsy Docy",category:"correction"));expectEqual(store.alias("MY ai COURSE"),e.target);expectEqual(store.corrected("Open Tipsy Docky"),"Open Tipsy Docy");expectEqual(store.corrected("Tipsy Dockyard"),"Tipsy Dockyard");expectThrows(try store.remember(MemoryEntry(phrase:e.phrase,target:"/other")));let reloaded=try LocalMemoryStore(url:url);expectEqual(reloaded.alias(e.phrase),e.target);try reloaded.remove(e.id);expectNil(reloaded.alias(e.phrase));try reloaded.browser("com.apple.Safari");expectEqual(try LocalMemoryStore(url:url).document.preferredBrowser,"com.apple.Safari");try reloaded.clear();expectTrue(reloaded.document.entries.isEmpty)}
 func testCorruptMemoryPreserved()throws{let root=try temporary(),url=root.appendingPathComponent("memory.json");let data=Data("{bad".utf8);try data.write(to:url);expectThrows(try LocalMemoryStore(url:url));expectEqual(try Data(contentsOf:url),data)}
 func testNestedHiddenSymlinkAndMissingSearch()throws{let root=try temporary(),nested=root.appendingPathComponent("courses/Notion Masterclass");try FileManager.default.createDirectory(at:nested,withIntermediateDirectories:true);let hidden=root.appendingPathComponent(".Secret invoice.pdf");try Data().write(to:hidden);try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("loop"),withDestinationURL:root);let service=FileSearchService();let results=try service.search("Notion Masterclass",scopes:[root]);expectEqual(results.first?.url.path.replacingOccurrences(of:"/private/var/",with:"/var/"),nested.path.replacingOccurrences(of:"/private/var/",with:"/var/"));expectTrue(FileSearchService.unambiguous(results));expectTrue(try service.search("Secret invoice",scopes:[root]).isEmpty);expectFalse(try service.search("Secret invoice",scopes:[root],hidden:true).isEmpty);expectTrue(try service.search("missing elephant",scopes:[root]).isEmpty)}
 func testEqualMatchesClarify()throws{let root=try temporary();for parent in ["one","two"]{try FileManager.default.createDirectory(at:root.appendingPathComponent(parent+"/Course"),withIntermediateDirectories:true)};let matches=try FileSearchService().search("Course",scopes:[root]);expectEqual(matches.count,2);expectFalse(FileSearchService.unambiguous(matches))}
 func testPathAndFolderValidation()throws{let root=try temporary();for name in ["..",".","../escape","a/b","bad:name",""]{expectThrows(try PathValidator.folder(name:name,parent:root))};let target=try PathValidator.folder(name:"Assets",parent:root);try FileManager.default.createDirectory(at:target,withIntermediateDirectories:false);expectThrows(try PathValidator.folder(name:"Assets",parent:root));expectThrows(try PathValidator.existing("relative"));expectThrows(try PathValidator.existing(root.appendingPathComponent("missing").path));expectEqual(try PathValidator.existing(target.path),target)}
 func testSearchCancellation() async throws {let root=try temporary();let task=Task{try Task.checkCancellation();return try FileSearchService().search("x",scopes:[root])};task.cancel();do{_ = try await task.value;fail("Expected cancellation")}catch is CancellationError{} }
 func testMalformedModelIntentRejected(){expectThrows(try JSONDecoder().decode(Intent.self,from:Data("{\"kind\":\"run_arbitrary_shell\"}".utf8)))}
 func testWebsiteAuthorizationCancellationExpiryAndReplay()throws{
 var auth=WebsiteAuthorization();let url=try URLValidator.validate("youtube")
 expectThrows(try auth.consume(url));_ = try auth.propose("youtube");expectThrows(try auth.consume(url));_ = try auth.propose("youtube");expectEqual(try auth.approve(),url);try auth.consume(url);expectThrows(try auth.consume(url))
 _ = try auth.propose("youtube");auth.clear();expectThrows(try auth.approve())
 let now=Date();_ = try auth.propose("youtube",now:now);expectThrows(try auth.approve(now:now.addingTimeInterval(121)))
 _ = try auth.propose("youtube");_ = try auth.approve();expectThrows(try auth.consume(try URLValidator.validate("github")))
 }
 func testToolArgumentValidation(){let registry=ToolRegistry();expectThrows(try registry.validate(Intent(.shell,query:"rm -rf")));expectThrows(try registry.validate(Intent(.clipboard)));expectThrows(try registry.validate(Intent(.openItem,query:"bad\0path")))}

 func testBrowserExplicitPreferenceAndUnavailable(){
 let installed=[AvailableBrowser(id:"safari",name:"Safari"),AvailableBrowser(id:"arc",name:"Arc")]
 expectEqual(BrowserPolicy.resolve(installed:installed,explicit:"Arc",saved:"safari"),.selected("arc"))
 expectEqual(BrowserPolicy.resolve(installed:installed,explicit:"",saved:"safari"),.selected("safari"))
 expectEqual(BrowserPolicy.resolve(installed:installed,explicit:"Chrome",saved:"safari"),.choose(explicitUnavailable:true))
 expectEqual(BrowserPolicy.resolve(installed:installed,explicit:"",saved:nil),.choose(explicitUnavailable:false))
 expectEqual(BrowserPolicy.resolve(installed:[],explicit:"Arc",saved:nil),.none)
 }

 func testThreeModifierActivation(){
 var chord=ModifierChord()
 for (control,option,command) in [(false,false,false),(true,false,false),(false,true,false),(false,false,true),(true,true,false),(true,false,true),(false,true,true)]{expectFalse(chord.update(control:control,option:option,command:command))}
 expectTrue(chord.update(control:true,option:true,command:true));expectFalse(chord.update(control:true,option:true,command:true));expectFalse(chord.update(control:true,option:false,command:true));expectTrue(chord.update(control:true,option:true,command:true));chord.reset();expectTrue(chord.update(control:true,option:true,command:true))
 }

 func testSpeechPunctuationAndSpokenDomain(){let parser=IntentParser();expectEqual(parser.parse("Open Notes app.")?.kind,.launchApp);expectEqual(parser.parse("Open Notes app.")?.query,"Notes");expectEqual(parser.parse("Open example dot com")?.kind,.website);expectEqual(parser.parse("Open example dot com")?.query,"example.com");expectEqual(FileSearchService.score("Tipsy Docy",url:URL(fileURLWithPath:"/Documents/Tipsy-Docy-Web")),88)}

 func testUnsupportedCompoundAppEditing(){let intent=IntentParser().parse("Open Notes app and in folder named code create a new page.");expectEqual(intent?.kind,.unsupported);expectTrue(intent?.explanation.contains("not supported") == true)}

 func testPersistedGestureModes(){var chosen=ActivationChord();expectFalse(chosen.update(control:false,option:false,command:true,leftCommand:true,rightCommand:true));expectTrue(chosen.update(control:true,option:true,command:true));expectFalse(chosen.update(control:true,option:true,command:true));var legacy=ActivationChord(gesture:.dualCommand);expectFalse(legacy.update(control:true,option:true,command:true,leftCommand:true));expectTrue(legacy.update(control:false,option:false,command:true,leftCommand:true,rightCommand:true));legacy.reset();expectTrue(legacy.update(control:false,option:false,command:true,leftCommand:true,rightCommand:true))}

}
