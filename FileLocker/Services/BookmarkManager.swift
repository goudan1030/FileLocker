import Foundation

// 因为模块导入问题，临时注释掉导入语句
// 在完成项目结构调整后，应该使用 import FileLocker
// import FileLocker

// 不再定义或导入 FileLockError，改用自定义 Error

class BookmarkManager {
    static let shared = BookmarkManager()
    private init() {}
    
    // 创建安全书签
    func createSecureBookmark(for url: URL) throws -> Data {
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            return bookmarkData
        } catch {
            print("创建书签失败: \(error.localizedDescription)")
            // 使用 NSError 作为错误类型
            throw NSError(domain: "BookmarkManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "创建书签失败: \(error.localizedDescription)"])
        }
    }
    
    // 恢复安全书签
    func resolveSecureBookmark(_ bookmarkData: Data) throws -> URL {
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                // 书签过期，尝试更新
                _ = try? createSecureBookmark(for: url)
                print("书签已过时，已尝试更新")
            }
            return url
        } catch {
            print("解析书签失败: \(error.localizedDescription)")
            // 使用 NSError 作为错误类型
            throw NSError(domain: "BookmarkManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "解析书签失败: \(error.localizedDescription)"])
        }
    }
} 