import SwiftUI
import Foundation
import AppKit

// 重命名结构体以避免与FileLockerMain中的定义冲突
struct SettingsFullDiskAccessView: View {
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部图标区域
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue.opacity(0.8), .teal], 
                                        startPoint: .topLeading, 
                                        endPoint: .bottomTrailing))
                    .frame(width: 100, height: 100)
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 5)
                
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 50))
                    .foregroundColor(.white)
            }
            .padding(.top, 40)
            .padding(.bottom, 20)
            
            // 标题区域
            Text("完全磁盘访问权限")
                .font(.system(size: 28, weight: .bold))
                .padding(.bottom, 10)
            
            // 说明文本
            Text("FileLocker需要完全磁盘访问权限才能锁定和保护您的重要文件。")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
            
            // 按钮区域
            HStack(spacing: 20) {
                Button("稍后再说") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.gray.opacity(0.3))
                
                Button("前往系统设置") {
                    if let url = URL(string: "x-apple.systempreferences:Security") {
                        NSWorkspace.shared.open(url)
                    }
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.blue)
            }
            .padding(.bottom, 40)
        }
        .frame(width: 550)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
    }
} 