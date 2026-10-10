import AppKit
import Foundation
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for (name, size) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 65, y: 65, width: 894, height: 894), xRadius: 200, yRadius: 200)
    NSColor(red: 0.06, green: 0.10, blue: 0.15, alpha: 1).setFill(); background.fill()
    NSColor(red: 0.17, green: 0.27, blue: 0.35, alpha: 1).setStroke(); background.lineWidth = 4; background.stroke()
    let halo = NSBezierPath(ovalIn: NSRect(x: 170, y: 170, width: 684, height: 684))
    NSColor(red: 0.44, green: 0.90, blue: 0.96, alpha: 0.15).setStroke(); halo.lineWidth = 2; halo.stroke()
    func polygon(_ points: [NSPoint], color: NSColor) {
        color.setFill(); let path = NSBezierPath(); path.move(to: points[0]); for point in points.dropFirst() { path.line(to: point) }; path.close(); path.fill()
    }
    polygon([NSPoint(x: 518,y: 770),NSPoint(x: 283,y: 307),NSPoint(x: 402,y: 345),NSPoint(x: 574,y: 655)], color: NSColor(red: 0.44, green: 0.91, blue: 0.96, alpha: 1))
    polygon([NSPoint(x: 564,y: 613),NSPoint(x: 742,y: 307),NSPoint(x: 625,y: 345),NSPoint(x: 465,y: 504)], color: NSColor(red: 0.42, green: 0.66, blue: 0.81, alpha: 1))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
}
