import VoiceyCore
func neuralVoiceChecks(){
 expectEqual(NeuralVoice.selected(nil),.michael)
 expectEqual(NeuralVoice.selected(""),.michael)
 expectEqual(NeuralVoice.selected("removed-voice"),.michael)
 expectEqual(NeuralVoice.selected("heart"),.heart)
 expectEqual(NeuralVoice.selected("bella"),.bella)
 expectEqual(NeuralVoice.selected("emma"),.emma)
 expectEqual(NeuralVoice.selected("system"),.system)
 expectEqual(NeuralVoice.michael.speaker,16)
 expectEqual(NeuralVoice.heart.speaker,3)
 expectEqual(NeuralVoice.bella.speaker,2)
 expectEqual(NeuralVoice.emma.speaker,21)
 expectTrue(NeuralVoice.emma.british);expectFalse(NeuralVoice.michael.british)
 expectEqual(Set(NeuralVoice.allCases.map(\.rawValue)).count,5)
 print("CHECK neural voice: Michael default, persisted alternatives, invalid preference recovery, verified speaker IDs and UK pronunciation")
}
