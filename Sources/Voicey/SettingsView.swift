import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import VoiceyCore

private enum SettingsPane:String,CaseIterable,Identifiable {
 case general,voice,models,computer,browsers,files,memory,communication,privacy
 var id:String{rawValue}
 var title:String{switch self{case .general:return "General";case .voice:return "Voice";case .models:return "Local Models";case .computer:return "Computer Use";case .browsers:return "Browsers";case .files:return "Files";case .memory:return "Memory";case .communication:return "Communication";case .privacy:return "Privacy"}}
 var icon:String{switch self{case .general:return "gearshape";case .voice:return "waveform";case .models:return "cpu";case .computer:return "cursorarrow";case .browsers:return "globe";case .files:return "folder";case .memory:return "brain";case .communication:return "message";case .privacy:return "hand.raised"}}
}
struct SettingsView:View {
 @ObservedObject var agent:AgentOrchestrator
 @ObservedObject private var permissions=PermissionStatus.shared
 @AppStorage("settingsPane") private var selected="general"
 @AppStorage("speechRate") private var speechRate=Double(AVSpeechUtteranceDefaultSpeechRate)
 @AppStorage("speechVoice") private var speechVoice="michael"
 @AppStorage("voiceID") private var voiceID=""
 @AppStorage("language") private var language="en"
 @AppStorage("listenTimeout") private var timeout=20.0
 @AppStorage("idleDismissal") private var dismissal=12.0
 @AppStorage("reviewTranscript") private var review=false
 @AppStorage("hiddenFiles") private var hidden=false
 @AppStorage("rememberBrowser") private var rememberBrowser=false
 @AppStorage("spokenResponses") private var spoken=true
 @AppStorage("fallbackKey") private var fallbackKey=49
 @AppStorage("modelIdleSeconds") private var modelIdleSeconds=120
 @AppStorage("primaryActivationGesture") private var primaryActivationGesture="tripleModifiers"
 @ViewState private var phrase=""
 @ViewState private var target=""
 @ViewState private var category="alias"
 @ViewState private var feedback=""
 @ViewState private var removeModels=false
 @ViewState private var clearPersonalization=false
 private var pane:SettingsPane{SettingsPane(rawValue:selected) ?? .general}
 var body:some View {
 NavigationSplitView {
 List(selection:Binding<SettingsPane?>(get:{pane},set:{if let value=$0{selected=value.rawValue}})) {
 Section("Voicey") {ForEach([SettingsPane.general,.voice,.models]){item in Label(item.title,systemImage:item.icon).tag(item)}}
 Section("Workspace") {ForEach([SettingsPane.computer,.browsers,.files,.memory,.communication]){item in Label(item.title,systemImage:item.icon).tag(item)}}
 Section {Label(SettingsPane.privacy.title,systemImage:SettingsPane.privacy.icon).tag(SettingsPane.privacy)}
 }.listStyle(.sidebar).navigationSplitViewColumnWidth(min:170,ideal:195,max:230)
 } detail: {
 content.navigationTitle(pane.title)
 }
 .navigationSplitViewStyle(.balanced).onAppear{permissions.begin()}.onDisappear{permissions.end()}
 .confirmationDialog("Remove downloaded recognition and language models?",isPresented:$removeModels){Button("Remove models",role:.destructive){agent.removeModels()}}message:{Text("Neural voices remain available. You can download the other models again later.")}
 .confirmationDialog("Clear saved aliases and corrections?",isPresented:$clearPersonalization){Button("Clear personalization",role:.destructive){do{try agent.memory?.clear();agent.memories=[]}catch{agent.memoryError=error.localizedDescription}}}
 }
 @ViewBuilder private var content:some View {
 switch pane {
 case .general:general
 case .voice:voice
 case .models:models
 case .computer:ComputerUseSettings(agent:agent).formStyle(.grouped)
 case .browsers:browsers
 case .files:files
 case .memory:memory
 case .communication:CommunicationSettings(controller:agent.communication).formStyle(.grouped)
 case .privacy:privacy
 }
 }
 private var general:some View {
 Form {
 Section("Activation") {
 Picker("Talk to Voicey",selection:$primaryActivationGesture){Text("⌃⌥⌘ Control + Option + Command").tag("tripleModifiers");Text("Left + right Command").tag("dualCommand")}.onChange(of:primaryActivationGesture){_,_ in agent.hotkey.start()}
 Picker("Alternative shortcut",selection:$fallbackKey){Text("⌥⌘Space").tag(49);Text("⌥⌘V").tag(9)}.onChange(of:fallbackKey){_,_ in agent.hotkey.start()}
 Text("Hold the keys together. Voicey activates once per hold.").font(.caption).foregroundStyle(.secondary)
 if !permissions.keyboard {
 LabeledContent("Keyboard access"){Text("Needs permission").foregroundStyle(.orange)}
 Button("Allow Keyboard Monitoring…"){agent.hotkey.requestPermission();agent.objectWillChange.send()}
 Button("Open Input Monitoring Settings…"){openPrivacy("ListenEvent")}
 }
 }
 Section("Conversation") {
 Text("The shortcut starts listening immediately. Voicey replies after it understands your request.").font(.caption).foregroundStyle(.secondary)
 Toggle("Speak replies",isOn:$spoken)
 LabeledContent("Dismiss after"){HStack{Slider(value:$dismissal,in:5...60).frame(maxWidth:190).accessibilityLabel("Dismiss after");Text("\(Int(dismissal)) sec").monospacedDigit().frame(width:52,alignment:.trailing)}}
 }
 Section("Setup & Testing") {Button("Test Voicey…"){AppDelegate.current?.onboarding()}}
 Section("Startup") {
 Toggle("Open Voicey at login",isOn:Binding(get:{SMAppService.mainApp.status == .enabled},set:{enabled in do{if enabled{try SMAppService.mainApp.register()}else{try SMAppService.mainApp.unregister()};feedback="Login setting updated."}catch{feedback=error.localizedDescription}}))
 if !feedback.isEmpty{Text(feedback).font(.caption).foregroundStyle(.secondary)}
 }
 }.formStyle(.grouped)
 }
 private var voice:some View {
 Form {
 Section {
 Picker("Speaking voice",selection:$speechVoice){ForEach(NeuralVoice.allCases){Text($0.title).tag($0.rawValue)}}.onChange(of:speechVoice){_,_ in agent.tts.stop()}
 if speechVoice=="system" {
 Picker("System voice",selection:$voiceID){Text("Automatic").tag("");ForEach(AVSpeechSynthesisVoice.speechVoices(),id:\.identifier){Text("\($0.name) · \($0.language)").tag($0.identifier)}}
 }
 LabeledContent("Speaking speed"){HStack{Text("Slower").font(.caption).foregroundStyle(.secondary);Slider(value:$speechRate,in:0.25...0.65).frame(maxWidth:220).accessibilityLabel("Speaking speed");Text("Faster").font(.caption).foregroundStyle(.secondary)}}
 SpeechPreviewControls(tts:agent.tts,voiceID:voiceID,rate:Float(speechRate))
 } header:{Text("Voice & Playback")} footer:{Text("Neural voices speak English and work offline. Hindi replies use an installed Hindi system voice.")}
 Section("Listening") {
 Picker("Recognition language",selection:$language){Text("English").tag("en");Text("Hindi").tag("hi");Text("Automatic").tag("auto")}
 LabeledContent("Listening timeout"){HStack{Slider(value:$timeout,in:5...60).frame(maxWidth:220).accessibilityLabel("Listening timeout");Text("\(Int(timeout)) sec").monospacedDigit().frame(width:52,alignment:.trailing)}}
 Toggle("Review transcript before taking action",isOn:$review)
 }
 Section {
 LabeledContent("Microphone"){Label(microphoneStatus,systemImage:permissions.microphone == .authorized ? "checkmark.circle.fill":"mic.slash").foregroundStyle(permissions.microphone == .authorized ? Color.secondary:Color.orange)}
 if permissions.microphone == .notDetermined {
 Button("Allow Microphone Access…"){Task{_ = await AVCaptureDevice.requestAccess(for:.audio);agent.objectWillChange.send()}}
 }else if permissions.microphone != .authorized{
 Button("Open Microphone Settings…"){openPrivacy("Microphone")}
 }
 } header:{Text("Permission")} footer:{Text("Audio stays on your Mac. Voicey listens before replying.")}
 }.formStyle(.grouped)
 }
 private var models:some View {
 Form {
 Section("Recognition & Reasoning") {
 LabeledContent("Language model"){Text("Qwen3 · 1.28 GB")}
 LabeledContent("Speech recognition"){Text("Whisper · 148 MB")}
 Text(agent.modelStatus).font(.callout).textSelection(.enabled)
 if agent.downloading{ProgressView(value:agent.modelProgress);Button("Cancel download"){agent.cancelDownload()}}
 HStack{Button("Download Models"){agent.downloadModels()};Menu("Import…"){Button("Language model…"){agent.importModel(.llm)};Button("Speech model…"){agent.importModel(.speech)}}}.disabled(agent.downloading)
 }
 Section("Memory Usage") {
 Picker("Release idle models after",selection:$modelIdleSeconds){Text("30 seconds").tag(30);Text("2 minutes").tag(120);Text("5 minutes").tag(300)}
 Text("Shorter intervals save memory. The next request may take longer to start.").font(.caption).foregroundStyle(.secondary)
 Button("Release Models Now"){Task{await agent.engine.unload();await agent.tts.neural.unload()}}
 }
 Section("Storage") {
 LabeledContent("Neural voices"){Text("Included · available offline")}
 Button("Show Model Folder…"){NSWorkspace.shared.activateFileViewerSelecting([supportDirectory.appendingPathComponent("Models")])}
 Button("Remove Downloaded Models…",role:.destructive){removeModels=true}.disabled(agent.downloading)
 }
 DisclosureGroup("Model details") {
 Text("Recognition and language models run in-process using whisper.cpp and llama.cpp. Imported files must use compatible GGML or GGUF formats. Michael, Heart, Bella and Emma use the bundled Kokoro model. No cloud inference fallback.").font(.caption).foregroundStyle(.secondary)
 }
 }.formStyle(.grouped)
 }
 private var files:some View {
 Form {
 Section("Search") {Toggle("Include hidden files",isOn:$hidden);Text("Voicey searches Desktop, Documents and Downloads, plus folders you authorize.").font(.caption).foregroundStyle(.secondary)}
 Section("Authorized Folders") {ForEach(agent.searchScopes(),id:\.path){url in Label(url.lastPathComponent,systemImage:"folder").help(url.path)};Button("Add Folder…"){agent.addScope()};Button("Remove Additional Folders"){UserDefaults.standard.removeObject(forKey:"folderBookmarks");agent.objectWillChange.send()}}
 Section {Text("Search reads file names and metadata. It does not read file contents or retain a permanent index.").font(.caption).foregroundStyle(.secondary)}
 }.formStyle(.grouped)
 }
 private var browsers:some View {
 Form {
 Section("Browser Choice") {
 Toggle("Remember my browser choice",isOn:$rememberBrowser)
 Picker("Preferred browser",selection:Binding(get:{agent.memory?.document.preferredBrowser ?? ""},set:{value in do{try agent.memory?.browser(value.isEmpty ? nil:value);agent.objectWillChange.send()}catch{agent.memoryError=error.localizedDescription}})){Text("Ask each time").tag("");ForEach(agent.discovery.browsers()){Text($0.name).tag($0.bundleID)}}
 }
 Section {Text("A browser named in your request takes priority. Voicey keeps your Mac's default browser unchanged. Approved website actions share the content you authorize with that website.").font(.caption).foregroundStyle(.secondary)}
 }.formStyle(.grouped)
 }
 private var memory:some View {
 Form {
 Section("Saved Memories") {
 if agent.memories.isEmpty{Text("No aliases or corrections saved yet.").foregroundStyle(.secondary)}
 ForEach(agent.memories){entry in HStack{VStack(alignment:.leading,spacing:4){Text(entry.phrase).fontWeight(.medium);Text(entry.target).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)};Spacer();Button("Delete",role:.destructive){agent.removeMemory(entry)}}}
 }
 Section("Add a Memory") {
 Picker("Type",selection:$category){Text("Alias").tag("alias");Text("Transcript correction").tag("correction")}
 TextField("Phrase",text:$phrase)
 TextField(category=="alias" ? "Path, app or URL":"Corrected phrase",text:$target)
 HStack{Button("Save Memory"){agent.saveMemory(phrase:phrase,target:target,category:category);phrase="";target=""}.disabled(phrase.trimmingCharacters(in:.whitespaces).isEmpty || target.trimmingCharacters(in:.whitespaces).isEmpty)
 Button("Replace Existing"){if let entry=agent.memories.first(where:{$0.phrase==phrase && $0.category==category}){do{try agent.memory?.remember(MemoryEntry(phrase:phrase,target:target,category:category),replace:true);agent.memories=agent.memory?.document.entries ?? []}catch{agent.memoryError=error.localizedDescription}}}.disabled(!agent.memories.contains{$0.phrase==phrase && $0.category==category})}
 if let error=agent.memoryError{Text(error).font(.caption).foregroundStyle(.orange)}
 }
 Section{Text("Voicey remembers only what you explicitly save. These entries stay on your Mac.").font(.caption).foregroundStyle(.secondary)}
 }.formStyle(.grouped)
 }
 private var privacy:some View {
 Form {
 Section("On Your Mac") {
 Label("Speech and reasoning run locally",systemImage:"checkmark.shield")
 Text("Microphone audio and generated speech stay in memory. Voicey has no account, analytics or cloud inference service.").font(.callout)
 }
 Section("Website Actions") {Text("Questions submitted to ChatGPT, Gmail drafts and other approved website actions share the authorized content with that website.")}
 Section("Saved Data") {Text("Only explicit memories and brief task summaries are stored. Audio, screenshots and task payloads are not saved in those summaries.");Button("Show Local Data…"){NSWorkspace.shared.activateFileViewerSelecting([supportDirectory])};Button("Clear Personalization…",role:.destructive){clearPersonalization=true}}
 }.formStyle(.grouped)
 }
 private var microphoneStatus:String{switch permissions.microphone{case .authorized:return "Allowed";case .denied:return "Denied";case .restricted:return "Restricted";default:return "Not enabled"}}
 private func openPrivacy(_ name:String){if let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_"+name){NSWorkspace.shared.open(url)}}
}
