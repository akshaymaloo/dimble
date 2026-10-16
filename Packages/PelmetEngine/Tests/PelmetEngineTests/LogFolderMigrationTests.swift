// LogFolderMigrationTests.swift
// The log folder move to Dimble (PelmetLog.migrateOldFolder): the newest real
// old folder (Pliss, else Pelmet) moves and leaves a symlink; anything else is
// left exactly as found.

import Foundation
import Testing
@testable import PelmetEngine

struct LogFolderMigrationTests {
    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("log-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func kind(of url: URL) -> FileAttributeType? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
    }

    @Test func movesARealOldFolderAndLeavesASymlink() throws {
        let logs = try scratch()
        defer { try? FileManager.default.removeItem(at: logs) }
        let old = logs.appendingPathComponent("Pelmet")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("history".utf8).write(to: old.appendingPathComponent("pelmet.log"))

        let note = PelmetLog.migrateOldFolder(in: logs)

        #expect(note?.contains("symlink left") == true)
        let new = logs.appendingPathComponent("Dimble")
        #expect(kind(of: new) == .typeDirectory)
        #expect(kind(of: old) == .typeSymbolicLink)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: old.path) == "Dimble")
        // The history moved with the folder and reads through both paths.
        #expect(try Data(contentsOf: new.appendingPathComponent("pelmet.log")) == Data("history".utf8))
        #expect(try Data(contentsOf: old.appendingPathComponent("pelmet.log")) == Data("history".utf8))
    }

    /// A 0.3.2 beta install: a real Pliss folder, Pelmet a symlink to it.
    @Test func movesABetaPlissFolderAndOldLinksStillResolve() throws {
        let logs = try scratch()
        defer { try? FileManager.default.removeItem(at: logs) }
        let pliss = logs.appendingPathComponent("Pliss")
        let pelmet = logs.appendingPathComponent("Pelmet")
        try FileManager.default.createDirectory(at: pliss, withIntermediateDirectories: true)
        try Data("history".utf8).write(to: pliss.appendingPathComponent("pliss.log"))
        try FileManager.default.createSymbolicLink(atPath: pelmet.path, withDestinationPath: "Pliss")

        let note = PelmetLog.migrateOldFolder(in: logs)

        #expect(note?.contains("symlink left") == true)
        let new = logs.appendingPathComponent("Dimble")
        #expect(kind(of: new) == .typeDirectory)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: pliss.path) == "Dimble")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: pelmet.path) == "Pliss")
        #expect(try Data(contentsOf: pelmet.appendingPathComponent("pliss.log")) == Data("history".utf8))
    }

    @Test func leavesEverythingWhenDimbleAlreadyExists() throws {
        let logs = try scratch()
        defer { try? FileManager.default.removeItem(at: logs) }
        let old = logs.appendingPathComponent("Pelmet")
        let new = logs.appendingPathComponent("Dimble")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)

        #expect(PelmetLog.migrateOldFolder(in: logs) == nil)
        #expect(kind(of: old) == .typeDirectory)
        #expect(kind(of: new) == .typeDirectory)
    }

    @Test func doesNothingWithoutAnOldFolder() throws {
        let logs = try scratch()
        defer { try? FileManager.default.removeItem(at: logs) }

        #expect(PelmetLog.migrateOldFolder(in: logs) == nil)
        #expect(kind(of: logs.appendingPathComponent("Dimble")) == nil)
        #expect(kind(of: logs.appendingPathComponent("Pelmet")) == nil)
    }

    @Test func doesNotTouchAnOldPathThatIsAlreadyASymlink() throws {
        let logs = try scratch()
        defer { try? FileManager.default.removeItem(at: logs) }
        let elsewhere = logs.appendingPathComponent("Elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let old = logs.appendingPathComponent("Pelmet")
        try FileManager.default.createSymbolicLink(atPath: old.path, withDestinationPath: "Elsewhere")

        #expect(PelmetLog.migrateOldFolder(in: logs) == nil)
        #expect(kind(of: old) == .typeSymbolicLink)
        #expect(kind(of: logs.appendingPathComponent("Dimble")) == nil)
    }
}
