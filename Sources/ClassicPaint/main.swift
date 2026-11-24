import AppKit

let accent = NSColor(calibratedRed: 0.12, green: 0.40, blue: 0.76, alpha: 1)
func label(_ text: String, size: CGFloat = 12, color: NSColor = .labelColor) -> NSTextField {
    let v = NSTextField(labelWithString: text); v.font = .systemFont(ofSize: size); v.textColor = color; return v
}
func stack(_ views: [NSView], vertical: Bool = false, spacing: CGFloat = 8) -> NSStackView {
    let s = NSStackView(views: views); s.orientation = vertical ? .vertical : .horizontal; s.spacing = spacing; s.alignment = vertical ? .leading : .centerY; return s
}
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    var window: NSWindow!; let canvas = Canvas(frame: NSRect(x:0,y:0,width:960,height:600))
    let ribbon = NSView(); let info = label("就绪", size:11, color:.secondaryLabelColor)
    let zoomLabel = label("100%",size:11); var zoomSlider: NSSlider!; let scroll = NSScrollView(); var buttons: [NSButton] = []; var colorSlot = 0
    var primaryButton: NSButton!; var secondaryButton: NSButton!
    var tabButtons: [NSButton] = []
    let dimensions = label("960 × 600 像素",size:11,color:.secondaryLabelColor)
    var bottomBar:NSView!; var thumbnailPanel:NSPanel?; var thumbnailView:NSImageView?
    var textTab:NSButton?; var tabsStack:NSStackView!; var activeTab = 1
    var customColors:[NSColor] = []
    var pendingOpenURLs:[URL] = []
    var closeApproved = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.appearance = NSAppearance(named:.aqua)
        buildMenu()
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:1180,height:820),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.delegate = self; window.title = "未命名 — 画图"; window.minSize = NSSize(width:1120,height:600); window.titlebarAppearsTransparent = true; window.backgroundColor = NSColor(rgb:0xEAF0F7)
        let root = window.contentView!
        let quick = stack([classic("保存",icon:"externaldrive.fill",width:24,iconOnly:true), classic("撤销",icon:"arrow.uturn.backward",width:24,iconOnly:true,action:#selector(undoAction)),classic("重做",icon:"arrow.uturn.forward",width:24,iconOnly:true,action:#selector(redoAction))],spacing:2)
        let top = stack([classic("文件 ▾",width:58,action:#selector(classicTab(_:))),classic("主页",width:58,action:#selector(classicTab(_:))),classic("查看",width:58,action:#selector(classicTab(_:)))],spacing:0)
        tabsStack = top
        tabButtons = top.arrangedSubviews.compactMap { $0 as? NSButton }
        for (i,b) in tabButtons.enumerated() { b.tag = i; (b as? ClassicButton)?.tab = true }
        (tabButtons[0] as? ClassicButton)?.fileTab = true; tabButtons[1].state = .on
        ribbon.wantsLayer = true; ribbon.layer?.backgroundColor = NSColor(rgb:0xF1F5FA).cgColor
        quick.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(quick)
        NSLayoutConstraint.activate([quick.topAnchor.constraint(equalTo:root.topAnchor,constant:2),quick.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:8)])
        let work = NSView(); work.wantsLayer = true; work.layer?.backgroundColor = NSColor(rgb:0xCAD8E8).cgColor; work.layer?.masksToBounds = true
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = true; scroll.backgroundColor = NSColor(rgb:0xCAD8E8); scroll.allowsMagnification = true; scroll.minMagnification = 0.25; scroll.maxMagnification = 8
        let document = ClassicDocument(frame:NSRect(x:0,y:0,width:980,height:620)); canvas.frame.origin = NSPoint(x:5,y:5); document.addSubview(canvas); scroll.documentView = document
        canvas.wantsLayer = true; canvas.layer?.borderWidth = 1; canvas.layer?.borderColor = NSColor(white:0.72,alpha:1).cgColor
        canvas.status = { [weak self] in self?.info.stringValue = $0 }
        let slider = NSSlider(value:100,minValue:25,maxValue:800,target:self,action:#selector(zoomChanged(_:))); slider.widthAnchor.constraint(equalToConstant:140).isActive = true; zoomSlider = slider
        let bottom = stack([info, NSView(), dimensions,separator(),zoomLabel,slider],spacing:16)
        bottomBar = bottom
        for v in [top,ribbon,work,bottom] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        scroll.translatesAutoresizingMaskIntoConstraints = false; work.addSubview(scroll)
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo:root.topAnchor,constant:28),top.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:0),top.heightAnchor.constraint(equalToConstant:24),
            ribbon.topAnchor.constraint(equalTo:top.bottomAnchor,constant:0),ribbon.leadingAnchor.constraint(equalTo:root.leadingAnchor),ribbon.trailingAnchor.constraint(equalTo:root.trailingAnchor),ribbon.heightAnchor.constraint(equalToConstant:98),
            work.topAnchor.constraint(equalTo:ribbon.bottomAnchor),work.leadingAnchor.constraint(equalTo:root.leadingAnchor),work.trailingAnchor.constraint(equalTo:root.trailingAnchor),work.bottomAnchor.constraint(equalTo:bottom.topAnchor,constant:-8),
            scroll.leadingAnchor.constraint(equalTo:work.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:work.trailingAnchor),scroll.topAnchor.constraint(equalTo:work.topAnchor),scroll.bottomAnchor.constraint(equalTo:work.bottomAnchor),
            bottom.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:16),bottom.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-16),bottom.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-8),bottom.heightAnchor.constraint(equalToConstant:22)
        ])
        canvas.changed = { [weak self] in self?.documentChanged() }
        canvas.colorChanged = { [weak self] in self?.syncColors() }
        canvas.zoomRequested = { [weak self] up in if up { self?.zoomIn() } else { self?.zoomOut() } }
        canvas.textModeChanged = { [weak self] enabled in self?.showTextTools(enabled) }
        scroll.addObserver(self,forKeyPath:"magnification",options:.new,context:nil)
        showRibbon(1); documentChanged(); window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        if let url = pendingOpenURLs.first { openURL(url) }; pendingOpenURLs.removeAll()
    }
    func separator() -> NSView { let v = NSBox(); v.boxType = .separator; v.widthAnchor.constraint(equalToConstant:1).isActive = true; v.heightAnchor.constraint(equalToConstant:24).isActive = true; return v }
    func button(_ text: String, action: Selector = #selector(preview(_:))) -> NSButton { let b = NSButton(title:text,target:self,action:action); b.bezelStyle = .rounded; b.font = .systemFont(ofSize:12); return b }
    func classic(_ title:String, icon:String = "", width:CGFloat = 72, large:Bool = false, iconOnly:Bool = false, action:Selector = #selector(preview(_:))) -> ClassicButton {
        let b = ClassicButton(title:title,target:self,action:action); b.isBordered = false
        b.icon = icon; b.large = large; b.iconOnly = iconOnly; b.toolTip = title; b.setAccessibilityLabel(title)
        b.widthAnchor.constraint(equalToConstant:width).isActive = true
        b.heightAnchor.constraint(equalToConstant:large ? 72 : 22).isActive = true
        return b
    }
    func tool(_ name:String, icon:String, large:Bool = false, width:CGFloat = 24) -> ClassicButton {
        let b = classic(name,icon:icon,width:width,large:large,iconOnly:!large,action:#selector(toolPicked(_:)))
        b.setButtonType(.toggle); b.state = canvas.tool == name ? .on : .off; buttons.append(b); return b
    }
    func group(_ name:String,_ content:NSView) -> NSView {
        let v = NSView(); let caption = label(name,size:10,color:.secondaryLabelColor)
        let divider = NSBox(); divider.boxType = .separator
        for sub in [content,caption,divider] { sub.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(sub) }
        NSLayoutConstraint.activate([
            v.heightAnchor.constraint(equalToConstant:92),
            content.topAnchor.constraint(equalTo:v.topAnchor,constant:4),
            content.leadingAnchor.constraint(equalTo:v.leadingAnchor,constant:6),
            content.trailingAnchor.constraint(equalTo:v.trailingAnchor,constant:-6),
            caption.centerXAnchor.constraint(equalTo:v.centerXAnchor),
            caption.bottomAnchor.constraint(equalTo:v.bottomAnchor,constant:-4),
            divider.trailingAnchor.constraint(equalTo:v.trailingAnchor),
            divider.topAnchor.constraint(equalTo:v.topAnchor,constant:4),
            divider.bottomAnchor.constraint(equalTo:v.bottomAnchor,constant:-4),
            divider.widthAnchor.constraint(equalToConstant:1)
        ])
        return v
    }
    func showRibbon(_ index:Int) {
        ribbon.subviews.forEach{$0.removeFromSuperview()}; buttons.removeAll(); activeTab = index
        var groups:[NSView] = []
        if index == 1 {
            groups.append(group("剪贴板",stack([classic("粘贴",icon:"doc.on.clipboard.fill",width:44,large:true),stack([classic("剪切",icon:"scissors",width:52),classic("复制",icon:"doc.on.doc",width:52)],vertical:true,spacing:2)],spacing:1)))
            groups.append(group("图像",stack([tool("选择",icon:"rectangle.dashed",large:true,width:44),stack([classic("裁剪",icon:"crop",width:80),classic("重新调整大小",icon:"rectangle.arrowtriangle.2.outward",width:104),classic("旋转 ▾",icon:"rotate.right",width:80)],vertical:true,spacing:2)],spacing:1)))
            let tools = stack([stack([tool("铅笔",icon:"pencil"),tool("填充",icon:"paintbrush.fill"),tool("文字",icon:"textformat")],spacing:2),stack([tool("橡皮擦",icon:"eraser.fill"),tool("取色器",icon:"eyedropper"),tool("放大镜",icon:"magnifyingglass")],spacing:2)],vertical:true,spacing:4)
            groups.append(group("工具",tools))
            groups.append(group("",tool("画笔",icon:"paintbrush.pointed.fill",large:true,width:48)))
            let rows = stride(from:0,to:shapeNames.count,by:7).map { start in stack((start..<min(start+7,shapeNames.count)).map { i -> NSButton in
                let b = classic("",width:20,iconOnly:true,action:#selector(shapePicked(_:))); b.tag = i; b.toolTip = shapeNames[i]; b.setAccessibilityLabel(shapeNames[i]); b.shapePreview = canvas.shapePath(shapeNames[i] == "多边形" ? "五边形" : shapeNames[i],from:CGPoint(x:3,y:4),to:CGPoint(x:17,y:18)); if shapeNames[i] == "曲线" { let curve = CGMutablePath(); curve.move(to:CGPoint(x:3,y:16)); curve.addCurve(to:CGPoint(x:17,y:5),control1:CGPoint(x:17,y:17),control2:CGPoint(x:3,y:3)); b.shapePreview = curve }; b.setButtonType(.toggle); b.state = canvas.tool == shapeNames[i] ? .on : .off; buttons.append(b); return b
            },spacing:0) }
            let shapeStack = stack(rows,vertical:true,spacing:0); shapeStack.frame = NSRect(x:0,y:0,width:140,height:88)
            let gallery = NSScrollView(); gallery.hasVerticalScroller = true; gallery.autohidesScrollers = false; gallery.scrollerStyle = .legacy; gallery.borderType = .lineBorder; gallery.drawsBackground = true; gallery.backgroundColor = .white
            let shapeDocument = ClassicDocument(frame:NSRect(x:0,y:0,width:140,height:88)); shapeDocument.addSubview(shapeStack); gallery.documentView = shapeDocument
            gallery.widthAnchor.constraint(equalToConstant:156).isActive = true; gallery.heightAnchor.constraint(equalToConstant:66).isActive = true
            groups.append(group("形状",stack([gallery,stack([classic("轮廓 ▾",icon:"pencil.tip",width:70),classic("填充 ▾",icon:"square.fill",width:70)],vertical:true,spacing:3)],spacing:4)))
            groups.append(group("",classic("粗细",icon:"lines",width:48,large:true,action:#selector(sizeMenu(_:)))))
            primaryButton = classic("颜色 1",width:44,large:true,action:#selector(slotPicked(_:)))
            secondaryButton = classic("颜色 2",width:44,large:true,action:#selector(slotPicked(_:)))
            (primaryButton as? ClassicButton)?.swatch = canvas.primary; (secondaryButton as? ClassicButton)?.swatch = canvas.secondary
            primaryButton.state = colorSlot == 0 ? .on : .off; secondaryButton.state = colorSlot == 1 ? .on : .off
            let hexes:[UInt32] = [0x000000,0x7F7F7F,0x880015,0xED1C24,0xFF7F27,0xFFF200,0x22B14C,0x00A2E8,0x3F48CC,0xA349A4,0xFFFFFF,0xC3C3C3,0xB97A57,0xFFAEC9,0xFFC90E,0xEFE4B0,0xB5E61D,0x99D9EA,0x7092BE,0xC8BFE7]
            let swatches = hexes.enumerated().map { i,h -> NSButton in let b = NSButton(title:"",target:self,action:#selector(colorPicked(_:))); b.tag = Int(h); b.isBordered = false; b.wantsLayer = true; b.layer?.backgroundColor = NSColor(rgb:h).cgColor; b.layer?.borderWidth = 1; b.layer?.borderColor = NSColor(rgb:0xA8B2BF).cgColor; b.widthAnchor.constraint(equalToConstant:18).isActive = true; b.heightAnchor.constraint(equalToConstant:18).isActive = true; b.toolTip = "色板 \(i+1)"; return b }
            let empty = (0..<10).map { i -> NSView in let v = NSButton(title:"",target:self,action:#selector(customColorPicked(_:))); v.tag = i; v.isBordered = false; v.wantsLayer = true; v.layer?.backgroundColor = (i < customColors.count ? customColors[i] : NSColor(rgb:0xEDF1F6)).cgColor; v.layer?.borderColor = NSColor(rgb:0xCDD5DF).cgColor; v.layer?.borderWidth = 1; v.widthAnchor.constraint(equalToConstant:18).isActive = true; v.heightAnchor.constraint(equalToConstant:18).isActive = true; v.toolTip = "自定义颜色"; return v }
            let palette = stack([stack(Array(swatches.prefix(10)),spacing:3),stack(Array(swatches.suffix(10)),spacing:3),stack(empty,spacing:3)],vertical:true,spacing:3)
            groups.append(group("颜色",stack([primaryButton,secondaryButton,palette,classic("编辑颜色",icon:"palette",width:56,large:true)],spacing:3)))
        } else if index == 3 {
            groups = textGroups()
        } else if index == 0 {
            groups = [group("文件",stack([button("新建画布",action:#selector(newCanvas)),button("打开…"),button("保存"),button("另存为…")])), group("计划支持的格式",label("PNG  ·  JPEG  ·  BMP",color:.secondaryLabelColor))]
        } else {
            let grid = classic("网格线",icon:"square.grid.3x3",width:90,action:#selector(gridChanged(_:))); grid.setButtonType(.toggle); grid.state = canvas.grid ? .on : .off
            groups = [
                group("缩放",stack([classic("放大",icon:"plus.magnifyingglass",width:52,large:true,action:#selector(zoomIn)),classic("缩小",icon:"minus.magnifyingglass",width:52,large:true,action:#selector(zoomOut)),classic("100%",icon:"1.magnifyingglass",width:52,large:true,action:#selector(actualSize))],spacing:2)),
                group("显示或隐藏",stack([classic("标尺",icon:"ruler",width:90),grid,classic("状态栏",icon:"rectangle.bottomthird.inset.filled",width:90)],vertical:true,spacing:2)),
                group("显示",stack([classic("全屏",icon:"arrow.up.left.and.arrow.down.right",width:60,large:true),classic("缩略图",icon:"photo",width:60,large:true)],spacing:2))
            ]
        }
        let row = stack(groups,spacing:0); row.translatesAutoresizingMaskIntoConstraints = false; ribbon.addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo:ribbon.leadingAnchor,constant:4),row.topAnchor.constraint(equalTo:ribbon.topAnchor,constant:0)])
    }
    @objc func classicTab(_ b:NSButton) {
        if b.tag == 0 { popup(["新建","打开…","保存","另存为…","打印…","图像属性…","退出"],sender:b,action:#selector(fileAction(_:))); return }
        tabButtons.forEach { $0.state = $0 === b ? .on : .off }; textTab?.state = b.tag == 3 ? .on : .off; showRibbon(b.tag)
    }
    @objc func sizeMenu(_ b:NSButton) { popup(["1 px","3 px","5 px","8 px"],sender:b,action:#selector(pickSize(_:))) }
    @objc func pickSize(_ item:NSMenuItem) { canvas.width = CGFloat(Int(item.title.components(separatedBy:" ")[0]) ?? 3) }
    @objc func toolPicked(_ b:NSButton) {
        let p = NSApp.currentEvent.map { b.convert($0.locationInWindow,from:nil) }
        if b.title == "画笔", let p, p.y > b.bounds.height-18 { popup(["画笔","书法画笔 1","书法画笔 2","喷枪","油画笔","蜡笔","标记笔","天然铅笔","水彩笔"],sender:b,action:#selector(brushPicked(_:))); return }
        if b.title == "选择", let p, p.y > b.bounds.height-18 { popup(["矩形选择","自由图形选择","全选","删除","透明选择"],sender:b,action:#selector(selectionPicked(_:))); return }
        canvas.pickTool(b.title); syncTools(); info.stringValue = b.title
    }
    func syncTools() { buttons.forEach { b in let name = b.action == #selector(shapePicked(_:)) ? shapeNames[b.tag] : b.title; b.state = canvas.tool == name ? .on : .off }; canvas.needsDisplay = true }
    @objc func shapePicked(_ b:NSButton) { canvas.pickTool(shapeNames[b.tag]); syncTools(); info.stringValue = "\(canvas.tool) · Shift 约束比例；曲线拖动两次弯曲，多边形双击完成" }
    @objc func slotPicked(_ b:NSButton) { colorSlot = b === primaryButton ? 0 : 1; syncColors() }
    func syncColors() { (primaryButton as? ClassicButton)?.swatch = canvas.primary; (secondaryButton as? ClassicButton)?.swatch = canvas.secondary; primaryButton?.state = colorSlot == 0 ? .on : .off; secondaryButton?.state = colorSlot == 1 ? .on : .off; primaryButton?.needsDisplay = true; secondaryButton?.needsDisplay = true; canvas.updateTextStyle() }
    func setColor(_ c:NSColor) { if colorSlot == 0 { canvas.primary = c } else { canvas.secondary = c }; syncColors() }
    @objc func colorPicked(_ b:NSButton) { setColor(NSColor(rgb:UInt32(b.tag))) }
    @objc func customColorPicked(_ b:NSButton) { if b.tag < customColors.count { setColor(customColors[b.tag]) } else { editColors() } }
    @objc func gridChanged(_ b:NSButton) { canvas.grid = b.state == .on; canvas.needsDisplay = true; info.stringValue = canvas.grid ? "网格线在 400% 及以上显示像素边界" : "就绪" }
    @objc func zoomChanged(_ s:NSSlider) { setZoom(s.doubleValue) }
    func setZoom(_ value:Double) { let z = min(800,max(25,value)); scroll.magnification = z / 100; zoomSlider.doubleValue = z; zoomLabel.stringValue = "\(Int(z))%"; canvas.needsDisplay = true }
    override func observeValue(forKeyPath keyPath:String?,of object:Any?,change:[NSKeyValueChangeKey:Any]?,context:UnsafeMutableRawPointer?) { if keyPath == "magnification" { canvas.invalidateToolCursor(); zoomSlider?.doubleValue = scroll.magnification*100; zoomLabel.stringValue = "\(Int(scroll.magnification*100))%"; canvas.needsDisplay = true } }
    @objc func zoomIn() { setZoom(scroll.magnification * 200) }
    @objc func zoomOut() { setZoom(scroll.magnification * 50) }
    @objc func actualSize() { setZoom(100) }
    @objc func undoAction() { if let e = canvas.textEditor,window.firstResponder === e { e.undoManager?.undo() } else { canvas.settle(); canvas.selection = nil; canvas.document.undo() } }
    @objc func redoAction() { if let e = canvas.textEditor,window.firstResponder === e { e.undoManager?.redo() } else { canvas.settle(); canvas.selection = nil; canvas.document.redo() } }
    @objc func newCanvas() { guard confirmDiscard() else { return }; canvas.cancelPending(); canvas.document.reset(width:960,height:600); actualSize() }
    @objc func preview(_ b:NSButton) { performCommand(b.title,sender:b) }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply { (closeApproved || confirmDiscard()) ? .terminateNow : .terminateCancel }
    func windowShouldClose(_ sender:NSWindow) -> Bool { closeApproved = confirmDiscard(); return closeApproved }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { true }
    func application(_ sender:NSApplication,open urls:[URL]) { if window == nil { pendingOpenURLs = urls } else if let url = urls.first { openURL(url) } }
}
extension NSColor { convenience init(rgb: UInt32) { self.init(calibratedRed:CGFloat((rgb >> 16) & 255)/255,green:CGFloat((rgb >> 8) & 255)/255,blue:CGFloat(rgb & 255)/255,alpha:1) } }
if CommandLine.arguments.contains("--self-test") { runRasterTests(); exit(0) }
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
