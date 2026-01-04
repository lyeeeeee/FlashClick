import Foundation

class FileLogger {
    static let shared = FileLogger()

    private let logFileURL: URL

    private init() {
        // 1. 构造路径
        let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!
        let logsDir = libraryDir.appendingPathComponent("Logs")

        // 尝试创建 Logs 目录 (如果不存在)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        logFileURL = logsDir.appendingPathComponent("FlashClick.log")

        // 2. 打印路径，方便你去找
        print("📝 日志文件路径: \(logFileURL.path)")

        // 3. 尝试创建空文件 (如果不存在)
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            let created = FileManager.default.createFile(
                atPath: logFileURL.path, contents: nil, attributes: nil)
            if !created {
                print("❌ 严重错误: 无法创建日志文件，请检查权限！")
            }
        }
    }

    func log(_ message: String) {
        let timestamp = Date().formattedString
        let logMessage = "[\(timestamp)] \(message)\n"

        // 1. 控制台打印
        print(logMessage, terminator: "")

        // 2. 文件写入
        guard let data = logMessage.data(using: .utf8) else { return }

        do {
            // 尝试打开文件句柄
            let fileHandle = try FileHandle(forWritingTo: logFileURL)

            // 移动到末尾
            if #available(macOS 10.15.4, *) {
                try fileHandle.seekToEnd()
            } else {
                fileHandle.seekToEndOfFile()
            }

            // 写入并关闭
            fileHandle.write(data)

            // 【关键】强制刷新缓冲区并关闭
            if #available(macOS 10.15, *) {
                try fileHandle.synchronize()
            }
            fileHandle.closeFile()

        } catch {
            // 如果打开失败（比如文件被删了），尝试重新追加写入
            try? data.append(fileURL: logFileURL)
            print("⚠️ 写入文件触发备用方案 (Error: \(error.localizedDescription))")
        }
    }
}

// 简单的追加扩展
extension Data {
    func append(fileURL: URL) throws {
        if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
            defer { fileHandle.closeFile() }
            if #available(macOS 10.15.4, *) {
                try fileHandle.seekToEnd()
            } else {
                fileHandle.seekToEndOfFile()
            }
            fileHandle.write(self)
        } else {
            try write(to: fileURL, options: .atomic)
        }
    }
}

extension Date {
    var formattedString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: self)
    }
}
