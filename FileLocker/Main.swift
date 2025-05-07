//
//  Main.swift
//  FileLocker
//
//  Created by zwd on 2025/5/6.
//

import SwiftUI
import SwiftData

// 这是应用的主入口点
@main
struct FileLockerAppMain {
    static func main() {
        // 在应用启动时检查设置
        checkSettingsOnLaunch()
        
        // 启动应用
        FileLockerApp.main()
    }
    
    // 检查应用设置，确保首次运行时显示正确的引导信息
    static func checkSettingsOnLaunch() {
        // 仅在首次运行时显示权限提示
        if !UserDefaults.standard.bool(forKey: "hasShownInitialGuide") {
            UserDefaults.standard.set(true, forKey: "hasShownInitialGuide")
            
            // 延迟显示沙盒限制说明
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                FileLockerAccessHelper.shared.showSandboxLimitations()
            }
        }
    }
}

// Application Controller
class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, willPresentError error: Error) -> Error {
        print("将显示错误: \(error.localizedDescription)")
        return error
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("应用程序启动完成")
        
        // 显示文件访问权限限制说明
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // 在应用启动后显示权限信息
            FileLockerAccessHelper.shared.showSandboxLimitations()
        }
    }
} 