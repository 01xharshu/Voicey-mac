import AVFoundation
import Foundation
import VoiceyCore
import NativeBridge

private final class SpeechRenderCapture:@unchecked Sendable {
 private let lock=NSLock()
 private var frames:AVAudioFramePosition=0
 private var peak:Float=0
 private var finished=false
 private var failure:String?
 private var file:AVAudioFile?
 let output:URL
 init(output:URL){self.output=output}
 func receive(_ buffer:AVAudioBuffer){
 lock.lock();defer{lock.unlock()}
 guard let pcm=buffer as? AVAudioPCMBuffer else{failure="Unexpected audio format";finished=true;return}
 if pcm.frameLength==0{finished=true;return}
 do{
 if file==nil{file=try AVAudioFile(forWriting:output,settings:pcm.format.settings)}
 try file?.write(from:pcm);frames+=AVAudioFramePosition(pcm.frameLength)
 if let data=pcm.floatChannelData{for index in 0..<Int(pcm.frameLength){peak=max(peak,abs(data[0][index]))}}
 }catch{failure=error.localizedDescription;finished=true}
 }
 func snapshot()->(Bool,AVAudioFramePosition,Float,String?){lock.lock();defer{lock.unlock()};return(finished,frames,peak,failure)}
}
@MainActor enum SpeechNativeChecks {
 static func runNeural() async -> Int32 {
 var failures=0
 func check(_ ok:Bool,_ title:String){print("\(ok ? "PASS":"FAIL") \(title)");if !ok{failures+=1};fflush(stdout)}
 check(NeuralVoice.selected(nil) == .michael,"Michael is the default neural voice")
 let engine=NeuralSpeechEngine()
 let output=FileManager.default.temporaryDirectory.appendingPathComponent("Voicey-neural-voices",isDirectory:true)
 do{
 try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
 var generated=[Data]()
 for voice in [NeuralVoice.michael,.heart,.bella,.emma] {
 let start=Date()
 let data=try await engine.render("Hi, I'm Voicey. What would you like to work on? I can help you find a file, check your project, or get something done in your browser.",voice:voice,rate:0.5)
 let player=try AVAudioPlayer(data:data)
 check(data.count>48000 && player.duration>1 && data.prefix(4)==Data("RIFF".utf8),"in-process \(voice.title) generates valid audio")
 generated.append(data);try data.write(to:output.appendingPathComponent(voice.rawValue+".wav"))
 print("NEURAL_RENDER \(voice.rawValue) duration=\(player.duration) generation=\(Date().timeIntervalSince(start))")
 }
 check(Set(generated).count==4,"changing voices produces four distinct waveforms")
 check(await engine.resident,"neural model is resident after synthesis")
 let long=String(repeating:"This speech will be cancelled before playback. ",count:50)
 let cancelled=Task{try await engine.render(long,voice:.michael,rate:0.5)}
 try await Task.sleep(nanoseconds:200_000_000);cancelled.cancel();vy_tts_cancel()
 do{_ = try await cancelled.value;check(false,"cancelled inference discarded")}catch{check(true,"cancelled inference discarded")}
 await engine.unload();check(!(await engine.resident),"neural model unload releases its instance")
 print("NEURAL_PREVIEW_DIRECTORY \(output.path)")
 }catch{check(false,error.localizedDescription)}
 // Exercise the actual reply service, including its default route and delegates.
 let service=SpeechSynthesisService();var oldFinished=false,newFinished=false
 service.speak("This reply should be interrupted.",voice:nil,rate:0.5){oldFinished=true}
 try? await Task.sleep(nanoseconds:100_000_000);service.stop()
 service.speak("Hi, I'm Voicey. I'm ready to help.",voice:nil,rate:0.5){newFinished=true}
 let deadline=Date().addingTimeInterval(20);var usedNeural=false
 while !newFinished && Date()<deadline{
 if service.status.contains("Michael") && service.status.contains("Speaking"){usedNeural=true}
 try? await Task.sleep(nanoseconds:100_000_000)
 }
 check(usedNeural,"actual reply service plays Michael, without system fallback")
 check(newFinished && !oldFinished,"replacement playback completes only its own reply")
 service.stop();await service.neural.unload()
 print("Neural speech checks failures: \(failures)")
 return failures==0 ? 0:1
 }
 static func run() async -> Int32 {
 var failures=0
 func check(_ ok:Bool,_ title:String){print("\(ok ? "PASS":"FAIL") \(title)");if !ok{failures+=1}}
 let automatic=LocalSpeechVoices.automatic(language:"en")
 print("LOCAL_VOICE \(automatic?.identifier ?? "none") quality=\(automatic.map{LocalSpeechVoices.qualityLabel($0)} ?? "none")")
 let enhanced=AVSpeechSynthesisVoice.speechVoices().filter{$0.language.hasPrefix("en") && $0.quality.rawValue>1}
 check(automatic != nil,"installed English voice available")
 check(enhanced.isEmpty || (automatic?.quality.rawValue ?? 0)>1,"automatic prefers higher quality installed voice")
 check(LocalSpeechVoices.selected(identifier:"voicey-missing-voice",text:"Hello")?.identifier==automatic?.identifier,"removed voice safely falls back to automatic")
 check(LocalSpeechVoices.selected(identifier:nil,text:"नमस्ते")?.language.hasPrefix("hi")==true,"Hindi reply uses installed Hindi voice")
 if let automatic{check(LocalSpeechVoices.selected(identifier:automatic.identifier,text:"Hello")?.identifier==automatic.identifier,"explicit installed voice preserved")}
 check(LocalSpeechVoices.utterance("Hello",voice:nil,rate:10).rate==0.65,"invalid speech speed bounded")
 let output=FileManager.default.temporaryDirectory.appendingPathComponent("Voicey-local-voice-preview.wav")
 try? FileManager.default.removeItem(at:output)
 let capture=SpeechRenderCapture(output:output),synth=AVSpeechSynthesizer()
 synth.write(LocalSpeechVoices.utterance("Hi! I'm Voicey. Tell me what you'd like to do, and I'll help you get it done.",voice:nil,rate:AVSpeechUtteranceDefaultSpeechRate)){capture.receive($0)}
 let deadline=Date().addingTimeInterval(25)
 while !capture.snapshot().0 && Date()<deadline{try? await Task.sleep(nanoseconds:100_000_000)}
 let rendered=capture.snapshot()
 check(rendered.0 && rendered.1>16000 && rendered.2>0.001 && rendered.3==nil,"real selected voice synthesizes non-silent local audio")
 synth.stopSpeaking(at:.immediate)
 if let error=rendered.3{print("RENDER_ERROR \(error)")}
 if rendered.0 && rendered.1>0{print("LOCAL_AUDIO_PREVIEW \(output.path)")}
 // Exercise the actual service's cancellation followed by a replacement utterance.
 let service=SpeechSynthesisService();var cancelledCompleted=false,replacementCompleted=false
 service.speak("This is an interrupted preview that must not trigger recording.",voice:nil,rate:0.5){cancelledCompleted=true}
 service.stop()
 service.speak("Ready.",voice:nil,rate:0.5){replacementCompleted=true}
 let finishDeadline=Date().addingTimeInterval(10)
 while !replacementCompleted && Date()<finishDeadline{try? await Task.sleep(nanoseconds:100_000_000)}
 service.stop()
 check(!cancelledCompleted && replacementCompleted,"interrupt and replace speech completes only the current request")
 print("Speech checks failures: \(failures)")
 return failures==0 ? 0:1
 }
}
