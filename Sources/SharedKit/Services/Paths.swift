import Foundation

public enum AppPaths {
    public static let appName = "MailSorter"

    public static var appSupportDir: URL {
        let base = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent(appName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public static var databaseURL: URL {
        appSupportDir.appendingPathComponent("mailsorter.sqlite")
    }

    public static var classifierModelURL: URL {
        appSupportDir.appendingPathComponent("classifier.mlmodel")
    }

    public static var compiledClassifierURL: URL {
        appSupportDir.appendingPathComponent("classifier.mlmodelc")
    }

    public static var logsDir: URL {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/\(appName)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
