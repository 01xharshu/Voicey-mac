import SwiftUI
import Combine
import AppKit
import AVFoundation
import ServiceManagement
import VoiceyCore
typealias ViewState<Value> = SwiftUI.State<Value>

@main struct VoiceyApp:App {
 @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
 var body:some Scene {
 Settings{SettingsView(agent:delegate.agent).frame(minWidth:740,minHeight:580)}
 .commands{CommandGroup(after:.appInfo){Button("Test Voicey…"){delegate.onboarding()};Button("Type a command"){delegate.typeCommand()}.keyboardShortcut("v",modifiers:[.command,.shift]);Button("Talk to Voicey"){delegate.activate()}}}
 }
}
@MainActor final class AppDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
 static weak var current:AppDelegate?
 let agent=AgentOrchestrator()
 private var panel:FloatingPanelController?,item:NSStatusItem?
 private var settingsWindow:NSWindow?
 private var onboardingWindow:NSWindow?
 private var onboardingController:OnboardingController?
 func applicationDidFinishLaunching(_ notification:Notification){
 Self.current=self
 if CommandLine.arguments.contains("--neural-speech-self-test") {
 Task {let result=await SpeechNativeChecks.runNeural();fflush(stdout);exit(result)};return
 }
 if CommandLine.arguments.contains("--speech-self-test") {
 Task {let result=await SpeechNativeChecks.run();fflush(stdout);exit(result)};return
 }
 if CommandLine.arguments.contains("--computer-self-test") {
 Task {let result=await ComputerNativeChecks.run();fflush(stdout);exit(result)};return
 }
 NSApp.setActivationPolicy(.accessory)
 panel=FloatingPanelController(agent:agent)
 agent.showPanel={[weak self] in self?.panel?.show()};agent.hidePanel={[weak self] in self?.panel?.hide()}
 item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength);item?.button?.image=NSImage(systemSymbolName:"waveform.circle",accessibilityDescription:"Voicey")
 let menu=NSMenu();menu.addItem(withTitle:"Talk to Voicey",action:#selector(activate),keyEquivalent:"");menu.addItem(withTitle:"Type a command",action:#selector(typeCommand),keyEquivalent:"");menu.addItem(.separator());menu.addItem(withTitle:"Test Voicey…",action:#selector(onboarding),keyEquivalent:"");menu.addItem(withTitle:"Settings…",action:#selector(settings),keyEquivalent:",");menu.addItem(withTitle:"Quit Voicey",action:#selector(quit),keyEquivalent:"q");menu.items.forEach{$0.target=self};item?.menu=menu
 agent.start()
 if UserDefaults.standard.integer(forKey:"onboardingVersion")<2{onboarding();UserDefaults.standard.set(true,forKey:"onboarded")}

 }
 func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool{typeCommand();return false}
 @objc func activate(){agent.activate()}
 @objc func typeCommand(){panel?.show();panel?.focus();NotificationCenter.default.post(name:Notification.Name("VoiceyTextInput"),object:nil)}
 @objc func settings(){
 if settingsWindow==nil{let window=NSWindow(contentRect:NSRect(x:0,y:0,width:860,height:660),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false);window.title="Voicey Settings";window.isReleasedWhenClosed=false;window.minSize=NSSize(width:740,height:580);window.contentView=NSHostingView(rootView:SettingsView(agent:agent));window.center();settingsWindow=window}
 NSApp.activate(ignoringOtherApps:true);settingsWindow?.makeKeyAndOrderFront(nil)
 }
 @objc func onboarding(){
 agent.dismiss()
 if onboardingWindow==nil{
 let controller=OnboardingController(agent:agent);onboardingController=controller
 let window=NSWindow(contentRect:NSRect(x:0,y:0,width:700,height:650),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
 window.title="Set Up Voicey";window.titlebarAppearsTransparent=true;window.delegate=self;window.isReleasedWhenClosed=false;window.minSize=NSSize(width:640,height:560)
 window.contentView=NSHostingView(rootView:OnboardingView(controller:controller,agent:agent,close:{[weak self] in self?.onboardingWindow?.close()}));window.center();onboardingWindow=window
 }
 NSApp.activate(ignoringOtherApps:true);onboardingWindow?.makeKeyAndOrderFront(nil)
 }
 func windowWillClose(_ notification:Notification){if let window=notification.object as? NSWindow,window===onboardingWindow{onboardingController?.stop()}}
 func restart(){
 let configuration=NSWorkspace.OpenConfiguration();configuration.createsNewApplicationInstance=true
 NSWorkspace.shared.openApplication(at:Bundle.main.bundleURL,configuration:configuration){_,error in
 guard error==nil else{return};DispatchQueue.main.async{NSApp.terminate(nil)}
 }
 }
 @objc func quit(){agent.stop();NSApp.terminate(nil)}
}
final class CompanionPanel:NSPanel { override var canBecomeKey:Bool { true } }
@MainActor final class FloatingPanelController {
 private let panel:NSPanel
 private let hosting:NSHostingView<CompanionView>
 private var observation:AnyCancellable?
 private var screen:NSScreen?
 private var outsideGlobalMonitor:Any?
 private var outsideLocalMonitor:Any?
 private weak var agent:AgentOrchestrator?
 init(agent:AgentOrchestrator){
 self.agent=agent
 panel=CompanionPanel(contentRect:NSRect(x:0,y:0,width:380,height:500),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
 panel.level = .statusBar;panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true;panel.isMovableByWindowBackground=false;panel.hidesOnDeactivate=false
 hosting=NSHostingView(rootView:CompanionView(agent:agent));hosting.sizingOptions = [.intrinsicContentSize];panel.contentView=hosting;panel.isReleasedWhenClosed=false
 observation=agent.objectWillChange.sink{[weak self] _ in DispatchQueue.main.async{self?.resizeAndPosition()}}
 }
 private func resizeAndPosition(){
 guard panel.isVisible else{return}
 hosting.invalidateIntrinsicContentSize();hosting.layoutSubtreeIfNeeded()
 let ideal=hosting.intrinsicContentSize
 let screen=screen ?? NSScreen.main
 let available=screen?.frame ?? NSRect(x:0,y:0,width:1200,height:800)
 let height=min(max(ideal.height,220),available.height-24)
 panel.setContentSize(NSSize(width:max(260,ideal.width),height:height))
 // Attach the black surface to the physical screen edge, including the hardware notch row.
 panel.setFrameOrigin(NSPoint(x:available.midX-panel.frame.width/2,y:available.maxY-panel.frame.height))
 }
 func show(){screen=NSScreen.screens.first{$0.frame.contains(NSEvent.mouseLocation)} ?? NSScreen.main;panel.orderFrontRegardless();installOutsideClickMonitors();resizeAndPosition();DispatchQueue.main.async{[weak self] in self?.resizeAndPosition()}}
 func focus(){panel.makeKey();NSApp.activate(ignoringOtherApps:true)}
 private func installOutsideClickMonitors(){
 guard outsideGlobalMonitor==nil,outsideLocalMonitor==nil else{return}
 outsideGlobalMonitor=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]){[weak self] _ in
 Task{@MainActor in guard let self,self.panel.isVisible,!self.panel.frame.contains(NSEvent.mouseLocation) else{return};self.agent?.dismiss()}
 }
 outsideLocalMonitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]){[weak self] event in
 MainActor.assumeIsolated{guard let self,self.panel.isVisible,event.window !== self.panel else{return};if !self.panel.frame.contains(NSEvent.mouseLocation){self.agent?.dismiss()}}
 return event
 }
 }
 func hide(){panel.orderOut(nil);if let outsideGlobalMonitor{NSEvent.removeMonitor(outsideGlobalMonitor)};if let outsideLocalMonitor{NSEvent.removeMonitor(outsideLocalMonitor)};outsideGlobalMonitor=nil;outsideLocalMonitor=nil}
}

