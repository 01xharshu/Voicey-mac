import Foundation
import NativeBridge
import VoiceyCore

actor NeuralSpeechEngine {
 private var model:UnsafeMutableRawPointer?
 private var british=false
 private var releaseTask:Task<Void,Never>?
 var resident:Bool{model != nil}
 func unload(){releaseTask?.cancel();releaseTask=nil;if let model{vy_tts_free(model)};model=nil}
 func render(_ text:String,voice:NeuralVoice,rate:Float) throws->Data {
 releaseTask?.cancel()
 defer{releaseTask=Task{[weak self] in do{try await Task.sleep(nanoseconds:60_000_000_000);try Task.checkCancellation();await self?.unload()}catch{}}}
 try Task.checkCancellation()
 let root=Bundle.main.bundleURL
 let bundled=root.appendingPathComponent("Contents/Frameworks")
 let runtime=FileManager.default.fileExists(atPath:bundled.appendingPathComponent("libsherpa-onnx-c-api.dylib").path) ? bundled:URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/runtimes")
 guard vy_tts_open(runtime.path)==1 else{throw VoiceyError.unavailable("Neural speech runtime is missing. Rebuild Voicey with scripts/build.sh.")}
 let bundledModel=root.appendingPathComponent("Contents/Resources/Kokoro")
 let directory=FileManager.default.fileExists(atPath:bundledModel.appendingPathComponent("model.onnx").path) ? bundledModel:URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".deps/sherpa-onnx/kokoro-multi-lang-v1_0")
 guard ["model.onnx","voices.bin","tokens.txt","lexicon-us-en.txt","lexicon-gb-en.txt","espeak-ng-data"].allSatisfy({FileManager.default.fileExists(atPath:directory.appendingPathComponent($0).path)}) else{throw VoiceyError.unavailable("Kokoro voice assets are missing from this build.")}
 if model != nil,british != voice.british{if let model{vy_tts_free(model)};model=nil}
 if model==nil {model=vy_tts_load(directory.path,voice.british ? 1:0);british=voice.british}
 guard let model else{throw VoiceyError.unavailable("The local neural speech model could not load.")}
 try Task.checkCancellation()
 var count:Int32=0,sampleRate:Int32=0
 let speed=min(1.3,max(0.5,rate.isFinite ? rate/0.5:1))
 guard let audio=vy_tts_render(model,text,voice.speaker,speed,&count,&sampleRate) else{try Task.checkCancellation();throw VoiceyError.unavailable("Neural speech stopped or could not generate audio.")}
 defer{vy_audio_free(audio)}
 try Task.checkCancellation()
 return Self.wav(UnsafeBufferPointer(start:audio,count:Int(count)),sampleRate:Int(sampleRate))
 }
 private static func wav(_ samples:UnsafeBufferPointer<Float>,sampleRate:Int)->Data {
 var data=Data()
 func bytes(_ value:String){data.append(contentsOf:value.utf8)}
 func u32(_ value:UInt32){var v=value.littleEndian;withUnsafeBytes(of:&v){data.append(contentsOf:$0)}}
 func u16(_ value:UInt16){var v=value.littleEndian;withUnsafeBytes(of:&v){data.append(contentsOf:$0)}}
 bytes("RIFF");u32(UInt32(36+samples.count*2));bytes("WAVEfmt ");u32(16);u16(1);u16(1);u32(UInt32(sampleRate));u32(UInt32(sampleRate*2));u16(2);u16(16);bytes("data");u32(UInt32(samples.count*2))
 var pcm=[Int16]();pcm.reserveCapacity(samples.count)
 for sample in samples{pcm.append(Int16(min(1,max(-1,sample.isFinite ? sample:0))*32767).littleEndian)}
 pcm.withUnsafeBytes{data.append(contentsOf:$0)}
 return data
 }
}
