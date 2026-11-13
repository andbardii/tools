// Touchscreen -> mouse per macOS: legge i digitizer USB HID (usage page 13)
// e li trasforma in movimento/click del cursore sullo schermo scelto.
import Foundation
import IOKit.hid
import CoreGraphics
import ApplicationServices
import AppKit

func displays() -> [CGDirectDisplayID] {
    var n: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &n)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
    CGGetOnlineDisplayList(n, &ids, &n)
    return ids
}

func describe(_ id: CGDirectDisplayID) -> String {
    let b = CGDisplayBounds(id)
    return "id \(id): \(Int(b.width))x\(Int(b.height)) in (\(Int(b.origin.x)),\(Int(b.origin.y)))"
        + (CGDisplayIsMain(id) != 0 ? " [principale]" : "")
        + (CGDisplayIsBuiltin(id) != 0 ? " [integrato]" : "")
        + " \"\(name(id))\""
}

if CommandLine.arguments.contains("list") {
    displays().forEach { print(describe($0)) }
    exit(0)
}

// Schermo di destinazione, in ordine: TOUCH_DISPLAY=<id>; poi il monitor il cui nome contiene
// TOUCH_SCREEN (default "MPI107", il touchscreen); altrimenti l'ultimo schermo non principale.
func name(_ id: CGDirectDisplayID) -> String {
    NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }?
        .localizedName ?? ""
}

func targetDisplay() -> CGDirectDisplayID {
    let env = ProcessInfo.processInfo.environment
    if let s = env["TOUCH_DISPLAY"], let v = UInt32(s), displays().contains(v) { return v }
    let wanted = env["TOUCH_SCREEN"] ?? "MPI107"
    if let byName = displays().first(where: { name($0).localizedCaseInsensitiveContains(wanted) }) { return byName }
    let others = displays().filter { CGDisplayIsMain($0) == 0 }
    return others.max { CGDisplayBounds($0).origin.x < CGDisplayBounds($1).origin.x } ?? CGMainDisplayID()
}

let debug = ProcessInfo.processInfo.environment["TOUCH_DEBUG"] != nil

struct Axis { var min = 0, max = 1 }
final class Touch {
    var x = Axis(), y = Axis()
    var rawX = 0, rawY = 0
    var down = false          // dito appoggiato (tip switch)
    var sent = false          // mouseDown già inviato
    var contact = 0           // contact id corrente
    var primary = 0           // dito seguito (il primo che tocca)
}
let touch = Touch()

func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

func point() -> CGPoint {
    let b = CGDisplayBounds(targetDisplay())
    let fx = Double(touch.rawX - touch.x.min) / Double(max(1, touch.x.max - touch.x.min))
    let fy = Double(touch.rawY - touch.y.min) / Double(max(1, touch.y.max - touch.y.min))
    return CGPoint(x: b.origin.x + min(max(fx, 0), 1) * (b.width - 1),
                   y: b.origin.y + min(max(fy, 0), 1) * (b.height - 1))
}

func update() {
    let p = point()
    if debug { print("evento: down=\(touch.down) -> \(Int(p.x)),\(Int(p.y)) fiducia=\(AXIsProcessTrusted())"); fflush(stdout) }
    if touch.down {
        post(touch.sent ? .leftMouseDragged : .leftMouseDown, p)
        touch.sent = true
    } else if touch.sent {
        post(.leftMouseUp, p)
        touch.sent = false
    }
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: 13] as CFDictionary)

let onValue: IOHIDValueCallback = { _, _, _, value in
    let e = IOHIDValueGetElement(value)
    let page = IOHIDElementGetUsagePage(e), usage = IOHIDElementGetUsage(e)
    let v = IOHIDValueGetIntegerValue(value)
    if debug { print("hid page \(page) usage \(usage) valore \(v)"); fflush(stdout) }
    switch (page, usage) {
    case (13, 0x51):                                  // Contact ID
        touch.contact = v
    case (13, 0x42):                                  // Tip Switch
        if v != 0 && !touch.down { touch.primary = touch.contact }
        if touch.contact == touch.primary { touch.down = v != 0; update() }
    case (1, 0x30):                                   // X
        if touch.contact == touch.primary {
            if touch.x.max <= 1 { touch.x = Axis(min: IOHIDElementGetLogicalMin(e), max: IOHIDElementGetLogicalMax(e)) }
            touch.rawX = v
        }
    case (1, 0x31):                                   // Y
        if touch.contact == touch.primary {
            if touch.y.max <= 1 { touch.y = Axis(min: IOHIDElementGetLogicalMin(e), max: IOHIDElementGetLogicalMax(e)) }
            touch.rawY = v; if touch.down { update() }
        }
    default: break
    }
}

let onAttach: IOHIDDeviceCallback = { _, _, _, device in
    let name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "sconosciuto"
    print("Touch collegato: \(name) -> schermo \(describe(targetDisplay()))")
    fflush(stdout)
}

IOHIDManagerRegisterDeviceMatchingCallback(manager, onAttach, nil)
IOHIDManagerRegisterInputValueCallback(manager, onValue, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
let r = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
if r != kIOReturnSuccess {
    FileHandle.standardError.write("Impossibile leggere il touch (0x\(String(r, radix: 16))): consenti il Monitoraggio input in Impostazioni di Sistema > Privacy e sicurezza.\n".data(using: .utf8)!)
    exit(1)
}
// Nessun prompt a ogni avvio: il permesso Accessibilità si dà una volta sola.
let input = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
print("Monitoraggio input: \(input == kIOHIDAccessTypeGranted ? "consentito" : "NON consentito (stato \(input.rawValue)): richiedo il permesso")")
if input != kIOHIDAccessTypeGranted { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
let trusted = AXIsProcessTrusted()
print("Accessibilità: \(trusted ? "consentita" : "NON consentita (Impostazioni di Sistema > Privacy e sicurezza > Accessibilità > Touchscreen)")")
print("In ascolto sul touch. Schermo: \(describe(targetDisplay()))")
fflush(stdout)
CFRunLoopRun()
