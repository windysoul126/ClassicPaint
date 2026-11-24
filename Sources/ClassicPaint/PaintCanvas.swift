import AppKit

let shapeNames = ["直线","曲线","椭圆","矩形","圆角矩形","三角形","直角三角形","菱形","五边形","六边形","向右箭头","向左箭头","向上箭头","向下箭头","四角星","五角星","六角星","圆角矩形标注","椭圆标注","云形标注","多边形","闪电","心形"]
final class Canvas: NSView {
    let document = RasterDocument()
    var primary:NSColor = .black; var secondary:NSColor = .white
    var tool = "铅笔" { didSet { invalidateToolCursor() } }
    var width:CGFloat = 3 { didSet { invalidateToolCursor() } }
    var brush = "画笔" { didSet { invalidateToolCursor() } }
    var outline = "纯色"; var shapeFill = "无填充"
    var transparentSelection = false; var freeSelection = false
    var grid = false
    var selection:CGRect?; var selectionPath:CGPath?
    var textFont = NSFont(name:"Helvetica",size:20)!; var textOpaque = false
    var textEditor:NSTextView?
    var status:((String)->Void)?; var changed:(()->Void)?; var colorChanged:(()->Void)?; var zoomRequested:((Bool)->Void)?; var textModeChanged:((Bool)->Void)?
    private var before:RasterState?
    private var start = CGPoint.zero; private var last = CGPoint.zero
    private var right = false; private var moving = false; private var resizingSelection = false; private var resizingCanvas = false
    private var originalSelection:CGRect?; private var movingImage:CGImage?; private var movingPath:CGPath?
    private var lasso:[CGPoint] = []
    private var curvePoints:[CGPoint] = []; private var curveBase:RasterState?
    private var polygon:[CGPoint] = []; private var polygonBase:RasterState?
    override var isFlipped:Bool { true }
    override var acceptsFirstResponder:Bool { true }
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
    override init(frame:NSRect) {
        super.init(frame:frame)
        document.onChange = { [weak self] in self?.refresh() }
        registerForDraggedTypes([.fileURL,.tiff,.png])
    }
    required init?(coder:NSCoder) { fatalError() }
    func refresh() { frame.size = document.size; superview?.setFrameSize(NSSize(width:document.width+24,height:document.height+24)); needsDisplay = true; changed?() }
    override func updateTrackingAreas() { super.updateTrackingAreas(); trackingAreas.forEach(removeTrackingArea); addTrackingArea(NSTrackingArea(rect:bounds,options:[.activeInKeyWindow,.mouseMoved,.inVisibleRect],owner:self)) }
    private var cachedCursor:NSCursor?
    func invalidateToolCursor() { cachedCursor = nil; window?.invalidateCursorRects(for:self) }
    var footprintDiameter:CGFloat {
        if tool == "橡皮擦" { return max(4,width*4) }
        if tool == "铅笔" { return 1 }
        let base = width*3
        if brush == "喷枪" { return base*3.4+2.8 }
        if brush == "水彩笔" || brush == "标记笔" { return base*2 }
        if brush.hasPrefix("书法") { return base*1.4 }
        if ["油画笔","蜡笔","天然铅笔"].contains(brush) { return base*1.2+2.8 }
        return base
    }
    func toolCursor() -> NSCursor {
        if let cachedCursor { return cachedCursor }
        let cursor:NSCursor
        if tool == "文字" { cursor = .iBeam }
        else if tool == "画笔" || tool == "橡皮擦" {
            let diameter = max(3,footprintDiameter*(enclosingScrollView?.magnification ?? 1))
            let size = CGSize(width:ceil(diameter)+6,height:ceil(diameter)+6)
            let image = NSImage(size:size); image.lockFocus()
            let circle = NSBezierPath(ovalIn:CGRect(x:(size.width-diameter)/2,y:(size.height-diameter)/2,width:diameter,height:diameter))
            NSColor.white.setStroke(); circle.lineWidth = 3; circle.stroke(); NSColor.black.setStroke(); circle.lineWidth = 1; circle.stroke()
            image.unlockFocus(); cursor = NSCursor(image:image,hotSpot:CGPoint(x:size.width/2,y:size.height/2))
        } else if let symbol = ["铅笔":"pencil.tip","取色器":"eyedropper","填充":"drop.fill","放大镜":"magnifyingglass"][tool],let icon = NSImage(systemSymbolName:symbol,accessibilityDescription:tool) {
            let image = NSImage(size:NSSize(width:26,height:26)); image.lockFocus()
            NSColor.white.setFill(); NSBezierPath(ovalIn:NSRect(x:0,y:0,width:7,height:7)).fill()
            icon.draw(in:NSRect(x:4,y:4,width:20,height:20)); NSColor.black.setStroke(); let cross = NSBezierPath(); cross.move(to:NSPoint(x:0,y:3)); cross.line(to:NSPoint(x:6,y:3)); cross.move(to:NSPoint(x:3,y:0)); cross.line(to:NSPoint(x:3,y:6)); cross.stroke(); image.unlockFocus()
            cursor = NSCursor(image:image,hotSpot:NSPoint(x:3,y:23))
        } else { cursor = .crosshair }
        cachedCursor = cursor; return cursor
    }
    override func resetCursorRects() { addCursorRect(bounds,cursor:toolCursor()) }
    override func mouseMoved(with event:NSEvent) {
        let p = convert(event.locationInWindow,from:nil)
        if tool == "选择",let r = selection,r.contains(p) { (abs(p.x-r.maxX)<8 && abs(p.y-r.maxY)<8 ? NSCursor.crosshair : NSCursor.openHand).set() }
        else { toolCursor().set() }
        status?("\(Int(p.x)), \(Int(p.y)) 像素")
    }
    override func draw(_ dirtyRect:NSRect) {
        NSColor.white.setFill(); bounds.fill()
        NSImage(cgImage:document.image(),size:document.size).draw(in:bounds,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        if grid {
            let zoom = enclosingScrollView?.magnification ?? 1
            if zoom >= 4 {
                let p = NSBezierPath(); p.lineWidth = 1/zoom
                let clip = dirtyRect.intersection(bounds)
                for x in Int(clip.minX)...Int(clip.maxX) { p.move(to:NSPoint(x:CGFloat(x),y:clip.minY)); p.line(to:NSPoint(x:CGFloat(x),y:clip.maxY)) }
                for y in Int(clip.minY)...Int(clip.maxY) { p.move(to:NSPoint(x:clip.minX,y:CGFloat(y))); p.line(to:NSPoint(x:clip.maxX,y:CGFloat(y))) }
                NSColor(white:0.5,alpha:0.35).setStroke(); p.stroke()
            }
        }
        if let r = selection {
            let p = NSBezierPath(rect:r); p.lineWidth = 1/(enclosingScrollView?.magnification ?? 1); p.setLineDash([4,3],count:2,phase:0); NSColor.black.setStroke(); p.stroke()
            let handle = NSRect(x:r.maxX-3,y:r.maxY-3,width:6,height:6); NSColor.white.setFill(); handle.fill(); NSColor.black.setStroke(); NSBezierPath(rect:handle).stroke()
        }
        if lasso.count > 1 && before != nil { let p = NSBezierPath(); p.move(to:lasso[0]); for pt in lasso.dropFirst() { p.line(to:pt) }; p.setLineDash([3,3],count:2,phase:0); NSColor.darkGray.setStroke(); p.stroke() }
        if selection == nil { NSColor(rgb:0x6A7A8A).setFill(); NSRect(x:bounds.maxX-4,y:bounds.maxY-4,width:4,height:4).fill() }
    }
    func point(_ event:NSEvent) -> CGPoint { let p = convert(event.locationInWindow,from:nil); return CGPoint(x:max(0,min(CGFloat(document.width),p.x)),y:max(0,min(CGFloat(document.height),p.y))) }
    func rect(_ a:CGPoint,_ b:CGPoint) -> CGRect { CGRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(a.x-b.x),height:abs(a.y-b.y)).integral }
    func pickTool(_ name:String) { finishText(); finishPending(); selection = nil; selectionPath = nil; tool = name; window?.makeFirstResponder(self); window?.invalidateCursorRects(for:self); needsDisplay = true }
    func finishPending() {
        if let base = curveBase { document.commit(base); curveBase = nil; curvePoints.removeAll() }
        if let base = polygonBase { if polygon.count > 2 { drawPolygon(close:true) }; document.commit(base); polygonBase = nil; polygon.removeAll() }
    }
    func settle() { finishText(); finishPending() }
    override func mouseDown(with e:NSEvent) { begin(e,right:false) }
    override func rightMouseDown(with e:NSEvent) { begin(e,right:true) }
    func begin(_ e:NSEvent,right:Bool) {
        window?.makeFirstResponder(self); let p = point(e)
        if let editor = textEditor { if !editor.frame.contains(p) { finishText() } else { return } }
        self.right = right; start = p; last = p
        if p.x >= bounds.width-6 && p.y >= bounds.height-6 && selection == nil { settle(); resizingCanvas = true; return }
        if tool == "取色器" { if right { secondary = document.colorAt(p) } else { primary = document.colorAt(p) }; colorChanged?(); return }
        if tool == "放大镜" { zoomRequested?(!right); return }
        if tool == "填充" { document.edit { document.fill(at:p,color:right ? secondary : primary) }; return }
        if tool == "文字" { selection = nil; before = document.snapshot(); return }
        if tool == "多边形" {
            if polygon.isEmpty { polygonBase = document.snapshot() }
            polygon.append(p); drawPolygon(close:e.clickCount > 1)
            if e.clickCount > 1 { finishPending() }; return
        }
        if tool == "曲线" && !curvePoints.isEmpty { before = curveBase; return }
        before = document.snapshot()
        if tool == "选择" {
            if let r = selection, r.insetBy(dx:-4,dy:-4).contains(p), let image = selectionImage() {
                originalSelection = r; movingImage = image; movingPath = selectionPath
                resizingSelection = abs(p.x-r.maxX)<8 && abs(p.y-r.maxY)<8
                moving = true
            } else { selection = nil; selectionPath = nil; lasso = [p] }
            return
        }
        selection = nil; selectionPath = nil
        if ["铅笔","画笔","橡皮擦"].contains(tool) { stroke(from:p,to:p,event:e) }
    }
    override func mouseDragged(with e:NSEvent) { drag(e) }
    override func rightMouseDragged(with e:NSEvent) { drag(e) }
    func drag(_ e:NSEvent) {
        var p = point(e)
        if resizingCanvas { let raw = convert(e.locationInWindow,from:nil); status?("画布尺寸：\(max(1,Int(raw.x))) × \(max(1,Int(raw.y)))"); return }
        guard let base = before else { return }
        if tool == "选择" {
            if moving, let source = originalSelection, let image = movingImage {
                document.restore(base); document.clear(source,color:secondary,path:movingPath)
                var target = source
                if resizingSelection { target.size = CGSize(width:max(1,p.x-source.minX),height:max(1,p.y-source.minY)) }
                else { target.origin = CGPoint(x:source.minX+p.x-start.x,y:source.minY+p.y-start.y) }
                document.paste(image,at:target); selection = target
                if let path = movingPath { var t = CGAffineTransform(translationX:-source.minX,y:-source.minY); let local = path.copy(using:&t)!; t = CGAffineTransform(a:target.width/source.width,b:0,c:0,d:target.height/source.height,tx:target.minX,ty:target.minY); selectionPath = local.copy(using:&t) }
            } else {
                if freeSelection { lasso.append(p) }
                selection = freeSelection ? bounding(lasso) : rect(start,p)
                status?("选区：\(Int(selection!.width)) × \(Int(selection!.height)) 像素")
            }; needsDisplay = true; return
        }
        if tool == "文字" { selection = rect(start,p); needsDisplay = true; return }
        if ["铅笔","画笔","橡皮擦"].contains(tool) { stroke(from:last,to:p,event:e); last = p; needsDisplay = true; return }
        document.restore(base)
        if e.modifierFlags.contains(.shift) {
            let dx = p.x-start.x, dy = p.y-start.y
            if tool == "直线" || tool == "曲线" { let angle = (atan2(dy,dx)/(.pi/4)).rounded() * (.pi/4); let len = hypot(dx,dy); p = CGPoint(x:start.x+cos(angle)*len,y:start.y+sin(angle)*len) }
            else { let length = max(abs(dx),abs(dy)); p = CGPoint(x:start.x+(dx < 0 ? -length:length),y:start.y+(dy < 0 ? -length:length)) }
        }
        if tool == "曲线" && !curvePoints.isEmpty {
            let path = CGMutablePath(); path.move(to:curvePoints[0]); let end = curvePoints[1]
            if curvePoints.count == 2 { path.addQuadCurve(to:end,control:p) } else { path.addCurve(to:end,control1:curvePoints[2],control2:p) }
            render(path,closed:false); last = p
        } else { render(shapePath(tool,from:start,to:p),closed:tool != "直线" && tool != "曲线"); last = p }
        needsDisplay = true
    }
    override func mouseUp(with e:NSEvent) { end(e) }
    override func rightMouseUp(with e:NSEvent) { end(e) }
    func end(_ e:NSEvent) {
        if resizingCanvas {
            resizingCanvas = false; let p = convert(e.locationInWindow,from:nil)
            do { try document.resize(max(1,Int(p.x)),max(1,Int(p.y)),scale:false,background:secondary) } catch { status?(error.localizedDescription) }; return
        }
        guard let base = before else { return }; before = nil
        if tool == "选择" {
            if moving { selection = selection?.intersection(bounds); if selection?.isNull == true { selection = nil; selectionPath = nil }; document.commit(base) }
            else if freeSelection && lasso.count > 2 { let p = CGMutablePath(); p.addLines(between:lasso); p.closeSubpath(); selectionPath = p }
            if selection?.isEmpty == true { selection = nil }
            moving = false; resizingSelection = false; originalSelection = nil; movingImage = nil; lasso.removeAll(); needsDisplay = true; return
        }
        if tool == "文字" {
            let r = selection ?? CGRect(x:start.x,y:start.y,width:min(280,bounds.width-start.x),height:min(100,bounds.height-start.y))
            selection = nil; beginText(r.width < 8 || r.height < 8 ? CGRect(x:start.x,y:start.y,width:min(280,bounds.width-start.x),height:min(100,bounds.height-start.y)) : r); return
        }
        if tool == "曲线" {
            if curvePoints.isEmpty { curveBase = base; curvePoints = [start,last]; status?("拖动两次调整曲线弯曲；Enter 完成，Esc 取消") }
            else { curvePoints.append(last); if curvePoints.count >= 4 { finishPending() } }; return
        }
        document.commit(base)
    }
    func stroke(from a:CGPoint,to b:CGPoint,event:NSEvent) {
        let color = tool == "橡皮擦" ? secondary : (right ? secondary : primary)
        if tool == "橡皮擦" && right {
            let key = primary.usingColorSpace(.deviceRGB)!, replacement = secondary.usingColorSpace(.deviceRGB)!
            let rgb = [UInt8((key.redComponent*255).rounded()),UInt8((key.greenComponent*255).rounded()),UInt8((key.blueComponent*255).rounded())]
            let out = [UInt8((replacement.redComponent*255).rounded()),UInt8((replacement.greenComponent*255).rounded()),UInt8((replacement.blueComponent*255).rounded())]
            let steps = max(1,Int(hypot(b.x-a.x,b.y-a.y)))
            for step in 0...steps { let t = CGFloat(step)/CGFloat(steps), radius = max(2,width*2); let x = a.x+(b.x-a.x)*t,y = a.y+(b.y-a.y)*t
                let r = CGRect(x:x-radius,y:y-radius,width:radius*2,height:radius*2).integral.intersection(bounds)
                if !r.isEmpty { for py in Int(r.minY)..<Int(r.maxY) { for px in Int(r.minX)..<Int(r.maxX) { if hypot(CGFloat(px)+0.5-x,CGFloat(py)+0.5-y) > radius { continue }; let i = (py*document.width+px)*4; if document.bytes[i] == rgb[0] && document.bytes[i+1] == rgb[1] && document.bytes[i+2] == rgb[2] { for k in 0..<3 { document.bytes[i+k] = out[k] } } } } }
            }; needsDisplay = true; return
        }
        document.paint { c in
            c.setStrokeColor(color.cgColor); c.setFillColor(color.cgColor); c.setLineCap(.round); c.setLineJoin(.round)
            var thickness = tool == "铅笔" ? 1 : (tool == "橡皮擦" ? max(4,width*4) : width*3)
            c.setShouldAntialias(tool != "铅笔" && tool != "橡皮擦")
            if tool == "画笔" {
                if brush == "水彩笔" { c.setAlpha(0.18); thickness *= 2 }
                if brush == "标记笔" { c.setAlpha(0.45); thickness *= 2; c.setLineCap(.square) }
                if brush == "书法画笔 1" || brush == "书法画笔 2" { c.setLineCap(.square); thickness *= 1.4 }
                if ["喷枪","蜡笔","油画笔","天然铅笔"].contains(brush) {
                    let distance = hypot(b.x-a.x,b.y-a.y), count = max(1,Int(distance))
                    for n in 0...count { let t = CGFloat(n)/CGFloat(count); let center = CGPoint(x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t)
                        for j in 0..<12 { let seed = Double((n*73+j*37+Int(center.x)*11+Int(center.y)*19)%997); let angle = seed*2.39996; let radius = CGFloat((seed.truncatingRemainder(dividingBy:31))/31)*thickness*(brush == "喷枪" ? 1.7 : 0.6)
                            c.setAlpha(brush == "油画笔" ? 0.65 : 0.35); c.fillEllipse(in:CGRect(x:center.x+cos(angle)*radius,y:center.y+sin(angle)*radius,width:brush == "天然铅笔" ? 0.6:1.4,height:1.4)) }
                    }; return
                }
            }
            c.setLineWidth(thickness)
            if a == b { c.fillEllipse(in:CGRect(x:a.x-thickness/2,y:a.y-thickness/2,width:thickness,height:thickness)) }
            else { c.move(to:a); c.addLine(to:b); c.strokePath() }
        }; needsDisplay = true
    }
    func texture(_ style:String,color:NSColor,path:CGPath,stroke:Bool,context c:CGContext) {
        c.saveGState()
        if stroke { c.addPath(path); c.setLineWidth(width); c.replacePathWithStrokedPath(); c.clip() } else { c.addPath(path); c.clip() }
        let area = path.boundingBoxOfPath.insetBy(dx:-width,dy:-width).intersection(bounds)
        c.setFillColor(color.cgColor)
        if style == "纯色" { c.fill(area) }
        else if style == "水彩" || style == "标记笔" { c.setAlpha(style == "水彩" ? 0.28 : 0.5); c.fill(area) }
        else {
            c.setAlpha(style == "油画" ? 0.72 : 0.35); c.fill(area)
            let step:CGFloat = style == "天然铅笔" ? 2 : 3
            if !area.isEmpty { for y in stride(from:area.minY,to:area.maxY,by:step) { for x in stride(from:area.minX,to:area.maxX,by:step) {
                let n = abs((Int(x)*73+Int(y)*31)%17); c.setAlpha(CGFloat(n+1)/22)
                c.fill(CGRect(x:x+CGFloat(n%3)*0.3,y:y,width:style == "油画" ? 1.5:0.8,height:style == "油画" ? 5:1))
            } } }
        }
        c.restoreGState()
    }
    func render(_ path:CGPath,closed:Bool) {
        document.paint { c in
            c.setLineWidth(width); c.setLineJoin(.round); c.setLineCap(.round)
            let stroke = right ? secondary : primary, fill = right ? primary : secondary
            if closed && shapeFill != "无填充" { texture(shapeFill,color:fill,path:path,stroke:false,context:c) }
            if outline != "无轮廓" || !closed { texture(outline == "无轮廓" ? "纯色":outline,color:stroke,path:path,stroke:true,context:c) }
        }
    }
    func shapePath(_ name:String,from a:CGPoint,to b:CGPoint) -> CGPath {
        let p = CGMutablePath(), r = rect(a,b)
        switch name {
        case "直线","曲线": p.move(to:a); p.addLine(to:b)
        case "椭圆": p.addEllipse(in:r)
        case "圆角矩形": p.addRoundedRect(in:r,cornerWidth:min(15,r.width/4),cornerHeight:min(15,r.height/4))
        case "矩形": p.addRect(r)
        case "心形":
            p.move(to:CGPoint(x:r.midX,y:r.maxY))
            p.addCurve(to:CGPoint(x:r.midX,y:r.minY+r.height*0.23),control1:CGPoint(x:r.minX-r.width*0.4,y:r.minY+r.height*0.35),control2:CGPoint(x:r.minX+r.width*0.15,y:r.minY-r.height*0.25))
            p.addCurve(to:CGPoint(x:r.midX,y:r.maxY),control1:CGPoint(x:r.maxX-r.width*0.15,y:r.minY-r.height*0.25),control2:CGPoint(x:r.maxX+r.width*0.4,y:r.minY+r.height*0.35)); p.closeSubpath()
        case "闪电":
            let points:[CGPoint] = [CGPoint(x:0.48,y:0),CGPoint(x:0.13,y:0.55),CGPoint(x:0.48,y:0.5),CGPoint(x:0.35,y:1),CGPoint(x:0.9,y:0.35),CGPoint(x:0.56,y:0.4),CGPoint(x:0.78,y:0)]
            p.addLines(between:points.map { CGPoint(x:r.minX+$0.x*r.width,y:r.minY+$0.y*r.height) }); p.closeSubpath()
        case "圆角矩形标注":
            let body = CGRect(x:r.minX,y:r.minY,width:r.width,height:r.height*0.78)
            let k = min(10,min(body.width,body.height)/4)
            p.move(to:CGPoint(x:body.minX+k,y:body.minY)); p.addLine(to:CGPoint(x:body.maxX-k,y:body.minY))
            p.addQuadCurve(to:CGPoint(x:body.maxX,y:body.minY+k),control:CGPoint(x:body.maxX,y:body.minY))
            p.addLine(to:CGPoint(x:body.maxX,y:body.maxY-k)); p.addQuadCurve(to:CGPoint(x:body.maxX-k,y:body.maxY),control:CGPoint(x:body.maxX,y:body.maxY))
            p.addLine(to:CGPoint(x:body.midX,y:body.maxY)); p.addLine(to:CGPoint(x:r.minX+r.width*0.25,y:r.maxY)); p.addLine(to:CGPoint(x:r.minX+r.width*0.35,y:body.maxY))
            p.addLine(to:CGPoint(x:body.minX+k,y:body.maxY)); p.addQuadCurve(to:CGPoint(x:body.minX,y:body.maxY-k),control:CGPoint(x:body.minX,y:body.maxY))
            p.addLine(to:CGPoint(x:body.minX,y:body.minY+k)); p.addQuadCurve(to:CGPoint(x:body.minX+k,y:body.minY),control:CGPoint(x:body.minX,y:body.minY)); p.closeSubpath()
        case "椭圆标注":
            let cy = r.minY+r.height*0.38, ry = r.height*0.38, rx = r.width/2
            p.move(to:CGPoint(x:r.midX,y:cy+ry))
            p.addCurve(to:CGPoint(x:r.maxX,y:cy),control1:CGPoint(x:r.midX+rx*0.55,y:cy+ry),control2:CGPoint(x:r.maxX,y:cy+ry*0.55))
            p.addCurve(to:CGPoint(x:r.midX,y:r.minY),control1:CGPoint(x:r.maxX,y:cy-ry*0.55),control2:CGPoint(x:r.midX+rx*0.55,y:r.minY))
            p.addCurve(to:CGPoint(x:r.minX,y:cy),control1:CGPoint(x:r.midX-rx*0.55,y:r.minY),control2:CGPoint(x:r.minX,y:cy-ry*0.55))
            p.addCurve(to:CGPoint(x:r.minX+r.width*0.32,y:cy+ry*0.94),control1:CGPoint(x:r.minX,y:cy+ry*0.6),control2:CGPoint(x:r.minX+r.width*0.17,y:cy+ry*0.8))
            p.addLine(to:CGPoint(x:r.minX+r.width*0.2,y:r.maxY)); p.addLine(to:CGPoint(x:r.midX,y:cy+ry)); p.closeSubpath()
        case "云形标注":
            let cx = r.midX,cy = r.minY+r.height*0.36,rx = r.width*0.43,ry = r.height*0.30
            p.move(to:CGPoint(x:cx+rx,y:cy))
            for i in 0..<12 { let end = CGFloat(i+1)*2 * .pi/12, mid = end - .pi/12; p.addQuadCurve(to:CGPoint(x:cx+cos(end)*rx,y:cy+sin(end)*ry),control:CGPoint(x:cx+cos(mid)*rx*1.34,y:cy+sin(mid)*ry*1.34)) }; p.closeSubpath()
            p.addEllipse(in:CGRect(x:r.minX+r.width*0.3,y:r.minY+r.height*0.75,width:r.width*0.12,height:r.height*0.1))
            p.addEllipse(in:CGRect(x:r.minX+r.width*0.23,y:r.minY+r.height*0.91,width:r.width*0.06,height:r.height*0.06))
        default:
            var points:[CGPoint] = []
            if name.contains("箭头") {
                let base:[CGPoint] = [CGPoint(x:0,y:0.3),CGPoint(x:0.6,y:0.3),CGPoint(x:0.6,y:0),CGPoint(x:1,y:0.5),CGPoint(x:0.6,y:1),CGPoint(x:0.6,y:0.7),CGPoint(x:0,y:0.7)]
                points = base.map { pt in var q = pt; if name == "向左箭头" { q.x = 1-pt.x }; if name == "向上箭头" { q = CGPoint(x:pt.y,y:1-pt.x) }; if name == "向下箭头" { q = CGPoint(x:pt.y,y:pt.x) }; return CGPoint(x:r.minX+q.x*r.width,y:r.minY+q.y*r.height) }
            } else if name == "直角三角形" { points = [CGPoint(x:r.minX,y:r.minY),CGPoint(x:r.minX,y:r.maxY),CGPoint(x:r.maxX,y:r.maxY)] }
            else {
                let n = ["三角形":3,"菱形":4,"五边形":5,"六边形":6,"四角星":4,"五角星":5,"六角星":6][name] ?? 4
                let star = name.contains("星"), count = star ? n*2 : n
                for i in 0..<count { let t = CGFloat(i)*2 * .pi/CGFloat(count)-(.pi/2); let ratio:CGFloat = star && i%2 == 1 ? 0.42 : 1; points.append(CGPoint(x:r.midX+cos(t)*r.width/2*ratio,y:r.midY+sin(t)*r.height/2*ratio)) }
            }
            p.addLines(between:points); p.closeSubpath()
        }; return p
    }
    func drawPolygon(close:Bool) { guard let base = polygonBase else { return }; document.restore(base); let p = CGMutablePath(); p.addLines(between:polygon); if close { p.closeSubpath() }; render(p,closed:close); needsDisplay = true }
    func bounding(_ points:[CGPoint]) -> CGRect { guard let first = points.first else { return .zero }; return points.reduce(CGRect(x:first.x,y:first.y,width:0,height:0)) { r,p in CGRect(x:min(r.minX,p.x),y:min(r.minY,p.y),width:max(r.maxX,p.x)-min(r.minX,p.x),height:max(r.maxY,p.y)-min(r.minY,p.y)) }.integral }
    func selectionImage() -> CGImage? { guard let r = selection else { return nil }; return document.extracted(r,path:selectionPath,transparentKey:transparentSelection ? secondary : nil) }
    func selectAll() { settle(); tool = "选择"; selection = bounds; selectionPath = nil; needsDisplay = true }
    func deleteSelection() { settle(); guard let r = selection else { return }; document.edit { document.clear(r,color:secondary,path:selectionPath) }; selection = nil; selectionPath = nil; needsDisplay = true }
    func copySelection(cut:Bool = false) {
        settle(); guard let image = selectionImage() else { return }
        let rep = NSBitmapImageRep(cgImage:image); guard let png = rep.representation(using:.png,properties:[:]) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setData(png,forType:.png)
        if cut { deleteSelection() }
    }
    func pasteImage(_ image:CGImage) {
        settle(); let before = document.snapshot()
        if image.width > document.width || image.height > document.height {
            let w = max(image.width,document.width),h = max(image.height,document.height); guard RasterDocument.validSize(w,h) else { status?("粘贴后的图像过大"); return }
            let temp = RasterDocument(width:w,height:h); temp.clear(temp.bounds,color:secondary); temp.paste(document.image(),at:document.bounds); document.restore(temp.snapshot())
        }
        let r = CGRect(x:0,y:0,width:image.width,height:image.height); document.paste(image,at:r); selection = r; selectionPath = nil; tool = "选择"; document.commit(before)
    }
    func pasteClipboard() {
        guard let img = NSImage(pasteboard:.general), let cg = img.cgImage(forProposedRect:nil,context:nil,hints:nil), RasterDocument.validSize(cg.width,cg.height) else { status?("剪贴板中没有可用图像"); return }; pasteImage(cg)
    }
    func transform(_ operation:String) {
        settle()
        if let r = selection, let image = selectionImage() {
            let transformed = document.transformedImage(image,operation:operation)
            document.edit { document.clear(r,color:secondary,path:selectionPath); document.paste(transformed,at:CGRect(origin:r.origin,size:CGSize(width:transformed.width,height:transformed.height))) }
            selection = CGRect(origin:r.origin,size:CGSize(width:transformed.width,height:transformed.height)); selectionPath = nil; needsDisplay = true
        } else { document.transform(operation) }
    }
    func beginText(_ r:CGRect) {
        guard r.width >= 1 && r.height >= 1 else { return }
        let editor = NSTextView(frame:r); editor.isRichText = true; editor.allowsUndo = true; editor.font = textFont; editor.textColor = primary; editor.drawsBackground = textOpaque; editor.backgroundColor = secondary; editor.isVerticallyResizable = false; editor.isHorizontallyResizable = false; editor.textContainerInset = NSSize(width:2,height:2); editor.textContainer?.containerSize = r.size; editor.textContainer?.widthTracksTextView = true
        editor.wantsLayer = true; editor.layer?.borderWidth = 1; editor.layer?.borderColor = accent.cgColor
        textEditor = editor; addSubview(editor); window?.makeFirstResponder(editor); textModeChanged?(true)
    }
    func updateTextStyle() { guard let e = textEditor else { return }; e.font = textFont; e.textColor = primary; e.drawsBackground = textOpaque; e.backgroundColor = secondary }
    func finishText() {
        guard let e = textEditor else { return }; let content = e.attributedString(); let r = e.frame
        textEditor = nil; e.removeFromSuperview(); textModeChanged?(false)
        guard content.length > 0 else { return }
        document.edit { document.paint { c in
            c.saveGState(); c.clip(to:r); if textOpaque { c.setFillColor(secondary.cgColor); c.fill(r) }
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext:c,flipped:true)
            content.draw(with:r.insetBy(dx:2,dy:2),options:[.usesLineFragmentOrigin,.usesFontLeading]); NSGraphicsContext.restoreGraphicsState(); c.restoreGState()
        } }
    }
    func cancelPending() {
        if let base = curveBase ?? polygonBase ?? before { document.restore(base) }
        curveBase = nil; polygonBase = nil; before = nil; curvePoints.removeAll(); polygon.removeAll(); lasso.removeAll()
        textEditor?.removeFromSuperview(); textEditor = nil; textModeChanged?(false); selection = nil; selectionPath = nil; needsDisplay = true
    }
    override func keyDown(with event:NSEvent) {
        if event.keyCode == 53 { cancelPending() }
        else if event.keyCode == 36 { settle() }
        else if event.keyCode == 51 || event.keyCode == 117 { deleteSelection() }
        else if [123,124,125,126].contains(event.keyCode), let r = selection, let image = selectionImage() {
            let distance:CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let dx:CGFloat = event.keyCode == 123 ? -distance : event.keyCode == 124 ? distance : 0
            let dy:CGFloat = event.keyCode == 126 ? -distance : event.keyCode == 125 ? distance : 0
            document.edit { document.clear(r,color:secondary,path:selectionPath); document.paste(image,at:r.offsetBy(dx:dx,dy:dy)) }; selection = r.offsetBy(dx:dx,dy:dy); selectionPath = nil; needsDisplay = true
        } else { super.keyDown(with:event) }
    }
    override func draggingEntered(_ sender:NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender:NSDraggingInfo) -> Bool {
        if let urls = sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:nil) as? [URL],let url = urls.first { do { pasteImage(try RasterDocument.read(url)); return true } catch { status?(error.localizedDescription); return false } }
        if let image = NSImage(pasteboard:sender.draggingPasteboard),let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil), RasterDocument.validSize(cg.width,cg.height) { pasteImage(cg); return true }; return false
    }
}
