import AppKit
import UniformTypeIdentifiers

extension AppDelegate {
    func documentChanged() {
        let doc = canvas.document
        dimensions.stringValue = "\(doc.width) × \(doc.height) 像素"
        window?.title = "\(doc.fileURL?.lastPathComponent ?? "未命名") — 画图"
        window?.isDocumentEdited = doc.dirty
        window?.representedURL = doc.fileURL
        thumbnailView?.image = NSImage(cgImage:doc.image(),size:doc.size)
    }
    func error(_ error:Error) { let a = NSAlert(error:error); a.runModal() }
    func popup(_ titles:[String],sender:NSButton,action:Selector) {
        let menu = NSMenu()
        for title in titles { let i = menu.addItem(withTitle:title,action:action,keyEquivalent:""); i.target = self
            if title == "透明选择" { i.state = canvas.transparentSelection ? .on : .off }
            if title == canvas.brush && action == #selector(brushPicked(_:)) { i.state = .on }
        }
        menu.popUp(positioning:nil,at:NSPoint(x:0,y:sender.bounds.height),in:sender)
    }
    func confirmDiscard() -> Bool {
        canvas.settle(); guard canvas.document.dirty else { return true }
        let a = NSAlert(); a.messageText = "要保存对“\(canvas.document.fileURL?.lastPathComponent ?? "未命名")”的更改吗？"; a.informativeText = "不保存的更改将丢失。"; a.addButton(withTitle:"保存"); a.addButton(withTitle:"不保存"); a.addButton(withTitle:"取消")
        switch a.runModal() { case .alertFirstButtonReturn: return saveDocument(forcePanel:false); case .alertSecondButtonReturn: return true; default: return false }
    }
    @objc func openDocument() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png,.jpeg,.bmp,.gif,.tiff]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK,let url = panel.url { openURL(url) }
    }
    func openURL(_ url:URL) {
        do { let image = try RasterDocument.read(url); guard confirmDiscard() else { return }; canvas.cancelPending(); canvas.document.reset(width:image.width,height:image.height,image:image); canvas.document.fileURL = url; documentChanged(); actualSize() }
        catch { self.error(error) }
    }
    @objc func saveAction() { _ = saveDocument(forcePanel:false) }
    @objc func saveAsAction() { _ = saveDocument(forcePanel:true) }
    func fileType(_ url:URL) -> UTType? { switch url.pathExtension.lowercased() { case "png":return .png; case "jpg","jpeg":return .jpeg; case "bmp":return .bmp; case "gif":return .gif; case "tif","tiff":return .tiff; default:return nil } }
    @discardableResult func saveDocument(forcePanel:Bool) -> Bool {
        canvas.settle(); let doc = canvas.document
        var url = forcePanel ? nil : doc.fileURL
        if url == nil {
            let panel = NSSavePanel(); panel.title = "保存图像"; panel.nameFieldStringValue = doc.fileURL?.lastPathComponent ?? "未命名.png"; panel.allowedContentTypes = [.png,.jpeg,.bmp,.gif,.tiff]; panel.allowsOtherFileTypes = false
            let formats = NSPopUpButton(frame:NSRect(x:0,y:0,width:220,height:28)); formats.addItems(withTitles:["PNG (.png)","JPEG (.jpg)","BMP (.bmp)","GIF (.gif)","TIFF (.tiff)"])
            let bridge = SaveFormatBridge(panel:panel); formats.target = bridge; formats.action = #selector(SaveFormatBridge.change(_:)); panel.accessoryView = formats; panel.isExtensionHidden = false
            let result = panel.runModal(); withExtendedLifetime(bridge) {}
            guard result == .OK else { return false }; url = panel.url
        }
        guard let destination = url,let type = fileType(destination) else { error(PaintError.message("请选择 PNG、JPEG、BMP、GIF 或 TIFF 文件扩展名。")); return false }
        do { try doc.save(to:destination,type:type); info.stringValue = "已保存：\(destination.lastPathComponent)"; return true } catch { self.error(error); return false }
    }
    @objc func fileAction(_ item:NSMenuItem) {
        switch item.title { case "新建":newCanvas(); case "打开…":openDocument(); case "保存":saveAction(); case "另存为…":saveAsAction(); case "打印…":printDocument(); case "图像属性…":imageProperties(); case "退出":NSApp.terminate(nil); default:break }
    }
    func performCommand(_ title:String,sender:NSButton) {
        switch title {
        case "保存":saveAction()
        case "粘贴":
            if let e = NSApp.currentEvent,sender.convert(e.locationInWindow,from:nil).y > sender.bounds.height-18 { popup(["粘贴","粘贴自…"],sender:sender,action:#selector(pastePicked(_:))) } else { pasteAction() }
        case "复制":copyAction()
        case "剪切":cutAction()
        case "裁剪":cropAction()
        case "重新调整大小":resizeDialog()
        case "旋转 ▾":popup(["向右旋转 90°","向左旋转 90°","旋转 180°","垂直翻转","水平翻转"],sender:sender,action:#selector(transformPicked(_:)))
        case "轮廓 ▾":popup(["无轮廓","纯色","蜡笔","标记笔","油画","天然铅笔","水彩"],sender:sender,action:#selector(outlinePicked(_:)))
        case "填充 ▾":popup(["无填充","纯色","蜡笔","标记笔","油画","天然铅笔","水彩"],sender:sender,action:#selector(fillPicked(_:)))
        case "编辑颜色":editColors()
        case "标尺":scroll.hasHorizontalRuler = true; scroll.hasVerticalRuler = true
            if scroll.horizontalRulerView == nil { scroll.horizontalRulerView = NSRulerView(scrollView:scroll,orientation:.horizontalRuler) }
            if scroll.verticalRulerView == nil { scroll.verticalRulerView = NSRulerView(scrollView:scroll,orientation:.verticalRuler) }
            NSRulerView.registerUnit(withName:NSRulerView.UnitName("像素"),abbreviation:"px",unitToPointsConversionFactor:1,stepUpCycle:[10],stepDownCycle:[0.5])
            scroll.horizontalRulerView?.measurementUnits = NSRulerView.UnitName("像素"); scroll.verticalRulerView?.measurementUnits = NSRulerView.UnitName("像素"); scroll.rulersVisible.toggle()
        case "状态栏":bottomBar.isHidden.toggle()
        case "全屏":window.toggleFullScreen(nil)
        case "缩略图":showThumbnail()
        default:break
        }
    }
    @objc func pastePicked(_ item:NSMenuItem) {
        if item.title == "粘贴" { pasteAction(); return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png,.jpeg,.bmp,.gif,.tiff]
        if panel.runModal() == .OK,let url = panel.url { do { canvas.pasteImage(try RasterDocument.read(url)); syncTools() } catch { self.error(error) } }
    }
    @objc func brushPicked(_ item:NSMenuItem) { canvas.brush = item.title; canvas.pickTool("画笔"); syncTools(); info.stringValue = item.title }
    @objc func selectionPicked(_ item:NSMenuItem) {
        switch item.title {
        case "全选":selectAllAction()
        case "删除":deleteAction()
        case "透明选择":canvas.transparentSelection.toggle()
        default:canvas.freeSelection = item.title == "自由图形选择"; canvas.pickTool("选择")
        }; syncTools()
    }
    @objc func outlinePicked(_ item:NSMenuItem) { canvas.outline = item.title; info.stringValue = "轮廓：\(item.title)" }
    @objc func fillPicked(_ item:NSMenuItem) { canvas.shapeFill = item.title; info.stringValue = "填充：\(item.title)" }
    @objc func transformPicked(_ item:NSMenuItem) { canvas.transform(item.title) }
    @objc func copyAction() { if let e = canvas.textEditor,window.firstResponder === e { e.copy(nil) } else { canvas.copySelection() } }
    @objc func cutAction() { if let e = canvas.textEditor,window.firstResponder === e { e.cut(nil) } else { canvas.copySelection(cut:true) } }
    @objc func pasteAction() { if let e = canvas.textEditor,window.firstResponder === e { e.paste(nil) } else { canvas.pasteClipboard(); syncTools() } }
    @objc func selectAllAction() { if let e = canvas.textEditor,window.firstResponder === e { e.selectAll(nil) } else { canvas.selectAll(); syncTools() } }
    @objc func deleteAction() { canvas.deleteSelection() }
    @objc func cropAction() { canvas.settle(); guard let r = canvas.selection else { info.stringValue = "请先选择要保留的区域"; return }; canvas.selection = nil; canvas.selectionPath = nil; canvas.document.crop(r) }
    @objc func invertAction() { canvas.settle(); canvas.document.invert(canvas.selection ?? canvas.bounds) }
    func editColors() {
        let panel = NSColorPanel.shared; panel.setTarget(self); panel.setAction(#selector(customColorChanged(_:))); panel.color = colorSlot == 0 ? canvas.primary : canvas.secondary; panel.showsAlpha = false; panel.isContinuous = false; panel.orderFront(nil)
    }
    @objc func customColorChanged(_ panel:NSColorPanel) { setColor(panel.color); if !customColors.contains(panel.color) { customColors.insert(panel.color,at:0); customColors = Array(customColors.prefix(10)); if activeTab == 1 { showRibbon(1) } } }
    func field(_ value:String) -> NSTextField { let f = NSTextField(string:value); f.widthAnchor.constraint(equalToConstant:110).isActive = true; return f }
    func resizeDialog() {
        canvas.settle()
        let r = canvas.selection ?? canvas.bounds
        let a = NSAlert(); a.messageText = "调整大小和扭曲"; a.addButton(withTitle:"确定"); a.addButton(withTitle:"取消")
        let units = NSPopUpButton(); units.addItems(withTitles:["像素","百分比"])
        let w = field("\(Int(r.width))"), h = field("\(Int(r.height))"), sx = field("0"), sy = field("0")
        let aspect = NSButton(checkboxWithTitle:"保持纵横比（按水平值计算）",target:nil,action:nil); aspect.state = .on
        let form = stack([stack([label("单位"),units]),stack([label("水平"),w,label("垂直"),h]),aspect,label("扭曲角度（-89° 至 89°）"),stack([label("水平"),sx,label("垂直"),sy])],vertical:true,spacing:12); form.frame = NSRect(x:0,y:0,width:360,height:170); a.accessoryView = form
        guard a.runModal() == .alertFirstButtonReturn else { return }
        guard let horizontal = Double(w.stringValue), let vertical = Double(h.stringValue),let skewX = Double(sx.stringValue),let skewY = Double(sy.stringValue),horizontal.isFinite,vertical.isFinite,skewX.isFinite,skewY.isFinite,horizontal > 0,vertical > 0,horizontal <= 100000,vertical <= 100000,abs(skewX)<89,abs(skewY)<89 else { error(PaintError.message("请输入有效的正数尺寸与 -89° 至 89° 的扭曲角度。")); return }
        let width = Int((units.indexOfSelectedItem == 1 ? r.width*horizontal/100 : horizontal).rounded())
        let height = aspect.state == .on ? Int((CGFloat(width)*r.height/r.width).rounded()) : Int((units.indexOfSelectedItem == 1 ? r.height*vertical/100 : vertical).rounded())
        guard RasterDocument.validSize(width,height) else { error(PaintError.message("尺寸超出支持范围。")); return }
        do {
            // Work in a temporary document so resize + skew is one atomic undo step.
            let source = canvas.selectionImage() ?? canvas.document.image()
            let temp = RasterDocument(width:source.width,height:source.height); temp.paste(source,at:temp.bounds)
            try temp.resize(width,height,scale:true,background:canvas.secondary)
            if skewX != 0 || skewY != 0 { try temp.skew(horizontal:skewX,vertical:skewY,background:canvas.secondary) }
            let before = canvas.document.snapshot()
            if let selected = canvas.selection {
                canvas.document.clear(selected,color:canvas.secondary,path:canvas.selectionPath); canvas.document.paste(temp.image(),at:CGRect(origin:selected.origin,size:temp.size)); canvas.selection = CGRect(origin:selected.origin,size:temp.size); canvas.selectionPath = nil
            } else { canvas.document.restore(temp.snapshot()) }
            canvas.document.commit(before)
        } catch { self.error(error) }
    }
    @objc func propertiesAction() { imageProperties() }
    func imageProperties() {
        canvas.settle(); let doc = canvas.document
        let a = NSAlert(); a.messageText = "图像属性"; a.informativeText = "更改画布大小将裁掉超出范围的内容，扩展区域使用颜色 2。"; a.addButton(withTitle:"确定"); a.addButton(withTitle:"取消")
        let w = field(String(doc.width)),h = field(String(doc.height)); let mono = NSButton(checkboxWithTitle:"转换为黑白",target:nil,action:nil)
        let form = stack([stack([label("宽度（像素）"),w]),stack([label("高度（像素）"),h]),mono],vertical:true,spacing:12); form.frame = NSRect(x:0,y:0,width:300,height:110); a.accessoryView = form
        guard a.runModal() == .alertFirstButtonReturn else { return }
        guard let width = Int(w.stringValue),let height = Int(h.stringValue),RasterDocument.validSize(width,height) else { error(PaintError.message("尺寸须为 1–16384 像素，总像素不超过 2400 万。")); return }
        do { try doc.resize(width,height,scale:false,background:canvas.secondary)
            if mono.state == .on { doc.edit { for i in stride(from:0,to:doc.width*doc.height*4,by:4) { let luminance = Double(doc.bytes[i])*0.299+Double(doc.bytes[i+1])*0.587+Double(doc.bytes[i+2])*0.114; let value:UInt8 = luminance >= 128 ? 255 : 0; doc.bytes[i] = value; doc.bytes[i+1] = value; doc.bytes[i+2] = value } } }
            canvas.selection = nil; canvas.selectionPath = nil
        } catch { self.error(error) }
    }
    @objc func printDocument() {
        canvas.settle(); let v = PrintableImage(image:canvas.document.image())
        let settings = NSPrintInfo.shared.copy() as! NSPrintInfo; settings.horizontalPagination = .fit; settings.verticalPagination = .fit; settings.isHorizontallyCentered = true; settings.isVerticallyCentered = true
        NSPrintOperation(view:v,printInfo:settings).run()
    }
    func showThumbnail() {
        if let panel = thumbnailPanel { if panel.isVisible { panel.orderOut(nil) } else { panel.orderFront(nil) }; return }
        let panel = NSPanel(contentRect:NSRect(x:0,y:0,width:300,height:220),styleMask:[.titled,.closable,.resizable,.utilityWindow],backing:.buffered,defer:false); panel.title = "缩略图"; panel.isReleasedWhenClosed = false
        let v = NSImageView(frame:panel.contentView!.bounds); v.autoresizingMask = [.width,.height]; v.imageScaling = .scaleProportionallyUpOrDown; panel.contentView?.addSubview(v); thumbnailView = v; thumbnailPanel = panel; documentChanged(); panel.center(); panel.orderFront(nil)
    }
    func showTextTools(_ enabled:Bool) {
        if enabled {
            if textTab == nil { let b = classic("文本",width:64,action:#selector(classicTab(_:))); b.tab = true; b.tag = 3; tabsStack.addArrangedSubview(b); textTab = b }
            tabButtons.forEach{$0.state = .off}; textTab?.state = .on; showRibbon(3)
        } else {
            if let tab = textTab { tabsStack.removeArrangedSubview(tab); tab.removeFromSuperview(); textTab = nil }
            if activeTab == 3 { tabButtons[1].state = .on; showRibbon(1) }
        }
    }
    func textGroups() -> [NSView] {
        let fonts = NSPopUpButton(); fonts.addItems(withTitles:NSFontManager.shared.availableFontFamilies.sorted()); fonts.selectItem(withTitle:canvas.textFont.familyName ?? "Helvetica"); fonts.target = self; fonts.action = #selector(fontPicked(_:)); fonts.widthAnchor.constraint(equalToConstant:180).isActive = true
        let sizes = NSComboBox(); sizes.addItems(withObjectValues:[8,9,10,11,12,14,16,18,20,24,28,36,48,72].map(String.init)); sizes.stringValue = String(Int(canvas.textFont.pointSize)); sizes.target = self; sizes.action = #selector(fontSizePicked(_:)); sizes.widthAnchor.constraint(equalToConstant:64).isActive = true
        let bold = classic("B",width:24,action:#selector(boldPicked)),italic = classic("I",width:24,action:#selector(italicPicked)),underline = classic("U",width:24,action:#selector(underlinePicked))
        let transparent = classic("透明",width:64,action:#selector(textTransparent)),opaque = classic("不透明",width:64,action:#selector(textOpaque))
        return [group("字体",stack([fonts,stack([sizes,bold,italic,underline],spacing:5)],vertical:true,spacing:4)),group("背景",stack([transparent,opaque],vertical:true,spacing:4)),group("颜色",stack([classic("文字颜色",icon:"palette",width:80,action:#selector(textColor)),classic("完成文字",width:80,action:#selector(finishTextAction))],vertical:true,spacing:4))]
    }
    @objc func fontPicked(_ b:NSPopUpButton) { canvas.textFont = NSFontManager.shared.font(withFamily:b.titleOfSelectedItem ?? "Helvetica",traits:[],weight:5,size:canvas.textFont.pointSize) ?? .systemFont(ofSize:canvas.textFont.pointSize); canvas.updateTextStyle() }
    @objc func fontSizePicked(_ b:NSComboBox) { if let value = Double(b.stringValue),value.isFinite,value>=1,value<=500 { canvas.textFont = NSFontManager.shared.convert(canvas.textFont,toSize:value); canvas.updateTextStyle() } }
    @objc func boldPicked() { let manager = NSFontManager.shared; canvas.textFont = manager.traits(of:canvas.textFont).contains(.boldFontMask) ? manager.convert(canvas.textFont,toNotHaveTrait:.boldFontMask) : manager.convert(canvas.textFont,toHaveTrait:.boldFontMask); canvas.updateTextStyle() }
    @objc func italicPicked() { let manager = NSFontManager.shared; canvas.textFont = manager.traits(of:canvas.textFont).contains(.italicFontMask) ? manager.convert(canvas.textFont,toNotHaveTrait:.italicFontMask) : manager.convert(canvas.textFont,toHaveTrait:.italicFontMask); canvas.updateTextStyle() }
    @objc func underlinePicked() {
        guard let editor = canvas.textEditor else { return }
        let range = NSRange(location:0,length:editor.string.utf16.count)
        let old = range.length > 0 ? (editor.textStorage?.attribute(.underlineStyle,at:0,effectiveRange:nil) as? Int ?? 0) : (editor.typingAttributes[.underlineStyle] as? Int ?? 0)
        let value = old == 0 ? NSUnderlineStyle.single.rawValue : 0
        if range.length > 0 { editor.textStorage?.addAttribute(.underlineStyle,value:value,range:range) }; editor.typingAttributes[.underlineStyle] = value
    }
    @objc func textTransparent() { canvas.textOpaque = false; canvas.updateTextStyle() }
    @objc func textOpaque() { canvas.textOpaque = true; canvas.updateTextStyle() }
    @objc func textColor() { colorSlot = 0; editColors() }
    @objc func finishTextAction() { canvas.finishText(); window.makeFirstResponder(canvas) }
    func buildMenu() {
        let main = NSMenu()
        func submenu(_ title:String) -> NSMenu { let item = NSMenuItem(title:title,action:nil,keyEquivalent:""); let menu = NSMenu(title:title); item.submenu = menu; main.addItem(item); return menu }
        func add(_ menu:NSMenu,_ title:String,_ action:Selector,_ key:String = "",_ shift:Bool = false) { let item = menu.addItem(withTitle:title,action:action,keyEquivalent:key); item.target = self; if shift { item.keyEquivalentModifierMask = [.command,.shift] } }
        let app = submenu("Classic Paint"); app.addItem(withTitle:"退出画图",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let file = submenu("文件"); add(file,"新建",#selector(newCanvas),"n"); add(file,"打开…",#selector(openDocument),"o"); add(file,"保存",#selector(saveAction),"s"); add(file,"另存为…",#selector(saveAsAction),"s",true); file.addItem(.separator()); add(file,"打印…",#selector(printDocument),"p")
        let edit = submenu("编辑"); add(edit,"撤销",#selector(undoAction),"z"); add(edit,"重做",#selector(redoAction),"z",true); edit.addItem(.separator()); add(edit,"剪切",#selector(cutAction),"x"); add(edit,"复制",#selector(copyAction),"c"); add(edit,"粘贴",#selector(pasteAction),"v"); add(edit,"全选",#selector(selectAllAction),"a"); add(edit,"删除",#selector(deleteAction))
        let image = submenu("图像"); add(image,"裁剪",#selector(cropAction)); add(image,"反色",#selector(invertAction),"i",true); add(image,"图像属性…",#selector(propertiesAction),"e")
        NSApp.mainMenu = main
    }
    func validateMenuItem(_ item:NSMenuItem) -> Bool {
        guard window != nil else { return true }
        if item.action == #selector(undoAction) { return canvas.textEditor != nil || !canvas.document.undoStates.isEmpty }
        if item.action == #selector(redoAction) { return canvas.textEditor != nil || !canvas.document.redoStates.isEmpty }
        if [#selector(cutAction),#selector(copyAction),#selector(deleteAction),#selector(cropAction)].contains(item.action) { return canvas.textEditor != nil || canvas.selection != nil }
        return true
    }
}
final class SaveFormatBridge:NSObject {
    weak var panel:NSSavePanel?
    init(panel:NSSavePanel) { self.panel = panel }
    @objc func change(_ popup:NSPopUpButton) {
        let types:[UTType] = [.png,.jpeg,.bmp,.gif,.tiff], extensions = ["png","jpg","bmp","gif","tiff"]
        let index = popup.indexOfSelectedItem; panel?.allowedContentTypes = [types[index]]
        if let panel { let old = URL(fileURLWithPath:panel.nameFieldStringValue).deletingPathExtension().lastPathComponent; panel.nameFieldStringValue = old+"."+extensions[index] }
    }
}
final class PrintableImage:NSView {
    let bitmap:CGImage
    init(image:CGImage) { bitmap = image; super.init(frame:NSRect(x:0,y:0,width:image.width,height:image.height)) }
    required init?(coder:NSCoder) { fatalError() }
    override var isFlipped:Bool { true }
    override func draw(_ dirtyRect:NSRect) { NSImage(cgImage:bitmap,size:bounds.size).draw(in:bounds,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
}
