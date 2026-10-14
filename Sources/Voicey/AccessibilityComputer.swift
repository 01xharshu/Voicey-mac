import AppKit
import ApplicationServices
import Vision
import ScreenCaptureKit
import VoiceyCore

struct AccessibleControl {
 let element:AXUIElement, role:String, label:String, value:String, enabled:Bool, actions:[String]
}
@MainActor final class AccessibilityComputer {
 var available:Bool{AXIsProcessTrusted()}
 func value(_ element:AXUIElement,_ key:String)->CFTypeRef? {var result:CFTypeRef?;guard AXUIElementCopyAttributeValue(element,key as CFString,&result) == .success else{return nil};return result}
 func controls(pid:pid_t) throws -> [AccessibleControl] {
 guard available else{throw VoiceyError.unavailable("Enable Accessibility for Voicey in System Settings to inspect this app.")}
 let app=AXUIElementCreateApplication(pid);AXUIElementSetMessagingTimeout(app,0.5)
 var queue:[AXUIElement]=[app],result:[AccessibleControl]=[],seen=Set<CFHashCode>(),index=0
 while index<queue.count,index<1600 {
 try Task.checkCancellation();let e=queue[index];index+=1
 guard seen.insert(CFHash(e)).inserted else{continue}
 let role=value(e,kAXRoleAttribute) as? String ?? ""
 let label=[kAXTitleAttribute,kAXDescriptionAttribute,kAXHelpAttribute,kAXIdentifierAttribute].compactMap{value(e,$0) as? String}.filter{!$0.isEmpty}.joined(separator:" ")
 let text=String((value(e,kAXValueAttribute) as? String ?? "").prefix(4096))
 var names:CFArray?;AXUIElementCopyActionNames(e,&names)
 result.append(AccessibleControl(element:e,role:role,label:label,value:text,enabled:(value(e,kAXEnabledAttribute) as? Bool) != false,actions:names as? [String] ?? []))
 if let children=value(e,kAXChildrenAttribute) as? [AXUIElement]{queue.append(contentsOf:children.prefix(200))}
 }
 return result
 }
 func window(pid:pid_t)->AXUIElement? {value(AXUIElementCreateApplication(pid),kAXFocusedWindowAttribute).map{unsafeBitCast($0,to:AXUIElement.self)}}
 func assertForeground(_ pid:pid_t) throws {guard NSWorkspace.shared.frontmostApplication?.processIdentifier==pid else{throw VoiceyError.unavailable("The target app lost focus. Stopped before issuing input.")}}
 func fill(_ c:AccessibleControl,text:String,pid:pid_t) throws {
 try assertForeground(pid);guard c.enabled else{throw VoiceyError.unavailable("The target field is disabled.")}
 var settable:DarwinBoolean=false
 guard AXUIElementIsAttributeSettable(c.element,kAXValueAttribute as CFString,&settable) == .success,settable.boolValue else{throw VoiceyError.unavailable("This control does not support setting its value through Accessibility.")}
 _ = AXUIElementSetAttributeValue(c.element,kAXFocusedAttribute as CFString,kCFBooleanTrue)
 guard AXUIElementSetAttributeValue(c.element,kAXValueAttribute as CFString,text as CFString) == .success else{throw VoiceyError.unavailable("Accessibility field update failed.")}
 guard value(c.element,kAXValueAttribute) as? String == text else{throw VoiceyError.unavailable("The field did not retain the requested text.")}
 }
 func press(_ c:AccessibleControl,pid:pid_t) throws {
 try assertForeground(pid);guard c.enabled,c.actions.contains(kAXPressAction),AXUIElementPerformAction(c.element,kAXPressAction as CFString) == .success else{throw VoiceyError.unavailable("The identified control cannot be pressed.")}
 }
}
struct VisualText {let text:String;let rect:CGRect}
struct VisualObservation {let pid:pid_t;let windowID:CGWindowID;let frame:CGRect;let captured:Date;let text:[VisualText]}
@MainActor final class VisualComputer {
 private var interrupted=false,monitor:Any?
 init(){monitor=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.keyDown]){[weak self] _ in Task{@MainActor in self?.interrupted=true}}}
 var available:Bool{CGPreflightScreenCaptureAccess() && AXIsProcessTrusted()}
 func cancel(){interrupted=true}
 func capture(pid:pid_t) async throws -> VisualObservation {
 guard CGPreflightScreenCaptureAccess() else{throw VoiceyError.unavailable("Screen Recording is required for visual inspection; enable it in Computer Use settings.")}
 guard NSWorkspace.shared.frontmostApplication?.processIdentifier==pid else{throw VoiceyError.unavailable("The target application is not in front.")}
 let front=(CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []).first{$0[kCGWindowOwnerPID as String] as? pid_t==pid && $0[kCGWindowLayer as String] as? Int==0}?[kCGWindowNumber as String] as? UInt32
 let content=try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true)
 guard let window=content.windows.first(where:{$0.owningApplication?.processID==pid && $0.windowID==front && $0.windowLayer==0}) else{throw VoiceyError.unavailable("No visible target window can be captured.")}
 let filter=SCContentFilter(desktopIndependentWindow:window),config=SCStreamConfiguration()
 config.width=Int(window.frame.width*2);config.height=Int(window.frame.height*2);config.showsCursor=false
 let image=try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
 let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate
 try VNImageRequestHandler(cgImage:image).perform([request]);try Task.checkCancellation()
 let words=(request.results ?? []).compactMap{r->VisualText? in guard let text=r.topCandidates(1).first?.string else{return nil};return VisualText(text:text,rect:r.boundingBox)}
 interrupted=false
 return VisualObservation(pid:pid,windowID:window.windowID,frame:window.frame,captured:Date(),text:words)
 }
 // Used only for a uniquely recognized visible control. A new capture is mandatory
 // after this action; callers cannot replay old coordinates.
 func click(text:String,in observation:VisualObservation) throws {
 guard available,!interrupted,Date().timeIntervalSince(observation.captured)<2,NSWorkspace.shared.frontmostApplication?.processIdentifier==observation.pid else{throw VoiceyError.unavailable("Visual observation expired or the user took control.")}
 let matches=observation.text.filter{$0.text.caseInsensitiveCompare(text) == .orderedSame}
 guard matches.count==1,let item=matches.first else{throw VoiceyError.unavailable("The visible target isn't unique.")}
 let windows=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
 guard let first=windows.first(where:{$0[kCGWindowOwnerPID as String] as? pid_t==observation.pid && $0[kCGWindowLayer as String] as? Int==0}),first[kCGWindowNumber as String] as? UInt32==observation.windowID else{throw VoiceyError.unavailable("Target window changed.")}
 let p=CGPoint(x:observation.frame.minX+item.rect.midX*observation.frame.width,y:observation.frame.minY+(1-item.rect.midY)*observation.frame.height)
 CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:p,mouseButton:.left)?.post(tap:.cghidEventTap)
 CGEvent(mouseEventSource:nil,mouseType:.leftMouseUp,mouseCursorPosition:p,mouseButton:.left)?.post(tap:.cghidEventTap)
 interrupted=true
 }
}
