import AppKit
import AVFoundation
import Combine
import NativeBridge
import ApplicationServices
import Carbon
import VoiceyCore

struct InstalledApp:Identifiable,Equatable {
 let url:URL,name:String,bundleID:String
 var id:String{url.path}
 var icon:NSImage{NSWorkspace.shared.icon(forFile:url.path)}
}
@MainActor final class ApplicationDiscoveryService {
 func applications()->[InstalledApp] {
 var found:[InstalledApp]=[],seen=Set<String>()
 for root in ["/Applications","/System/Applications",NSHomeDirectory()+"/Applications"] {
 guard let e=FileManager.default.enumerator(at:URL(fileURLWithPath:root),includingPropertiesForKeys:[.isDirectoryKey],options:[.skipsHiddenFiles,.skipsPackageDescendants]) else{continue}
 for case let url as URL in e where url.pathExtension=="app" {
 guard let b=Bundle(url:url),let id=b.bundleIdentifier,seen.insert(id).inserted else{continue}
 let name=b.object(forInfoDictionaryKey:"CFBundleDisplayName") as? String ?? b.object(forInfoDictionaryKey:"CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
 found.append(InstalledApp(url:url,name:name,bundleID:id))
 }
 }
 for app in NSWorkspace.shared.runningApplications {
 guard let url=app.bundleURL,let id=app.bundleIdentifier,seen.insert(id).inserted else{continue}
 found.append(InstalledApp(url:url,name:app.localizedName ?? url.deletingPathExtension().lastPathComponent,bundleID:id))
 }
 return found.sorted{$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending}
 }
 func browsers()->[InstalledApp] {
 let handlers=Set(NSWorkspace.shared.urlsForApplications(toOpen:URL(string:"https://example.com/")!).compactMap{Bundle(url:$0)?.bundleIdentifier})
 return applications().filter{handlers.contains($0.bundleID) && $0.bundleID != "com.popclip.Opener" && !$0.name.lowercased().contains("opener")}
 }
 func matches(_ query:String)->[InstalledApp] {
 let q=query.lowercased().replacingOccurrences(of:"google chrome",with:"chrome").replacingOccurrences(of:"microsoft edge",with:"edge")
 let all=applications();let exact=all.filter{$0.name.lowercased()==q || $0.url.deletingPathExtension().lastPathComponent.lowercased()==q}
 return exact.isEmpty ? all.filter{$0.name.lowercased().contains(q)}:exact
 }
 func launch(_ app:InstalledApp) async throws {
 try await withCheckedThrowingContinuation{(c:CheckedContinuation<Void,Error>) in NSWorkspace.shared.openApplication(at:app.url,configuration:NSWorkspace.OpenConfiguration()){_,error in if let error{c.resume(throwing:error)}else{c.resume()}}}
 }
 func website(_ url:URL,browser:InstalledApp) async throws {
 try await withCheckedThrowingContinuation{(c:CheckedContinuation<Void,Error>) in NSWorkspace.shared.open([url],withApplicationAt:browser.url,configuration:NSWorkspace.OpenConfiguration()){_,error in if let error{c.resume(throwing:error)}else{c.resume()}}}
 }
}
// Only installed voices are considered; speech never calls a remote service.
enum LocalSpeechVoices {
 static func qualityLabel(_ voice:AVSpeechSynthesisVoice)->String {
 switch voice.quality {case .premium:return "Premium";case .enhanced:return "Enhanced";default:return "Standard"}
 }
 static func automatic(language:String)->AVSpeechSynthesisVoice? {
 let voices=AVSpeechSynthesisVoice.speechVoices()
 let prefix=language == "hi" ? "hi" : "en"
 let candidates=voices.filter{$0.language.hasPrefix(prefix) && !$0.identifier.contains("eloquence") && !$0.identifier.hasPrefix("com.apple.speech.synthesis.voice.")}
 return candidates.sorted {
 if $0.quality.rawValue != $1.quality.rawValue{return $0.quality.rawValue > $1.quality.rawValue}
 let preferred=prefix == "hi" ? "hi-IN":"en-IN"
 if ($0.language == preferred) != ($1.language == preferred){return $0.language == preferred}
 if $0.identifier.contains("super-compact") != $1.identifier.contains("super-compact"){return !$0.identifier.contains("super-compact")}
 return $0.identifier < $1.identifier
 }.first ?? AVSpeechSynthesisVoice(language:prefix == "hi" ? "hi-IN":"en-US")
 }
 static func selected(identifier:String?,text:String)->AVSpeechSynthesisVoice? {
 if let identifier,!identifier.isEmpty,let voice=AVSpeechSynthesisVoice(identifier:identifier){return voice}
 // Hindi replies use Hindi speech even when recognition is set to Automatic.
 let hindi=text.unicodeScalars.contains{(0x0900...0x097F).contains(Int($0.value))}
 return automatic(language:hindi ? "hi":"en")
 }
 static func utterance(_ text:String,voice:String?,rate:Float)->AVSpeechUtterance {
 let u=AVSpeechUtterance(string:text)
 u.voice=selected(identifier:voice,text:text)
 u.rate=rate.isFinite ? min(0.65,max(0.25,rate)):AVSpeechUtteranceDefaultSpeechRate
 u.pitchMultiplier=1;u.volume=1
 return u
 }
}
@MainActor final class SpeechSynthesisService:NSObject,ObservableObject,AVSpeechSynthesizerDelegate,AVAudioPlayerDelegate {
 private let synth=AVSpeechSynthesizer()
 let neural=NeuralSpeechEngine()
 @Published private(set) var status="Michael · local neural speech"
 private var completion:(()->Void)?
 private var activeUtterance:AVSpeechUtterance?
 private var player:AVAudioPlayer?
 private var synthesis:Task<Void,Never>?
 private var generation=UUID()
 override init(){super.init();synth.delegate=self}
 func speak(_ text:String,voice:String?,rate:Float,completion:(()->Void)?=nil){
 stop();guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{completion?();return}
 self.completion=completion
 let choice=NeuralVoice.selected(UserDefaults.standard.string(forKey:"speechVoice"))
 let hindi=text.unicodeScalars.contains{(0x0900...0x097F).contains(Int($0.value))}
 if choice == .system || hindi{systemSpeech(text,voice:voice,rate:rate);return}
 let token=generation;status="Preparing \(choice.title)…"
 synthesis=Task{[weak self] in
 guard let self else{return}
 do {
 let data=try await self.neural.render(text,voice:choice,rate:rate)
 try Task.checkCancellation();guard self.generation==token else{return}
 let player=try AVAudioPlayer(data:data);player.delegate=self;self.player=player
 guard player.prepareToPlay(),player.play() else{throw VoiceyError.unavailable("Audio output could not start.")}
 self.status="Speaking with \(choice.title) · on-device"
 }catch{
 guard self.generation==token,!Task.isCancelled else{return}
 // Surface the degraded backend instead of silently claiming neural playback.
 self.systemSpeech(text,voice:voice,rate:rate)
 self.status="Neural voice unavailable: \(error.localizedDescription) Using macOS speech."
 }
 }
 }
 private func systemSpeech(_ text:String,voice:String?,rate:Float){
 let u=LocalSpeechVoices.utterance(text,voice:voice,rate:rate);activeUtterance=u
 status="Speaking with \(u.voice?.name ?? "macOS") · on-device";synth.speak(u)
 }
 func stop(){generation=UUID();synthesis?.cancel();synthesis=nil;vy_tts_cancel();player?.stop();player=nil;activeUtterance=nil;completion=nil;synth.stopSpeaking(at:.immediate)}
 private func finished(){let c=completion;completion=nil;status="Ready · local speech";c?()}
 nonisolated func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didFinish utterance:AVSpeechUtterance){Task{@MainActor in
 guard self.activeUtterance === utterance else{return};self.activeUtterance=nil;self.finished()
 }}
 nonisolated func audioPlayerDidFinishPlaying(_ player:AVAudioPlayer,successfully flag:Bool){Task{@MainActor in
 guard self.player === player else{return};self.player=nil
 if flag{self.finished()}else{self.completion=nil;self.status="Audio playback failed. Try the voice preview again."}
 }}
}
// Audio callback owns only this lock-protected buffer. No disk recordings.
final class AudioBuffer:@unchecked Sendable {
 let lock=NSLock();var values:[Float]=[];var lastVoice=Date();var peak:Float=0
 func append(_ samples:[Float]){lock.lock();defer{lock.unlock()};values.append(contentsOf:samples);peak=samples.reduce(0){max($0,abs($1))};if peak>0.015{lastVoice=Date()}}
 func snapshot()->(Int,Date,Float){lock.lock();defer{lock.unlock()};return(values.count,lastVoice,peak)}
 func finish()->[Float]{lock.lock();defer{lock.unlock()};let s=values;values.removeAll(keepingCapacity:false);return s}
}
@MainActor final class AudioCaptureService {
 private var engine:AVAudioEngine?,timer:Timer?,buffer:AudioBuffer?
 func start(timeout:Double,level:@escaping(Float)->Void,finished:@escaping([Float])->Void) throws {
 stop();let engine=AVAudioEngine(),input=engine.inputNode,format=input.outputFormat(forBus:0)
 guard format.sampleRate>0,format.channelCount>0,let out=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:16000,channels:1,interleaved:false),let converter=AVAudioConverter(from:format,to:out) else{throw VoiceyError.unavailable("No usable microphone is available.")}
 let buffer=AudioBuffer();self.buffer=buffer
 input.installTap(onBus:0,bufferSize:2048,format:format){pcm,_ in
 let capacity=AVAudioFrameCount(Double(pcm.frameLength)*16000/format.sampleRate)+64
 guard let converted=AVAudioPCMBuffer(pcmFormat:out,frameCapacity:capacity) else{return}
 var supplied=false;var error:NSError?
 converter.convert(to:converted,error:&error){_,status in if supplied{status.pointee = .noDataNow;return nil};supplied=true;status.pointee = .haveData;return pcm}
 if error==nil,let channel=converted.floatChannelData?[0]{buffer.append(Array(UnsafeBufferPointer(start:channel,count:Int(converted.frameLength))))}
 }
 engine.prepare();do{try engine.start()}catch{input.removeTap(onBus:0);throw error};self.engine=engine
 let start=Date()
 timer=Timer.scheduledTimer(withTimeInterval:0.15,repeats:true){[weak self] _ in
 Task{@MainActor in guard let self,self.engine != nil else{return};let (count,last,peak)=buffer.snapshot();level(peak)
 if Date().timeIntervalSince(start)>=timeout || (count>16000 && Date().timeIntervalSince(last)>1.2 && Date().timeIntervalSince(start)>2){let s=self.stop();finished(s)}
 }
 }
 }
 @discardableResult func stop()->[Float]{timer?.invalidate();timer=nil;if let engine{engine.inputNode.removeTap(onBus:0);engine.stop()};engine=nil;let samples=buffer?.finish() ?? [];buffer=nil;return samples}
}
@MainActor final class HotkeyManager {
 private var tap:CFMachPort?,source:CFRunLoopSource?,timer:Timer?,chord=ActivationChord()
 private var monitor:Any?,fallbackRef:EventHotKeyRef?,handler:EventHandlerRef?
 var activate:(()->Void)?
 func requestPermission(){_ = CGRequestListenEventAccess();start()}
 func start(){stop()
 // Persisted user preference takes precedence over defaults in pasted task specifications.
 chord=ActivationChord(gesture:ActivationGesture(rawValue:UserDefaults.standard.string(forKey:"primaryActivationGesture") ?? "tripleModifiers") ?? .tripleModifiers)
 let callback:CGEventTapCallBack={_,type,event,info in
 guard let info else{return Unmanaged.passUnretained(event)}
 let manager=Unmanaged<HotkeyManager>.fromOpaque(info).takeUnretainedValue()
 MainActor.assumeIsolated {
 if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput{manager.chord.reset();if let tap=manager.tap{CGEvent.tapEnable(tap:tap,enable:true)}}
 else{manager.observe(flags:event.flags)}
 }
 return Unmanaged.passUnretained(event)
 }
 tap=CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,options:.listenOnly,eventsOfInterest:1 << CGEventType.flagsChanged.rawValue,callback:callback,userInfo:Unmanaged.passUnretained(self).toOpaque())
 if let tap{source=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0);CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes);CGEvent.tapEnable(tap:tap,enable:true)}
 // Event-driven activation; one-second recovery handles missed releases without 10 Hz wakeups.
 // Coalesce recovery with other timers to reduce idle energy use.
 timer=Timer.scheduledTimer(withTimeInterval:1.0,repeats:true){[weak self] _ in Task{@MainActor in if self?.tap != nil{self?.observe()}}}
 timer?.tolerance=0.25
 var type=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
 InstallEventHandler(GetApplicationEventTarget(),{_,_,info in guard let info else{return noErr};let manager=Unmanaged<HotkeyManager>.fromOpaque(info).takeUnretainedValue();MainActor.assumeIsolated{manager.activate?()};return noErr},1,&type,Unmanaged.passUnretained(self).toOpaque(),&handler)
 let key=UInt32(UserDefaults.standard.integer(forKey:"fallbackKey") == 0 ? 49:UserDefaults.standard.integer(forKey:"fallbackKey"))
 let mods=UInt32(UserDefaults.standard.integer(forKey:"fallbackModifiers") == 0 ? cmdKey|optionKey:UserDefaults.standard.integer(forKey:"fallbackModifiers"))
 RegisterEventHotKey(key,mods,EventHotKeyID(signature:0x56594359,id:1),GetApplicationEventTarget(),0,&fallbackRef)
 }
 private func observe(flags:CGEventFlags? = nil){
 if chord.gesture == .tripleModifiers,let flags{
 if chord.update(control:flags.contains(.maskControl),option:flags.contains(.maskAlternate),command:flags.contains(.maskCommand)){activate?()};return
 }
 let left=CGEventSource.keyState(.combinedSessionState,key:55)
 let right=CGEventSource.keyState(.combinedSessionState,key:54)
 let control=CGEventSource.keyState(.combinedSessionState,key:59) || CGEventSource.keyState(.combinedSessionState,key:62)
 let option=CGEventSource.keyState(.combinedSessionState,key:58) || CGEventSource.keyState(.combinedSessionState,key:61)
 if chord.update(control:control,option:option,command:left || right,leftCommand:left,rightCommand:right){activate?()}
 }
 var available:Bool{tap != nil}
 func stop(){timer?.invalidate();timer=nil;if let source{CFRunLoopRemoveSource(CFRunLoopGetMain(),source,.commonModes)};source=nil;if let tap{CFMachPortInvalidate(tap)};tap=nil;chord.reset();if let fallbackRef{UnregisterEventHotKey(fallbackRef)};fallbackRef=nil;if let handler{RemoveEventHandler(handler)};handler=nil}
}
