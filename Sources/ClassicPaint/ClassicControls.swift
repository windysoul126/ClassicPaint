import AppKit

final class ClassicButton: NSButton {
    var icon = ""
    var large = false
    var iconOnly = false
    var fileTab = false
    var tab = false
    var swatch: NSColor?
    var shapePreview: CGPath?
    private var hovering = false
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect:bounds, options:[.activeAlways,.mouseEnteredAndExited,.inVisibleRect],owner:self))
    }
    override func mouseEntered(with event:NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event:NSEvent) { hovering = false; needsDisplay = true }
    override func draw(_ dirtyRect:NSRect) {
        let r = bounds.insetBy(dx:0.5,dy:0.5)
        if fileTab {
            NSGradient(starting:NSColor(rgb:0x5795D0),ending:NSColor(rgb:0x2264A6))!.draw(in:r,angle:90)
            NSColor(rgb:0x205893).setStroke(); NSBezierPath(rect:r).stroke()
        } else if state == .on || hovering || isHighlighted {
            let start:UInt32 = tab ? 0xFFFFFF : 0xFFF4D6
            let end:UInt32 = tab ? 0xEAF0F7 : 0xFFDF96
            NSGradient(starting:NSColor(rgb:start),ending:NSColor(rgb:end))!.draw(in:r,angle:90)
            NSColor(rgb:tab ? 0xB8C8D9 : 0xE6B44A).setStroke(); NSBezierPath(rect:r).stroke()
        }
        let attrs:[NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:11),.foregroundColor:fileTab ? NSColor.white : NSColor(rgb:0x172434)]
        let text = title as NSString
        let sz = text.size(withAttributes:attrs)
        if let path = shapePreview,let c = NSGraphicsContext.current?.cgContext {
            c.saveGState(); c.setStrokeColor(NSColor(rgb:0x23394F).cgColor); c.setLineWidth(1); c.addPath(path); c.strokePath(); c.restoreGState()
        } else if let color = swatch {
            let box = NSRect(x:(bounds.width-28)/2,y:8,width:28,height:28)
            NSColor.white.setFill(); box.insetBy(dx:-3,dy:-3).fill()
            color.setFill(); box.fill(); NSColor(rgb:0x8393A2).setStroke(); NSBezierPath(rect:box.insetBy(dx:-1,dy:-1)).stroke()
        } else if !icon.isEmpty {
            let side:CGFloat = large ? 30 : 16
            let rect = NSRect(x:large || iconOnly ? (bounds.width-side)/2 : 4,y:large ? 6 : (bounds.height-side)/2,width:side,height:side)
            drawIcon(icon,in:rect)
        }
        if !iconOnly {
            let x = large || tab || fileTab || icon.isEmpty ? (bounds.width-sz.width)/2 : 24
            let y:CGFloat = large ? 44 : (bounds.height-sz.height)/2
            text.draw(at:NSPoint(x:x,y:y),withAttributes:attrs)
        }
        if large && swatch == nil {
            let p = NSBezierPath(); let x = bounds.midX; p.move(to:NSPoint(x:x-3,y:bounds.height-7)); p.line(to:NSPoint(x:x+3,y:bounds.height-7)); p.line(to:NSPoint(x:x,y:bounds.height-4)); p.close(); NSColor(rgb:0x344454).setFill(); p.fill()
        }
    }
    func drawIcon(_ name:String,in r:NSRect) {
        if name == "lines" {
            NSColor(rgb:0x23394F).setFill()
            for i in 0..<4 { NSRect(x:r.minX,y:r.minY+CGFloat(i)*8,width:r.width,height:CGFloat(i+1)).fill() }; return
        }
        if name == "palette" {
            let colors:[UInt32] = [0xED1C24,0xFF7F27,0xFFF200,0x22B14C,0x00A2E8,0xA349A4,0xFFAEC9,0x99D9EA,0xB5E61D]
            for i in 0..<9 { NSColor(rgb:colors[i]).setFill(); NSRect(x:r.minX+CGFloat(i%3)*r.width/3,y:r.minY+CGFloat(i/3)*r.height/3,width:r.width/3,height:r.height/3).fill() }; return
        }
        let colors:[String:UInt32] = ["pencil":0xCF9E22,"paintbrush.pointed.fill":0xAD722F,"paintbrush.fill":0xAD722F,"eraser.fill":0xD985A1,"eyedropper":0x4272A2,"doc.on.clipboard.fill":0xBB8C38,"scissors":0x4272A2,"doc.on.doc":0x4272A2,"externaldrive.fill":0x527FAD]
        guard let image = NSImage(systemSymbolName:name,accessibilityDescription:nil) else { return }
        let tinted = NSImage(size:image.size); tinted.lockFocus(); image.draw(at:.zero,from:.zero,operation:.sourceOver,fraction:1); NSColor(rgb:colors[name] ?? 0x334C64).setFill(); NSRect(origin:.zero,size:image.size).fill(using:.sourceAtop); tinted.unlockFocus()
        tinted.draw(in:r)
    }
}
final class ClassicDocument: NSView { override var isFlipped:Bool { true } }
