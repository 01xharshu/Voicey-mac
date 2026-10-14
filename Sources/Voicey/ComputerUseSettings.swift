import AppKit
import SwiftUI
import ApplicationServices
import VoiceyCore

struct ComputerUseSettings:View {
 @ObservedObject var agent:AgentOrchestrator
 @ObservedObject private var permissions=PermissionStatus.shared
 @AppStorage("computerUseEnabled") private var enabled=true
 @AppStorage("previewExternalPrompts") private var preview=false
 @AppStorage("computerStepBudget") private var budget=24
 @AppStorage("computerRetries") private var retries=2
 @AppStorage("computerNarration") private var narration=true
 @ViewState private var refresh=0
 var body:some View {
 Form {
 Section("Task Control") {
 Toggle("Enable computer use",isOn:$enabled).onChange(of:enabled){_,value in if !value{agent.cancel()}}
 Toggle("Preview website submissions",isOn:$preview)
 Toggle("Speak task results",isOn:$narration)
 Text("Voicey checks the outcome of each step. Actions with external effects need your approval.").font(.caption).foregroundStyle(.secondary)
 }
 Section("Permissions") {
 LabeledContent("Accessibility"){permission(permissions.accessibility)}
 if !permissions.accessibility{Button("Allow Accessibility…"){let key=kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String;_ = AXIsProcessTrustedWithOptions([key:true] as CFDictionary);refresh+=1}}
 Button("Open Accessibility Settings…"){privacy("Accessibility")}
 LabeledContent("Screen Recording"){permission(permissions.screenRecording)}
 if !permissions.screenRecording{Button("Allow Screen Recording…"){_ = CGRequestScreenCaptureAccess();permissions.refresh()}}
 Button("Open Screen Recording Settings…"){privacy("ScreenCapture")}
 Text("Accessibility lets Voicey work with app controls. Screen Recording is used only when visual inspection is needed.").font(.caption).foregroundStyle(.secondary)
 if !permissions.accessibility || !permissions.screenRecording {
 Text("Already enabled in macOS? Restart this copy of Voicey. Permissions must apply to the app at the location below.").font(.caption).foregroundStyle(.secondary)
 Text(Bundle.main.bundleURL.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
 HStack{Button("Check Again"){permissions.refresh()};Button("Restart Voicey…"){AppDelegate.current?.restart()}}
 }
 }
 Section("Browser Integration") {
 ForEach(agent.discovery.browsers()){browser in LabeledContent(browser.name){Text(agent.browserComputer.bridge.available(browser) ? "Connected":browser.bundleID == "company.thebrowser.Browser" ? "Native integration":"Setup needed").foregroundStyle(.secondary)}}
 Button("Show Browser Extension…"){let folder=Bundle.main.resourceURL?.appendingPathComponent("BrowserExtension");if let folder,FileManager.default.fileExists(atPath:folder.path){NSWorkspace.shared.open(folder)}}
 DisclosureGroup("Setup instructions") {Text("Install the included extension in your browser, then register its exact ID with the installer in Voicey's Resources folder. Allow ChatGPT and Gmail individually in the extension. Browser connection is verified when a task runs.").font(.caption).foregroundStyle(.secondary)}
 Button("Refresh Status"){refresh+=1;agent.objectWillChange.send()}
 }
 Section {
 DisclosureGroup("Advanced") {
 Stepper("Maximum task steps: \(budget)",value:$budget,in:1...64)
 Stepper("Recovery retries: \(retries)",value:$retries,in:0...3)
 Text("Uncertain submissions are not automatically repeated.").font(.caption).foregroundStyle(.secondary)
 Button("Open Automation Settings…"){privacy("Automation")}
 DisclosureGroup("Available tools") {ForEach(agent.computer.capabilities,id:\.name){adapter in VStack(alignment:.leading,spacing:4){Text(adapter.name).fontWeight(.medium);Text(adapter.verification).foregroundStyle(.secondary);if !adapter.limitations.isEmpty{Text(adapter.limitations).foregroundStyle(.secondary)}}.font(.caption)}}
 }
 }
 Section("Recent Tasks") {
 if agent.recentComputerTasks.isEmpty{Text("No recent tasks.").foregroundStyle(.secondary)}
 ForEach(Array(agent.recentComputerTasks.enumerated()),id:\.offset){_,summary in Text(summary).font(.caption)}
 Button("Clear Task History",role:.destructive){agent.clearComputerHistory()}.disabled(agent.recentComputerTasks.isEmpty)
 }
 }.formStyle(.grouped).id(refresh).onAppear{permissions.begin()}.onDisappear{permissions.end()}
 }
 private func permission(_ allowed:Bool)->some View{Label(allowed ? "Allowed":"Not enabled",systemImage:allowed ? "checkmark.circle.fill":"circle").foregroundStyle(allowed ? Color.secondary:Color.orange)}
 private func privacy(_ permission:String){if let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_"+permission){NSWorkspace.shared.open(url)}}
}
