// Throwaway spike tool: one real left click at screen point (x, y). System Settings' wallpaper tiles have no
// AXPress action, so selecting "Livepaper" without a person takes this. Needs the Accessibility permission.
//   swift scripts/click.swift 481 796

import CoreGraphics
import Foundation
let x = Double(CommandLine.arguments[1])!, y = Double(CommandLine.arguments[2])!
let p = CGPoint(x: x, y: y)
let src = CGEventSource(stateID: .hidSystemState)
CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(150_000)
CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(80_000)
CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
