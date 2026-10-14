import AppKit
import AVFoundation
import ApplicationServices
import Combine

@MainActor final class PermissionStatus:ObservableObject {
 static let shared=PermissionStatus()
 @Published private(set) var accessibility=false
 @Published private(set) var screenRecording=false
 @Published private(set) var keyboard=false
 @Published private(set) var microphone=AVAuthorizationStatus.notDetermined
 private var observer:NSObjectProtocol?
 private var users=0
 private var timer:Timer?
 init(){refresh();observer=NotificationCenter.default.addObserver(forName:NSApplication.didBecomeActiveNotification,object:nil,queue:.main){[weak self] _ in Task{@MainActor in self?.refresh()}}}
 func refresh(){
 let ax=AXIsProcessTrusted(),screen=CGPreflightScreenCaptureAccess(),keys=CGPreflightListenEventAccess(),mic=AVCaptureDevice.authorizationStatus(for:.audio)
 if accessibility != ax{accessibility=ax};if screenRecording != screen{screenRecording=screen};if keyboard != keys{keyboard=keys};if microphone != mic{microphone=mic}
 }
 func begin(){users+=1;refresh();guard timer==nil else{return};timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true){[weak self] _ in Task{@MainActor in self?.refresh()}};timer?.tolerance=0.25}
 func end(){users=max(0,users-1);if users==0{timer?.invalidate();timer=nil}}
}
