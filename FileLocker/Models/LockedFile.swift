import Foundation
import SwiftData

// 锁定文件模型
@Model
public class LockedFile {
    // 文件路径
    public var path: String
    // 文件名称（从路径中提取）
    public var name: String
    // 是否已锁定
    public var isLocked: Bool
    // 是否是文件夹
    public var isDirectory: Bool
    // 文件书签数据（用于持久访问）
    public var bookmark: Data
    // 上次操作时间
    public var lockDate: Date
    
    // 初始化方法
    public init(path: String, isLocked: Bool, isDirectory: Bool, bookmark: Data) {
        self.path = path
        self.name = URL(fileURLWithPath: path).lastPathComponent
        self.isLocked = isLocked
        self.isDirectory = isDirectory
        self.bookmark = bookmark
        self.lockDate = Date()
    }
} 