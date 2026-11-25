import Foundation

public enum MediaKind: Sendable { case snap, vlog }

public enum MediaLocation {
    public static func folder(for kind: MediaKind, home: URL) -> URL {
        switch kind {
        case .snap: home.appendingPathComponent("Pictures/Compact")
        case .vlog: home.appendingPathComponent("Movies/Compact")
        }
    }

    public static func fileName(for kind: MediaKind, date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stamp = f.string(from: date)
        switch kind {
        case .snap: return "Compact Snap \(stamp).png"
        case .vlog: return "Compact Vlog \(stamp).mov"
        }
    }

    public static func uniqueURL(for kind: MediaKind, in folder: URL, date: Date,
                                 timeZone: TimeZone = .current,
                                 fileManager: FileManager = .default) throws -> URL {
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = fileName(for: kind, date: date, timeZone: timeZone) as NSString
        let base = name.deletingPathExtension, ext = name.pathExtension
        var url = folder.appendingPathComponent(name as String)
        var n = 2
        while fileManager.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        return url
    }
}
