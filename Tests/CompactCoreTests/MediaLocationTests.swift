import Testing
import Foundation
@testable import CompactCore

struct MediaLocationTests {
    let utc = TimeZone(identifier: "UTC")!
    var date: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 25; c.hour = 14; c.minute = 3; c.second = 22
        c.timeZone = utc
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return cal.date(from: c)!
    }

    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("compact-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test func folders() {
        let h = URL(fileURLWithPath: "/Users/x")
        #expect(MediaLocation.folder(for: .snap, home: h) == h.appendingPathComponent("Pictures/Compact"))
        #expect(MediaLocation.folder(for: .vlog, home: h) == h.appendingPathComponent("Movies/Compact"))
    }

    @Test func fileNames() {
        #expect(MediaLocation.fileName(for: .snap, date: date, timeZone: utc) == "Compact Snap 2026-11-25 at 14.03.22.png")
        #expect(MediaLocation.fileName(for: .vlog, date: date, timeZone: utc) == "Compact Vlog 2026-11-25 at 14.03.22.mov")
    }

    @Test func uniqueURLCreatesFolder() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Pictures/Compact")
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        let url = try MediaLocation.uniqueURL(for: .snap, in: folder, date: date, timeZone: utc)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(url.lastPathComponent == MediaLocation.fileName(for: .snap, date: date, timeZone: utc))
    }

    @Test func uniqueURLAddsSuffix() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try MediaLocation.uniqueURL(for: .snap, in: root, date: date, timeZone: utc)
        try Data().write(to: first)
        let second = try MediaLocation.uniqueURL(for: .snap, in: root, date: date, timeZone: utc)
        #expect(second.lastPathComponent == "Compact Snap 2026-11-25 at 14.03.22 (2).png")
        try Data().write(to: second)
        let third = try MediaLocation.uniqueURL(for: .snap, in: root, date: date, timeZone: utc)
        #expect(third.lastPathComponent == "Compact Snap 2026-11-25 at 14.03.22 (3).png")
    }

    @Test func uniqueURLThrowsWhenUnwritable() throws {
        let root = try tempDir()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        let folder = root.appendingPathComponent("Pictures/Compact")
        #expect(throws: (any Error).self) {
            try MediaLocation.uniqueURL(for: .snap, in: folder, date: date, timeZone: utc)
        }
    }
}
