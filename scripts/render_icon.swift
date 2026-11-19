// SVG → 透明底 PNG 渲染器:gen_brand_icons.py 调用,替代 qlmanage(后者把 SVG 压平到白底)。
// 用法: swift render_icon.swift <svg> <png> <边长>
import AppKit

let args = CommandLine.arguments
guard args.count == 4, let size = Int(args[3]), size > 0 else {
    fputs("用法: render_icon <svg> <png> <边长>\n", stderr)
    exit(2)
}
guard let image = NSImage(contentsOfFile: args[1]) else {
    fputs("SVG 无法读取: \(args[1])\n", stderr)
    exit(1)
}
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
) else {
    fputs("位图上下文创建失败\n", stderr)
    exit(1)
}
rep.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(
    in: NSRect(x: 0, y: 0, width: size, height: size),
    from: NSRect.zero,
    operation: .sourceOver,
    fraction: 1.0
)
NSGraphicsContext.restoreGraphicsState()
guard let data = rep.representation(using: .png, properties: [:]) else {
    fputs("PNG 编码失败\n", stderr)
    exit(1)
}
do {
    try data.write(to: URL(fileURLWithPath: args[2]))
} catch {
    fputs("写文件失败: \(error)\n", stderr)
    exit(1)
}