struct VoiceyGlow:View {
 let state:AssistantState,level:Float
 @Environment(\.accessibilityReduceMotion) private var reduced
 private var tint:Color {switch state{case .success:return .mint;case .error,.missing:return .orange;default:return .cyan}}
 private var busy:Bool{[.thinking,.transcribing,.executing].contains(state)}
 var body:some View {
 TimelineView(.animation(minimumInterval:1.0/30,paused:reduced || state == .idle)){time in
 let t=reduced ? 0:time.date.timeIntervalSinceReferenceDate
 let breathe=1+sin(t*(state == .listening ? 3:1.4))*0.055
 let response=state == .listening ? min(CGFloat(level)*3,0.3):0
 ZStack {
 Circle().fill(RadialGradient(colors:[tint.opacity(0.3),.indigo.opacity(0.13),.clear],center:.center,startRadius:25,endRadius:95)).frame(width:190,height:190).scaleEffect(breathe+response)
 Circle().fill(Color.black.opacity(0.65)).frame(width:100,height:100)
 ForEach(0..<3){i in
 Ellipse().fill(RadialGradient(colors:[i == 0 ? Color.cyan:i == 1 ? Color.purple:Color.blue,.clear],center:.center,startRadius:5,endRadius:55))
 .frame(width:90,height:65).offset(x:CGFloat(cos(t*0.7+Double(i)*2.1))*15,y:CGFloat(sin(t*0.9+Double(i)*2.1))*15).blur(radius:11).blendMode(.screen)
 }
 Circle().stroke(AngularGradient(colors:[.cyan.opacity(0.1),tint,.indigo,.purple,.cyan.opacity(0.1)],center:.center),lineWidth:2).frame(width:104,height:104).rotationEffect(.degrees(t*(busy ? 100:25))).shadow(color:tint.opacity(0.8),radius:12)
 Circle().fill(RadialGradient(colors:[.white.opacity(0.75),tint.opacity(0.4),.clear],center:.topLeading,startRadius:0,endRadius:70)).frame(width:88,height:88).blur(radius:4).opacity(state == .listening ? 0.7:0.38)
 if state == .listening {
 HStack(spacing:3){ForEach(0..<7){i in Capsule().fill(.white.opacity(0.9)).frame(width:3,height:8+CGFloat(abs(sin(t*4+Double(i))))*(8+CGFloat(level)*100))}}.frame(height:40)
 }
 }.frame(width:190,height:180)
 }
 .accessibilityLabel("Voicey \(state.rawValue)")
 }
}
struct NotchSurface:Shape {
 func path(in rect:CGRect)->Path {
 let r:CGFloat=24
 var p=Path();p.move(to:CGPoint(x:0,y:0));p.addLine(to:CGPoint(x:rect.maxX,y:0));p.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY-r));p.addQuadCurve(to:CGPoint(x:rect.maxX-r,y:rect.maxY),control:CGPoint(x:rect.maxX,y:rect.maxY));p.addLine(to:CGPoint(x:r,y:rect.maxY));p.addQuadCurve(to:CGPoint(x:0,y:rect.maxY-r),control:CGPoint(x:0,y:rect.maxY));p.closeSubpath();return p
 }
}
struct CompanionView:View {
 @ObservedObject var agent:AgentOrchestrator
 @FocusState private var textFocused:Bool
 @ViewState private var showText=false
 private var notchInset:CGFloat{let display=NSScreen.screens.first{$0.frame.contains(NSEvent.mouseLocation)} ?? NSScreen.main;return max(display?.safeAreaInsets.top ?? 0,24)}
 private var expanded:Bool{showText || agent.pending != nil || agent.computerTask?.status == .running || [.success,.error,.missing].contains(agent.state)}
 private var status:String{switch agent.state{case .idle:return "Ready when you are";case .greeting:return "I'm here";case .listening:return "Listening";case .transcribing:return "Hearing you";case .thinking:return "Thinking";case .executing:return "On it";case .success:return "Done";case .error:return "Let's try again";case .missing:return "Let's get ready";case .clarification,.confirmation:return "A quick check";case .browser:return "Choose your browser";case .results:return "Here's what I found"}}
 var body:some View {
 VStack(spacing:8){
 HStack{Text("voicey").font(.system(.caption,design:.rounded).weight(.semibold)).foregroundStyle(.white.opacity(0.6));Spacer();Button{agent.dismiss()}label:{Image(systemName:"xmark").font(.caption2)}.buttonStyle(.plain).help("Dismiss · Escape")}
 Button{if agent.state == .listening{agent.finishListening()}else{agent.listen()}}label:{VoiceyGlow(state:agent.state,level:agent.level).scaleEffect(0.65).frame(width:140,height:120)}.buttonStyle(.plain).help(agent.state == .listening ? "Finish speaking":"Speak to Voicey")
 HStack(spacing:6){Circle().fill(agent.state == .listening ? Color.cyan:Color.white.opacity(0.5)).frame(width:5,height:5);Text(status).font(.system(.caption,design:.rounded).weight(.medium)).foregroundStyle(.white.opacity(0.8))}
 if expanded {Text(agent.message).font(.system(.callout,design:.rounded)).foregroundStyle(.white.opacity(0.9)).multilineTextAlignment(.center).textSelection(.enabled).padding(.top,8)}
 if !agent.transcript.isEmpty && (expanded || agent.state == .thinking){Text(agent.transcript).font(.caption2).foregroundStyle(.white.opacity(0.5)).lineLimit(3)}
 if let pending=agent.pending {
 switch pending {
 case .website(let url,_):Text(url.absoluteString).font(.caption.monospaced()).textSelection(.enabled).padding(10).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:10));HStack{Button("Open"){agent.approveWebsite()}.buttonStyle(.borderedProminent);Button("Change"){agent.changeWebsite();showText=true};Button("Cancel"){agent.cancel()}}.font(.caption)
 case .browser(let url):ScrollView{VStack{ForEach(agent.apps){app in Button{agent.openWebsite(url,browser:app)}label:{appRow(app)}}}}.frame(maxHeight:140)
 case .apps(let intent,_):ScrollView{VStack{ForEach(agent.apps){app in Button{agent.selectApp(app,intent:intent)}label:{appRow(app)}}}}.frame(maxHeight:140)
 case .files(let intent,_):ScrollView{VStack(alignment:.leading){ForEach(agent.results){result in Button{agent.selectFile(result,intent:intent)}label:{VStack(alignment:.leading){Text(result.url.lastPathComponent).font(.caption.bold());Text(result.url.path).font(.caption2).foregroundStyle(.white.opacity(0.5)).lineLimit(2)}.frame(maxWidth:.infinity,alignment:.leading).padding(5)}}}}.frame(maxHeight:150)
 case .computer:
 HStack{Button(agent.computer.pending?.kind == .approval ? "Approve":"Continue"){agent.submit("continue")}.buttonStyle(.borderedProminent);Button("Cancel"){agent.cancel()}}
 case .workflow:EmptyView()
 case .destination:EmptyView()
 }
 }
 if let task=agent.computerTask {
 DisclosureGroup("Task details · \(task.steps.filter{$0.status == .verified}.count)/\(task.steps.count)"){
 ScrollView{VStack(alignment:.leading,spacing:8){
 Text(task.originalRequest).font(.caption).textSelection(.enabled)
 Text("Goal: \(task.intention)").font(.caption)
 ForEach(task.steps){step in VStack(alignment:.leading){Text("\(step.status.rawValue) · \(step.title)").font(.caption.bold());if !step.arguments.application.isEmpty{Text(step.arguments.application).font(.caption2)};if let evidence=step.evidence{Text("\(evidence.state.rawValue): \(evidence.detail)").font(.caption2).textSelection(.enabled)}}}
 Button("Cancel task"){agent.cancel()}
 }}.frame(maxHeight:180)
 }.font(.caption)
 }
 if showText {
 HStack{TextField("Tell Voicey…",text:$agent.input,axis:.vertical).lineLimit(1...3).textFieldStyle(.plain).focused($textFocused).onSubmit{agent.submitInput()};Button{agent.submitInput()}label:{Image(systemName:"arrow.up.circle.fill")}.buttonStyle(.plain).disabled(agent.input.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}.font(.callout).padding(10).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:12))
 }
 HStack(spacing:20){
 Button{showText.toggle();textFocused=showText}label:{Image(systemName:"keyboard")}.help("Type a command")
 Button{agent.cancel()}label:{Image(systemName:"stop.circle")}.help("Cancel")
 Button{AppDelegate.current?.settings()}label:{Image(systemName:"gearshape")}.help("Settings")
 }.buttonStyle(.plain).font(.caption).foregroundStyle(.white.opacity(0.45)).padding(.top,8)
 }.padding(.horizontal,18).padding(.bottom,16).padding(.top,notchInset+6).frame(width:expanded ? 340:240).fixedSize(horizontal:false,vertical:true)
 .background{NotchSurface().fill(Color.black)}.foregroundStyle(.white)
 .onExitCommand{agent.dismiss()}
 .onReceive(NotificationCenter.default.publisher(for:Notification.Name("VoiceyTextInput"))){_ in showText=true;textFocused=true}
 .onReceive(NotificationCenter.default.publisher(for:Notification.Name("VoiceyVoiceInput"))){_ in showText=false;textFocused=false}
 }
 private func appRow(_ app:InstalledApp)->some View{HStack{Image(nsImage:app.icon).resizable().frame(width:24,height:24);Text(app.name);Spacer()}.padding(6)}
}


struct SpeechPreviewControls:View {
 @ObservedObject var tts:SpeechSynthesisService
 let voiceID:String,rate:Float
 var body:some View{VStack(alignment:.leading){
 HStack{Button("Test voice"){tts.speak("Hi, I'm Voicey. What would you like to work on? I can help you find a file, check your project, or get something done in your browser.",voice:voiceID,rate:rate)};Button("Stop preview"){tts.stop()}}
 Text(tts.status).font(.caption).textSelection(.enabled)
 }}
}
