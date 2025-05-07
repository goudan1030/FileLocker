import Foundation
import AppKit

// 重命名类以避免与FileLockerMain中的定义冲突
public class FileLockerAccessHelper {
    public static let shared = FileLockerAccessHelper()
    private let hasShownAccessPromptKey = "hasShownBookmarkAccessPrompt"
    
    private init() {}
    
    public var hasShownAccessPrompt: Bool {
        get {
            return UserDefaults.standard.bool(forKey: hasShownAccessPromptKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hasShownAccessPromptKey)
        }
    }
    
    // 检查是否有足够的文件访问权限
    public func hasFileAccess() -> Bool {
        // 在沙盒中，我们只能通过用户交互来获取文件权限
        // 此函数主要用于UI显示，真正的权限检查在文件操作时进行
        return true
    }
    
    // 请求文件访问权限（在沙盒中通过打开文件选择器）
    public func requestFileAccess() {
        print("请求文件访问权限...")
        
        // 显示文件访问权限提示
        let alert = NSAlert()
        alert.messageText = "需要选择文件以保护它们"
        alert.informativeText = "由于macOS的安全限制，FileLocker只能操作您明确选择的文件。\n\n使用\"添加文件\"按钮选择您要保护的文件。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "了解")
        alert.runModal()
        
        hasShownAccessPrompt = true
    }
    
    // 显示沙盒限制提示
    public func showSandboxLimitations() {
        let alert = NSAlert()
        alert.messageText = "文件访问权限说明"
        alert.informativeText = """
        作为Mac App Store应用，FileLocker受系统沙盒限制，只能访问：

        1. 您明确授权的文件和文件夹
        2. 下载文件夹中的文件（需授权）
        3. 应用自己创建的文件

        要锁定文件，请使用"添加文件"或"添加文件夹"按钮，或将文件拖放到应用中。
        
        这些限制是Apple强制执行的安全措施，以保护您的系统安全。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "了解")
        alert.addButton(withTitle: "复制说明")
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            // 复制说明到剪贴板
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(alert.informativeText, forType: .string)
        }
    }
    
    // 打开指定的系统设置面板
    public func openSystemSettings(panel: String) {
        if let url = URL(string: "x-apple.systempreferences:\(panel)") {
                NSWorkspace.shared.open(url)
            }
    }
} 