import Foundation
import Darwin
// A dedicated process group lets cancellation stop ordinary child processes too.
// This helper has no IPC/listener and receives only the already-approved argv.
guard CommandLine.arguments.count>1 else{exit(64)}
guard setpgid(0,0)==0 else{exit(71)}
let args=Array(CommandLine.arguments.dropFirst())
let pointers=args.map{strdup($0)}+[nil]
defer{pointers.forEach{if let p=$0{free(p)}}}
let executable=args[0]
var argv=pointers
argv.withUnsafeMutableBufferPointer{buffer in execv(executable,buffer.baseAddress!)}
exit(72)
