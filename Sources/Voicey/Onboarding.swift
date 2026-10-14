import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import VoiceyCore

private enum SetupStep:Int,CaseIterable,Identifiable {
 case welcome,voice,microphone,shortcut,commands,finish
 var id:Int{rawValue}
 var title:String{switch self{case .welcome:return "Welcome";case .voice:return "Speaker";case .microphone:return "Microphone";case .shortcut:return "Shortcut";case .commands:return "Understanding & Actions";case .finish:return "Your Results"}}
 var icon:String{switch self{case .welcome:return "waveform.circle";case .voice:return "speaker.wave.2";case .microphone:return "mic";case .shortcut:return "keyboard";case .commands:return "cursorarrow";case .finish:return "checklist"}}
}
private enum SetupResult:String {case untested="Not tested",running="Testing…",confirm="Needs your check",passed="Passed",failed="Needs attention"}
@MainActor final class OnboardingController:ObservableObject {
 @Published fileprivate var step=SetupStep.welcome
 @Published fileprivate var results:[String:SetupResult]=[:]
 @Published var detail=""
 @Published var heard=""
 @Published var speakerFinished=false
 @Published var waitingForShortcut=false
 @Published var working=false
 let agent:AgentOrchestrator
 private var work:Task<Void,Never>?
 private var generation=UUID()
 private var shortcutBaseline=0
 init(agent:AgentOrchestrator){self.agent=agent}
 fileprivate func result(_ key:String)->SetupResult{results[key] ?? .untested}
 func stop(){for (key,value) in results where value == .running{results[key] = .untested};generation=UUID();work?.cancel();work=nil;working=false;waitingForShortcut=false;agent.cancel();speakerFinished=false;heard="";detail=""}
 fileprivate func move(_ next:SetupStep){
 for (key,result) in results where result == .running{results[key] = .untested}
 stop();step=next
 }
 func preview(){
 stop();results["Speaker"] = .running;working=true
 let token=generation
 agent.tts.speak("Hi, I'm Voicey. I'm ready to help. You can speak naturally, and I'll listen before I reply.",voice:UserDefaults.standard.string(forKey:"voiceID"),rate:agent.speechRate){[weak self] in
 guard let self,self.generation==token else{return};self.speakerFinished=true;self.working=false;self.results["Speaker"] = .confirm;self.detail="Did you hear the voice clearly?"
 }
 }
 func confirmSpeaker(_ good:Bool){results["Speaker"] = good ? .passed:.failed;speakerFinished=false;detail=good ? "Playback checked by you.":"Try another voice or check your Mac's audio output."}
 func microphone(){
 stop();results["Microphone"] = .running;working=true
 agent.startMicrophoneTest{[weak self] text in guard let self else{return};self.heard=text;self.working=false;self.results["Microphone"] = .confirm;self.detail="Compare the transcript with what you said."}
 }
 func confirmMicrophone(_ correct:Bool){results["Microphone"] = correct ? .passed:.failed;detail=correct ? "Recording and local transcription checked by you.":"Try again in a quiet room or change the recognition language."}
 func armShortcut(){
 stop();results["Shortcut"] = .running;waitingForShortcut=true;shortcutBaseline=agent.shortcutActivations
 agent.prepareMicrophoneTest{[weak self] text in self?.heard=text}
 detail="Hold Control, Option and Command together. You should see Listening without a spoken greeting."
 }
 func observeState(){
 if waitingForShortcut,agent.shortcutActivations>shortcutBaseline,agent.state == .listening {
 results["Shortcut"] = .passed;waitingForShortcut=false;detail="The physical shortcut reached live microphone recording. No greeting played."
 }
 if [.missing,.error].contains(agent.state),working || waitingForShortcut {
 let key=step == .microphone ? "Microphone":"Shortcut"
 results[key] = .failed;working=false;waitingForShortcut=false;detail=agent.message
 }
 }
 func conversation(){
 stop();results["Conversation"] = .running;working=true
 detail="Say hello or ask how Voicey is doing, then finish speaking."
 let token=generation
 agent.startMicrophoneTest{[weak self] text in
 guard let self,self.generation==token else{return}
 self.heard=text
 guard let expected=LocalConversation.reply(text) else{self.results["Conversation"] = .failed;self.working=false;self.detail="I heard: \(text). Try a greeting for this check.";return}
 self.agent.submit(text)
 self.work=Task{[weak self] in guard let self else{return};let deadline=Date().addingTimeInterval(20)
 while Date()<deadline{
 if Task.isCancelled || self.generation != token{return}
 if self.agent.state == .success,self.agent.message==expected,self.agent.tts.status.hasPrefix("Speaking with"){
 self.results["Conversation"] = .confirm;self.detail="Voicey answered your recorded greeting. Confirm that you heard the reply.";self.working=false;return
 }
 try? await Task.sleep(nanoseconds:100_000_000)
 }
 self.results["Conversation"] = .failed;self.detail="No spoken reply verified. Check Speak replies and your audio output.";self.working=false
 }
 }
 }
 func confirmConversation(_ heardReply:Bool){results["Conversation"] = heardReply ? .passed:.failed;detail=heardReply ? "Your spoken greeting and audible reply are checked.":"Spoken reply needs attention."}
 func understanding(){
 stop();working=true;results["Understanding"] = .running
 detail="Ask Voicey to open Calculator in your own words. This check listens to you."
 let token=generation
 agent.startMicrophoneTest{[weak self] text in
 guard let self,self.generation==token else{return};self.heard=text
 self.work=Task{[weak self] in guard let self else{return}
 do{
 let intent=try await self.agent.engine.interpret(text,context:"Available application: Calculator.")
 try Task.checkCancellation();guard self.generation==token else{return}
 let ok=intent.kind == .launchApp && intent.query.caseInsensitiveCompare("Calculator") == .orderedSame
 self.results["Understanding"] = ok ? .confirm:.failed
 self.detail=ok ? "Your recorded request was understood as opening Calculator. Confirm the transcript matches what you asked.":"Your recorded request did not resolve to opening Calculator. Heard: \(text)"
 }catch{guard self.generation==token,!Task.isCancelled else{return};self.results["Understanding"] = .failed;self.detail=error.localizedDescription}
 self.working=false
 }
 }
 }
 func confirmUnderstanding(_ correct:Bool){results["Understanding"] = correct ? .passed:.failed;detail=correct ? "Your recorded request and interpretation are checked.":"Try recording the request again."}
 func appAction(){
 stop();working=true;results["App action"] = .running
 let token=generation
 // The same request route as normal typed/spoken commands, not a fixture adapter.
 agent.submit("Launch Calculator")
 work=Task{[weak self] in guard let self else{return};let deadline=Date().addingTimeInterval(20)
 while Date()<deadline {
 if Task.isCancelled || self.generation != token{return}
 if self.agent.state == .success {
 let running=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.calculator").contains{!$0.isTerminated}
 self.results["App action"] = running ? .passed:.failed;self.detail=running ? "Calculator is running after the normal command route completed.":"The command reported success, but Calculator was not running.";self.working=false;return
 }
 if [.error,.missing,.clarification].contains(self.agent.state){self.results["App action"] = .failed;self.detail=self.agent.message;self.working=false;return}
 try? await Task.sleep(nanoseconds:100_000_000)
 }
 self.results["App action"] = .failed;self.detail="The app action did not verify within 20 seconds.";self.working=false
 }
 }
 func finish(){stop();UserDefaults.standard.set(2,forKey:"onboardingVersion");UserDefaults.standard.set(results.mapValues(\.rawValue),forKey:"onboardingResults")}
}
struct OnboardingView:View {
 @ObservedObject var controller:OnboardingController
 @ObservedObject var agent:AgentOrchestrator
 @AppStorage("speechVoice") private var voice="michael"
 let close:()->Void
 private var heading:String{switch controller.step{case .welcome:return "Meet Voicey";case .voice:return "Make it sound like you";case .microphone:return "Let's hear you";case .shortcut:return "One shortcut. Ready to listen.";case .commands:return "Try your first conversation";case .finish:return "You're ready to get started"}}
 private var subtitle:String{switch controller.step{case .welcome:return "A private voice assistant, right on your Mac.";case .voice:return "Michael is ready. Pick another voice anytime.";case .microphone:return "Check your microphone with a quick phrase.";case .shortcut:return "Hold Control, Option and Command to talk.";case .commands:return "Say hello, then try a simple Mac action.";case .finish:return "Here's what you've checked on this Mac."}}
 var body:some View {
 VStack(spacing:0){
 HStack{Label("Voicey",systemImage:"waveform").fontWeight(.semibold);Spacer();Button("Set Up Later"){controller.finish();close()}.buttonStyle(.plain).foregroundStyle(.secondary)}.padding(.horizontal,28).padding(.top,18)
 ScrollView{
 VStack(spacing:18){
 Image(systemName:controller.step.icon).font(.system(size:34,weight:.medium)).foregroundStyle(Color.accentColor).frame(width:76,height:76).background(.regularMaterial,in:RoundedRectangle(cornerRadius:22)).overlay{RoundedRectangle(cornerRadius:22).stroke(.quaternary,lineWidth:1)}.accessibilityHidden(true)
 VStack(spacing:8){Text(heading).font(.system(size:26,weight:.semibold)).multilineTextAlignment(.center);Text(subtitle).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)}
 VStack(alignment:.leading,spacing:16){stepContent
 if !controller.detail.isEmpty{Text(controller.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)}
 }.frame(maxWidth:470,alignment:.leading).padding(20).background(.background,in:RoundedRectangle(cornerRadius:16)).overlay{RoundedRectangle(cornerRadius:16).stroke(.quaternary,lineWidth:1)}
 }.frame(maxWidth:.infinity).padding(.horizontal,28).padding(.top,22).padding(.bottom,20)
 }
 HStack(spacing:6){ForEach(SetupStep.allCases){step in Capsule().fill(step == controller.step ? Color.accentColor:Color.secondary.opacity(0.2)).frame(width:step == controller.step ? 20:6,height:6)}}.accessibilityLabel("Step \(controller.step.rawValue+1) of 6").padding(.bottom,14)
 HStack{
 if controller.step != .welcome{Button("Back"){controller.move(SetupStep(rawValue:controller.step.rawValue-1)!)}.keyboardShortcut(.leftArrow,modifiers:.command)}
 Spacer()
 Button(controller.step == .finish ? "Start Using Voicey":controller.step == .welcome ? "Get Started":"Continue"){
 if controller.step == .finish{controller.finish();close()}else{controller.move(SetupStep(rawValue:controller.step.rawValue+1)!)}
 }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
 }.padding(.horizontal,28).padding(.bottom,22)
 }.frame(minWidth:640,minHeight:560).background(Color(nsColor:.windowBackgroundColor))
 .onChange(of:agent.state){_,_ in controller.observeState()}
 .onChange(of:agent.shortcutActivations){_,_ in controller.observeState()}
 .onDisappear{controller.stop()}
 }
 @ViewBuilder private var stepContent:some View {
 switch controller.step {
 case .welcome:
 Label("Natural voices, entirely offline",systemImage:"speaker.wave.2")
 Label("Listen first. Reply after you speak.",systemImage:"mic")
 Label("Apps, files and supported Mac actions",systemImage:"cursorarrow")
 Text("Hold ⌃⌥⌘ to start listening. Voicey responds after you speak.").fontWeight(.medium)
 Text("Speech and reasoning stay on this Mac. This walkthrough does not send messages or submit anything to a website.").font(.caption).foregroundStyle(.secondary)
 case .voice:
 Text("Choose a voice, then listen to the preview.")
 Picker("Voice",selection:$voice){ForEach(NeuralVoice.allCases){Text($0.title).tag($0.rawValue)}}.onChange(of:voice){_,_ in controller.stop()}
 HStack{Button("Play Preview"){controller.preview()}.disabled(controller.working);Button("Stop"){controller.stop()}.disabled(!controller.working)}
 if controller.speakerFinished{HStack{Button("Sounds Good"){controller.confirmSpeaker(true)};Button("Try Again"){controller.confirmSpeaker(false)}}}
 result("Speaker")
 case .microphone:
 Text("Say “Can you hear me clearly?” We will show the transcript for you to check. This test does not run commands.")
 LabeledContent("Microphone permission"){Text(AVCaptureDevice.authorizationStatus(for:.audio) == .authorized ? "Allowed":"Not enabled")}
 HStack{Button(controller.working ? "Listening…":"Start Microphone Test"){controller.microphone()}.disabled(controller.working);if agent.state == .listening{Button("Finish Recording"){agent.finishListening()}}}
 if controller.working{ProgressView(agent.state == .transcribing ? "Transcribing locally…":"Speak now").controlSize(.small)}
 if !controller.heard.isEmpty{GroupBox("Heard on your Mac"){Text(controller.heard).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)};HStack{Button("Transcript Is Correct"){controller.confirmMicrophone(true)};Button("Try Again"){controller.microphone()}}}
 result("Microphone")
 case .shortcut:
 Text("Test the actual Control + Option + Command shortcut. Enable Input Monitoring if macOS needs it, then return here and arm the test.")
 Button("Allow Keyboard Monitoring…"){agent.hotkey.requestPermission()}
 Button("Open Input Monitoring Settings…"){NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)}
 Button(controller.waitingForShortcut ? "Waiting for ⌃⌥⌘…":"Arm Shortcut Test"){agent.hotkey.start();controller.armShortcut()}.disabled(controller.waitingForShortcut)
 LabeledContent("Recording state"){Text(agent.state == .listening ? "Listening":"Not recording")}
 result("Shortcut")
 case .commands:
 HStack{Button("Record a Greeting"){controller.conversation()}.disabled(controller.working);result("Conversation")}
 if controller.result("Conversation") == .confirm {HStack{Button("I Heard the Reply"){controller.confirmConversation(true)};Button("No Reply"){controller.confirmConversation(false)}}}
 if controller.result("Conversation") == .passed{Text("Hi! I'm Voicey. What would you like to do?").font(.callout).foregroundStyle(.secondary)}
 Button("Open Model Settings…"){UserDefaults.standard.set("models",forKey:"settingsPane");AppDelegate.current?.settings()}
 GroupBox("Natural language") {VStack(alignment:.leading,spacing:12){Text("“Could you please bring up the Calculator application for me?”").foregroundStyle(.secondary);Button("Record a Request"){controller.understanding()}.disabled(controller.working);result("Understanding");if controller.result("Understanding") == .confirm {HStack{Button("That Matches"){controller.confirmUnderstanding(true)};Button("Try Again"){controller.confirmUnderstanding(false)}}}}.frame(maxWidth:.infinity,alignment:.leading).padding(8)}
 GroupBox("App action") {VStack(alignment:.leading,spacing:12){Text("Send “Launch Calculator” through Voicey's normal command path and verify that Calculator is running.").foregroundStyle(.secondary);Button("Open Calculator & Verify"){controller.appAction()}.disabled(controller.working);result("App action")}.frame(maxWidth:.infinity,alignment:.leading).padding(8)}
 if controller.working{ProgressView().controlSize(.small)}
 case .finish:
 Text("Your test results").font(.headline)
 ForEach(["Speaker","Microphone","Shortcut","Conversation","Understanding","App action"],id:\.self){key in LabeledContent(key){result(key)}}
 Text("Only completed, verified checks show Passed. You can repeat this walkthrough from Voicey → Test Voicey or Settings → General.").font(.caption).foregroundStyle(.secondary)
 }
 }
 private func result(_ key:String)->some View {
 let value=controller.result(key)
 return Label(value.rawValue,systemImage:value == .passed ? "checkmark.circle.fill":value == .failed ? "exclamationmark.circle":"circle").font(.callout).foregroundStyle(value == .passed ? Color.green:value == .failed ? Color.orange:Color.secondary)
 }
}
