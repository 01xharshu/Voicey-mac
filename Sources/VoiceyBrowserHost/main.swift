import Foundation
import Darwin
import VoiceyCore

// Native Messaging host; launched by the browser only. No TCP listener.
struct Configuration:Codable {let extensionID:String,browserID:String,browserExecutable:String,token:String}
let fm=FileManager.default
let root=fm.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Voicey/BrowserBridge")
func privateFile(_ url:URL)throws->Data {
 let attrs=try fm.attributesOfItem(atPath:url.path)
 guard (attrs[.ownerAccountID] as? NSNumber)?.uint32Value==getuid(),(attrs[.posixPermissions] as? NSNumber)?.intValue==0o600,attrs[.type] as? FileAttributeType == .typeRegular else{throw VoiceyError.invalid("Unsafe bridge configuration permissions")}
 return try Data(contentsOf:url)
}
func exact(_ handle:FileHandle,_ count:Int)throws->Data {
 var result=Data();while result.count<count {guard let bytes=try handle.read(upToCount:count-result.count),!bytes.isEmpty else{throw VoiceyError.unavailable("Native messaging disconnected")};result.append(bytes)};return result
}
func readFrame(_ handle:FileHandle)throws->Data {let header=try exact(handle,4);let n=header.withUnsafeBytes{$0.loadUnaligned(as:UInt32.self).littleEndian};guard n>0,n<=1_048_576 else{throw VoiceyError.invalid("Oversized native message")};return try exact(handle,Int(n))}
func writeFrame(_ handle:FileHandle,_ data:Data)throws {var size=UInt32(data.count).littleEndian;try handle.write(contentsOf:Data(bytes:&size,count:4));try handle.write(contentsOf:data)}
func run()throws {
 guard CommandLine.arguments.count>=2 else{throw VoiceyError.invalid("Missing extension origin")}
 // The installer supplies a browser-specific configuration path as executable name.
 let configURL=root.appendingPathComponent(URL(fileURLWithPath:CommandLine.arguments[0]).lastPathComponent+".json")
 let config=try JSONDecoder().decode(Configuration.self,from:privateFile(configURL))
 guard config.extensionID.range(of:"^[a-p]{32}$",options:.regularExpression) != nil,CommandLine.arguments[1]=="chrome-extension://\(config.extensionID)/" else{throw VoiceyError.invalid("Unapproved extension identity")}
 // proc_info.h defines this compound macro as 4 * MAXPATHLEN; Swift does not import it.
 var path=[CChar](repeating:0,count:4 * Int(MAXPATHLEN))
 guard proc_pidpath(getppid(),&path,UInt32(path.count))>0 else{throw VoiceyError.invalid("Native browser parent unavailable")}
 let actualParent=String(cString:path)
 let frameworks=URL(fileURLWithPath:config.browserExecutable).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Frameworks").path+"/"
 guard actualParent==config.browserExecutable || actualParent.hasPrefix(frameworks) else{throw VoiceyError.invalid("Unexpected native host parent")}
 let lockURL=root.appendingPathComponent(config.browserID+".lock")
 let lock=open(lockURL.path,O_CREAT|O_RDWR|O_NOFOLLOW,0o600)
 guard lock>=0,flock(lock,LOCK_EX|LOCK_NB)==0 else{throw VoiceyError.unavailable("A bridge for this browser is already connected")}
 defer{close(lock)}
 let socketURL=root.appendingPathComponent(config.browserID+".sock")
 signal(SIGPIPE,SIG_IGN)
 let server=socket(AF_UNIX,SOCK_STREAM,0);guard server>=0 else{throw VoiceyError.unavailable("socket failed")};defer{close(server);unlink(socketURL.path)}
 var address=sockaddr_un();address.sun_family=sa_family_t(AF_UNIX)
 let bytes=Array(socketURL.path.utf8CString);guard bytes.count<MemoryLayout.size(ofValue:address.sun_path) else{throw VoiceyError.invalid("Socket path too long")}
 withUnsafeMutableBytes(of:&address.sun_path){$0.copyBytes(from:bytes.map{UInt8(bitPattern:$0)})}
 unlink(socketURL.path)
 let bound=withUnsafePointer(to:&address){p in p.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.bind(server,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}
 guard bound==0,chmod(socketURL.path,0o600)==0,listen(server,2)==0 else{throw VoiceyError.unavailable("Private bridge socket failed")}
 while true {
 let client=accept(server,nil,nil);if client<0{continue}
 let file=FileHandle(fileDescriptor:client,closeOnDealloc:true)
 do {
 var uid:uid_t=0,gid:gid_t=0
 guard getpeereid(client,&uid,&gid)==0,uid==getuid() else{throw VoiceyError.invalid("Unexpected IPC user")}
 var timeout=timeval(tv_sec:20,tv_usec:0);setsockopt(client,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
 let payload=try readFrame(file)
 guard let object=try JSONSerialization.jsonObject(with:payload) as? [String:Any],Set(object.keys)==Set(["token","command"]),let commandObject=object["command"] as? [String:Any],Set(commandObject.keys)==Set(["version","id","operation","url","text","recipient","subject"]) else{throw VoiceyError.invalid("Unexpected IPC schema fields")}
 let envelope=try JSONDecoder().decode(BrowserEnvelope.self,from:payload)
 guard envelope.token==config.token else{throw VoiceyError.invalid("Invalid IPC authentication")}
 try envelope.command.validate()
 try writeFrame(.standardOutput,JSONEncoder().encode(envelope.command))
 var polling=[pollfd(fd:STDIN_FILENO,events:Int16(POLLIN),revents:0),pollfd(fd:client,events:Int16(POLLIN|POLLHUP),revents:0)]
 guard poll(&polling,2,18000)>0 else{exit(2)}
 if polling[1].revents != 0 {
 var cancel=BrowserCommand(.cancel,url:envelope.command.url);cancel.id=envelope.command.id
 try writeFrame(.standardOutput,JSONEncoder().encode(cancel))
 // Exit after cancelling: a late response must never become the next request's reply.
 exit(0)
 }
 let data=try readFrame(.standardInput)
 let reply=try JSONDecoder().decode(BrowserReply.self,from:data);try reply.validate(for:envelope.command)
 try writeFrame(file,data)
 } catch {
 // Never write logs to stdout (it is the native messaging transport).
 let data=Data("Bridge request failed: \(error.localizedDescription)\n".utf8);try? FileHandle.standardError.write(contentsOf:data)
 }
 try? file.close()
 }
}
do{try run()}catch{try? FileHandle.standardError.write(contentsOf:Data((error.localizedDescription+"\n").utf8));exit(1)}
