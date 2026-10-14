import Foundation
import Darwin

// Walk relative to opened directories. O_NOFOLLOW prevents alias/symlink escapes and
// mkdirat tolerates a competing creator without replacing incompatible objects.
public struct AuthorizedFilesystem: Sendable {
 public let roots:[URL]
 public init(roots:[URL]){self.roots=roots.map{$0.standardizedFileURL.resolvingSymlinksInPath()}}
 public func authorize(_ raw:String) throws -> URL {
 let url=URL(fileURLWithPath:(raw as NSString).expandingTildeInPath).standardizedFileURL
 let canonical=url.resolvingSymlinksInPath()
 guard roots.contains(where:{canonical.path==$0.path || canonical.path.hasPrefix($0.path+"/")}),FileManager.default.isReadableFile(atPath:canonical.path) else {throw VoiceyError.invalid("The folder isn't authorized or accessible. Add it in Settings → Files.")}
 var directory:ObjCBool=false
 guard FileManager.default.fileExists(atPath:canonical.path,isDirectory:&directory),directory.boolValue else{throw VoiceyError.invalid("The working location is not a directory.")}
 return canonical
 }
 public func directory(root:String,components:[String],create:Bool) throws -> URL {
 let parent=try authorize(root)
 var fd=open(parent.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
 guard fd>=0 else{throw VoiceyError.unavailable("Cannot open the authorized parent folder.")}
 defer{close(fd)}
 var target=parent
 for name in components {
 guard !name.isEmpty,name.utf8.count<256,name != ".",name != "..",!name.contains("/"),!name.contains(":"),!name.contains("\0") else{throw VoiceyError.invalid("Invalid folder component.")}
 try Task.checkCancellation()
 var child=openat(fd,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
 if child<0,errno==ENOENT,create {
 if mkdirat(fd,name,0o755) != 0,errno != EEXIST {throw VoiceyError.unavailable("Could not create \(name): \(String(cString:strerror(errno)))")}
 child=openat(fd,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
 }
 guard child>=0 else{throw VoiceyError.unavailable("\(name) is missing, inaccessible, a symlink, or not a directory. Nothing was overwritten.")}
 close(fd);fd=child;target.appendPathComponent(name,isDirectory:true)
 }
 // Recheck the namespace too; an unlinked open descriptor is not completion evidence.
 guard target.resolvingSymlinksInPath().path==target.path, FileManager.default.fileExists(atPath:target.path) else{throw VoiceyError.unavailable("The target changed during execution.")}
 return target
 }
}
@MainActor public final class FilesystemComputerAdapter: ComputerAdapter {
 public let descriptor=AdapterDescriptor("Native filesystem",[.ensureDirectory,.verifyFile],permissions:["authorized filesystem scope"],verification:"openat directory descriptors and live metadata")
 public var filesystem:AuthorizedFilesystem
 public init(roots:[URL]){filesystem=AuthorizedFilesystem(roots:roots)}
 public func observe(_ step:ComputerStep) async throws -> Verification {
 let a=step.arguments
 if step.operation == .verifyFile {
 let parent=try filesystem.authorize(a.root)
 guard !a.output.isEmpty,!a.output.hasPrefix("/"),!a.output.split(separator:"/").contains("..") else{throw VoiceyError.invalid("Expected output must be relative to the working folder.")}
 let target=parent.appendingPathComponent(a.output).standardizedFileURL
 guard target.resolvingSymlinksInPath().path.hasPrefix(parent.path+"/") else{throw VoiceyError.invalid("Output escaped the authorized folder.")}
 return Verification(FileManager.default.fileExists(atPath:target.path) ? .success:.failure,"Output file: \(target.path)")
 }
 do{let url=try filesystem.directory(root:a.root,components:a.components,create:false);return Verification(.success,"Verified directory: \(url.path)")}catch{return Verification(.failure,error.localizedDescription)}
 }
 public func execute(_ step:ComputerStep) async throws -> AdapterResult {
 if step.operation == .verifyFile {return .verified(try await observe(step))}
 _ = try filesystem.directory(root:step.arguments.root,components:step.arguments.components,create:true)
 return .verified(try await observe(step))
 }
}
