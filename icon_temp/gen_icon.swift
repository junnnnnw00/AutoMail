import Cocoa

let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let ctx = NSGraphicsContext.current!.cgContext
ctx.clear(CGRect(origin: .zero, size: size))

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowOffset = NSSize(width: 0, height: -15)
shadow.shadowBlurRadius = 25

// Gradient Squircle
ctx.saveGState()
shadow.set()
let bgRect = NSRect(x: 102, y: 102, width: 820, height: 820)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 185, yRadius: 185)
NSColor.white.set()
bgPath.fill() // dummy fill for shadow
ctx.restoreGState()

// Draw the actual gradient inside the squircle (without shadow leaking inside)
let gradient = NSGradient(starting: NSColor(red: 0.1, green: 0.4, blue: 0.85, alpha: 1.0),
                          ending: NSColor(red: 0.3, green: 0.7, blue: 0.98, alpha: 1.0))
gradient?.draw(in: bgPath, angle: 90)

// Envelope Base
ctx.saveGState()
shadow.set()
let envRect = NSRect(x: 252, y: 332, width: 520, height: 360)
let envPath = NSBezierPath(roundedRect: envRect, xRadius: 24, yRadius: 24)
NSColor.white.set()
envPath.fill()
ctx.restoreGState()

// Envelope flap
let flapPath = NSBezierPath()
flapPath.move(to: NSPoint(x: 252, y: 668)) // top left minus corner radius
flapPath.line(to: NSPoint(x: 512, y: 460))
flapPath.line(to: NSPoint(x: 772, y: 668))
flapPath.line(to: NSPoint(x: 772, y: 668 + 24))
flapPath.line(to: NSPoint(x: 252, y: 668 + 24))
flapPath.close()

// draw flap shadow
ctx.saveGState()
let flapShadow = NSShadow()
flapShadow.shadowColor = NSColor.black.withAlphaComponent(0.15)
flapShadow.shadowOffset = NSSize(width: 0, height: -5)
flapShadow.shadowBlurRadius = 10
flapShadow.set()
NSColor(white: 0.96, alpha: 1.0).set()
flapPath.fill()
ctx.restoreGState()

let flapOutline = NSBezierPath()
flapOutline.move(to: NSPoint(x: 252, y: 668))
flapOutline.line(to: NSPoint(x: 512, y: 460))
flapOutline.line(to: NSPoint(x: 772, y: 668))
flapOutline.lineWidth = 12
flapOutline.lineCapStyle = .round
flapOutline.lineJoinStyle = .round
NSColor(white: 0.9, alpha: 1.0).set()
flapOutline.stroke()

image.unlockFocus()

if let tiff = image.tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: tiff),
   let pngData = bitmap.representation(using: .png, properties: [:]) {
    try? pngData.write(to: URL(fileURLWithPath: "icon_temp/icon_1024x1024.png"))
}
