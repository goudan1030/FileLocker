import Cocoa
import AppKit

// 图标生成函数
func generateFileLockerIcon(size: CGSize) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    
    // 设置背景为渐变
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.0, green: 0.4, blue: 0.8, alpha: 1.0),
        NSColor(calibratedRed: 0.0, green: 0.6, blue: 0.9, alpha: 1.0)
    ])
    let path = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: size.width, height: size.height))
    gradient?.draw(in: path, angle: 45)
    
    // 绘制锁图标
    let lockSize = CGSize(width: size.width * 0.6, height: size.height * 0.6)
    let lockOrigin = CGPoint(x: (size.width - lockSize.width) / 2, y: (size.height - lockSize.height) / 2)
    let lockRect = NSRect(origin: lockOrigin, size: lockSize)
    
    // 锁体
    NSColor.white.setFill()
    let lockBody = NSBezierPath(roundedRect: NSRect(
        x: lockRect.origin.x,
        y: lockRect.origin.y,
        width: lockRect.size.width,
        height: lockRect.size.height * 0.6
    ), xRadius: lockRect.size.width * 0.1, yRadius: lockRect.size.width * 0.1)
    lockBody.fill()
    
    // 锁环
    let lockShackleWidth = lockRect.size.width * 0.4
    let lockShackleHeight = lockRect.size.height * 0.5
    let lockShackleRect = NSRect(
        x: lockRect.origin.x + (lockRect.size.width - lockShackleWidth) / 2,
        y: lockRect.origin.y + lockRect.size.height * 0.5,
        width: lockShackleWidth,
        height: lockShackleHeight
    )
    
    let lockShackle = NSBezierPath()
    lockShackle.lineWidth = lockRect.size.width * 0.1
    lockShackle.move(to: NSPoint(x: lockShackleRect.origin.x, y: lockShackleRect.origin.y))
    lockShackle.line(to: NSPoint(x: lockShackleRect.origin.x, y: lockShackleRect.origin.y + lockShackleRect.size.height))
    lockShackle.appendArc(
        withCenter: NSPoint(
            x: lockShackleRect.origin.x + lockShackleRect.size.width / 2,
            y: lockShackleRect.origin.y + lockShackleRect.size.height
        ),
        radius: lockShackleRect.size.width / 2,
        startAngle: 180,
        endAngle: 0
    )
    lockShackle.line(to: NSPoint(x: lockShackleRect.origin.x + lockShackleRect.size.width, y: lockShackleRect.origin.y))
    NSColor.white.setStroke()
    lockShackle.stroke()
    
    image.unlockFocus()
    return image
}

// 定义所需的图标尺寸
let iconSizes = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2)
]

// 生成所有尺寸的图标
for (size, scale) in iconSizes {
    let actualSize = CGSize(width: size, height: size)
    let image = generateFileLockerIcon(size: actualSize)
    
    // 保存图标到文件
    if let tiffData = image.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffData),
       let pngData = bitmap.representation(using: .png, properties: [:]) {
        let filename = "icon_\(size)x\(size)"
        let scaleText = scale > 1 ? "@\(scale)x" : ""
        let fullFilename = "\(filename)\(scaleText).png"
        
        let appIconFolder = "FileLocker/Assets.xcassets/AppIcon.appiconset"
        let fileURL = URL(fileURLWithPath: appIconFolder).appendingPathComponent(fullFilename)
        
        do {
            try pngData.write(to: fileURL)
            print("生成图标: \(fullFilename)")
        } catch {
            print("保存图标出错: \(error.localizedDescription)")
        }
    }
}

print("图标生成完成！") 