//
//  FileLockerMain.swift
//  FileLocker
//
//  Created by zwd on 2025/5/6.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Foundation
import CryptoKit

// MARK: - 数据模型

@Model
final class LockedFile {
    var path: String
    var isLocked: Bool
    var isDirectory: Bool
    var name: String
    var lockDate: Date
    var bookmark: Data? // 添加书签数据以便持久访问文件
    var isPasswordProtected: Bool // 添加密码保护标志
    var passwordHash: String? // 存储密码的哈希值，而非明文密码
    var accessAttempts: Int // 记录访问尝试次数
    var lastAccessTime: Date? // 最后一次访问时间
    
    init(path: String, isLocked: Bool = true, isDirectory: Bool = false, bookmark: Data? = nil) {
        self.path = path
        self.isLocked = isLocked
        self.isDirectory = isDirectory
        self.name = URL(fileURLWithPath: path).lastPathComponent
        self.lockDate = Date()
        self.bookmark = bookmark
        self.isPasswordProtected = false
        self.passwordHash = nil
        self.accessAttempts = 0
        self.lastAccessTime = nil
    }
}

// 添加密码访问记录模型
@Model
final class PasswordAccessLog {
    var filePath: String
    var fileName: String
    var accessTime: Date
    var isSuccessful: Bool
    var accessType: String // "unlock", "lock", "view"
    
    init(filePath: String, fileName: String, accessTime: Date = Date(), isSuccessful: Bool, accessType: String) {
        self.filePath = filePath
        self.fileName = fileName
        self.accessTime = accessTime
        self.isSuccessful = isSuccessful
        self.accessType = accessType
    }
}

// MARK: - 错误类型

enum FileLockError: Error, LocalizedError {
    case fileNotFound
    case accessDenied
    case unknown(String)
    case bookmarkCreationFailed
    case bookmarkRestorationFailed
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "找不到文件，可能已被移动或删除"
        case .accessDenied:
            return "没有足够权限操作该文件，请检查是否已获得完全磁盘访问权限"
        case .bookmarkCreationFailed:
            return "创建文件书签失败，无法持久访问文件"
        case .bookmarkRestorationFailed:
            return "文件书签已失效，无法访问该文件"
        case .unknown(let message):
            return "未知错误: \(message)"
        }
    }
}

// MARK: - 服务类

class FileLockerService {
    static let shared = FileLockerService()
    
    private init() {}
    
    // 创建安全书签以持久访问文件
    func createSecureBookmark(for url: URL) throws -> Data {
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            return bookmarkData
        } catch {
            throw FileLockError.bookmarkCreationFailed
        }
    }
    
    // 从书签恢复URL
    func resolveSecureBookmark(_ bookmarkData: Data) throws -> URL {
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            return url
        } catch {
            throw FileLockError.bookmarkRestorationFailed
        }
    }
    
    // 生成密码哈希
    func hashPassword(_ password: String) -> String {
        // 简单哈希实现，实际应用中应使用更安全的哈希算法和加盐
        let passwordData = password.data(using: .utf8)!
        let hash = SHA256.hash(data: passwordData)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // 验证密码
    func verifyPassword(_ password: String, against hash: String) -> Bool {
        let inputHash = hashPassword(password)
        return inputHash == hash
    }
    
    // 锁定文件并设置密码保护
    func lockFileWithPassword(at path: String, password: String, withBookmark bookmark: Data? = nil) throws -> String {
        // 先常规锁定文件
        try lockFile(at: path, withBookmark: bookmark)
        
        // 生成密码哈希并返回
        return hashPassword(password)
    }
    
    // 用密码解锁文件
    func unlockFileWithPassword(at path: String, password: String, against hash: String, withBookmark bookmark: Data? = nil) throws -> Bool {
        // 验证密码
        if !verifyPassword(password, against: hash) {
            return false
        }
        
        // 密码验证通过，解锁文件
        try unlockFile(at: path, withBookmark: bookmark)
        return true
    }
    
    func lockFile(at path: String, withBookmark bookmark: Data? = nil) throws {
        print("尝试锁定文件: \(path)")
        var url: URL
        var shouldStopAccessing = false
        
        // 尝试通过书签访问文件
        if let bookmarkData = bookmark {
            do {
                url = try resolveSecureBookmark(bookmarkData)
                if url.startAccessingSecurityScopedResource() {
                    shouldStopAccessing = true
                    print("通过书签成功访问文件")
                }
            } catch {
                print("书签恢复失败，尝试直接访问路径: \(error.localizedDescription)")
                // 如果书签无效，回退到直接路径
                url = URL(fileURLWithPath: path)
            }
        } else {
            url = URL(fileURLWithPath: path)
            print("使用直接路径访问文件")
        }
        
        var resourceValues = URLResourceValues()
        resourceValues.isUserImmutable = true
        
        do {
            var mutableURL = url
            try mutableURL.setResourceValues(resourceValues)
            print("成功锁定文件: \(path)")
        } catch {
            if let nsError = error as NSError? {
                switch nsError.code {
                case NSFileNoSuchFileError:
                    print("找不到文件: \(path)")
                    throw FileLockError.fileNotFound
                case NSFileWriteNoPermissionError:
                    print("没有写入权限: \(path)")
                    throw FileLockError.accessDenied
                default:
                    print("未知错误: \(nsError.code) - \(error.localizedDescription)")
                    throw FileLockError.unknown(error.localizedDescription)
                }
            } else {
                print("未分类错误: \(error.localizedDescription)")
                throw FileLockError.unknown(error.localizedDescription)
            }
        }
        
        if shouldStopAccessing {
            url.stopAccessingSecurityScopedResource()
            print("已停止安全资源访问")
        }
    }
    
    func unlockFile(at path: String, withBookmark bookmark: Data? = nil) throws {
        print("尝试解锁文件: \(path)")
        var url: URL
        var shouldStopAccessing = false
        
        // 尝试通过书签访问文件
        if let bookmarkData = bookmark {
            do {
                url = try resolveSecureBookmark(bookmarkData)
                if url.startAccessingSecurityScopedResource() {
                    shouldStopAccessing = true
                    print("通过书签成功访问文件")
                }
            } catch {
                print("书签恢复失败，尝试直接访问路径: \(error.localizedDescription)")
                // 如果书签无效，回退到直接路径
                url = URL(fileURLWithPath: path)
            }
        } else {
            url = URL(fileURLWithPath: path)
            print("使用直接路径访问文件")
        }
        
        var resourceValues = URLResourceValues()
        resourceValues.isUserImmutable = false
        
        do {
            var mutableURL = url
            try mutableURL.setResourceValues(resourceValues)
            print("成功解锁文件: \(path)")
        } catch {
            if let nsError = error as NSError? {
                switch nsError.code {
                case NSFileNoSuchFileError:
                    print("找不到文件: \(path)")
                    throw FileLockError.fileNotFound
                case NSFileWriteNoPermissionError:
                    print("没有写入权限: \(path)")
                    throw FileLockError.accessDenied
                default:
                    print("未知错误: \(nsError.code) - \(error.localizedDescription)")
                    throw FileLockError.unknown(error.localizedDescription)
                }
            } else {
                print("未分类错误: \(error.localizedDescription)")
                throw FileLockError.unknown(error.localizedDescription)
            }
        }
        
        if shouldStopAccessing {
            url.stopAccessingSecurityScopedResource()
            print("已停止安全资源访问")
        }
    }
    
    func isFileLocked(at path: String, withBookmark bookmark: Data? = nil) -> Bool {
        var url: URL
        var shouldStopAccessing = false
        
        // 尝试通过书签访问文件
        if let bookmarkData = bookmark {
            do {
                url = try resolveSecureBookmark(bookmarkData)
                if url.startAccessingSecurityScopedResource() {
                    shouldStopAccessing = true
                }
            } catch {
                // 如果书签无效，回退到直接路径
                url = URL(fileURLWithPath: path)
            }
        } else {
            url = URL(fileURLWithPath: path)
        }
        
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isUserImmutableKey])
            let isLocked = resourceValues.isUserImmutable ?? false
            
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
            
            return isLocked
        } catch {
            print("检查文件状态错误: \(error.localizedDescription)")
            
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
            
            return false
        }
    }
}

// MARK: - 完全磁盘访问权限助手

class FullDiskAccessHelper {
    static let shared = FullDiskAccessHelper()
    private let hasShownAccessPromptKey = "hasShownFullDiskAccessPrompt"
    
    private init() {
        createInfoPlistIfNeeded()
    }
    
