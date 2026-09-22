import Foundation

private extension LogLevel {
    var priority: Int {
        switch self {
        case .off:
            return 0
        case .basic:
            return 1
        case .debug:
            return 2
        }
    }
}

func isAppLogEnabled(_ level: LogLevel) -> Bool {
    #if !DEBUG
    if level == .debug { return false }
    #endif
    let configuredLevel = SettingsStore.shared.getSettings().logLevel
    return configuredLevel.priority >= level.priority
}

func appLog(_ message: String, level: LogLevel = .basic) {
    guard isAppLogEnabled(level) else { return }
    AppLogger.shared.enqueue(message)
}

private final class AppLogger {
    static let shared = AppLogger()

    private let queue = DispatchQueue(label: "com.autoswitch.logger", qos: .utility)
    private let logFile: URL
    private let backupLogFile: URL
    private let flushThresholdBytes = 16_384
    private let maxActiveLogBytes = 5 * 1024 * 1024
    private let maxBackupLogBytes = 5 * 1024 * 1024
    private let maxLogAge: TimeInterval = 7 * 24 * 60 * 60
    private var bufferedData = Data()
    private let formatter: DateFormatter
    private let flushTimer: DispatchSourceTimer

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("AutoSwitch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.logFile = dir.appendingPathComponent("autoswitch_log.txt")
        self.backupLogFile = dir.appendingPathComponent("autoswitch_log.old.txt")
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        self.formatter = formatter
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        self.flushTimer = timer
        self.flushTimer.setEventHandler { [weak self] in
            self?.flushLocked()
        }
        self.flushTimer.resume()
        queue.async { [logFile, backupLogFile, maxActiveLogBytes, maxBackupLogBytes, maxLogAge] in
            Self.rotateLogsIfNeeded(
                logFile: logFile,
                backupLogFile: backupLogFile,
                maxActiveLogBytes: maxActiveLogBytes,
                maxBackupLogBytes: maxBackupLogBytes,
                maxLogAge: maxLogAge,
                forceAgeCheck: true
            )
        }
    }

    func enqueue(_ message: String) {
        queue.async {
            let timestamp = self.formatter.string(from: Date())
            guard let data = "[\(timestamp)] \(message)\n".data(using: .utf8) else { return }
            self.bufferedData.append(data)
            if self.bufferedData.count >= self.flushThresholdBytes {
                self.flushLocked()
            }
        }
    }

    private func flushLocked() {
        Self.rotateLogsIfNeeded(
            logFile: logFile,
            backupLogFile: backupLogFile,
            maxActiveLogBytes: maxActiveLogBytes,
            maxBackupLogBytes: maxBackupLogBytes,
            maxLogAge: maxLogAge,
            forceAgeCheck: false
        )
        guard !bufferedData.isEmpty else { return }
        let dataToWrite = bufferedData
        bufferedData.removeAll(keepingCapacity: true)
        do {
            if FileManager.default.fileExists(atPath: logFile.path) {
                let fileHandle = try FileHandle(forWritingTo: logFile)
                try fileHandle.seekToEnd()
                try fileHandle.write(contentsOf: dataToWrite)
                try fileHandle.close()
            } else {
                try dataToWrite.write(to: logFile)
            }
        } catch {
        }
    }

    private static func rotateLogsIfNeeded(
        logFile: URL,
        backupLogFile: URL,
        maxActiveLogBytes: Int,
        maxBackupLogBytes: Int,
        maxLogAge: TimeInterval,
        forceAgeCheck: Bool
    ) {
        trimFileIfNeeded(at: backupLogFile, maxBytes: maxBackupLogBytes)
        if shouldRotateActiveLog(
            at: logFile,
            maxActiveLogBytes: maxActiveLogBytes,
            maxLogAge: maxLogAge,
            forceAgeCheck: forceAgeCheck
        ) {
            try? FileManager.default.removeItem(at: backupLogFile)
            if FileManager.default.fileExists(atPath: logFile.path) {
                try? FileManager.default.moveItem(at: logFile, to: backupLogFile)
            }
        }
    }

    private static func shouldRotateActiveLog(
        at url: URL,
        maxActiveLogBytes: Int,
        maxLogAge: TimeInterval,
        forceAgeCheck: Bool
    ) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return false
        }
        if let size = attributes[.size] as? NSNumber, size.intValue > maxActiveLogBytes {
            return true
        }
        if forceAgeCheck,
           let modifiedAt = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modifiedAt) > maxLogAge {
            return true
        }
        return false
    }

    private static func trimFileIfNeeded(at url: URL, maxBytes: Int) {
        guard FileManager.default.fileExists(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > maxBytes else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }
}
