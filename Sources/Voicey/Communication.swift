import SwiftUI
import AppKit
import ApplicationServices
import UserNotifications
import VoiceyCore

// No private database access or synthesized UI clicks. Native operations remain gated
// until a version-specific Accessibility message schema has been verified.
@MainActor final class WhatsAppAdapter:MessagingAdapter {
 var limitation:String {"WhatsApp is installed. Chat names, message direction, timestamps and composer controls have not been verified for this version; reading, counting and sending are unavailable. No verified WhatsApp browser adapter is connected."}
 var permission:Bool {AXIsProcessTrusted()}
 func launch() async throws {
 guard let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"net.whatsapp.WhatsApp") else{throw VoiceyError.unavailable("Install WhatsApp first.")}
 let config=NSWorkspace.OpenConfiguration();config.activates=true
 _ = try await NSWorkspace.shared.openApplication(at:url,configuration:config)
 }
 func conversations() async throws->[Conversation] {throw VoiceyError.unavailable(limitation)}
 func open(_ conversation:Conversation) async throws {throw VoiceyError.unavailable(limitation)}
 func inspect(_ conversation:Conversation) async throws->ChatSnapshot {throw VoiceyError.unavailable(limitation)}
 func compose(_ reply:ReplyProposal) async throws {throw VoiceyError.unavailable(limitation)}
 func send(_ reply:ReplyProposal) async throws->ChatSnapshot {throw VoiceyError.unavailable(limitation)}
}
@MainActor final class CommunicationController:ObservableObject {
 let adapter=WhatsAppAdapter()
 @Published var watches:[ReplyWatch]=[]
 @Published var status="No verified message observation source. Watches cannot currently be activated."
 @Published var notificationStatus="Not checked"
 @Published var blocked=false
 private var store:CommunicationStore?
 private var deadlineTimer:Timer?
 init(){do{store=try CommunicationStore(url:supportDirectory.appendingPathComponent("communication-watches.json"));watches=store!.watches
 var resumed=watches;for i in resumed.indices where resumed[i].status == .waiting{resumed[i].status = .paused;resumed[i].gap="Voicey stopped or observation became unavailable. No messages were observed during the gap."};try store?.update(resumed);watches=resumed
 }catch{status=error.localizedDescription}
 deadlineTimer=Timer.scheduledTimer(withTimeInterval:30,repeats:true){[weak self] _ in Task{@MainActor in self?.tick()}}
 }
 func tick(){
 guard let store else{return}
 let result=WatchProcessor.process(watches,messages:[],now:Date(),connected:false)
 guard result.watches != watches else{return}
 do{try store.update(result.watches);watches=result.watches
 for alert in result.alerts{Task{await deliver(alert)}}
 }catch{status=error.localizedDescription}
 }
 private func deliver(_ alert:CommunicationAlert) async {
 let center=UNUserNotificationCenter.current(),settings=await center.notificationSettings()
 guard [.authorized,.provisional].contains(settings.authorizationStatus) else{status="Deadline reached, but notification permission is unavailable.";return}
 let content=UNMutableNotificationContent();content.title=alert.title;content.body=alert.body;content.userInfo=["conversationID":alert.conversationID];content.sound = .default
 do{try await center.add(UNNotificationRequest(identifier:alert.id,content:content,trigger:nil))}catch{status="Notification failed: \(error.localizedDescription)"}
 }
 func permissions(){Task{let settings=await UNUserNotificationCenter.current().notificationSettings();notificationStatus=String(describing:settings.authorizationStatus)}}
 func requestNotifications(){Task{do{let allowed=try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound]);notificationStatus=allowed ? "Allowed":"Denied"}catch{notificationStatus=error.localizedDescription}}}
 func cancelAll(){do{try store?.cancelAll();watches=store?.watches ?? []}catch{status=error.localizedDescription}}
 func clear(){do{try store?.clear();watches=[]}catch{status=error.localizedDescription}}
 func handle(_ text:String) async ->String? {
 blocked=false
 let lower=text.lowercased()
 if lower=="show everyone i'm waiting for" || lower=="show active watches" {return watches.isEmpty ? "No reply watches are saved.":watches.map{"\($0.conversation.name): \($0.status.rawValue)"}.joined(separator:"\n")}
 if lower=="cancel all watches"{cancelAll();return "Cancelled all saved watches."}
 guard lower.contains("whatsapp") || lower.hasPrefix("reply to ") || lower.hasPrefix("tell me when ") || lower.hasPrefix("stop watching ") || lower.contains("messages from ") else{return nil}
 if lower=="open whatsapp" || lower=="launch whatsapp"{do{try await adapter.launch();return "Opened WhatsApp. Complete linking or login in WhatsApp if required."}catch{return error.localizedDescription}}
 if lower.hasPrefix("stop watching "){let name=String(text.dropFirst(14));var values=watches;for i in values.indices where values[i].conversation.name.caseInsensitiveCompare(name) == .orderedSame{values[i].status = .cancelled};do{try store?.update(values);watches=values;return "Cancelled matching saved watches."}catch{return error.localizedDescription}}
 blocked=true
 return adapter.limitation + (adapter.permission ? "":" Enable Accessibility in System Settings for future native integration testing.")
 }
}
struct CommunicationSettings:View {
 @ObservedObject var controller:CommunicationController
 @AppStorage("communicationPreview") var preview=false
 @AppStorage("communicationSpeak") var speak=false
 var body:some View {Form{
 Section("WhatsApp") {
 Label("Messaging integration is not ready",systemImage:"info.circle").font(.headline)
 Text("You can open WhatsApp. Reading chats, sending messages and watching for replies are unavailable in this build.").foregroundStyle(.secondary)
 DisclosureGroup("Integration details"){Text(controller.adapter.limitation).font(.caption).textSelection(.enabled)}
 }
 Section("Notifications") {
 LabeledContent("Permission"){Text(controller.notificationStatus)}
 Button("Allow Notifications…"){controller.requestNotifications()}
 Toggle("Include message previews",isOn:$preview)
 Toggle("Speak reply announcements",isOn:$speak)
 }
 Section("Saved Watches") {
 if controller.watches.isEmpty{Text("No reply watches saved.").foregroundStyle(.secondary)}
 ForEach(controller.watches){watch in LabeledContent(watch.conversation.name){Text(watch.status.rawValue)}}
 Button("Cancel All Watches"){controller.cancelAll()}.disabled(controller.watches.isEmpty)
 Button("Clear Local History",role:.destructive){controller.clear()}.disabled(controller.watches.isEmpty)
 }
 Section{Text("Voicey does not save message transcripts or screenshots. Reply monitoring needs a verified messaging integration.").font(.caption).foregroundStyle(.secondary)}
 }.formStyle(.grouped).onAppear{controller.permissions()}}
}
