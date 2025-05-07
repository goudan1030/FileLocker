import Foundation
import AppKit
import SwiftUI

// FileLockError 现在从 Utils/Errors.swift 导入
// public enum FileLockError: Error, LocalizedError { ... } // 这部分整个删除

public class FileLockerService {
    // 单例实例
    public static let shared = FileLockerService()
    
    // 私有初始化方法（单例模式）
    private init() {}
    
    // 锁定文件
    public func lockFile(at path: String, withBookmark bookmark: Data) throws {
        do {
            // 验证路径
            var url = URL(fileURLWithPath: path)
            
            // 尝试恢复书签访问权限
            var isStale = false
            let bookmarkURL = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale)
            
            // 确保书签匹配当前路径
            guard bookmarkURL.path == path else {
                throw FileLockError.bookmarkRestorationFailed
            }
            
            // 开始访问安全作用域资源
            guard bookmarkURL.startAccessingSecurityScopedResource() else {
                throw FileLockError.accessDenied
            }
            
            defer {
                // 确保在完成时停止访问
                bookmarkURL.stopAccessingSecurityScopedResource()
            }
            
            // 检查文件是否存在
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: path) else {
                throw FileLockError.fileNotFound
            }
            
            // 设置文件不可变属性
            var resourceValues = URLResourceValues()
            resourceValues.isUserImmutable = true
            
            try url.setResourceValues(resourceValues)
            
            print("文件已锁定: \(path)")
        } catch let error as FileLockError {
            throw error
        } catch {
            // 处理其他可能的错误
            print("锁定文件时出错: \(error.localizedDescription)")
            throw FileLockError.unknown(error.localizedDescription)
        }
    }
    
    // 解锁文件
    public func unlockFile(at path: String, withBookmark bookmark: Data) throws {
        do {
            // 验证路径
            var url = URL(fileURLWithPath: path)
            
            // 尝试恢复书签访问权限
            var isStale = false
            let bookmarkURL = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale)
            
            // 确保书签匹配当前路径
            guard bookmarkURL.path == path else {
                throw FileLockError.bookmarkRestorationFailed
            }
            
            // 开始访问安全作用域资源
            guard bookmarkURL.startAccessingSecurityScopedResource() else {
                throw FileLockError.accessDenied
            }
            
            defer {
                // 确保在完成时停止访问
                bookmarkURL.stopAccessingSecurityScopedResource()
            }
            
            // 检查文件是否存在
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: path) else {
                throw FileLockError.fileNotFound
            }
            
            // 移除文件不可变属性
            var resourceValues = URLResourceValues()
            resourceValues.isUserImmutable = false
            
            try url.setResourceValues(resourceValues)
            
            print("文件已解锁: \(path)")
        } catch let error as FileLockError {
            throw error
        } catch {
            // 处理其他可能的错误
            print("解锁文件时出错: \(error.localizedDescription)")
            throw FileLockError.unknown(error.localizedDescription)
        }
    }
    
    // 检查文件是否已锁定
    public func isFileLocked(at path: String) -> Bool {
        do {
            let url = URL(fileURLWithPath: path)
            let resourceValues = try url.resourceValues(forKeys: [.isUserImmutableKey])
            return resourceValues.isUserImmutable ?? false
        } catch {
            print("检查文件锁定状态时出错: \(error.localizedDescription)")
            return false
        }
    }
    
    // 创建安全书签
    public func createSecureBookmark(for url: URL) throws -> Data {
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            return bookmarkData
        } catch {
            print("创建书签时出错: \(error.localizedDescription)")
            throw FileLockError.bookmarkCreationFailed
        }
    }
} 