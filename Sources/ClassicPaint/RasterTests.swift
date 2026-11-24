import AppKit
import UniformTypeIdentifiers

func runRasterTests() {
    var passed = 0
    func check(_ condition:@autoclosure () -> Bool,_ name:String) { guard condition() else { fputs("FAIL: \(name)\n",stderr); exit(1) }; passed += 1; print("PASS: \(name)") }
    func rgb(_ doc:RasterDocument,_ x:Int,_ y:Int) -> [UInt8] { let i = (y*doc.width+x)*4; return [doc.bytes[i],doc.bytes[i+1],doc.bytes[i+2]] }
    let doc = RasterDocument(width:8,height:6)
    check(!doc.dirty,"new document is clean")
    doc.edit { doc.clear(CGRect(x:1,y:1,width:2,height:2),color:.red) }
    check(rgb(doc,1,1) == [255,0,0] && rgb(doc,1,4) == [255,255,255],"top-left pixel coordinates")
    check(doc.dirty,"edit marks dirty")
    doc.undo(); check(rgb(doc,1,1) == [255,255,255] && !doc.dirty,"undo restores pixels and clean revision")
    doc.redo(); check(rgb(doc,1,1) == [255,0,0] && doc.dirty,"redo restores pixels")
    doc.edit { doc.fill(at:CGPoint(x:0,y:0),color:.blue) }
    check(rgb(doc,7,5) == [0,0,255] && rgb(doc,1,1) == [255,0,0],"flood fill respects boundary")
    let fillState = doc.snapshot(); doc.edit { doc.fill(at:CGPoint(x:0,y:0),color:.blue) }; check(doc.revision == fillState.revision,"same-color fill is a no-op")
    guard let crop = doc.extracted(CGRect(x:1,y:1,width:2,height:2)) else { fatalError() }
    let copy = RasterDocument(width:4,height:4); copy.paste(crop,at:CGRect(x:0,y:0,width:2,height:2))
    check(rgb(copy,0,0) == [255,0,0] && rgb(copy,0,3) == [255,255,255],"crop and paste orientation")
    let pattern = RasterDocument(width:3,height:2)
    pattern.edit { pattern.clear(CGRect(x:0,y:0,width:1,height:1),color:.red); pattern.clear(CGRect(x:2,y:1,width:1,height:1),color:.blue) }
    pattern.transform("向右旋转 90°"); check(pattern.width == 2 && pattern.height == 3 && rgb(pattern,1,0) == [255,0,0] && rgb(pattern,0,2) == [0,0,255],"clockwise rotation dimensions and corners")
    pattern.undo(); pattern.transform("水平翻转"); check(rgb(pattern,2,0) == [255,0,0] && rgb(pattern,0,1) == [0,0,255],"horizontal flip")
    pattern.undo(); pattern.transform("垂直翻转"); check(rgb(pattern,0,1) == [255,0,0],"vertical flip")
    pattern.undo(); pattern.crop(CGRect(x:0,y:0,width:2,height:1)); check(pattern.width == 2 && pattern.height == 1 && rgb(pattern,0,0) == [255,0,0],"crop updates canvas dimensions")
    pattern.undo(); check(pattern.width == 3 && pattern.height == 2,"undo crop restores dimensions")
    do {
        try pattern.resize(6,4,scale:false,background:.green); check(rgb(pattern,0,0) == [255,0,0] && rgb(pattern,5,3) == [0,255,0],"canvas resize preserves pixels and background")
        pattern.undo(); try pattern.resize(6,4,scale:true,background:.white); check(pattern.width == 6 && pattern.height == 4,"image resize")
        pattern.undo(); let initial = pattern.snapshot(); try pattern.skew(horizontal:20,vertical:0,background:.white); check(pattern.width > 3,"skew expands canvas"); pattern.undo(); check(pattern.snapshot().pixels == initial.pixels,"undo skew is lossless")
        let dir = URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("classicpaint-tests-\(UUID().uuidString)"); try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:dir) }
        for (type,ext) in [(UTType.png,"png"),(.bmp,"bmp"),(.tiff,"tiff"),(.jpeg,"jpg"),(.gif,"gif")] {
            let url = dir.appendingPathComponent("roundtrip.\(ext)"); try pattern.save(to:url,type:type); let image = try RasterDocument.read(url)
            let restored = RasterDocument(width:image.width,height:image.height); restored.paste(image,at:restored.bounds)
            check(restored.width == pattern.width && restored.height == pattern.height,"\(ext) file roundtrip dimensions")
            if ext == "png" || ext == "bmp" || ext == "tiff" { check(restored.snapshot().pixels == pattern.snapshot().pixels,"\(ext) file roundtrip pixels") }
        }
        check(!pattern.dirty,"save clears dirty flag"); pattern.edit { pattern.fill(at:CGPoint(x:1,y:0),color:.black) }; check(pattern.dirty,"edit after save marks dirty"); pattern.undo(); check(!pattern.dirty,"undo to saved revision is clean")
        let before = pattern.snapshot(); do { try pattern.resize(0,1,scale:true,background:.white); check(false,"invalid dimensions rejected") } catch { check(pattern.snapshot().pixels == before.pixels,"invalid resize leaves document unchanged") }
    } catch { fputs("FAIL: \(error)\n",stderr); exit(1) }
    let transparent = doc.extracted(CGRect(x:0,y:0,width:4,height:4),transparentKey:.blue)!
    let rep = NSBitmapImageRep(cgImage:transparent)
    check(rep.colorAt(x:0,y:0)!.alphaComponent == 0 && rep.colorAt(x:1,y:1)!.alphaComponent == 1,"transparent selection removes only background color")
    let path = CGMutablePath(); path.move(to:CGPoint(x:0,y:0)); path.addLine(to:CGPoint(x:4,y:0)); path.addLine(to:CGPoint(x:0,y:4)); path.closeSubpath()
    let masked = NSBitmapImageRep(cgImage:doc.extracted(CGRect(x:0,y:0,width:4,height:4),path:path)!)
    check(masked.colorAt(x:3,y:3)!.alphaComponent == 0,"freeform selection clips outside polygon")
    let stable = pattern.snapshot(), undoCount = pattern.undoStates.count
    do { try pattern.resize(pattern.width,pattern.height,scale:false,background:.white) } catch { fatalError("unexpected resize error") }
    check(pattern.revision == stable.revision && pattern.undoStates.count == undoCount,"no-op resize preserves revision and history")
    let inverted = RasterDocument(width:3,height:3); inverted.invert(CGRect(x:1,y:1,width:1,height:1))
    check(rgb(inverted,1,1) == [0,0,0] && rgb(inverted,0,0) == [255,255,255],"invert affects only selected pixels")
    let rotated = RasterDocument(width:3,height:2); rotated.clear(CGRect(x:0,y:0,width:1,height:1),color:.red)
    rotated.transform("向左旋转 90°"); check(rgb(rotated,0,2) == [255,0,0],"counterclockwise rotation")
    rotated.undo(); rotated.transform("旋转 180°"); check(rgb(rotated,2,1) == [255,0,0],"180-degree rotation")
    _ = NSApplication.shared
    let canvas = Canvas(frame:NSRect(x:0,y:0,width:960,height:600))
    let emptyCanvas = canvas.document.snapshot()
    for name in shapeNames where name != "多边形" {
        canvas.document.restore(emptyCanvas)
        canvas.render(canvas.shapePath(name,from:CGPoint(x:20,y:20),to:CGPoint(x:120,y:100)),closed:name != "直线" && name != "曲线")
        check(canvas.document.snapshot().pixels != emptyCanvas.pixels,"shape renders: \(name)")
    }
    canvas.shapeFill = "纯色"; canvas.outline = "无轮廓"; canvas.secondary = .red; canvas.document.restore(emptyCanvas)
    canvas.render(canvas.shapePath("矩形",from:CGPoint(x:20,y:20),to:CGPoint(x:120,y:100)),closed:true)
    check(rgb(canvas.document,50,50) == [255,0,0] && rgb(canvas.document,10,10) == [255,255,255],"shape fill uses color 2 without outline")
    var textureResults = Set<Data>()
    for style in ["纯色","蜡笔","标记笔","油画","天然铅笔","水彩"] { canvas.document.restore(emptyCanvas); canvas.shapeFill = style; canvas.render(canvas.shapePath("矩形",from:CGPoint(x:20,y:20),to:CGPoint(x:120,y:100)),closed:true); textureResults.insert(canvas.document.snapshot().pixels) }
    check(textureResults.count == 6,"six shape material modes produce distinct pixels")
    canvas.tool = "橡皮擦"; canvas.width = 3
    check(canvas.footprintDiameter == 12,"eraser cursor diameter matches erase width")
    let smallCursor = canvas.toolCursor().image.size.width
    canvas.width = 8
    check(canvas.toolCursor().image.size.width > smallCursor,"width change invalidates cached cursor")
    canvas.tool = "画笔"; canvas.brush = "水彩笔"
    check(canvas.footprintDiameter == 48,"watercolor footprint includes expanded width")
    canvas.brush = "画笔"
    check(canvas.footprintDiameter == 24,"brush change refreshes footprint")
    canvas.tool = "文字"
    check(canvas.toolCursor() === NSCursor.iBeam,"text tool uses insertion cursor")
    print("\(passed) raster and canvas tests passed")
}
