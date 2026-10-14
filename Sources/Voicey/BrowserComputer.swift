import AppKit
import Darwin
import VoiceyCore

private final class BrowserCancellation:@unchecked Sendable {
 private let lock=NSLock();private var descriptor:Int32?;private var cancelled=false
 func attach(_ fd:Int32){lock.lock();defer{lock.unlock()};descriptor=fd;if cancelled{shutdown(fd,SHUT_RDWR)}}
 func detach(){lock.lock();defer{lock.unlock()};descriptor=nil}
 func cancel(){lock.lock();defer{lock.unlock()};cancelled=true;if let fd=descriptor{shutdown(fd,SHUT_RDWR)}}
}
@MainActor final class LocalBrowserBridge {
 private var activeCancellation:BrowserCancellation?
 func cancel(){activeCancellation?.cancel();activeCancellation=nil}
 let root=supportDirectory.appendingPathComponent("BrowserBridge")
 var connectedBrowsers:[String]{(try? FileManager.default.contentsOfDirectory(atPath:root.path))?.filter{$0.hasSuffix(".sock")}.map{String($0.dropLast(5))} ?? []}
 func available(_ browser:InstalledApp)->Bool{FileManager.default.fileExists(atPath:root.appendingPathComponent(browser.bundleID+".sock").path)}
 func send(_ command:BrowserCommand,browser:InstalledApp) async throws -> BrowserReply {
 try command.validate()
 let path=root.appendingPathComponent(browser.bundleID+".sock").path
 let config=root.appendingPathComponent("voicey-host-"+browser.bundleID+".json")
 let attrs=try FileManager.default.attributesOfItem(atPath:config.path)
 guard (attrs[.ownerAccountID] as? NSNumber)?.uint32Value==getuid(),(attrs[.posixPermissions] as? NSNumber)?.intValue==0o600 else{throw VoiceyError.invalid("Unsafe bridge configuration permissions")}
 let data=try Data(contentsOf:config)
 guard let object=try JSONSerialization.jsonObject(with:data) as? [String:Any],let token=object["token"] as? String else{throw VoiceyError.invalid("Missing bridge authentication")}
 let bytes=try JSONEncoder().encode(BrowserEnvelope(token:token,command:command))
 let cancellation=BrowserCancellation();activeCancellation=cancellation
 defer{activeCancellation=nil}
 let job=Task.detached{()throws->BrowserReply in
 let fd=socket(AF_UNIX,SOCK_STREAM,0);guard fd>=0 else{throw VoiceyError.unavailable("Browser IPC unavailable")};defer{cancellation.detach();close(fd)}
 cancellation.attach(fd)
 var noPipe:Int32=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noPipe,socklen_t(MemoryLayout<Int32>.size))
 var timeout=timeval(tv_sec:18,tv_usec:0);setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size));setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
 var address=sockaddr_un();address.sun_family=sa_family_t(AF_UNIX);let chars=Array(path.utf8CString)
 guard chars.count<MemoryLayout.size(ofValue:address.sun_path) else{throw VoiceyError.invalid("Bridge socket path too long")}
 withUnsafeMutableBytes(of:&address.sun_path){$0.copyBytes(from:chars.map{UInt8(bitPattern:$0)})}
 let result=withUnsafePointer(to:&address){p in p.withMemoryRebound(to:sockaddr.self,capacity:1){connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}
 guard result==0 else{throw VoiceyError.unavailable("The browser bridge is disconnected. Open its extension popup and Connect.")}
 var uid:uid_t=0,gid:gid_t=0;guard getpeereid(fd,&uid,&gid)==0,uid==getuid() else{throw VoiceyError.invalid("Wrong IPC peer")}
 let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:false)
 var length=UInt32(bytes.count).littleEndian;try handle.write(contentsOf:Data(bytes:&length,count:4));try handle.write(contentsOf:bytes)
 func read(_ count:Int)throws->Data{var data=Data();while data.count<count {try Task.checkCancellation();guard let next=try handle.read(upToCount:count-data.count),!next.isEmpty else{throw VoiceyError.unavailable("Browser bridge ended before verification")};data.append(next)};return data}
 let header=try read(4),size=header.withUnsafeBytes{$0.loadUnaligned(as:UInt32.self).littleEndian}
 guard size>0,size<=1_048_576 else{throw VoiceyError.invalid("Invalid browser reply size")}
 let reply=try JSONDecoder().decode(BrowserReply.self,from:read(Int(size)));try reply.validate(for:command);return reply
 }
 let reply=try await withTaskCancellationHandler(operation:{try await job.value},onCancel:{job.cancel();cancellation.cancel()})
 try Task.checkCancellation();return reply
 }
}
@MainActor final class BrowserComputerAdapter:ComputerAdapter {
 let descriptor=AdapterDescriptor("Local browser bridge / Accessibility",[.navigate,.inspectPage,.fillPrompt,.submitPrompt,.gmailDraft],permissions:["site-specific extension permission","Automation for Arc origin fallback","Accessibility if bridge missing"],verification:"actual URL, semantic field value, submitted user message, Gmail saved-draft indicator",limitations:"Gmail requires bridge and English semantic controls; login/consent completed by user; uncertain external actions never retried")
 let native:NativeComputerAdapter,bridge=LocalBrowserBridge(),ax=AccessibilityComputer(),visual=VisualComputer()
 private var evidence:[UUID:Verification]=[:]
 private var touched=Set<UUID>()
 init(native:NativeComputerAdapter){self.native=native}
 func cancel(){bridge.cancel();visual.cancel();evidence=[:];touched=[]}
 func finish(){evidence=[:];touched=[]}
 func observe(_ step:ComputerStep) async throws -> Verification {
 let a=step.arguments,browser=try native.application(a.application)
 if bridge.available(browser) {
 var cmd=BrowserCommand(.inspect,url:a.url);cmd.text=a.text
 let r=try await bridge.send(cmd,browser:browser)
 if !r.ok{return Verification(.unknown,r.detail)}
 switch step.operation {
 case .navigate:return Verification(.success,"Actual authorized origin: \(r.url)")
 case .inspectPage:return Verification(r.state=="ready" ? .success:.unknown,r.detail)
 case .fillPrompt:return Verification(r.prompt==a.text ? .success:.failure,"Prompt value compared with exact requested text")
 case .submitPrompt:return Verification(touched.contains(step.id) && r.submitted==true ? .success:.unknown,evidence[step.id]?.detail ?? "Submission not acknowledged")
 case .gmailDraft:return evidence[step.id] ?? Verification(.unknown,"No verified Gmail draft yet")
 default:break
 }
 }
 if step.operation == .navigate {
 if browser.bundleID=="company.thebrowser.Browser" {
 let actual=try await arcURL()
 if let url=URL(string:actual),url.scheme=="https",url.host==URL(string:a.url)?.host,url.port==nil{return Verification(.success,"Arc scripting observed actual URL: \(actual)")}
 }
 return Verification(.unknown,"Actual destination not verified; browser bridge unavailable")
 }
 return try await axObserve(step,browser:browser)
 }
 func execute(_ step:ComputerStep) async throws -> AdapterResult {
 let a=step.arguments,browser=try native.application(a.application)
 if bridge.available(browser) {
 let operation:BrowserOperation
 switch step.operation {case .navigate:operation = .navigate;case .inspectPage:operation = .inspect;case .fillPrompt:operation = .fillPrompt;case .submitPrompt:operation = .submitPrompt;case .gmailDraft:operation = .gmailDraft;default:throw VoiceyError.invalid("Unknown browser operation")}
 var cmd=BrowserCommand(operation,url:a.url);cmd.text=a.text;cmd.recipient=a.recipient;cmd.subject=a.subject
 let r=try await bridge.send(cmd,browser:browser)
 if ["login","loading","consent","missing"].contains(r.state) {return .wait("\(r.detail). Complete login/consent or wait in \(browser.name), then say ‘continue’. No access controls will be bypassed.")}
 touched.insert(step.id)
 let verified=r.ok && (step.operation != .submitPrompt || r.submitted==true) && (step.operation != .gmailDraft || r.draftSaved==true && r.recipient==a.recipient && r.body==a.text)
 let result=Verification(verified ? .success:.unknown,r.detail);evidence[step.id]=result;return .verified(result)
 }
 if step.operation == .navigate {
 try await native.discovery.website(try URLValidator.validate(a.url),browser:browser)
 for _ in 0..<20 {try Task.checkCancellation();let r=try await observe(step);if r.state == .success{return .verified(r)};try await Task.sleep(nanoseconds:250_000_000)}
 return .wait("Opened the requested destination, but the actual origin could not be verified. Install/connect the browser bridge or enable Arc Automation; then continue.")
 }
 if step.operation == .gmailDraft {throw VoiceyError.unavailable("Gmail drafting requires the local bridge and Gmail permission. No draft was created.")}
 let status=try await axObserve(step,browser:browser)
 if status.state == .success {return .verified(status)}
 guard let app=NSRunningApplication.runningApplications(withBundleIdentifier:browser.bundleID).first else{throw VoiceyError.unavailable("The browser closed.")}
 if ax.available {
 let controls=try ax.controls(pid:app.processIdentifier)
 let fields=controls.filter{["AXTextArea","AXTextField"].contains($0.role) && $0.label.range(of:"message|prompt|ask",options:[.regularExpression,.caseInsensitive]) != nil}
 if step.operation == .fillPrompt,fields.count==1 {
 guard fields[0].value.isEmpty || fields[0].value==a.text else{throw VoiceyError.unavailable("The prompt field already contains other text.")}
 try ax.fill(fields[0],text:a.text,pid:app.processIdentifier);return .verified(try await axObserve(step,browser:browser))
 }
 if step.operation == .submitPrompt,fields.count==1,fields[0].value==a.text {
 let send=controls.filter{$0.role=="AXButton" && ["send","send message","send prompt"].contains($0.label.lowercased())}
 guard send.count==1 else{throw VoiceyError.unavailable("No unique accessible Send button")}
 try ax.press(send[0],pid:app.processIdentifier);touched.insert(step.id)
 for _ in 0..<15 {try Task.checkCancellation();let result=try await axObserve(step,browser:browser);if result.state == .success{return .verified(result)};try await Task.sleep(nanoseconds:200_000_000)}
 return .verified(Verification(.unknown,"Submission attempted through Accessibility; acknowledgement unavailable. Inspect the conversation. No automatic retry."))
 }
 }
 if visual.available {
 let screen=try await visual.capture(pid:app.processIdentifier)
 if screen.text.contains(where:{$0.text.range(of:"log in|sign in",options:[.regularExpression,.caseInsensitive]) != nil}){return .wait("Sign in to the website in your browser, then continue.")}
 // Visual-only text cannot prove a DOM origin or safely identify a web editor.
 return .verified(Verification(.unknown,"Local OCR inspected \(screen.text.count) text regions. A reliable semantic target isn't available; connect the browser bridge. No coordinate input was issued."))
 }
 return .wait("Browser bridge unavailable and no reliable accessible prompt was found. Enable Accessibility or install the bridge, then continue.")
 }
 private func arcURL() async throws -> String {try await AppleScripting.run("tell application id \"company.thebrowser.Browser\" to get URL of active tab of front window")}
 private func axObserve(_ step:ComputerStep,browser:InstalledApp) async throws -> Verification {
 guard browser.bundleID=="company.thebrowser.Browser",let actual=URL(string:try await arcURL()),actual.scheme=="https",actual.host==URL(string:step.arguments.url)?.host else{return Verification(.unknown,"Origin cannot be verified through this browser's scripting adapter. Connect the local bridge.")}
 guard let app=NSRunningApplication.runningApplications(withBundleIdentifier:browser.bundleID).first else{throw VoiceyError.unavailable("The browser is no longer running")}
 let controls=try ax.controls(pid:app.processIdentifier)
 let fields=controls.filter{["AXTextArea","AXTextField"].contains($0.role) && $0.label.range(of:"message|prompt|ask",options:[.regularExpression,.caseInsensitive]) != nil}
 if step.operation == .inspectPage {return Verification(fields.count==1 ? .success:.unknown,"Accessibility prompt discovery: \(fields.count) matches")}
 if step.operation == .fillPrompt {return Verification(fields.count==1 && fields[0].value==step.arguments.text ? .success:.failure,"Accessible prompt value inspected")}
 if step.operation == .submitPrompt {
 let message=controls.contains{$0.role=="AXStaticText" && $0.value==step.arguments.text}
 return Verification(touched.contains(step.id) && message && fields.count==1 && fields[0].value.isEmpty ? .success:.unknown,"Checked visible question text and cleared prompt")
 }
 return Verification(.unknown,"No supported accessible verification")
 }
}
