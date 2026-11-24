import AppKit
import ImageIO
import UniformTypeIdentifiers

struct RasterState {
    let width: Int
    let height: Int
    let pixels: Data
    let revision: UUID
}
enum PaintError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
/// All edit coordinates and storage rows use a top-left origin, one unit per image pixel.
final class RasterDocument {
    static let maxPixels = 24_000_000
    private(set) var width: Int
    private(set) var height: Int
    private var storage: UnsafeMutableRawPointer
    private(set) var revision = UUID()
    private(set) var undoStates: [RasterState] = []
    private(set) var redoStates: [RasterState] = []
    var savedRevision: UUID?
    var fileURL: URL?
    var onChange: (() -> Void)?
    var dirty: Bool { savedRevision != revision }
    var size: CGSize { CGSize(width:width,height:height) }
    var bounds: CGRect { CGRect(origin:.zero,size:size) }
    var bytes: UnsafeMutablePointer<UInt8> { storage.assumingMemoryBound(to:UInt8.self) }
    init(width:Int = 960,height:Int = 600) {
        precondition(Self.validSize(width,height))
        self.width = width; self.height = height
        storage = .allocate(byteCount:width*height*4,alignment:64)
        memset(storage,255,width*height*4); savedRevision = revision
    }
    deinit { storage.deallocate() }
    static func validSize(_ w:Int,_ h:Int) -> Bool { w > 0 && h > 0 && w <= 16384 && h <= 16384 && w <= maxPixels / h }
    func snapshot() -> RasterState { RasterState(width:width,height:height,pixels:Data(bytes:storage,count:width*height*4),revision:revision) }
    func restore(_ state:RasterState) {
        if width != state.width || height != state.height {
            storage.deallocate(); width = state.width; height = state.height
            storage = .allocate(byteCount:width*height*4,alignment:64)
        }
        state.pixels.withUnsafeBytes { source in storage.copyMemory(from:source.baseAddress!,byteCount:source.count) }
        revision = state.revision
    }
    private func context() -> CGContext {
        CGContext(data:storage,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    }
    func image() -> CGImage { context().makeImage()! }
    func paint(_ body:(CGContext)->Void) {
        let c = context(); c.translateBy(x:0,y:CGFloat(height)); c.scaleBy(x:1,y:-1)
        body(c)
    }
    func commit(_ before:RasterState) {
        let changed = before.width != width || before.height != height || before.pixels != Data(bytes:storage,count:width*height*4)
        guard changed else { revision = before.revision; onChange?(); return }
        undoStates.append(before); redoStates.removeAll(); revision = UUID(); trimHistory(); onChange?()
    }
    private func trimHistory() {
        var total = undoStates.reduce(0) { $0 + $1.pixels.count }
        while undoStates.count > 1 && (total > 160_000_000 || undoStates.count > 50) { total -= undoStates.removeFirst().pixels.count }
    }
    func edit(_ body:()->Void) { let before = snapshot(); body(); commit(before) }
    func undo() { guard let s = undoStates.popLast() else { return }; redoStates.append(snapshot()); restore(s); onChange?() }
    func redo() { guard let s = redoStates.popLast() else { return }; undoStates.append(snapshot()); restore(s); onChange?() }
    func reset(width:Int,height:Int,image:CGImage? = nil) {
        precondition(Self.validSize(width,height))
        let blank = RasterDocument(width:width,height:height); restore(blank.snapshot())
        if let image { paste(image,at:bounds) }
        revision = UUID(); savedRevision = revision; fileURL = nil; undoStates.removeAll(); redoStates.removeAll(); onChange?()
    }
    static func drawImage(_ image:CGImage,in rect:CGRect,context c:CGContext) {
        c.saveGState(); c.translateBy(x:rect.minX,y:rect.maxY); c.scaleBy(x:1,y:-1)
        c.draw(image,in:CGRect(origin:.zero,size:rect.size)); c.restoreGState()
    }
    func paste(_ image:CGImage,at rect:CGRect,interpolation:CGInterpolationQuality = .none) {
        paint { c in c.interpolationQuality = interpolation; Self.drawImage(image,in:rect,context:c) }
    }
    func clear(_ rect:CGRect,color:NSColor,path:CGPath? = nil) {
        paint { c in if let path { c.addPath(path); c.clip() }; c.setFillColor(color.cgColor); c.fill(rect) }
    }
    func colorAt(_ point:CGPoint) -> NSColor {
        let x = min(width-1,max(0,Int(point.x))), y = min(height-1,max(0,Int(point.y)))
        let p = (y*width+x)*4
        return NSColor(calibratedRed:CGFloat(bytes[p])/255,green:CGFloat(bytes[p+1])/255,blue:CGFloat(bytes[p+2])/255,alpha:1)
    }
    func fill(at point:CGPoint,color:NSColor) {
        let x = Int(point.x), y = Int(point.y); guard x >= 0 && y >= 0 && x < width && y < height else { return }
        let c = color.usingColorSpace(.deviceRGB) ?? color
        let replacement:[UInt8] = [UInt8((c.redComponent*255).rounded()),UInt8((c.greenComponent*255).rounded()),UInt8((c.blueComponent*255).rounded()),255]
        let start = (y*width+x)*4; let target = Array(UnsafeBufferPointer(start:bytes+start,count:4))
        guard target != replacement else { return }
        func same(_ px:Int,_ py:Int) -> Bool { let p = (py*width+px)*4; return bytes[p] == target[0] && bytes[p+1] == target[1] && bytes[p+2] == target[2] && bytes[p+3] == target[3] }
        // Scanline flood fill keeps the queue bounded for large solid regions.
        var queue:[(Int,Int)] = [(x,y)]
        while let (sx,sy) = queue.popLast() {
            guard same(sx,sy) else { continue }
            var left = sx; while left > 0 && same(left-1,sy) { left -= 1 }
            var px = left; var up = false; var down = false
            while px < width && same(px,sy) {
                let p = (sy*width+px)*4; for k in 0..<4 { bytes[p+k] = replacement[k] }
                if sy > 0 { let hit = same(px,sy-1); if hit && !up { queue.append((px,sy-1)) }; up = hit }
                if sy+1 < height { let hit = same(px,sy+1); if hit && !down { queue.append((px,sy+1)) }; down = hit }
                px += 1
            }
        }
    }
    func extracted(_ rect:CGRect,path:CGPath? = nil,transparentKey:NSColor? = nil) -> CGImage? {
        let r = rect.integral.intersection(bounds); guard !r.isEmpty, let source = image().cropping(to:r) else { return nil }
        guard path != nil || transparentKey != nil else { return source }
        let temp = RasterDocument(width:Int(r.width),height:Int(r.height)); memset(temp.storage,0,temp.width*temp.height*4)
        temp.paint { c in
            if let path { var transform = CGAffineTransform(translationX:-r.minX,y:-r.minY); if let local = path.copy(using:&transform) { c.addPath(local); c.clip() } }
            Self.drawImage(source,in:temp.bounds,context:c)
        }
        if let key = transparentKey?.usingColorSpace(.deviceRGB) {
            let rgb = [UInt8((key.redComponent*255).rounded()),UInt8((key.greenComponent*255).rounded()),UInt8((key.blueComponent*255).rounded())]
            for p in stride(from:0,to:temp.width*temp.height*4,by:4) {
                if temp.bytes[p] == rgb[0] && temp.bytes[p+1] == rgb[1] && temp.bytes[p+2] == rgb[2] { memset(temp.bytes+p,0,4) }
            }
        }
        return temp.image()
    }
    func resize(_ w:Int,_ h:Int,scale:Bool,background:NSColor) throws {
        guard Self.validSize(w,h) else { throw PaintError.message("尺寸须为 1–16384 像素，总像素不超过 2400 万。") }
        let before = snapshot(), old = image(); let temp = RasterDocument(width:w,height:h)
        temp.clear(temp.bounds,color:background)
        temp.paste(old,at:scale ? temp.bounds : bounds,interpolation:scale ? .high : .none)
        restore(temp.snapshot()); commit(before)
    }
    func crop(_ rect:CGRect) {
        guard let img = extracted(rect) else { return }
        let before = snapshot(); let temp = RasterDocument(width:img.width,height:img.height); temp.paste(img,at:temp.bounds); restore(temp.snapshot()); commit(before)
    }
    func transformedImage(_ image:CGImage,operation:String) -> CGImage {
        let quarter = operation == "向右旋转 90°" || operation == "向左旋转 90°"
        let src = RasterDocument(width:image.width,height:image.height); src.paste(image,at:src.bounds)
        let dst = RasterDocument(width:quarter ? image.height : image.width,height:quarter ? image.width : image.height)
        for y in 0..<src.height { for x in 0..<src.width {
            let dx:Int, dy:Int
            switch operation {
            case "向右旋转 90°": dx = src.height-1-y; dy = x
            case "向左旋转 90°": dx = y; dy = src.width-1-x
            case "旋转 180°": dx = src.width-1-x; dy = src.height-1-y
            case "水平翻转": dx = src.width-1-x; dy = y
            default: dx = x; dy = src.height-1-y
            }
            memcpy(dst.bytes+(dy*dst.width+dx)*4,src.bytes+(y*src.width+x)*4,4)
        } }
        return dst.image()
    }
    func transform(_ operation:String) {
        let before = snapshot(), img = transformedImage(image(),operation:operation)
        let temp = RasterDocument(width:img.width,height:img.height); temp.paste(img,at:temp.bounds); restore(temp.snapshot()); commit(before)
    }
    func skew(horizontal:Double,vertical:Double,background:NSColor) throws {
        let tx = tan(horizontal * .pi/180), ty = tan(vertical * .pi/180)
        let w = Int(ceil(Double(width)+abs(tx)*Double(height))), h = Int(ceil(Double(height)+abs(ty)*Double(width)))
        guard Self.validSize(w,h), abs(1-tx*ty) > 0.001 else { throw PaintError.message("倾斜后的图像过大，或角度组合使图像退化。") }
        let before = snapshot(), img = image(); let temp = RasterDocument(width:w,height:h)
        temp.clear(temp.bounds,color:background)
        temp.paint { c in c.translateBy(x:tx < 0 ? -tx*Double(height) : 0,y:ty < 0 ? -ty*Double(width) : 0); c.concatenate(CGAffineTransform(a:1,b:ty,c:tx,d:1,tx:0,ty:0)); Self.drawImage(img,in:bounds,context:c) }
        restore(temp.snapshot()); commit(before)
    }
    func invert(_ rect:CGRect) { let r = rect.integral.intersection(bounds); guard !r.isEmpty else { return }; edit { for y in Int(r.minY)..<Int(r.maxY) { for x in Int(r.minX)..<Int(r.maxX) { let p = (y*width+x)*4; for k in 0..<3 { bytes[p+k] = 255-bytes[p+k] } } } } }
    static func read(_ url:URL) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL,nil), let props = CGImageSourceCopyPropertiesAtIndex(src,0,nil) as? [CFString:Any], let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int, validSize(w,h) else { throw PaintError.message("无法打开图像，或尺寸超过 2400 万像素限制。") }
        // Apply EXIF orientation on import, without changing the original file.
        let options:[CFString:Any] = [kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:max(w,h)]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src,0,options as CFDictionary) else { throw PaintError.message("图像解码失败。") }; return img
    }
    func encoded(type:UTType) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output,type.identifier as CFString,1,nil) else { throw PaintError.message("此系统不支持写入所选格式。") }
        CGImageDestinationAddImage(destination,image(),[kCGImageDestinationLossyCompressionQuality:0.95] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PaintError.message("图像编码失败。") }; return output as Data
    }
    func save(to url:URL,type:UTType) throws { let data = try encoded(type:type); try data.write(to:url,options:.atomic); fileURL = url; savedRevision = revision; onChange?() }
}
