import Foundation
public enum NeuralVoice:String,CaseIterable,Identifiable,Sendable {
 case michael,heart,bella,emma,system
 public var id:String{rawValue}
 public static func selected(_ preference:String?)->NeuralVoice{preference.flatMap(Self.init(rawValue:)) ?? .michael}
 public var title:String{switch self{case .michael:return "Michael · American English · male";case .heart:return "Heart · American English · female";case .bella:return "Bella · American English · female";case .emma:return "Emma · British English · female";case .system:return "macOS system voice"}}
 public var speaker:Int32{switch self{case .michael:return 16;case .heart:return 3;case .bella:return 2;case .emma:return 21;case .system:return -1}}
 public var british:Bool{self == .emma}
}
