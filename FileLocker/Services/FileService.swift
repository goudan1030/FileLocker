import Foundation

class FileService {
    static let shared = FileService()
    private init() {}
    
    // 锁定文件
    func lockFile(at path: String, withBookmark bookmark: Data? = nil) throws {
        try FileServiceHelper.lockFile(at: path, withBookmark: bookmark)
    }
    
    // 解锁文件
    func unlockFile(at path: String, withBookmark bookmark: Data? = nil) throws {
        try FileServiceHelper.unlockFile(at: path, withBookmark: bookmark)
    }
    
    // 检查文件是否被锁定
    func isFileLocked(at path: String, withBookmark bookmark: Data? = nil) -> Bool {
        return FileServiceHelper.isFileLocked(at: path, withBookmark: bookmark)
    }
}

// 具体实现细节分离到Helper，便于测试和维护
fileprivate class FileServiceHelper {
    static func lockFile(at path: String, withBookmark bookmark: Data? = nil) throws {
        var url: URL
        var shouldStopAccessing = false
        if let bookmarkData = bookmark {
            do {
                url = try BookmarkManager.shared.resolveSecureBookmark(bookmarkData)
                if url.startAccessingSecurityScopedResource() {
                    shouldStopAccessing = true
                } else {
                    throw NSError(domain: "FileService", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法访问安全作用域资源"])
                }
            } catch {
                url = URL(fileURLWithPath: path)
            }
        } else {
            url = URL(fileURLWithPath: path)
        }
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw NSError(domain: "FileService", code: 2, userInfo: [NSLocalizedDescriptionKey: "文件不存在"])
        }
        var resourceValues = URLResourceValues()
        resourceValues.isUserImmutable = true
        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)
    }
    static func unlockFile(at path: String, withBookmark bookmark: Data? = nil) throws {
        var url: URL
        var shouldStopAccessing = false
        if let bookmarkData = bookmark {
            do {
                url = try BookmarkManager.shared.resolveSecureBookmark(bookmarkData)
                if url.startAccessingSecurityScopedResource() {
                    shouldStopAccessing = true
                } else {
                    throw NSError(domain: "FileService", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法访问安全作用域资源"])
                }
            } catch {
                url = URL(fileURLWithPath: path)
            }
        } else {
            url = URL(fileURLWithPath: path)
        }
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw NSError(domain: "FileService", code: 2, userInfo: [NSLocalizedDescriptionKey: "文件不存在"])
        }
        var resourceValues = URLResourceValues()
        resourceValues.isUserImmutable = false
        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)
    }
    static func isFileLocked(at path: String, withBookmark bookmark: Data? = nil) -> Bool {
        var url: URL
        var shouldStopAccessing = false
        if let bookmarkData = bookmark {
            do {
                url = try BookmarkManager.shared.resolveSecureBookmark(bookmarkData)
                if url.startAccessingSecurityScopedResource() {
                    shouldStopAccessing = true
                }
            } catch {
                url = URL(fileURLWithPath: path)
            }
        } else {
            url = URL(fileURLWithPath: path)
        }
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isUserImmutableKey])
            return resourceValues.isUserImmutable ?? false
        } catch {
            return false
        }
    }
} 