    // 创建Info.plist文件(如果需要)
    private func createInfoPlistIfNeeded() {
        // 获取应用的包路径
        let bundlePath = Bundle.main.bundlePath
        let infoPlistPath = bundlePath + "/Contents/Info.plist"
        
        // 检查Info.plist是否存在
        if !FileManager.default.fileExists(atPath: infoPlistPath) {
            print("Info.plist不存在，尝试创建")
            
            // 创建基本的Info.plist内容
            let infoPlistDict: [String: Any] = [
                "NSFullDiskAccessUsageDescription": "FileLocker需要完全磁盘访问权限来保护您的文件免受意外删除",
                "CFBundleIdentifier": "com.example.FileLocker",
                "CFBundleName": "FileLocker",
                "CFBundleDisplayName": "FileLocker",
                "CFBundleVersion": "1.0",
                "CFBundleShortVersionString": "1.0"
            ]
            
            // 尝试创建Info.plist文件
            if let plistData = try? PropertyListSerialization.data(fromPropertyList: infoPlistDict, format: .xml, options: 0) {
                do {
                    try plistData.write(to: URL(fileURLWithPath: infoPlistPath))
                    print("成功创建Info.plist文件")
                } catch {
                    print("创建Info.plist失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    var hasShownAccessPrompt: Bool {
        get {
            return UserDefaults.standard.bool(forKey: hasShownAccessPromptKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hasShownAccessPromptKey)
        }
    }
    
    // 主动触发完全磁盘访问权限请求 - 增强版
    func requestFullDiskAccess() {
        // 确保Info.plist中有必要的权限描述
        createInfoPlistIfNeeded()
        
        print("开始请求完全磁盘访问权限...")
        
        // 尝试访问一些需要完全磁盘访问的位置
        let systemPaths = [
            "/Library",
            "/Library/Application Support",
            "/System/Library/CoreServices",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path
        ]
        
        var accessiblePaths = 0
        
        // 对多个系统路径进行访问尝试，增加应用出现在隐私设置中的几率
        for path in systemPaths {
            do {
                let _ = try FileManager.default.contentsOfDirectory(atPath: path)
                print("已有对 \(path) 的访问权限")
                accessiblePaths += 1
            } catch {
                print("尝试访问 \(path) 时出错: \(error.localizedDescription)")
            }
        }
        
        print("可访问路径: \(accessiblePaths)/\(systemPaths.count)")
        
        // 特别尝试访问下载文件夹
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if let url = downloadsURL {
            do {
                // 尝试创建临时文件测试写入权限
                let temporaryFileURL = url.appendingPathComponent("filelocker_permission_test_\(Int.random(in: 1000...9999)).tmp")
                let testString = "权限测试"
                try testString.write(to: temporaryFileURL, atomically: true, encoding: .utf8)
                
                // 成功创建，尝试删除
                print("成功在下载文件夹创建临时文件，确认有写入权限")
                try FileManager.default.removeItem(at: temporaryFileURL)
                print("成功删除测试文件")
            } catch {
                print("无法在下载文件夹创建测试文件: \(error.localizedDescription)")
            }
        }
        
        // 在尝试访问受限目录后，打开系统偏好设置
        openFullDiskAccessPreferences()
        hasShownAccessPrompt = true
        
        // 显示详细指导
        showDetailedGuidance()
    }
    
    // 显示详细的设置指导
    private func showDetailedGuidance() {
        let alert = NSAlert()
        alert.messageText = "如何授予FileLocker完全磁盘访问权限"
        alert.informativeText = """
        1. 在系统设置中，点击"隐私与安全性"
        2. 在左侧列表中，选择"完全磁盘访问权限"
        3. 点击左下角的锁图标并解锁
        4. 点击"+"按钮添加应用
        5. 导航到应用程序文件夹，选择FileLocker应用
        6. 勾选FileLocker旁边的复选框
        
        注意：如果在列表中没有看到FileLocker，请先通过Finder将应用从下载文件夹移动到应用程序文件夹，然后重新打开它。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "了解")
        alert.addButton(withTitle: "复制这些步骤")
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            // 复制步骤到剪贴板
            let steps = """
            如何授予FileLocker完全磁盘访问权限:
            1. 在系统设置中，点击"隐私与安全性"
            2. 在左侧列表中，选择"完全磁盘访问权限"
            3. 点击左下角的锁图标并解锁
            4. 点击"+"按钮添加应用
            5. 导航到应用程序文件夹，选择FileLocker应用
            6. 勾选FileLocker旁边的复选框
            """
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(steps, forType: .string)
        }
    }
    
    // 打开系统偏好设置的完全磁盘访问面板
    func openFullDiskAccessPreferences() {
        let privacyPrefPanePath = "/System/Library/PreferencePanes/Security.prefPane"
        
        if FileManager.default.fileExists(atPath: privacyPrefPanePath) {
            // 使用旧的方式打开
            let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        } else {
            // 尝试使用新的macOS设置方式
            let venturaPrefPath = "/System/Applications/System Settings.app"
            if FileManager.default.fileExists(atPath: venturaPrefPath) {
                // macOS Ventura及以上版本
                let url = URL(fileURLWithPath: venturaPrefPath)
                NSWorkspace.shared.open(url)
            } else {
                // 尝试打开系统偏好设置
                let prefURL = URL(fileURLWithPath: "/System/Applications/System Preferences.app")
                NSWorkspace.shared.open(prefURL)
            }
        }
    }
    
    // 检查是否可能有完全磁盘访问
    func checkFullDiskAccess() -> Bool {
        // 尝试访问用户下载文件夹
        let userHomeDirectory = NSHomeDirectory()
        let downloadsPath = userHomeDirectory + "/Downloads"
        
        do {
            let _ = try FileManager.default.contentsOfDirectory(atPath: downloadsPath)
            print("可以访问用户下载文件夹，已获得完全磁盘访问权限")
            return true
        } catch {
            print("无法访问用户下载文件夹: \(error.localizedDescription)")
        }
        
        // 备用方法：尝试访问其他系统目录
        let testPaths = [
            "/Library/Application Support",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").path
        ]
        
        for path in testPaths {
            do {
                let _ = try FileManager.default.contentsOfDirectory(atPath: path)
                print("可以访问系统目录: \(path)，已获得完全磁盘访问权限")
                return true
            } catch {
                print("无法访问系统目录: \(path)")
            }
        }
        
        print("所有测试路径都无法访问，未获得完全磁盘访问权限")
        return false
    }
}

// MARK: - 视图

struct FullDiskAccessView: View {
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部图标
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [.blue.opacity(0.8), .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 5)
                
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 50))
                    .foregroundColor(.white)
            }
            .padding(.top, 40)
            .padding(.bottom, 20)
            
            // 标题和说明
            Text("完全磁盘访问权限")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.linearGradient(colors: [.primary, .primary.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                .padding(.bottom, 10)
            
            Text("FileLocker需要完全磁盘访问权限才能锁定和保护您的重要文件。\n\n没有这个权限，应用将无法正常保护您的文件。")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
            
            // 步骤卡片
            VStack(alignment: .leading, spacing: 0) {
                Text("请按照以下步骤授予权限")
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.bottom, 16)
                
                VStack(spacing: 20) {
                    StepView(number: 1, text: "点击下方前往系统设置按钮")
                    StepView(number: 2, text: "点击左下方锁定图标并解锁")
                    StepView(number: 3, text: "在左侧选择完全磁盘访问权限")
                    StepView(number: 4, text: "在右侧列表中勾选FileLocker应用")
                    StepView(number: 5, text: "返回应用并点击检查权限状态")
                }
            }
            .padding(25)
            .frame(maxWidth: 450)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color.black.opacity(0.2) : Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
            )
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
            
            // 底部按钮
            HStack(spacing: 20) {
                Button("稍后再说") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .foregroundColor(.secondary)
                
                Button("前往系统设置") {
                    FullDiskAccessHelper.shared.openFullDiskAccessPreferences()
                    isPresented = false
                    FullDiskAccessHelper.shared.hasShownAccessPrompt = true
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(colors: [.blue, .blue.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                        )
                )
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
            .padding(.bottom, 40)
        }
        .frame(width: 550)
        .background(colorScheme == .dark ? Color.black.opacity(0.2) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
    }
}

// 步骤视图组件
struct StepView: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 15) {
            // 步骤数字
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                Text("\(number)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.blue)
            }
            
            // 步骤文本
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

struct FileDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    let file: LockedFile
    @State private var alertMessage: String?
    @State private var showingAlert = false
    @State private var isHovering = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 文件头部信息
                HStack(alignment: .top, spacing: 12) {
                    // 文件图标
                    ZStack {
                        Circle()
                            .fill(file.isDirectory ? 
                                  Color.blue.opacity(0.15) : 
                                  Color.purple.opacity(0.15))
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(
                                file.isLocked ?
                                    LinearGradient(colors: [.red, .orange], startPoint: .top, endPoint: .bottom) :
                                    LinearGradient(colors: [.green, .teal], startPoint: .top, endPoint: .bottom)
                            )
                    }
                    .padding(.top, 2)
                    
                    // 文件信息
                    VStack(alignment: .leading, spacing: 4) {
                        Text(file.name)
                            .font(.system(size: 18, weight: .bold))
                            .lineLimit(1)
                        
                        Text(file.path)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                        
                        HStack(spacing: 8) {
                            // 锁定状态标志
                            Label(
                                file.isLocked ? "已锁定" : "未锁定",
                                systemImage: file.isLocked ? "lock.fill" : "lock.open.fill"
                            )
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(file.isLocked ? 
                                          Color.red.opacity(0.15) : 
                                          Color.green.opacity(0.15))
                            )
                            .foregroundColor(file.isLocked ? .red : .green)
                            
                            // 文件类型标志
                            Label(
                                file.isDirectory ? "文件夹" : "文件",
                                systemImage: file.isDirectory ? "folder" : "doc"
                            )
                            .font(.system(size: 12))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(colorScheme == .dark ? 
                                          Color.gray.opacity(0.3) : 
                                          Color.gray.opacity(0.15))
                            )
                            .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? 
                              Color.black.opacity(0.2) : 
                              Color.white)
                        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
                )
                
                // 文件属性部分
                VStack(alignment: .leading, spacing: 10) {
                    Text("文件属性")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.bottom, 2)
                    
                    VStack(spacing: 8) {
                        // 锁定状态开关
                        HStack {
                            Text("文件锁定状态:")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { file.isLocked },
                                set: { newValue in
                                    toggleLockState(to: newValue)
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                        }
                        
                        Divider()
                        
                        // 锁定时间
                        HStack {
                            Text("上次操作时间:")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text(file.lockDate, style: .date)
                                .font(.system(size: 13))
                            
                            Text(file.lockDate, style: .time)
                                .font(.system(size: 13))
                        }
                        
                        Divider()
                        
                        // 文件状态
                        HStack {
                            Text("当前保护状态:")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(file.isLocked ? .green : .red)
                                    .frame(width: 6, height: 6)
                                
                                Text(file.isLocked ? "受保护" : "未受保护")
                                    .font(.system(size: 13))
                                    .foregroundColor(file.isLocked ? .green : .red)
                            }
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(colorScheme == .dark ? 
                                  Color.black.opacity(0.2) : 
                                  Color.white)
                            .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
                    )
                }
                
                Spacer()
                
                // 动作按钮
                Button(action: { toggleLockState(to: !file.isLocked) }) {
                    HStack {
                        Image(systemName: file.isLocked ? "lock.open.fill" : "lock.fill")
                        Text(file.isLocked ? "解锁文件" : "锁定文件")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(file.isLocked ? Color.orange : Color.blue)
                            .opacity(isHovering ? 0.9 : 1.0)
                    )
                    .foregroundColor(.white)
                    .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .onHover { hover in
                    isHovering = hover
                }
                .animation(.easeInOut(duration: 0.2), value: isHovering)
            }
            .padding(12)
        }
        .background(colorScheme == .dark ? Color.clear : Color.gray.opacity(0.05))
        .alert("操作提示", isPresented: $showingAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            if let message = alertMessage {
                Text(message)
            }
        }
    }
    
    private func toggleLockState(to newState: Bool) {
        do {
            if newState {
                // 锁定文件
                try FileLockerService.shared.lockFile(at: file.path, withBookmark: file.bookmark)
                withAnimation {
                    file.isLocked = true
                    file.lockDate = Date()
                }
            } else {
                // 解锁文件
                try FileLockerService.shared.unlockFile(at: file.path, withBookmark: file.bookmark)
                withAnimation {
                    file.isLocked = false
                    file.lockDate = Date()
                }
            }
            
        } catch FileLockError.fileNotFound {
            alertMessage = "找不到文件，可能已被移动或删除"
            showingAlert = true
        } catch FileLockError.accessDenied {
            alertMessage = "没有足够权限操作该文件"
            showingAlert = true
        } catch FileLockError.bookmarkRestorationFailed {
            alertMessage = "无法访问文件，书签恢复失败"
            showingAlert = true
        } catch {
            alertMessage = "操作出错: \(error.localizedDescription)"
            showingAlert = true
        }
    }
}

// MARK: - 功能按钮组件
struct TabBarItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .symbolVariant(isSelected ? .fill : .none)
                    .foregroundColor(isSelected ? .accentColor : .gray)
                
                Text(title)
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .accentColor : .gray)
            }
            .frame(width: 70, height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// 新增权限视图用于权限检查页面
struct PermissionView: View {
    @State private var showingFullDiskAccessDialog = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var hasAccess = false
    @State private var isCheckingAccess = false
    @State private var showSuccessAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 顶部图标
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [.blue.opacity(0.8), .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 5)
                    
                    Image(systemName: hasAccess ? "checkmark.shield.fill" : "shield.slash")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                }
                .padding(.top, 20)
                .padding(.bottom, 20)
                
                // 标题和说明
                Text(hasAccess ? "已获得完全磁盘访问权限" : "需要完全磁盘访问权限")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.linearGradient(colors: [.primary, .primary.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                    .padding(.bottom, 10)
                
                Text(hasAccess 
                    ? "您已成功授予FileLocker完全磁盘访问权限，现在可以锁定和保护系统中的任何文件。"
                    : "FileLocker需要完全磁盘访问权限才能锁定和保护您的重要文件。\n\n没有这个权限，应用将无法正常保护您的文件。")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 30)
                
                if !hasAccess {
                    // 步骤卡片
                    VStack(alignment: .leading, spacing: 0) {
                        Text("请按照以下步骤授予权限")
                            .font(.system(size: 18, weight: .semibold))
                            .padding(.bottom, 16)
                        
                        VStack(spacing: 20) {
                            StepView(number: 1, text: "点击下方前往系统设置按钮")
                            StepView(number: 2, text: "点击左下方锁定图标并解锁")
                            StepView(number: 3, text: "在左侧选择完全磁盘访问权限")
                            StepView(number: 4, text: "在右侧列表中勾选FileLocker应用")
                            StepView(number: 5, text: "返回应用并点击检查权限状态")
                        }
                    }
                    .padding(25)
                    .frame(maxWidth: 450)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(colorScheme == .dark ? Color.black.opacity(0.2) : Color.white)
                            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
                    )
                    .padding(.horizontal, 30)
                    .padding(.bottom, 40)
                }
                
                // 底部按钮
                HStack(spacing: 20) {
                    if !hasAccess {
                        Button("前往系统设置") {
                            showingFullDiskAccessDialog = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    
                    Button(isCheckingAccess ? "正在检查..." : "检查权限状态") {
                        isCheckingAccess = true
                        // 检查权限
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            let previousAccess = hasAccess
                            hasAccess = FullDiskAccessHelper.shared.checkFullDiskAccess()
                            isCheckingAccess = false
                            
                            // 检查结果提示
                            if hasAccess {
                                if !previousAccess {
                                    // 如果是刚获得权限
                                    alertMessage = "已成功获取完全磁盘访问权限！"
                                } else {
                                    // 如果已经有权限
                                    alertMessage = "已有完全磁盘访问权限，可以正常使用所有功能。"
                                }
                                showSuccessAlert = true
                            } else {
                                // 只有在没有权限时才显示提示
                                showingFullDiskAccessDialog = true
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isCheckingAccess)
                }
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
            .background(colorScheme == .dark ? Color.clear : Color.white)
        }
        .sheet(isPresented: $showingFullDiskAccessDialog) {
            FullDiskAccessView(isPresented: $showingFullDiskAccessDialog)
        }
        .alert("权限状态", isPresented: $showSuccessAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            // 检查当前权限状态
            hasAccess = FullDiskAccessHelper.shared.checkFullDiskAccess()
            
            // 只有在没有权限时才显示权限请求弹窗
            if !hasAccess && !FullDiskAccessHelper.shared.hasShownAccessPrompt {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showingFullDiskAccessDialog = true
                }
            } else if hasAccess {
                // 如果已有权限，显示一个简短的提示
                alertMessage = "已有完全磁盘访问权限，可以正常使用所有功能。"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showSuccessAlert = true
                }
            }
        }
    }
}

// MARK: - 文件系统浏览模型

class FileSystemItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let icon: String
    var children: [FileSystemItem]?
    var isExpanded: Bool = false
    
    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        
        // 使用更可靠的方法检查是否是目录
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue && exists
        
        // 根据文件类型选择合适的图标
        if self.isDirectory {
            self.icon = "folder"
            self.children = []
        } else {
            // 根据文件扩展名设置不同图标
            let ext = url.pathExtension.lowercased()
            switch ext {
            case "pdf":
                self.icon = "doc.text.fill"
            case "txt", "md", "rtf":
                self.icon = "doc.text"
            case "jpg", "jpeg", "png", "gif":
                self.icon = "photo"
            case "mp3", "wav", "m4a", "aac":
                self.icon = "music.note"
            case "mp4", "mov", "avi":
                self.icon = "film"
            case "zip", "rar", "7z":
                self.icon = "doc.zipper"
            case "app":
                self.icon = "app.badge"
            default:
                self.icon = "doc"
            }
            self.children = nil
        }
    }
    
    static func == (lhs: FileSystemItem, rhs: FileSystemItem) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    func loadChildren() {
        guard isDirectory else { return }
        guard children?.isEmpty ?? true else { return }
        
        do {
            // 使用更直接的方法获取子项
            let childPaths = try FileManager.default.contentsOfDirectory(atPath: url.path)
            
            // 过滤掉隐藏文件，并创建子项列表
            let visiblePaths = childPaths.filter { !$0.hasPrefix(".") }
            
            // 转换为完整路径并创建项目
            let childItems = visiblePaths.map { childPath -> FileSystemItem in
                let childURL = url.appendingPathComponent(childPath)
                return FileSystemItem(url: childURL)
            }
            
            // 按目录在前，文件在后排序
            children = childItems.sorted { (item1, item2) -> Bool in
                if item1.isDirectory && !item2.isDirectory {
                    return true
                } else if !item1.isDirectory && item2.isDirectory {
                    return false
                } else {
                    return item1.name.localizedStandardCompare(item2.name) == .orderedAscending
                }
            }
            
            print("成功加载目录 \(url.path) 下的 \(children?.count ?? 0) 个子项")
        } catch {
            print("加载 \(url.path) 子项出错: \(error.localizedDescription)")
            children = []
        }
    }
}

class FileSystemBrowser: ObservableObject {
    @Published var rootItems: [FileSystemItem] = []
    @Published var currentItems: [FileSystemItem] = []
    @Published var currentPath: String = ""
    @Published var errorMessage: String? = nil
    @Published var favoriteLocations: [URL] = []
    @Published var recentLocations: [URL] = []
    @Published var isLoading: Bool = false
    // 添加以下属性支持分栏浏览
    @Published var selectedDirectoryItems: [FileSystemItem] = [] // 存储选中文件夹的内容
    @Published var selectedDirectoryPath: String = "" // 选中文件夹的路径
    @Published var isLoadingSelectedDirectory: Bool = false // 正在加载选中文件夹的内容
    @Published var selectedDirectoryError: String? = nil // 加载选中文件夹时的错误
    
    // 添加多分栏支持
    @Published var browsePanels: [BrowserPanel] = [] // 存储所有分栏数据
    
    init() {
        // 初始化常用位置
        setupFavoriteLocations()
        // 从UserDefaults加载最近访问位置
        loadRecentLocations()
    }
    
    // 添加分栏时调用
    func addBrowserPanel(for item: FileSystemItem) {
        guard item.isDirectory else { return }
        
        // 首先检查新路径是否与当前路径相同或已在分栏中
        if item.url.path == currentPath {
            // 如果是当前路径，清空所有分栏
            browsePanels.removeAll()
            return
        }
        
        // 检查新路径是否与已有分栏有关系
        let newPath = item.url.path
        
        // 检查是否已存在相同路径的分栏，避免重复添加
        if browsePanels.contains(where: { $0.path == newPath }) {
            return
        }
        
        // 情况1: 当点击某个分栏中的文件夹时，应该基于该分栏添加新分栏
        // 查找当前选中项所在的分栏
        let currentPanelIndex = browsePanels.firstIndex { panel in
            panel.selectedItem?.id == item.id || 
            panel.items.contains(where: { $0.id == item.id })
        }
        
        if let index = currentPanelIndex {
            // 保留当前分栏及之前的所有分栏，移除后续分栏
            if index < browsePanels.count - 1 {
                browsePanels.removeSubrange((index + 1)...)
            }
            
            // 添加新分栏
            let newPanel = BrowserPanel(item: item)
            browsePanels.append(newPanel)
            loadBrowserPanelContent(for: newPanel)
            return
        }
        
        // 情况2: 如果新路径是某个已有分栏的子路径，保留所有前置分栏，添加新分栏
        var foundIndex: Int? = nil
        for (index, panel) in browsePanels.enumerated() {
            if newPath.hasPrefix(panel.path) && newPath != panel.path {
                foundIndex = index
            }
        }
        
        if let index = foundIndex {
            // 移除此分栏后的所有分栏
            if index < browsePanels.count - 1 {
                browsePanels.removeSubrange((index + 1)...)
            }
            
            // 添加新分栏
            let newPanel = BrowserPanel(item: item)
            browsePanels.append(newPanel)
            loadBrowserPanelContent(for: newPanel)
            return
        }
        
        // 情况3: 如果新路径是某个已有分栏的父路径，找到第一个这样的面板，保留之前所有面板
        for (index, panel) in browsePanels.enumerated() {
            if panel.path.hasPrefix(newPath) && panel.path != newPath {
                // 保留所有前面的面板，移除这个面板及后面的所有面板
                if index > 0 {
                    browsePanels = Array(browsePanels[0..<index])
                } else {
                    browsePanels.removeAll()
                }
                
                // 添加新面板
                let newPanel = BrowserPanel(item: item)
                browsePanels.append(newPanel)
                loadBrowserPanelContent(for: newPanel)
                return
            }
        }
        
        // 情况4: 如果是完全不相关的路径，清除所有分栏后添加新分栏
        browsePanels.removeAll()
        
        // 创建新面板
        let newPanel = BrowserPanel(item: item)
        browsePanels.append(newPanel)
        
        // 开始加载
        loadBrowserPanelContent(for: newPanel)
    }
    
    // 清除所有分栏
    func clearBrowserPanels() {
        browsePanels.removeAll()
    }
    
    // 加载分栏内容
    func loadBrowserPanelContent(for panel: BrowserPanel) {
        guard let item = panel.item else { return }
        
        panel.isLoading = true
        panel.error = nil
        panel.items = []
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // 获取目录内容
                let contents = try FileManager.default.contentsOfDirectory(atPath: item.url.path)
                
                var items: [FileSystemItem] = []
                for filename in contents {
                    // 跳过隐藏文件
                    if filename.hasPrefix(".") {
                        continue
                    }
                    
                    let itemPath = item.url.path + "/" + filename
                    let itemURL = URL(fileURLWithPath: itemPath)
                    let fileItem = FileSystemItem(url: itemURL)
                    items.append(fileItem)
                }
                
                // 排序：文件夹在前，文件在后
                let sortedItems = items.sorted { (item1, item2) -> Bool in
                    if item1.isDirectory && !item2.isDirectory {
                        return true
                    } else if !item1.isDirectory && item2.isDirectory {
                        return false
                    } else {
                        return item1.name.localizedStandardCompare(item2.name) == .orderedAscending
                    }
                }
                
                // 更新UI
                DispatchQueue.main.async {
                    panel.items = sortedItems
                    panel.isLoading = false
                    self.objectWillChange.send()
                }
            } catch {
                DispatchQueue.main.async {
                    panel.error = "无法加载文件夹内容: \(error.localizedDescription)"
                    panel.isLoading = false
                    self.objectWillChange.send()
                }
            }
        }
    }
    
    // 浏览面板类
    class BrowserPanel: Identifiable, ObservableObject {
        let id = UUID()
        var item: FileSystemItem?
        var path: String
        @Published var items: [FileSystemItem] = []
        @Published var isLoading: Bool = false
        @Published var error: String? = nil
        @Published var selectedItem: FileSystemItem? = nil
        
        init(item: FileSystemItem? = nil) {
            self.item = item
            self.path = item?.url.path ?? ""
        }
        
        // 判断指定路径是否是此面板的子路径
        func isParentOf(_ path: String) -> Bool {
            return !self.path.isEmpty && path.hasPrefix(self.path) && path != self.path
        }
        
        // 判断指定路径是否是此面板的父路径
        func isChildOf(_ path: String) -> Bool {
            return !path.isEmpty && self.path.hasPrefix(path) && self.path != path
        }
        
        // 判断是否是同一路径
        func isSamePath(_ path: String) -> Bool {
            return self.path == path
        }
    }
    
    // 设置常用位置
    private func setupFavoriteLocations() {
        let fileManager = FileManager.default
        
        // 添加默认常用位置
        var locations: [URL] = []
        
        // 下载文件夹
        if let downloadsURL = getDownloadsFolder() {
            locations.append(downloadsURL)
        }
        
        // 桌面
        if let desktopURL = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first {
            locations.append(desktopURL)
        }
        
        // 文档
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            locations.append(documentsURL)
        }
        
        // 用户主目录
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        locations.append(homeURL)
        
        // 应用程序文件夹
        let applicationsURL = URL(fileURLWithPath: "/Applications")
        if fileManager.fileExists(atPath: applicationsURL.path) {
            locations.append(applicationsURL)
        }
        
        // 更新到UI
        DispatchQueue.main.async {
            self.favoriteLocations = locations
        }
    }
    
    // 保存最近访问位置
    private func saveRecentLocation(_ url: URL) {
        // 确保这是一个有效的文件夹
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue else {
            return
        }
        
        // 从已有列表中移除相同路径
        recentLocations.removeAll { $0.path == url.path }
        
        // 添加到最前面
        recentLocations.insert(url, at: 0)
        
        // 限制最近位置列表长度
        if recentLocations.count > 10 {
            recentLocations = Array(recentLocations.prefix(10))
        }
        
        // 保存到UserDefaults
        if let bookmarkData = try? url.bookmarkData() {
            var bookmarksData = UserDefaults.standard.array(forKey: "recentLocationBookmarks") as? [Data] ?? []
            bookmarksData.insert(bookmarkData, at: 0)
            if bookmarksData.count > 10 {
                bookmarksData = Array(bookmarksData.prefix(10))
            }
            UserDefaults.standard.set(bookmarksData, forKey: "recentLocationBookmarks")
        }
    }
    
    // 加载最近访问位置
    private func loadRecentLocations() {
        guard let bookmarksData = UserDefaults.standard.array(forKey: "recentLocationBookmarks") as? [Data] else {
            return
        }
        
        var locations: [URL] = []
        
        for bookmarkData in bookmarksData {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale)
                if FileManager.default.fileExists(atPath: url.path) {
                    locations.append(url)
                }
            } catch {
                print("无法解析书签: \(error.localizedDescription)")
            }
        }
        
        DispatchQueue.main.async {
            self.recentLocations = locations
        }
    }

    // 浏览指定文件夹
    func browseLocation(_ url: URL) {
        // 保存到最近访问位置
        saveRecentLocation(url)
        
        // 设置当前路径并加载内容
        currentPath = url.path
        
        // 加载目录内容
        loadDirectory(url)
        
        // 注意：移除了对cleanupUnrelatedPanels的调用，让分栏保持不变，除非clearBrowserPanels被明确调用
    }
    
    // 清除与指定路径无关的分栏
    private func cleanupUnrelatedPanels(for path: String) {
        // 如果没有分栏或路径为空，直接清空所有分栏
        if browsePanels.isEmpty || path.isEmpty {
            browsePanels.removeAll()
            return
        }
        
        // 临时存储需要保留的分栏
        var panelsToKeep: [BrowserPanel] = []
        
        // 首先找到所有与新路径有直接父子关系的分栏
        for panel in browsePanels {
            // 如果分栏是新路径的父目录，保留
            if panel.isParentOf(path) {
                panelsToKeep.append(panel)
            }
            // 或者如果新路径是分栏的父目录，且是第一个这样的分栏，也保留
            else if panel.isChildOf(path) && panelsToKeep.isEmpty {
                panelsToKeep.append(panel)
            }
            // 如果是同一个路径，直接清空所有分栏并返回
            else if panel.isSamePath(path) {
                browsePanels.removeAll()
                return
            }
        }
        
        // 如果找到了有关系的分栏，更新列表
        if !panelsToKeep.isEmpty {
            // 确保分栏按照层级顺序排列
            panelsToKeep.sort { (panel1, panel2) -> Bool in
                // 如果panel1是panel2的父目录，panel1应该排在前面
                if panel1.isParentOf(panel2.path) {
                    return true
                }
                // 如果panel2是panel1的父目录，panel2应该排在前面
                else if panel2.isParentOf(panel1.path) {
                    return false
                }
                // 否则保持原有顺序
                else {
                    return browsePanels.firstIndex(where: { $0.id == panel1.id }) ?? 0 < 
                           browsePanels.firstIndex(where: { $0.id == panel2.id }) ?? 0
                }
            }
            browsePanels = panelsToKeep
        } 
        // 否则清空所有分栏
        else {
            browsePanels.removeAll()
        }
    }
    
    func loadFileSystem() {
        // 清除先前的错误信息
        errorMessage = nil
        
        // 尝试获取下载文件夹作为默认位置
        guard let downloadsURL = getDownloadsFolder() else {
            errorMessage = "无法访问下载文件夹"
            return
        }
        
        // 设置当前路径
        currentPath = downloadsURL.path
        
        // 加载下载文件夹内容
        loadDirectory(downloadsURL)
    }
    
    // 打开父文件夹
    func navigateToParent() {
        let currentURL = URL(fileURLWithPath: currentPath)
        let parentURL = currentURL.deletingLastPathComponent()
        
        // 防止导航到根目录以上
        if parentURL.path != "/" && currentURL.path != parentURL.path {
            browseLocation(parentURL)
        }
    }
    
    // 获取下载文件夹的URL，处理可能的错误
    private func getDownloadsFolder() -> URL? {
        print("尝试获取下载文件夹路径...")
        
        // 使用直接路径获取真实的Downloads文件夹（非沙盒路径）
        let userHomeDirectory = NSHomeDirectory()
        let downloadsPath = userHomeDirectory + "/Downloads"
        print("尝试使用真实用户路径: \(downloadsPath)")
        
        if FileManager.default.fileExists(atPath: downloadsPath) {
            // 检查是否真的能访问
            do {
                let _ = try FileManager.default.contentsOfDirectory(atPath: downloadsPath)
                print("通过真实路径成功访问下载文件夹")
                return URL(fileURLWithPath: downloadsPath)
            } catch {
                print("虽然路径存在，但访问失败: \(error.localizedDescription)")
            }
        }
        
        // 尝试通过固定路径获取
        let downloadsURL = URL(fileURLWithPath: "/Users/\(NSUserName())/Downloads")
        print("尝试使用固定用户路径: \(downloadsURL.path)")
        if FileManager.default.fileExists(atPath: downloadsURL.path) {
            do {
                let _ = try FileManager.default.contentsOfDirectory(atPath: downloadsURL.path)
                print("成功通过固定用户路径访问下载文件夹")
                return downloadsURL
            } catch {
                print("通过固定路径访问失败: \(error.localizedDescription)")
            }
        }
        
        // 如果以上方法都失败，尝试使用FileManager的标准目录（可能会返回沙盒路径）
        if let containerDownloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            print("通过FileManager标准目录获取路径: \(containerDownloadsURL.path)")
            
            // 检查是否真的能访问
            do {
                let _ = try FileManager.default.contentsOfDirectory(atPath: containerDownloadsURL.path)
                print("成功验证了FileManager返回的下载文件夹访问权限")
                return containerDownloadsURL
            } catch {
                print("虽然获取到了路径，但访问失败: \(error.localizedDescription)")
            }
        }
        
        // 都失败了
        print("所有获取下载文件夹的方法都失败了")
        return nil
    }
    
    // 添加加载选中文件夹内容的方法
    func loadSelectedDirectory(_ item: FileSystemItem) {
        guard item.isDirectory else { return }
        
        // 设置加载状态
        isLoadingSelectedDirectory = true
        selectedDirectoryError = nil
        selectedDirectoryPath = item.url.path
        selectedDirectoryItems = []
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // 获取目录内容
                let contents = try FileManager.default.contentsOfDirectory(atPath: item.url.path)
                
                var items: [FileSystemItem] = []
                for filename in contents {
                    // 跳过隐藏文件
                    if filename.hasPrefix(".") {
                        continue
                    }
                    
                    let itemPath = item.url.path + "/" + filename
                    let itemURL = URL(fileURLWithPath: itemPath)
                    let fileItem = FileSystemItem(url: itemURL)
                    items.append(fileItem)
                }
                
                // 排序：文件夹在前，文件在后
                let sortedItems = items.sorted { (item1, item2) -> Bool in
                    if item1.isDirectory && !item2.isDirectory {
                        return true
                    } else if !item1.isDirectory && item2.isDirectory {
                        return false
                    } else {
                        return item1.name.localizedStandardCompare(item2.name) == .orderedAscending
                    }
                }
                
                // 更新UI
                DispatchQueue.main.async {
                    self.selectedDirectoryItems = sortedItems
                    self.isLoadingSelectedDirectory = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.selectedDirectoryError = "无法加载文件夹内容: \(error.localizedDescription)"
                    self.isLoadingSelectedDirectory = false
                }
            }
        }
    }
    
    func loadDirectory(_ url: URL) {
        print("尝试加载目录: \(url.path)")
        
        // 进入加载状态
        DispatchQueue.main.async {
            self.isLoading = true
            self.currentItems = []
        }
        
        // 确保路径是完整的绝对路径
        let fullPath = url.path
        print("使用完整路径: \(fullPath)")
        
        do {
            // 检查目录是否存在且可访问
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir),
                  isDir.boolValue else {
                errorMessage = "指定的路径不是一个有效的目录"
                print("路径无效或不是目录: \(fullPath)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }
            
            // 不依赖安全书签，直接尝试强制访问目录
            print("直接尝试访问目录: \(fullPath)")
            let directoryContents = try FileManager.default.contentsOfDirectory(
                atPath: fullPath
            )
            
            print("成功读取目录: \(fullPath), 找到\(directoryContents.count)个项目")
            
            // 创建文件项目
            var items: [FileSystemItem] = []
            for filename in directoryContents {
                // 跳过隐藏文件
                if filename.hasPrefix(".") {
                    continue
                }
                
                let itemPath = fullPath + "/" + filename
                let itemURL = URL(fileURLWithPath: itemPath)
                let item = FileSystemItem(url: itemURL)
                items.append(item)
            }
            
            // 按照文件夹在前，文件在后的顺序排序
            let sortedItems = items.sorted { (item1, item2) -> Bool in
                if item1.isDirectory && !item2.isDirectory {
                    return true
                } else if !item1.isDirectory && item2.isDirectory {
                    return false
                } else {
                    return item1.name.localizedStandardCompare(item2.name) == .orderedAscending
                }
            }
            
            // 更新当前项目
            DispatchQueue.main.async {
                self.currentItems = sortedItems
                self.errorMessage = nil  // 清除错误信息
                self.isLoading = false   // 加载完成
            }
            
        } catch {
            let nsError = error as NSError
            let errorCode = nsError.code
            let errorDomain = nsError.domain
            
            print("加载目录出错 [\(errorDomain) - \(errorCode)]: \(error.localizedDescription)")
            
            var detailedMessage = "加载目录出错: \(error.localizedDescription)"
            
            // 根据错误类型提供更详细的信息
            if errorDomain == NSCocoaErrorDomain {
                switch errorCode {
                case NSFileReadNoSuchFileError:
                    detailedMessage = "找不到指定的文件夹，可能已被移动或删除"
                case NSFileReadNoPermissionError:
                    detailedMessage = "没有读取文件夹权限，请确认已授予应用完全磁盘访问权限"
                case NSFileReadInvalidFileNameError:
                    detailedMessage = "文件夹路径无效"
                default:
                    break
                }
            }
            
            DispatchQueue.main.async {
                self.currentItems = []
                self.errorMessage = detailedMessage
                self.isLoading = false  // 加载失败，同样完成
            }
            
            // 尝试请求访问权限
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if !FullDiskAccessHelper.shared.hasShownAccessPrompt {
                    FullDiskAccessHelper.shared.requestFullDiskAccess()
                }
            }
        }
    }
}

// MARK: - 文件树视图组件

struct FileTreeView: View {
    @ObservedObject var fileSystemBrowser: FileSystemBrowser
    @Binding var selectedItem: FileSystemItem?
    @State private var expandedItems = Set<UUID>()
    @Environment(\.modelContext) private var modelContext
    @State private var alertMessage: String?
    @State private var showingAlert = false
    
    var body: some View {
        List(selection: $selectedItem) {
            ForEach(fileSystemBrowser.rootItems) { item in
                FileItemRowView(item: item, expandedItems: $expandedItems, onToggleExpand: toggleExpand, onLockItem: lockItem)
                    .tag(item)
            }
        }
        .listStyle(.sidebar)
        .alert("操作提示", isPresented: $showingAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            if let message = alertMessage {
                Text(message)
            }
        }
    }
    
    private func toggleExpand(item: FileSystemItem) {
        if expandedItems.contains(item.id) {
            expandedItems.remove(item.id)
        } else {
            expandedItems.insert(item.id)
            
            // 加载子项
            if item.isDirectory {
                item.loadChildren()
            }
        }
    }
    
    private func lockItem(_ item: FileSystemItem) {
        // 移除仅限于Downloads目录的限制
        do {
            // 创建书签
            let bookmarkData = try FileLockerService.shared.createSecureBookmark(for: item.url)
            
            // 创建新的锁定文件记录
            let newFile = LockedFile(
                path: item.url.path, 
                isLocked: true, 
                isDirectory: item.isDirectory, 
                bookmark: bookmarkData
            )
            
            // 锁定文件
            try FileLockerService.shared.lockFile(at: item.url.path, withBookmark: bookmarkData)
            
            // 添加到数据库
            modelContext.insert(newFile)
            
            alertMessage = "文件已锁定"
            showingAlert = true
        } catch FileLockError.accessDenied {
            alertMessage = "没有足够权限锁定该文件。请确认FileLocker已获得完全磁盘访问权限。"
            showingAlert = true
        } catch {
            alertMessage = "锁定文件出错: \(error.localizedDescription)"
            showingAlert = true
        }
    }
}

// 新增单独的文件项行视图，解决递归编译问题
struct FileItemRowView: View {
    let item: FileSystemItem
    @Binding var expandedItems: Set<UUID>
    let onToggleExpand: (FileSystemItem) -> Void
    let onLockItem: (FileSystemItem) -> Void
    @State private var showingPasswordDialog = false
    @State private var password = ""
    @State private var confirmPassword = ""
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if item.isDirectory && (item.children?.count ?? 0) > 0 {
                    Button(action: {
                        onToggleExpand(item)
                    }) {
                        Image(systemName: expandedItems.contains(item.id) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundColor(.clear)
                }
                
                Image(systemName: item.icon + (item.isDirectory ? ".fill" : ""))
                    .foregroundColor(item.isDirectory ? .blue : .gray)
                
                Text(item.name)
                    .lineLimit(1)
                
                Spacer()
                
                if item.isDirectory {
                    Text("\(item.children?.count ?? 0)项")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Menu {
                    Button(action: {
                        onLockItem(item)
                    }) {
                        Label("常规锁定", systemImage: "lock")
                    }
                    
                    Button(action: {
                        showingPasswordDialog = true
                    }) {
                        Label("密码锁定", systemImage: "lock.shield")
                    }
                    
                    if item.isDirectory {
                        Button(action: {
                            onToggleExpand(item)
                        }) {
                            Label(
                                expandedItems.contains(item.id) ? "折叠" : "展开",
                                systemImage: expandedItems.contains(item.id) ? "chevron.up" : "chevron.down"
                            )
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            
            // 递归显示子项
            if item.isDirectory && expandedItems.contains(item.id) {
                let children = item.children ?? []
                ForEach(children) { child in
                    FileItemRowView(
                        item: child,
                        expandedItems: $expandedItems,
                        onToggleExpand: onToggleExpand, 
                        onLockItem: onLockItem
                    )
                    .padding(.leading, 20)
                }
            }
        }
        .sheet(isPresented: $showingPasswordDialog) {
            PasswordLockDialogView(
                password: $password,
                confirmPassword: $confirmPassword,
                onSubmit: {
                    lockWithPassword()
                }
            )
        }
    }
    
    private func lockWithPassword() {
        guard !password.isEmpty, password == confirmPassword else { return }
        
        do {
            // 创建书签
            let bookmarkData = try FileLockerService.shared.createSecureBookmark(for: item.url)
            
            // 生成密码哈希
            let passwordHash = FileLockerService.shared.hashPassword(password)
            
            // 创建新的锁定文件记录
            let newFile = LockedFile(
                path: item.url.path, 
                isLocked: true, 
                isDirectory: item.isDirectory, 
                bookmark: bookmarkData
            )
            
            // 设置密码保护相关属性
            newFile.isPasswordProtected = true
            newFile.passwordHash = passwordHash
            newFile.lastAccessTime = Date()
            
            // 锁定文件
            try FileLockerService.shared.lockFile(at: item.url.path, withBookmark: bookmarkData)
            
            // 添加到数据库
            modelContext.insert(newFile)
            
            // 添加访问日志
            let log = PasswordAccessLog(
                filePath: item.url.path,
                fileName: item.name,
                isSuccessful: true,
                accessType: "password_set"
            )
            modelContext.insert(log)
            
            // 清空密码
            password = ""
            confirmPassword = ""
            
        } catch {
            print("密码锁定文件失败: \(error.localizedDescription)")
        }
    }
}

// 密码锁定对话框
struct PasswordLockDialogView: View {
    @Binding var password: String
    @Binding var confirmPassword: String
    let onSubmit: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text("设置密码锁定")
                .font(.headline)
                .padding(.top, 20)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("请输入密码")
                    .font(.system(size: 13))
                
                SecureField("密码", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                
                Text("请确认密码")
                    .font(.system(size: 13))
                
                SecureField("确认密码", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
            }
            
            Text("提示: 密码锁定的文件，需要输入正确密码才能解锁访问")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 8)
            
            HStack(spacing: 12) {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("确定") {
                    onSubmit()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || confirmPassword.isEmpty || password != confirmPassword)
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .frame(width: 300)
    }
}

// MARK: - 全局文件浏览视图

struct GlobalFileBrowserView: View {
    @StateObject private var fileSystemBrowser = FileSystemBrowser()
    @State private var selectedItem: FileSystemItem?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var alertMessage: String?
    @State private var showingAlert = false
    @State private var isShowingFolderPicker = false
    // 添加以下变量以修复编译错误
    @State private var isShowingFilePicker = false
    // 添加一个ScrollViewProxy引用来控制滚动
    @Namespace private var scrollSpace
    
    var body: some View {
        VStack(spacing: 0) {
            // 文件路径导航栏
            HStack(spacing: 10) {
                Button(action: {
                    fileSystemBrowser.navigateToParent()
                    // 不自动清除分栏，以便能保持多层级导航状态
                }) {
                    Image(systemName: "chevron.left")
                }
                .disabled(fileSystemBrowser.currentPath == "/")
                .buttonStyle(.bordered)
                .help("返回上层目录")
                
                Text(fileSystemBrowser.currentPath)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Button(action: {
                    isShowingFolderPicker = true
                }) {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .help("选择文件夹")
                
                Button(action: {
                    fileSystemBrowser.loadFileSystem()
                    // 刷新时清空分栏，回到初始状态
                    fileSystemBrowser.clearBrowserPanels()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                }
                .buttonStyle(.bordered)
                .help("刷新文件列表")
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color.gray.opacity(0.1))
            
            // 如果有错误消息，显示错误信息
            if let errorMessage = fileSystemBrowser.errorMessage {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    
                    Text("无法加载文件夹")
                        .font(.headline)
                    
                    Text(errorMessage)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("可能原因:")
                            .font(.subheadline)
                            .bold()
                        
                        Text("• 应用没有足够的文件访问权限")
                        Text("• 文件夹路径可能有错误")
                        Text("• 您需要在系统设置中授予完全磁盘访问权限")
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.1))
                    )
                    
                    HStack(spacing: 15) {
                        Button("刷新") {
                            fileSystemBrowser.loadFileSystem()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("前往系统设置") {
                            FullDiskAccessHelper.shared.requestFullDiskAccess()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 10)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 分栏布局
                HStack(spacing: 0) {
                    // 左侧边栏 - 收藏夹和最近访问
                    VStack(spacing: 0) {
                        // 收藏位置
                        Section {
                            ForEach(fileSystemBrowser.favoriteLocations, id: \.self) { location in
                                SidebarLocationButton(
                                    name: location.lastPathComponent,
                                    icon: sidebarIconFor(location),
                                    isActive: fileSystemBrowser.currentPath == location.path
                                ) {
                                    fileSystemBrowser.browseLocation(location)
                                    // 不自动清除分栏，让用户点击文件夹时可以继续向下导航
                                }
                            }
                        } header: {
                            Text("收藏位置")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 10)
                                .padding(.top, 10)
                                .padding(.bottom, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        // 最近位置
                        if !fileSystemBrowser.recentLocations.isEmpty {
                            Section {
                                ForEach(fileSystemBrowser.recentLocations, id: \.self) { location in
                                    SidebarLocationButton(
                                        name: location.lastPathComponent, 
                                        icon: sidebarIconFor(location),
                                        isActive: fileSystemBrowser.currentPath == location.path
                                    ) {
                                        fileSystemBrowser.browseLocation(location)
                                        // 不自动清除分栏，让用户点击文件夹时可以继续向下导航
                                    }
                                }
                            } header: {
                                Text("最近位置")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 10)
                                    .padding(.bottom, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            Divider()
                                .padding(.vertical, 8)
                        }
                        
                        Spacer()
                    }
                    .frame(width: 200)
                    .background(colorScheme == .dark ? Color.black.opacity(0.1) : Color.white)
                    
                    // 分隔线
                    Divider()
                    
                    // 右侧内容 - 当前目录内容和分栏视图
                    VStack(spacing: 0) {
                        if fileSystemBrowser.isLoading {
                            VStack(spacing: 15) {
                                ProgressView()
                                    .padding(.bottom, 10)
                                Text("正在加载...")
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if fileSystemBrowser.currentItems.isEmpty {
                            VStack(spacing: 15) {
                                Image(systemName: "folder.badge.questionmark")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                    .padding(.bottom, 10)
                                Text("目录为空")
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            // 多分栏浏览视图 - 将VStack改为HStack，让详情面板固定在右侧
                            HStack(spacing: 0) {
                                // 分栏浏览视图
                                VStack(spacing: 0) {
                                    // 修改ScrollView实现，增强水平滚动效果，支持无限层级分栏
                                    ScrollViewReader { scrollProxy in
                                        ScrollView(.horizontal, showsIndicators: true) {
                                            HStack(spacing: 0) {
                                                // 第一个分栏 - 当前文件夹内容
                                                BrowserPanelView(
                                                    items: fileSystemBrowser.currentItems,
                                                    onItemSelected: { item in
                                                        // 更新选中项
                                                        selectedItem = item
                                                        
                                                        // 如果是文件夹，才添加新分栏
                                                        if item.isDirectory {
                                                            // 添加新分栏
                                                            fileSystemBrowser.addBrowserPanel(for: item)
                                                            
                                                            // 滚动到新添加的分栏
                                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                                withAnimation {
                                                                    if let lastPanel = fileSystemBrowser.browsePanels.last {
                                                                        scrollProxy.scrollTo(lastPanel.id, anchor: .trailing)
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                )
                                                .frame(width: 280)
                                                .id("root_panel") // 添加ID，便于滚动定位
                                                
                                                // 额外的分栏 - 展示选择的文件夹内容
                                                ForEach(fileSystemBrowser.browsePanels) { panel in
                                                    Divider()
                                                    
                                                    BrowserPanelContentView(
                                                        panel: panel, 
                                                        onItemSelected: { item in
                                                            // 更新选中状态
                                                            selectedItem = item
                                                            
                                                            if item.isDirectory {
                                                                // 如果是文件夹，添加新分栏
                                                                fileSystemBrowser.addBrowserPanel(for: item)
                                                                
                                                                // 滚动到新添加的分栏
                                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                                    withAnimation {
                                                                        if let lastPanel = fileSystemBrowser.browsePanels.last {
                                                                            scrollProxy.scrollTo(lastPanel.id, anchor: .trailing)
                                                                        }
                                                                    }
                                                                }
                                                            } else {
                                                                // 如果是文件，更新选中状态
                                                                panel.selectedItem = item
                                                            }
                                                        }
                                                    )
                                                    .frame(width: 280)
                                                    .id(panel.id) // 添加ID，便于滚动定位
                                                }
                                            }
                                            .padding(.bottom, 8) // 为滚动条留出空间
                                        }
                                        .padding(.bottom, 2) // 增加底部间距，使滚动条更明显
                                        .onChange(of: fileSystemBrowser.browsePanels.count) { _, newCount in
                                            // 当分栏数量变化时，自动滚动到最后一个分栏
                                            if newCount > 0 {
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                    withAnimation {
                                                        if let lastPanel = fileSystemBrowser.browsePanels.last {
                                                            scrollProxy.scrollTo(lastPanel.id, anchor: .trailing)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                // 移除可能导致空白的占位符
                                // 设置分栏区域不要无限扩展，只占用所需空间
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                // 右侧固定的操作区域 - 文件详情
                                if let item = selectedItem {
                                    Divider()
                                    
                                    VStack(spacing: 0) {
                                        HStack {
                                            Text(item.isDirectory ? "文件夹详情" : "文件详情")
                                                .font(.headline)
                                                .padding(.vertical, 8)
                                            
                                            Spacer()
                                            
                                            Button(action: {
                                                if item.isDirectory {
                                                    fileSystemBrowser.browseLocation(item.url)
                                                    // 不自动清除分栏，让用户能继续向下浏览
                                                }
                                            }) {
                                                Image(systemName: "arrow.right.circle")
                                            }
                                            .buttonStyle(.borderless)
                                            .help("导航到此位置")
                                            .opacity(item.isDirectory ? 1 : 0)
                                        }
                                        .padding(.horizontal)
                                        .background(Color.gray.opacity(0.1))
                                        
                                        // 文件详情
                                        ItemDetailView(item: item, onLock: {
                                            lockItem(item)
                                        })
                                        .padding()
                                        
                                        Spacer()
                                    }
                                    .frame(width: 280)
                                } else {
                                    // 未选择文件时显示提示
                                    Divider()
                                    
                                    VStack(spacing: 20) {
                                        Image(systemName: "arrow.left.circle")
                                            .font(.system(size: 40))
                                            .foregroundColor(.secondary)
                                        
                                        Text("从左侧选择文件查看详情")
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal)
                                            
                                        Spacer()
                                    }
                                    .padding(.top, 40)
                                    .frame(width: 280)
                                }
                            }
                            // 让整个HStack在水平方向上紧贴左边缘
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .alert("操作提示", isPresented: $showingAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            if let message = alertMessage {
                Text(message)
            }
        }
        .fileImporter(
            isPresented: $isShowingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // 切换到新目录时，清除所有分栏，从新位置开始导航
                    fileSystemBrowser.clearBrowserPanels()
                    fileSystemBrowser.browseLocation(url)
                }
            case .failure(let error):
                alertMessage = "选择文件夹出错: \(error.localizedDescription)"
                showingAlert = true
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                fileSystemBrowser.loadFileSystem()
            }
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self)
        }
        // 文件选择器
        .onChange(of: isShowingFilePicker) { _, newValue in
            if newValue {
                showNativeFilePicker(isDirectory: false)
            }
        }
        // 文件夹选择器
        .onChange(of: isShowingFolderPicker) { _, newValue in
            if newValue {
                showNativeFilePicker(isDirectory: true)
            }
        }
    }
    
    // 使用原生NSOpenPanel显示文件选择器
    private func showNativeFilePicker(isDirectory: Bool) {
        print("显示\(isDirectory ? "文件夹" : "文件")选择器")
        let panel = NSOpenPanel()
        panel.title = isDirectory ? "选择要锁定的文件夹" : "选择要锁定的文件"
        panel.message = isDirectory ? "请选择您要锁定的文件夹" : "请选择您要锁定的文件"
        panel.prompt = "选择"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = isDirectory
        panel.canCreateDirectories = isDirectory
        panel.canChooseFiles = !isDirectory
        
        // 设置文件类型
        if !isDirectory {
            // 允许所有文件类型
            panel.allowsOtherFileTypes = true
            panel.allowedFileTypes = nil // 设置为nil而不是空数组
        }
        
        // 确保在主线程运行
        DispatchQueue.main.async {
            // 确保面板显示在前台
            NSApp.activate(ignoringOtherApps: true)
            
            let response = panel.runModal()
            
            // 重置状态
            if isDirectory {
                self.isShowingFolderPicker = false
            } else {
                self.isShowingFilePicker = false
            }
            
            if response == .OK {
                print("用户选择了\(panel.urls.count)个\(isDirectory ? "文件夹" : "文件")")
                self.handleFileSelection(.success(panel.urls), isDirectory: isDirectory)
            } else {
                print("用户取消了选择")
            }
        }
    }
    
    // 为侧边栏位置生成合适的图标
    private func sidebarIconFor(_ location: URL) -> String {
        let path = location.path
        
        if path.hasSuffix("/Downloads") {
            return "arrow.down.circle"
        } else if path.hasSuffix("/Desktop") {
            return "desktopcomputer"
        } else if path.hasSuffix("/Documents") {
            return "doc.text"
        } else if path == NSHomeDirectory() {
            return "house"
        } else if path == "/Applications" {
            return "app.badge"
        }
        
        return "folder"
    }
    
    // 锁定文件
    private func lockItem(_ item: FileSystemItem) {
        do {
            // 创建书签
            let bookmarkData = try FileLockerService.shared.createSecureBookmark(for: item.url)
            
            // 创建新的锁定文件记录
            let newFile = LockedFile(
                path: item.url.path, 
                isLocked: true, 
                isDirectory: item.isDirectory, 
                bookmark: bookmarkData
            )
            
            // 锁定文件
            try FileLockerService.shared.lockFile(at: item.url.path, withBookmark: bookmarkData)
            
            // 添加到数据库
            modelContext.insert(newFile)
            
            // 刷新当前目录
            fileSystemBrowser.loadDirectory(URL(fileURLWithPath: fileSystemBrowser.currentPath))
            
            alertMessage = "文件已锁定"
            showingAlert = true
        } catch FileLockError.accessDenied {
            alertMessage = "没有足够权限锁定该文件。请确认FileLocker已获得完全磁盘访问权限。"
            showingAlert = true
        } catch {
            alertMessage = "锁定文件出错: \(error.localizedDescription)"
            showingAlert = true
        }
    }
    
    // 添加一个空的handleFileSelection函数以解决编译错误
    private func handleFileSelection(_ result: Result<[URL], Error>, isDirectory: Bool) {
        // 这个函数只是为了修复编译错误，实际功能在ContentView中实现
        print("GlobalFileBrowserView: 这个函数不应该被调用")
    }
}

// 浏览面板视图组件
struct BrowserPanelView: View {
    let items: [FileSystemItem]
    let onItemSelected: (FileSystemItem) -> Void
    @State private var selectedItemId: UUID? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(items, id: \.id) { item in
                    FileItemRow(item: item, isSelected: selectedItemId == item.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // 更新选中状态
                            selectedItemId = item.id
                            
                            // 直接调用回调，让父视图处理所有逻辑
                            onItemSelected(item)
                        }
                        .contextMenu {
                            if item.isDirectory {
                                Button(action: {
                                    // 复制路径
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(item.url.path, forType: .string)
                                }) {
                                    Label("复制路径", systemImage: "doc.on.clipboard")
                                }
                            } else {
                                Button(action: {
                                    // 复制路径
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(item.url.path, forType: .string)
                                }) {
                                    Label("复制路径", systemImage: "doc.on.clipboard")
                                }
                                
                                Button(action: {
                                    NSWorkspace.shared.open(item.url)
                                }) {
                                    Label("打开文件", systemImage: "eye")
                                }
                            }
                        }
                }
            }
            .listStyle(.plain)
        }
    }
}

// 浏览面板内容视图组件
struct BrowserPanelContentView: View {
    @ObservedObject var panel: FileSystemBrowser.BrowserPanel
    let onItemSelected: (FileSystemItem) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // 面板标题
            if let item = panel.item {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 14))
                    
                    Text(item.name)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
            }
            
            // 内容区域
            if panel.isLoading {
                Spacer()
                ProgressView("加载中...")
                Spacer()
            } else if let error = panel.error {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundColor(.orange)
                    Text("加载错误")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else if panel.items.isEmpty {
                Spacer()
                Text("文件夹为空")
                    .foregroundColor(.secondary)
                    .padding()
                Spacer()
            } else {
                // 显示文件夹内容
                List {
                    ForEach(panel.items, id: \.id) { item in
                        FileItemRow(item: item, isSelected: panel.selectedItem?.id == item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                panel.selectedItem = item
                                onItemSelected(item)
                                
                                // 如果是文件夹，并且是双击效果，直接导航
                                if item.isDirectory {
                                    // 向父级传递选中事件
                                    onItemSelected(item)
                                } else {
                                    // 文件项不需要额外处理
                                }
                            }
                            .contextMenu {
                                if item.isDirectory {
                                    Button(action: {
                                        // 复制路径
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(item.url.path, forType: .string)
                                    }) {
                                        Label("复制路径", systemImage: "doc.on.clipboard")
                                    }
                                    
                                    // 添加导航选项
                                    Button(action: {
                                        NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: "")
                                    }) {
                                        Label("在访达中打开", systemImage: "folder")
                                    }
                                } else {
                                    Button(action: {
                                        // 复制路径
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(item.url.path, forType: .string)
                                    }) {
                                        Label("复制路径", systemImage: "doc.on.clipboard")
                                    }
                                    
                                    Button(action: {
                                        NSWorkspace.shared.open(item.url)
                                    }) {
                                        Label("打开文件", systemImage: "eye")
                                    }
                                    
                                    Button(action: {
                                        NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: "")
                                    }) {
                                        Label("在访达中显示", systemImage: "folder")
                                    }
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

// 侧边栏位置按钮
struct SidebarLocationButton: View {
    let name: String
    let icon: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(isActive ? .blue : .gray)
                    .frame(width: 20)
                
                Text(name)
                    .foregroundColor(isActive ? .primary : .secondary)
                    .lineLimit(1)
                
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .background(isActive ? (Color.blue.opacity(0.1)) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// 文件项行视图
struct FileItemRow: View {
    let item: FileSystemItem
    @State private var isLocked: Bool = false
    var isSelected: Bool = false // 添加选中状态参数
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon + (item.isDirectory ? ".fill" : ""))
                .foregroundColor(item.isDirectory ? .blue : .gray)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .white : .primary)
                
                if !item.isDirectory {
                    Text(getFileSize(url: item.url))
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                }
            }
            
            Spacer()
            
            // 显示锁定状态
            if isLocked {
                Image(systemName: "lock.fill")
                    .foregroundColor(isSelected ? .white : .red)
                    .font(.caption)
                    .padding(.trailing, 4)
            }
            
            if item.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(isSelected ? Color.blue : Color.clear)
        .cornerRadius(4)
        .onAppear {
            // 检查文件是否被锁定
            checkLockStatus()
        }
    }
    
    // 获取文件大小
    private func getFileSize(url: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber {
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useAll]
                formatter.countStyle = .file
                return formatter.string(fromByteCount: Int64(truncating: size))
            }
        } catch {
            print("获取文件大小出错: \(error.localizedDescription)")
        }
        return "未知"
    }
    
    // 检查锁定状态
    private func checkLockStatus() {
        isLocked = FileLockerService.shared.isFileLocked(at: item.url.path)
    }
}

// 详情视图组件
struct ItemDetailView: View {
    let item: FileSystemItem
    let onLock: () -> Void
    @State private var isLocked: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // 文件图标和名称
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(item.isDirectory ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: item.icon + (item.isDirectory ? ".fill" : ""))
                            .font(.system(size: 24))
                            .foregroundColor(item.isDirectory ? .blue : .orange)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        
                        Text(item.url.deletingLastPathComponent().path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.bottom, 6)
                
                Divider()
                    .padding(.vertical, 3)
                
                // 文件信息
                VStack(alignment: .leading, spacing: 8) {
                    Text("文件信息")
                        .font(.headline)
                        .padding(.bottom, 2)
                    
                    InfoRow(label: "类型:", value: item.isDirectory ? "文件夹" : fileType(for: item.url))
                    
                    if !item.isDirectory {
                        InfoRow(label: "大小:", value: fileSizeFormatted(for: item.url))
                    }
                    
                    InfoRow(label: "创建时间:", value: fileCreationDate(for: item.url))
                    
                    InfoRow(label: "修改时间:", value: fileModificationDate(for: item.url))
                    
                    InfoRow(label: "完整路径:", value: item.url.path, isTruncated: true)
                    
                    InfoRow(label: "锁定状态:", value: isLocked ? "已锁定" : "未锁定", valueColor: isLocked ? .red : .green)
                }
                
                Spacer(minLength: 8)
                
                // 底部操作按钮
                VStack(spacing: 8) {
                    Button(action: onLock) {
                        HStack {
                            Image(systemName: "lock.fill")
                            Text(isLocked ? "重新锁定" : "锁定")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    // 在访达中打开按钮 - 对所有文件类型都可用
                    Button(action: {
                        NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: item.url.deletingLastPathComponent().path)
                    }) {
                        HStack {
                            Image(systemName: "finder")
                            Text("在访达中打开")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    // 仅对非文件夹显示"打开文件"按钮
                    if !item.isDirectory {
                        Button(action: {
                            NSWorkspace.shared.open(item.url)
                        }) {
                            HStack {
                                Image(systemName: "eye")
                                Text("打开文件")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(10)
        }
        .onAppear {
            checkLockStatus()
        }
    }
    
    // 检查锁定状态
    private func checkLockStatus() {
        isLocked = FileLockerService.shared.isFileLocked(at: item.url.path)
    }
    
    // 获取文件类型
    private func fileType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty {
            return "无类型文件"
        }
        
        // 根据扩展名返回可读的文件类型
        switch ext {
        case "pdf": return "PDF 文档"
        case "txt": return "文本文件"
        case "md": return "Markdown 文档"
        case "jpg", "jpeg": return "JPEG 图像"
        case "png": return "PNG 图像"
        case "gif": return "GIF 图像"
        case "mp3": return "MP3 音频"
        case "wav": return "WAV 音频"
        case "mp4": return "MP4 视频"
        case "mov": return "QuickTime 视频"
        case "zip": return "ZIP 压缩文件"
        case "app": return "应用程序"
        default: return "\(ext.uppercased()) 文件"
        }
    }
    
    // 格式化文件大小
    private func fileSizeFormatted(for url: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber {
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useAll]
                formatter.countStyle = .file
                return formatter.string(fromByteCount: Int64(truncating: size))
            }
        } catch {
            print("获取文件大小出错: \(error.localizedDescription)")
        }
        return "未知"
    }
    
    // 获取文件创建时间
    private func fileCreationDate(for url: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let date = attributes[.creationDate] as? Date {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                formatter.locale = Locale(identifier: "zh_CN")
                return formatter.string(from: date)
            }
        } catch {
            print("获取创建时间出错: \(error.localizedDescription)")
        }
        return "未知"
    }
    
    // 获取文件修改时间
    private func fileModificationDate(for url: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let date = attributes[.modificationDate] as? Date {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                formatter.locale = Locale(identifier: "zh_CN")
                return formatter.string(from: date)
            }
        } catch {
            print("获取修改时间出错: \(error.localizedDescription)")
        }
        return "未知"
    }
}

// 信息行组件
struct InfoRow: View {
    let label: String
    let value: String
    var isTruncated: Bool = false
    var valueColor: Color = .primary
    
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 64, alignment: .trailing)
            
            if isTruncated {
                Text(value)
                    .foregroundColor(valueColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(value)
                    .foregroundColor(valueColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(.caption, design: .rounded))
        .padding(.vertical, 1)
    }
}

// MARK: - 持久化管理器
class PersistenceManager {
    static let shared = PersistenceManager()
    
    let container: ModelContainer
    
    private init() {
        do {
            container = try ModelContainer(for: LockedFile.self)
        } catch {
            fatalError("无法初始化ModelContainer: \(error.localizedDescription)")
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var lockedFiles: [LockedFile]
    @State private var isShowingFilePicker = false {
        didSet {
            print("文件选择器状态变更: \(oldValue) -> \(isShowingFilePicker)")
        }
    }
    @State private var isShowingFolderPicker = false
    @State private var alertMessage: String?
    @State private var showingAlert = false
    @State private var isHoveringDropArea = false
    @State private var showingFullDiskAccessDialog = false
    @State private var selectedFunction: Int = 0
    @State private var selectedFile: LockedFile?
    @State private var searchText = ""
    
    // 密码保护相关状态
    @State private var showingPasswordDialog = false
    @State private var showingPasswordPrompt = false
    @State private var showingPasswordSettings = false
    @State private var password = ""
    @State private var confirmPassword = ""
    
    var filteredFiles: [LockedFile] {
        if searchText.isEmpty {
            return lockedFiles
        } else {
            return lockedFiles.filter { 
                $0.name.localizedCaseInsensitiveContains(searchText) || 
                $0.path.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部TabBar
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<5) { index in  // 修改为5个功能标签
                    let (title, icon) = functionInfo(for: index)
                    TabBarItem(title: title, icon: icon, isSelected: selectedFunction == index) {
                        withAnimation {
                            selectedFunction = index
                        }
                    }
                }
                
                Spacer()
                
                // 搜索框 - 只在常规功能选项卡显示
                if selectedFunction == 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        
                        TextField("搜索", text: $searchText)
                            .font(.system(size: 11))
                            .textFieldStyle(.plain)
                            .frame(width: 140)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                    )
                    .padding(.trailing, 10)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(Divider(), alignment: .bottom)
            
            // 功能区域
            ZStack {
                switch selectedFunction {
                case 0:
                    fileLockView
                case 1:
                    GlobalFileBrowserView()
                case 2:
                    PermissionView()
                case 3:
                    aboutView
                case 4:
                    SecurityView()  // 添加安全视图
                default:
                    fileLockView
                }
            }
            .animation(.easeInOut, value: selectedFunction)
            .transition(.opacity)
        }
        .frame(minWidth: 800, minHeight: 500)
        // 注释掉旧的fileImporter，使用新的实现
        /* 
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.item, .content, .data, .text, .image, .audio, .movie, .directory],
            allowsMultipleSelection: true
        ) { result in
            handleFileSelection(result, isDirectory: false)
        }
        .fileImporter(
            isPresented: $isShowingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            handleFileSelection(result, isDirectory: true)
        }
        */
        .alert("操作提示", isPresented: $showingAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            if let message = alertMessage {
                Text(message)
            }
        }
        .sheet(isPresented: $showingFullDiskAccessDialog) {
            FullDiskAccessView(isPresented: $showingFullDiskAccessDialog)
        }
        .onAppear {
            setupNotifications()
            
            // 检查是否需要显示完全磁盘访问权限提示
            if !FullDiskAccessHelper.shared.hasShownAccessPrompt {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showingFullDiskAccessDialog = true
                }
            }
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self)
        }
        // 文件选择器
        .onChange(of: isShowingFilePicker) { _, newValue in
            if newValue {
                showNativeFilePicker(isDirectory: false)
            }
        }
        // 文件夹选择器
        .onChange(of: isShowingFolderPicker) { _, newValue in
            if newValue {
                showNativeFilePicker(isDirectory: true)
            }
        }
        .sheet(isPresented: $showingPasswordDialog) {
            PasswordDialogView(
                password: $password,
                confirmPassword: $confirmPassword,
                onSubmit: addPasswordProtection,
                minLength: 6,
                requireSpecialChars: true,
                requireNumbers: true
            )
        }
        .sheet(isPresented: $showingPasswordPrompt) {
            PasswordPromptView(
                password: $password,
                onSubmit: {
                    verifyPasswordAndUnlock()
                }
            )
        }
        .sheet(isPresented: $showingPasswordSettings) {
            PasswordSettingsView(
                file: selectedFile!,
                modelContext: modelContext,
                onPasswordRemoved: {
                    alertMessage = "密码保护已移除"
                    showingAlert = true
                }
            )
        }
    }
    
    // 使用原生NSOpenPanel显示文件选择器
    private func showNativeFilePicker(isDirectory: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = isDirectory
        panel.canCreateDirectories = isDirectory
        panel.canChooseFiles = !isDirectory
        
        if !isDirectory {
            // 允许所有文件类型
            panel.allowedContentTypes = []
            panel.allowsOtherFileTypes = true
        }
        
        panel.begin { response in
            // 重置状态
            if isDirectory {
                isShowingFolderPicker = false
            } else {
                isShowingFilePicker = false
            }
            
            if response == .OK {
                let urls = panel.urls
                handleFileSelection(.success(urls), isDirectory: isDirectory)
            }
        }
    }
    
    private func functionInfo(for index: Int) -> (String, String) {
        switch index {
        case 0: return ("常规", "gearshape")
        case 1: return ("全局浏览", "globe")
        case 2: return ("权限检查", "shield")
        case 3: return ("关于", "info.circle")
        case 4: return ("安全", "lock.shield")  // 添加安全功能
        default: return ("", "")
        }
    }
    
    // 文件锁定功能视图
    private var fileLockView: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Text("文件锁定")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: {
                        print("点击了添加文件按钮")
                        // 强制刷新文件选择器状态
                        isShowingFilePicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isShowingFilePicker = true
                        }
                    }) {
                        Label("添加文件", systemImage: "plus.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 16))
                        Text("添加文件")
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button(action: {
                        print("点击了添加文件夹按钮")
                        // 强制刷新文件夹选择器状态
                        isShowingFolderPicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isShowingFolderPicker = true
                        }
                    }) {
                        Label("添加文件夹", systemImage: "folder.badge.plus")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 16))
                        Text("添加文件夹")
                    }
                    .buttonStyle(.bordered)
                    
                    Menu {
                        Button("授予完全磁盘访问权限") {
                            showingFullDiskAccessDialog = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16))
                    }
                    .menuStyle(.borderlessButton)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(colorScheme == .dark ? Color.black.opacity(0.2) : Color.white.opacity(0.5))
            
            // 拖放区域
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                    .fill(isHoveringDropArea ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isHoveringDropArea ? Color.blue.opacity(0.08) : Color.gray.opacity(0.05))
                    )
                
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 28))
                        .foregroundColor(isHoveringDropArea ? .blue : .gray)
                    
                    Text("拖放文件或文件夹到这里")
                        .font(.headline)
                        .foregroundColor(isHoveringDropArea ? .blue : .gray)
                    
                    Text("或点击上方按钮选择文件")
                        .font(.subheadline)
                        .foregroundColor(isHoveringDropArea ? .blue.opacity(0.8) : .gray.opacity(0.8))
                }
            }
            .frame(height: 120)
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .onDrop(of: [.fileURL], isTargeted: $isHoveringDropArea) { providers in
                handleDroppedItems(providers)
                return true
            }
            
            // 主内容区域
            HStack(spacing: 0) {
                // 左侧文件列表
                VStack {
                    if filteredFiles.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            
                            Text(searchText.isEmpty ? "没有锁定的文件" : "未找到匹配的文件")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            if !searchText.isEmpty {
                                Button("清除搜索") {
                                    searchText = ""
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(colorScheme == .dark ? Color.black.opacity(0.1) : Color.white.opacity(0.5))
                    } else {
                        VStack(spacing: 0) {
                            
                            List(selection: $selectedFile) {
                                ForEach(filteredFiles) { file in
                                    HStack(spacing: 12) {
                                        Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                                            .font(.system(size: 22))
                                            .foregroundStyle(file.isLocked ? 
                                                .linearGradient(colors: [.red, .orange], startPoint: .top, endPoint: .bottom) : 
                                                .linearGradient(colors: [.green, .teal], startPoint: .top, endPoint: .bottom))
                                            .frame(width: 24)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(file.name)
                                                .font(.system(size: 14, weight: .medium))
                                                .lineLimit(1)
                                            
                                            Text(file.path)
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        
                                        Spacer()
                                        
                                        Text(file.isLocked ? "已锁定" : "未锁定")
                                            .font(.system(size: 11, weight: .medium))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(file.isLocked ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
                                            .foregroundColor(file.isLocked ? .red : .green)
                                            .cornerRadius(4)
                                    }
                                    .padding(.vertical, 4)
                                    .tag(file)
                                    .contextMenu {
                                        if !file.isLocked {
                                            Button(role: .destructive, action: {
                                                deleteFile(file)
                                            }) {
                                                Label("删除", systemImage: "trash")
                                            }
                                        }
                                        
                                        Button(action: {
                                            // 复制路径到剪贴板
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(file.path, forType: .string)
                                        }) {
                                            Label("复制路径", systemImage: "doc.on.clipboard")
                                        }
                                        
                                        if file.isLocked {
                                            Button(action: {
                                                unlockFile(file)
                                            }) {
                                                Label("解锁", systemImage: "lock.open")
                                            }
                                        } else {
                                            Button(action: {
                                                lockFile(file)
                                            }) {
                                                Label("锁定", systemImage: "lock")
                                            }
                                        }
                                        
                                        Button(action: {
                                            if let url = URL(string: "file://\(file.path)") {
                                                NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
                                            }
                                        }) {
                                            Label("在访达中显示", systemImage: "finder")
                                        }
                                    }
                                }
                                .onDelete(perform: deleteFiles)
                            }
                            .listStyle(.inset)
                        }
                    }
                }
                .frame(minWidth: 280)
                
                // 分隔线
                Divider()
                
                // 右侧文件详情
                ZStack {
                    if let file = selectedFile {
                        FileDetailView(file: file)
                    } else {
                        VStack(spacing: 20) {
                            Image(systemName: "arrow.left.circle")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            
                            Text("从左侧列表选择文件查看详情")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 1)
        }
    }
    
    // 关于功能视图
    private var aboutView: some View {
        VStack(spacing: 0) {
            // 内容区域使用ScrollView包裹，允许滚动
            ScrollView {
                VStack(spacing: 30) {
                    // 应用图标
                    Image("Logo")
                        .resizable()
                        .frame(width: 128, height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                        .padding(.top, 40)
                    
                    // 应用标题和版本
                    VStack(spacing: 2) {
                        Text("FileLocker")
                            .font(.title)
                            .fontWeight(.semibold)
                        
                        Text("版本 1.0.0")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // 应用介绍
                    VStack(alignment: .leading, spacing: 16) {
                        Text("FileLocker是一款简单高效的文件保护工具，通过设置文件的\"用户不可变\"属性，可防止重要文件被意外修改或删除。")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("主要功能")
                                .font(.headline)
                                .padding(.leading)
                            
                            FeatureRow(icon: "lock.fill", 
                                      title: "文件锁定保护", 
                                      description: "一键锁定文件或文件夹，防止意外修改、删除或覆盖")
                            
                            FeatureRow(icon: "lock.open.fill", 
                                      title: "快速解锁文件", 
                                      description: "需要编辑时可随时解锁文件，操作简单方便")
                            
                            FeatureRow(icon: "bookmark.fill", 
                                      title: "文件书签管理", 
                                      description: "保存已锁定文件的记录，便于统一管理和快速访问")
                            
                            FeatureRow(icon: "magnifyingglass", 
                                      title: "全局浏览模式", 
                                      description: "查看所有已锁定文件的状态，提供文件详情和快捷操作")
                            
                            FeatureRow(icon: "checkmark.shield.fill", 
                                      title: "权限检查功能", 
                                      description: "检测系统权限状态，确保软件可正常访问和保护文件")
                            
                            FeatureRow(icon: "folder.badge.gearshape", 
                                      title: "批量文件处理", 
                                      description: "支持同时锁定或解锁多个文件，提高工作效率")
                        }
                        .padding(.bottom, 10)
                    }
                    
                    // 版权信息
                    Text("Copyright © 2025 设计方法 Fangfa.Design")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 20)
                }
                .padding(.horizontal)
            }
            .background(colorScheme == .dark ? Color.black.opacity(0.1) : Color.white.opacity(0.5))
        }
    }
    
    // 设置通知监听器来响应菜单操作
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("AddFile"),
            object: nil,
            queue: .main
        ) { _ in
            print("收到添加文件通知")
            // 强制刷新文件选择器状态
            self.isShowingFilePicker = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.isShowingFilePicker = true
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name("AddFolder"),
            object: nil,
            queue: .main
        ) { _ in
            print("收到添加文件夹通知")
            // 强制刷新文件夹选择器状态
            self.isShowingFolderPicker = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.isShowingFolderPicker = true
            }
        }
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>, isDirectory: Bool = false) {
        switch result {
        case .success(let urls):
            for selectedURL in urls {
                processSelectedURL(selectedURL, isDirectory: isDirectory)
            }
        case .failure(let error):
            alertMessage = "选择文件出错: \(error.localizedDescription)"
            showingAlert = true
        }
    }
    
    private func processSelectedURL(_ selectedURL: URL, isDirectory: Bool) {
        // 请求文件访问权限
        guard selectedURL.startAccessingSecurityScopedResource() else {
            alertMessage = "无法访问所选文件或文件夹"
            showingAlert = true
            return
        }
        
        do {
            // 创建书签数据用于持久化访问
            let bookmarkData = try FileLockerService.shared.createSecureBookmark(for: selectedURL)
            
            // 创建新的锁定文件记录
            let newFile = LockedFile(path: selectedURL.path, isLocked: true, isDirectory: isDirectory, bookmark: bookmarkData)
            
            // 锁定文件
            try FileLockerService.shared.lockFile(at: selectedURL.path, withBookmark: bookmarkData)
            
            // 添加到数据库
            withAnimation {
                modelContext.insert(newFile)
            }
        } catch FileLockError.accessDenied {
            alertMessage = "没有权限锁定该文件，请确认应用有足够的权限"
            showingAlert = true
        } catch FileLockError.fileNotFound {
            alertMessage = "找不到所选文件"
            showingAlert = true
        } catch FileLockError.bookmarkCreationFailed {
            alertMessage = "创建文件书签失败，无法持久访问文件"
            showingAlert = true
        } catch {
            alertMessage = "锁定文件出错: \(error.localizedDescription)"
            showingAlert = true
        }
        
        selectedURL.stopAccessingSecurityScopedResource()
    }

    private func deleteFiles(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let file = lockedFiles[index]
                // 在删除记录前先解锁文件
                if file.isLocked {
                    do {
                        try FileLockerService.shared.unlockFile(at: file.path, withBookmark: file.bookmark)
                    } catch {
                        alertMessage = "解锁文件失败: \(error.localizedDescription)"
                        showingAlert = true
                    }
                }
                modelContext.delete(file)
            }
        }
    }
    
    // 处理拖放的项目
    private func handleDroppedItems(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                guard error == nil else {
                    DispatchQueue.main.async {
                        alertMessage = "读取拖放的文件出错: \(error!.localizedDescription)"
                        showingAlert = true
                    }
                    return
                }
                
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }
                
                DispatchQueue.main.async {
                    // 判断是文件还是文件夹
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                        processSelectedURL(url, isDirectory: isDirectory.boolValue)
                    }
                }
            }
        }
    }
    
    // 删除单个文件
    private func deleteFile(_ file: LockedFile) {
        withAnimation {
            // 在删除记录前先解锁文件（如果需要）
            if file.isLocked {
                do {
                    try FileLockerService.shared.unlockFile(at: file.path, withBookmark: file.bookmark)
                } catch {
                    alertMessage = "解锁文件失败: \(error.localizedDescription)"
                    showingAlert = true
                    return
                }
            }
            
            // 从选中状态中移除
            if selectedFile?.id == file.id {
                selectedFile = nil
            }
            
            // 从数据库中删除
            modelContext.delete(file)
            
            // 成功提示
            alertMessage = "已删除文件记录"
            showingAlert = true
        }
    }
    
    // 锁定单个文件
    private func lockFile(_ file: LockedFile) {
        do {
            try FileLockerService.shared.lockFile(at: file.path, withBookmark: file.bookmark)
            withAnimation {
                file.isLocked = true
                file.lockDate = Date()
            }
            alertMessage = "文件已锁定"
            showingAlert = true
        } catch {
            alertMessage = "锁定文件失败: \(error.localizedDescription)"
            showingAlert = true
        }
    }
    
    // 解锁单个文件
    private func unlockFile(_ file: LockedFile) {
        do {
            try FileLockerService.shared.unlockFile(at: file.path, withBookmark: file.bookmark)
            withAnimation {
                file.isLocked = false
                file.lockDate = Date()
            }
            alertMessage = "文件已解锁"
            showingAlert = true
        } catch {
            alertMessage = "解锁文件失败: \(error.localizedDescription)"
            showingAlert = true
        }
    }
    
    // 密码保护相关方法
    private func showPasswordProtectionDialog() {
        password = ""
        confirmPassword = ""
        showingPasswordDialog = true
    }
    
    private func showPasswordSettingsDialog() {
        showingPasswordSettings = true
    }
    
    private func promptPasswordForUnlock(_ file: LockedFile) {
        password = ""
        selectedFile = file
        showingPasswordPrompt = true
    }
    
    private func addPasswordProtection() {
        guard let file = selectedFile else { return }
        
        // 生成密码哈希
        let passwordHash = FileLockerService.shared.hashPassword(password)
        
        // 设置密码保护相关属性
        file.isPasswordProtected = true
        file.passwordHash = passwordHash
        file.lastAccessTime = Date()
        
        // 添加访问日志
        let log = PasswordAccessLog(
            filePath: file.path,
            fileName: file.name,
            isSuccessful: true,
            accessType: "password_set"
        )
        modelContext.insert(log)
        
        // 清空密码
        password = ""
        confirmPassword = ""
        
        alertMessage = "密码保护已成功添加"
        showingAlert = true
    }
    
    private func verifyPasswordAndUnlock() {
        guard let file = selectedFile, file.isPasswordProtected else { return }
        
        // 增加访问尝试计数
        file.accessAttempts += 1
        
        // 验证密码
        if let hash = file.passwordHash, FileLockerService.shared.verifyPassword(password, against: hash) {
            // 密码正确，解锁文件
            do {
                try FileLockerService.shared.unlockFile(at: file.path, withBookmark: file.bookmark)
                
                // 更新文件状态
                file.isLocked = false
                file.lastAccessTime = Date()
                
                // 记录成功访问
                let log = PasswordAccessLog(
                    filePath: file.path,
                    fileName: file.name,
                    isSuccessful: true,
                    accessType: "unlock"
                )
                modelContext.insert(log)
                
                alertMessage = "文件已解锁"
                showingAlert = true
            } catch {
                // 记录失败访问
                let log = PasswordAccessLog(
                    filePath: file.path,
                    fileName: file.name,
                    isSuccessful: false,
                    accessType: "unlock"
                )
                modelContext.insert(log)
                
                alertMessage = "解锁文件失败: \(error.localizedDescription)"
                showingAlert = true
            }
        } else {
            // 记录失败访问
            let log = PasswordAccessLog(
                filePath: file.path,
                fileName: file.name,
                isSuccessful: false,
                accessType: "unlock"
            )
            modelContext.insert(log)
            
            alertMessage = "密码不正确，请重试"
            showingAlert = true
        }
        
        // 清空密码
        password = ""
    }
}

// MARK: - 应用入口

struct FileLockerApp: App {
    @StateObject private var fullDiskAccessState = FullDiskAccessState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            LockedFile.self,
            PasswordAccessLog.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 500)
                .environmentObject(fullDiskAccessState)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加文件") {
                    NotificationCenter.default.post(name: Notification.Name("AddFile"), object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("添加文件夹") {
                    NotificationCenter.default.post(name: Notification.Name("AddFolder"), object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                
                Button("授予完全磁盘访问权限") {
                    FullDiskAccessHelper.shared.openFullDiskAccessPreferences()
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }
    
    init() {
        // 确保Info.plist中的应用类别生效
        let bundleInfoDict = Bundle.main.infoDictionary
        if bundleInfoDict?["LSApplicationCategoryType"] == nil {
            // 若没有找到类别信息，尝试从自定义Info.plist加载
            if let infoPlistPath = Bundle.main.path(forResource: "Info", ofType: "plist"),
               let infoDict = NSDictionary(contentsOfFile: infoPlistPath) as? [String: Any] {
                // 打印确认类别已找到
                if let category = infoDict["LSApplicationCategoryType"] as? String {
                    print("已找到应用类别: \(category)")
                }
            }
        }
    }
}

class FullDiskAccessState: ObservableObject {
    @Published var hasRequested = FullDiskAccessHelper.shared.hasShownAccessPrompt
    
    init() {}
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 检查应用是否在应用程序文件夹中
        checkApplicationLocation()
    }
    
    private func checkApplicationLocation() {
        let bundlePath = Bundle.main.bundlePath
        
        if !bundlePath.hasPrefix("/Applications") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let alert = NSAlert()
                alert.messageText = "推荐将FileLocker移动到应用程序文件夹"
                alert.informativeText = """
                为了确保FileLocker能够正确显示在系统设置的权限列表中，建议将应用移动到应用程序文件夹。
                
                您希望现在进行移动吗？
                """
                alert.alertStyle = .informational
                alert.addButton(withTitle: "是，移动到应用程序")
                alert.addButton(withTitle: "稍后再说")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    // 尝试移动应用到应用程序文件夹
                    let applicationsPath = "/Applications"
                    let appName = URL(fileURLWithPath: bundlePath).lastPathComponent
                    let targetPath = "\(applicationsPath)/\(appName)"
                    
                    do {
                        try FileManager.default.copyItem(atPath: bundlePath, toPath: targetPath)
                        
                        let successAlert = NSAlert()
                        successAlert.messageText = "已成功移动到应用程序文件夹"
                        successAlert.informativeText = "FileLocker已被复制到应用程序文件夹。建议您关闭此版本，并从应用程序文件夹启动FileLocker。"
                        successAlert.alertStyle = .informational
                        successAlert.addButton(withTitle: "好的")
                        successAlert.runModal()
                    } catch {
                        let errorAlert = NSAlert()
                        errorAlert.messageText = "无法移动到应用程序文件夹"
                        errorAlert.informativeText = "出现错误: \(error.localizedDescription)\n\n您可以手动将应用拖到应用程序文件夹。"
                        errorAlert.alertStyle = .warning
                        errorAlert.addButton(withTitle: "好的")
                        errorAlert.runModal()
                    }
                }
            }
        }
    }
}

// 添加一个用于显示功能项的新组件
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.blue)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

// 添加SecurityView组件
struct SecurityView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var lockedFiles: [LockedFile]
    @Query private var accessLogs: [PasswordAccessLog]
    @State private var passwordProtectedOnly = false
    @State private var selectedFile: LockedFile?
    @State private var showingPasswordDialog = false
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var alertMessage: String?
    @State private var showingAlert = false
    @State private var showingResetDialog = false
    @State private var currentPassword = ""
    @State private var showingAccessLogs = false
    @State private var minPasswordLength = 6
    @State private var requireSpecialChars = true
    @State private var requireNumbers = true
    
    var filteredFiles: [LockedFile] {
        passwordProtectedOnly ? lockedFiles.filter { $0.isPasswordProtected } : lockedFiles
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Text("密码保护管理")
                .font(.headline)
                .padding(.top, 12)
            
            HStack(spacing: 16) {
                // 左侧列表
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("保护文件列表")
                            .font(.system(size: 14, weight: .medium))
                        
                        Spacer()
                        
                        Toggle("仅显示密码保护", isOn: $passwordProtectedOnly)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 12))
                    }
                    .padding(.bottom, 4)
                    
                    List(selection: $selectedFile) {
                        ForEach(filteredFiles) { file in
                            HStack {
                                Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                                    .foregroundColor(file.isPasswordProtected ? .blue : .gray)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.name)
                                        .font(.system(size: 13))
                                        .lineLimit(1)
                                    
                                    Text(file.path)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                if file.isPasswordProtected {
                                    Image(systemName: "lock.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 12))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                    }
                    .listStyle(.bordered(alternatesRowBackgrounds: true))
                    .frame(minHeight: 240)
                }
                .frame(width: 300)
                
                // 右侧详情
                VStack(alignment: .leading) {
                    Text("文件保护详情")
                        .font(.system(size: 14, weight: .medium))
                        .padding(.bottom, 8)
                    
                    if let file = selectedFile {
                        // 文件详情卡片
                        VStack(alignment: .leading, spacing: 16) {
                            // 文件信息
                            GroupBox(label: Text("文件信息").font(.system(size: 12, weight: .medium))) {
                                VStack(alignment: .leading, spacing: 8) {
                                    LabeledContent("名称", value: file.name)
                                    LabeledContent("路径", value: file.path)
                                    LabeledContent("类型", value: file.isDirectory ? "文件夹" : "文件")
                                    LabeledContent("锁定状态", value: file.isLocked ? "已锁定" : "未锁定")
                                    LabeledContent("密码保护", value: file.isPasswordProtected ? "已启用" : "未启用")
                                    if let lastAccess = file.lastAccessTime {
                                        LabeledContent("最后访问", value: formatDate(lastAccess))
                                    }
                                    LabeledContent("访问尝试次数", value: "\(file.accessAttempts)")
                                }
                                .font(.system(size: 12))
                                .padding(8)
                            }
                            .padding(.horizontal, 4)
                            
                            // 密码保护操作
                            GroupBox(label: Text("密码保护操作").font(.system(size: 12, weight: .medium))) {
                                VStack(spacing: 10) {
                                    if file.isPasswordProtected {
                                        Button("重设密码") {
                                            resetPassword()
                                        }
                                        .buttonStyle(.borderedProminent)
                                        
                                        Button("移除密码保护") {
                                            removePasswordProtection()
                                        }
                                        .buttonStyle(.bordered)
                                        
                                        Button("查看访问记录") {
                                            showingAccessLogs = true
                                        }
                                        .buttonStyle(.bordered)
                                    } else {
                                        Button("添加密码保护") {
                                            showingPasswordDialog = true
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                }
                                .padding(8)
                            }
                            .padding(.horizontal, 4)
                        }
                    } else {
                        // 未选择文件
                        VStack(spacing: 15) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 30))
                                .foregroundColor(.secondary)
                            Text("选择文件查看详情")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    Spacer()
                    
                    // 密码策略设置
                    GroupBox(label: Text("密码策略").font(.system(size: 12, weight: .medium))) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("最小密码长度")
                                    .font(.system(size: 12))
                                
                                Stepper("\(minPasswordLength)个字符", value: $minPasswordLength, in: 4...16)
                                    .font(.system(size: 12))
                            }
                            
                            HStack {
                                Toggle("要求特殊字符", isOn: $requireSpecialChars)
                                    .font(.system(size: 12))
                                
                                Spacer()
                                
                                Toggle("要求数字", isOn: $requireNumbers)
                                    .font(.system(size: 12))
                            }
                        }
                        .padding(8)
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(12)
        }
        .sheet(isPresented: $showingPasswordDialog) {
            PasswordDialogView(
                password: $password,
                confirmPassword: $confirmPassword,
                onSubmit: addPasswordProtection,
                minLength: minPasswordLength,
                requireSpecialChars: requireSpecialChars,
                requireNumbers: requireNumbers
            )
        }
        .sheet(isPresented: $showingResetDialog) {
            ResetPasswordView(
                currentPassword: $currentPassword,
                newPassword: $password,
                confirmPassword: $confirmPassword,
                onSubmit: confirmResetPassword,
                minLength: minPasswordLength,
                requireSpecialChars: requireSpecialChars,
                requireNumbers: requireNumbers
            )
        }
        .sheet(isPresented: $showingAccessLogs) {
            if let file = selectedFile {
                AccessLogsView(filePath: file.path)
            }
        }
        .alert("操作提示", isPresented: $showingAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            if let message = alertMessage {
                Text(message)
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func addPasswordProtection() {
        guard let file = selectedFile else { return }
        
        // 验证密码
        if !validatePassword() { return }
        
        // 验证通过，添加密码保护
        do {
            let passwordHash = FileLockerService.shared.hashPassword(password)
            
            // 设置密码保护属性
            file.isPasswordProtected = true
            file.passwordHash = passwordHash
            file.lastAccessTime = Date()
            
            // 重新锁定文件
            try FileLockerService.shared.lockFile(at: file.path, withBookmark: file.bookmark)
            
            // 记录操作日志
            let log = PasswordAccessLog(
                filePath: file.path,
                fileName: file.name,
                isSuccessful: true,
                accessType: "password_set"
            )
            modelContext.insert(log)
            
            // 清空密码字段
            password = ""
            confirmPassword = ""
            
            alertMessage = "密码保护已成功添加"
            showingAlert = true
        } catch {
            alertMessage = "设置密码保护失败: \(error.localizedDescription)"
            showingAlert = true
        }
    }
    
    private func resetPassword() {
        guard let file = selectedFile, file.isPasswordProtected else { return }
        showingResetDialog = true
    }
    
    private func confirmResetPassword() {
        guard let file = selectedFile, file.isPasswordProtected else { return }
        
        // 验证当前密码
        if let hash = file.passwordHash {
            if !FileLockerService.shared.verifyPassword(currentPassword, against: hash) {
                alertMessage = "当前密码验证失败"
                showingAlert = true
                return
            }
        }
        
        // 验证新密码
        if !validatePassword() { return }
        
        // 更新密码
        let newPasswordHash = FileLockerService.shared.hashPassword(password)
        file.passwordHash = newPasswordHash
        file.lastAccessTime = Date()
        
        // 记录操作日志
        let log = PasswordAccessLog(
            filePath: file.path,
            fileName: file.name,
            isSuccessful: true,
            accessType: "password_reset"
        )
        modelContext.insert(log)
        
        // 清空密码字段
        password = ""
        confirmPassword = ""
        currentPassword = ""
        
        alertMessage = "密码已成功重置"
        showingAlert = true
    }
    
    private func removePasswordProtection() {
        guard let file = selectedFile, file.isPasswordProtected else { return }
        
        // 弹出密码确认
        // 这里简化处理，实际应该弹出一个对话框确认密码
        file.isPasswordProtected = false
        file.passwordHash = nil
        file.lastAccessTime = Date()
        
        // 记录操作日志
        let log = PasswordAccessLog(
            filePath: file.path,
            fileName: file.name,
            isSuccessful: true,
            accessType: "password_removed"
        )
        modelContext.insert(log)
        
        alertMessage = "密码保护已移除"
        showingAlert = true
    }
    
    private func validatePassword() -> Bool {
        // 验证密码
        if password.isEmpty {
            alertMessage = "密码不能为空"
            showingAlert = true
            return false
        }
        
        if password != confirmPassword {
            alertMessage = "两次输入的密码不一致"
            showingAlert = true
            return false
        }
        
        if password.count < minPasswordLength {
            alertMessage = "密码长度必须至少\(minPasswordLength)个字符"
            showingAlert = true
            return false
        }
        
        // 验证是否包含特殊字符
        if requireSpecialChars {
            let specialCharRegex = ".*[^A-Za-z0-9].*"
            if !NSPredicate(format: "SELF MATCHES %@", specialCharRegex).evaluate(with: password) {
                alertMessage = "密码必须包含至少一个特殊字符"
                showingAlert = true
                return false
            }
        }
        
        // 验证是否包含数字
        if requireNumbers {
            let numberRegex = ".*[0-9].*"
            if !NSPredicate(format: "SELF MATCHES %@", numberRegex).evaluate(with: password) {
                alertMessage = "密码必须包含至少一个数字"
                showingAlert = true
                return false
            }
        }
        
        return true
    }
}

// 密码设置对话框
struct PasswordDialogView: View {
    @Binding var password: String
    @Binding var confirmPassword: String
    let onSubmit: () -> Void
    let minLength: Int
    let requireSpecialChars: Bool
    let requireNumbers: Bool
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text("设置密码保护")
                .font(.headline)
                .padding(.top, 20)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("请输入新密码")
                    .font(.system(size: 13))
                
                SecureField("密码", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                
                Text("请确认密码")
                    .font(.system(size: 13))
                
                SecureField("确认密码", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
            }
            
            // 密码规则提示
            VStack(alignment: .leading, spacing: 4) {
                Text("密码要求：")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text("• 至少\(minLength)个字符")
                    .font(.system(size: 11))
                    .foregroundColor(password.count >= minLength ? .green : .secondary)
                
                if requireSpecialChars {
                    Text("• 至少1个特殊字符")
                        .font(.system(size: 11))
                        .foregroundColor(
                            NSPredicate(format: "SELF MATCHES %@", ".*[^A-Za-z0-9].*").evaluate(with: password)
                            ? .green : .secondary
                        )
                }
                
                if requireNumbers {
                    Text("• 至少1个数字")
                        .font(.system(size: 11))
                        .foregroundColor(
                            NSPredicate(format: "SELF MATCHES %@", ".*[0-9].*").evaluate(with: password)
                            ? .green : .secondary
                        )
                }
            }
            .frame(width: 250, alignment: .leading)
            .padding(.top, 8)
            
            HStack(spacing: 12) {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("确定") {
                    onSubmit()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || confirmPassword.isEmpty || password != confirmPassword)
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .frame(width: 300)
    }
}

// 重置密码对话框
struct ResetPasswordView: View {
    @Binding var currentPassword: String
    @Binding var newPassword: String
    @Binding var confirmPassword: String
    let onSubmit: () -> Void
    let minLength: Int
    let requireSpecialChars: Bool
    let requireNumbers: Bool
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text("重置密码")
                .font(.headline)
                .padding(.top, 20)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("请输入当前密码")
                    .font(.system(size: 13))
                
                SecureField("当前密码", text: $currentPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                
                Text("请输入新密码")
                    .font(.system(size: 13))
                
                SecureField("新密码", text: $newPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                
                Text("请确认新密码")
                    .font(.system(size: 13))
                
                SecureField("确认新密码", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
            }
            
            // 密码规则提示 (与PasswordDialogView中相同)
            VStack(alignment: .leading, spacing: 4) {
                Text("密码要求：")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text("• 至少\(minLength)个字符")
                    .font(.system(size: 11))
                    .foregroundColor(newPassword.count >= minLength ? .green : .secondary)
                
                if requireSpecialChars {
                    Text("• 至少1个特殊字符")
                        .font(.system(size: 11))
                        .foregroundColor(
                            NSPredicate(format: "SELF MATCHES %@", ".*[^A-Za-z0-9].*").evaluate(with: newPassword)
                            ? .green : .secondary
                        )
                }
                
                if requireNumbers {
                    Text("• 至少1个数字")
                        .font(.system(size: 11))
                        .foregroundColor(
                            NSPredicate(format: "SELF MATCHES %@", ".*[0-9].*").evaluate(with: newPassword)
                            ? .green : .secondary
                        )
                }
            }
            .frame(width: 250, alignment: .leading)
            .padding(.top, 8)
            
            HStack(spacing: 12) {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("确定") {
                    onSubmit()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty || newPassword != confirmPassword)
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .frame(width: 300)
    }
}

// 访问记录视图
struct AccessLogsView: View {
    let filePath: String
    @Environment(\.dismiss) private var dismiss
    @Query private var allLogs: [PasswordAccessLog]
    
    var logs: [PasswordAccessLog] {
        allLogs.filter { $0.filePath == filePath }
            .sorted { $0.accessTime > $1.accessTime }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("文件访问记录")
                    .font(.headline)
                
                Spacer()
                
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding([.horizontal, .top], 16)
            
            if logs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    
                    Text("暂无访问记录")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(logs) {
                    TableColumn("时间") { log in
                        Text(formatDate(log.accessTime))
                            .font(.system(size: 12))
                    }
                    
                    TableColumn("操作类型") { log in
                        Text(formatAccessType(log.accessType))
                            .font(.system(size: 12))
                    }
                    
                    TableColumn("状态") { log in
                        Text(log.isSuccessful ? "成功" : "失败")
                            .foregroundColor(log.isSuccessful ? .green : .red)
                            .font(.system(size: 12))
                    }
                }
                .frame(minHeight: 250)
                .padding(.horizontal, 16)
            }
            
            Spacer()
        }
        .frame(width: 400, height: 350)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func formatAccessType(_ type: String) -> String {
        switch type {
        case "unlock": return "解锁"
        case "lock": return "锁定"
        case "view": return "查看"
        case "password_set": return "设置密码"
        case "password_reset": return "重置密码"
        case "password_removed": return "移除密码"
        default: return type
        }
    }
}

// 密码验证对话框
struct PasswordPromptView: View {
    @Binding var password: String
    let onSubmit: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text("密码验证")
                .font(.headline)
                .padding(.top, 20)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("请输入密码解锁文件")
                    .font(.system(size: 13))
                
                SecureField("密码", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
            }
            
            HStack(spacing: 12) {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("确定") {
                    onSubmit()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty)
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .frame(width: 300)
    }
}

// 密码设置管理视图
struct PasswordSettingsView: View {
    let file: LockedFile
    let modelContext: ModelContext
    let onPasswordRemoved: () -> Void
    @State private var showingConfirmRemove = false
    @State private var confirmPassword = ""
    @State private var alertMessage: String?
    @State private var showingAlert = false
    @State private var showingAccessLogs = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text("密码保护设置")
                .font(.headline)
                .padding(.top, 20)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("文件: \(file.name)")
                    .font(.system(size: 13, weight: .medium))
                
                Text("路径: \(file.path)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 300, alignment: .leading)
            .padding(.horizontal, 20)
            
            Divider()
                .padding(.vertical, 8)
            
            Button("查看访问记录") {
                showingAccessLogs = true
            }
            .buttonStyle(.bordered)
            
            Button("移除密码保护") {
                showingConfirmRemove = true
            }
            .buttonStyle(.bordered)
            .foregroundColor(.red)
            
            Button("关闭") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .frame(width: 350)
        .alert("操作提示", isPresented: $showingAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            if let message = alertMessage {
                Text(message)
            }
        }
        .sheet(isPresented: $showingConfirmRemove) {
            VStack(spacing: 16) {
                Text("确认移除密码保护")
                    .font(.headline)
                    .padding(.top, 20)
                
                Text("请输入当前密码以确认移除")
                    .font(.system(size: 13))
                
                SecureField("当前密码", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                
                HStack(spacing: 12) {
                    Button("取消") {
                        confirmPassword = ""
                        showingConfirmRemove = false
                    }
                    .buttonStyle(.bordered)
                    
                    Button("确定") {
                        removePasswordProtection()
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundColor(.red)
                    .disabled(confirmPassword.isEmpty)
                }
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .frame(width: 300)
        }
        .sheet(isPresented: $showingAccessLogs) {
            AccessLogsView(filePath: file.path)
        }
    }
    
    private func removePasswordProtection() {
        // 验证密码
        if let hash = file.passwordHash, FileLockerService.shared.verifyPassword(confirmPassword, against: hash) {
            // 密码正确，移除密码保护
            file.isPasswordProtected = false
            file.passwordHash = nil
            
            // 记录操作日志
            let log = PasswordAccessLog(
                filePath: file.path,
                fileName: file.name,
                isSuccessful: true,
                accessType: "password_removed"
            )
            modelContext.insert(log)
            
            // 关闭对话框
            showingConfirmRemove = false
            onPasswordRemoved()
            dismiss()
        } else {
            // 密码错误
            alertMessage = "密码不正确，无法移除密码保护"
            showingAlert = true
            confirmPassword = ""
            showingConfirmRemove = false
        }
    }
}
