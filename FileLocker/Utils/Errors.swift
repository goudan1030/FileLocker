import Foundation

// 文件锁定错误
// 为避免命名冲突，使用更明确的命名
public enum FileLockError: Error, LocalizedError {
    case fileNotFound
    case accessDenied
    case unknown(String)
    case bookmarkCreationFailed
    case bookmarkRestorationFailed
    
    public var errorDescription: String? {
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

// 书签错误
public enum BookmarkError: Error, LocalizedError {
    case invalidURL
    case creationFailed
    case restorationFailed
    case staleBookmark
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的文件URL"
        case .creationFailed:
            return "创建书签数据失败"
        case .restorationFailed:
            return "恢复书签访问失败"
        case .staleBookmark:
            return "书签已过期，需要重新创建"
        }
    }
}

// 权限错误
public enum PermissionError: Error, LocalizedError {
    case sandboxRestriction
    case fullDiskAccessDenied
    case unexpectedError(String)
    
    public var errorDescription: String? {
        switch self {
        case .sandboxRestriction:
            return "由于沙盒限制，无法访问此文件，请使用文件选择器或拖放方式添加文件"
        case .fullDiskAccessDenied:
            return "需要完全磁盘访问权限才能执行此操作"
        case .unexpectedError(let message):
            return "权限错误: \(message)"
        }
    }
}

// 应用其他可能的错误类型
public enum ApplicationError: Error, LocalizedError {
    case configurationError(String)
    case permissionDenied
    case operationCancelled
    
    public var errorDescription: String? {
        switch self {
        case .configurationError(let message):
            return "配置错误: \(message)"
        case .permissionDenied:
            return "权限被拒绝，无法执行操作"
        case .operationCancelled:
            return "操作已取消"
        }
    }
} 