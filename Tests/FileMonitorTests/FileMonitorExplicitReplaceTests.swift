import XCTest

@testable import FileMonitor
import FileMonitorShared

/// A file replaced in place — a new file renamed or cloned over it — is a change to that path,
/// even though FSEvents reports it with the rename or clone flags rather than `Modified`. This
/// is what an atomic write from any editor looks like, and what the iCloud daemon does when a
/// synced version lands.
final class FileMonitorExplicitReplaceTests: XCTestCase {

    let tmp = FileManager.default.temporaryDirectory
    let dir = String.random(length: 10)

    var directory: URL { tmp.appendingPathComponent(dir) }

    override func setUpWithError() throws {
        super.setUp()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        try FileManager.default.removeItem(at: directory)
    }

    final class Watcher: FileDidChangeDelegate {
        var events: [FileChangeEvent] = []
        let callback: () -> Void
        let file: URL

        init(on file: URL, completion: @escaping () -> Void) {
            self.file = file
            callback = completion
        }

        func fileDidChanged(event: FileChangeEvent) {
            events.append(event)
            if case .changed(let changed) = event, changed.lastPathComponent == file.lastPathComponent {
                callback()
            }
        }

        func events(for file: URL) -> [String] {
            events.compactMap { event in
                switch event {
                case .added(let url): return url.lastPathComponent == file.lastPathComponent ? "added" : nil
                case .deleted(let url): return url.lastPathComponent == file.lastPathComponent ? "deleted" : nil
                case .changed(let url): return url.lastPathComponent == file.lastPathComponent ? "changed" : nil
                }
            }
        }
    }

    private func watch(_ target: URL, during operation: () throws -> Void) throws -> Watcher {
        let expectation = expectation(description: "Wait for the replacement to be reported")
        expectation.assertForOverFulfill = false
        let watcher = Watcher(on: target) { expectation.fulfill() }

        let monitor = try FileMonitor(directory: directory, delegate: watcher)
        try monitor.start()

        try operation()
        wait(for: [expectation], timeout: 10)

        // Give any trailing events for the same operation time to arrive.
        Thread.sleep(forTimeInterval: 1)
        monitor.stop()
        return watcher
    }

    private func assertOnlyChanged(_ watcher: Watcher, for target: URL) {
        let kinds = watcher.events(for: target)
        XCTAssertFalse(kinds.isEmpty, "The replacement was not reported at all: \(watcher.events)")
        XCTAssertEqual(Set(kinds), ["changed"], "Expected only changes for the target, got \(watcher.events)")
    }

    func testRenameOverExistingFileIsAChange() throws {
        let target = directory.appendingPathComponent("note.md")
        let temp = directory.appendingPathComponent("note.md.tmp")
        try "before".write(to: target, atomically: false, encoding: .utf8)

        let watcher = try watch(target) {
            try "after".write(to: temp, atomically: false, encoding: .utf8)
            // `rename(2)` over an existing file, as `mv` does.
            XCTAssertEqual(rename(temp.path, target.path), 0)
        }

        assertOnlyChanged(watcher, for: target)
        XCTAssertFalse(watcher.events(for: temp).contains("changed"),
                       "The temp file was reported as changed: \(watcher.events)")
    }

    func testCloneOverExistingFileIsAChange() throws {
        let source = directory.appendingPathComponent("source.md")
        let target = directory.appendingPathComponent("note.md")
        try "before".write(to: target, atomically: false, encoding: .utf8)
        try "after".write(to: source, atomically: false, encoding: .utf8)

        let watcher = try watch(target) {
            // What `cp -c` does: remove the target, then `clonefile` the source over it.
            try FileManager.default.removeItem(at: target)
            XCTAssertEqual(clonefile(source.path, target.path, 0), 0)
        }

        XCTAssertTrue(watcher.events(for: target).contains("changed"),
                      "The clone over the target was not reported: \(watcher.events)")
        XCTAssertFalse(watcher.events(for: source).contains("changed"),
                       "The clone's source was reported as changed: \(watcher.events)")
    }

    func testAtomicWriteIsAChange() throws {
        let target = directory.appendingPathComponent("note.md")
        try "before".write(to: target, atomically: false, encoding: .utf8)

        let watcher = try watch(target) {
            try "after".write(to: target, atomically: true, encoding: .utf8)
        }

        assertOnlyChanged(watcher, for: target)
    }

    func testRenameIsADeletionAndAnAddition() throws {
        let from = directory.appendingPathComponent("from.md")
        let to = directory.appendingPathComponent("to.md")
        try "hello".write(to: from, atomically: false, encoding: .utf8)

        let expectation = expectation(description: "Wait for the new name to be reported")
        expectation.assertForOverFulfill = false
        let watcher = Watcher(on: to) { }
        let monitor = try FileMonitor(directory: directory, delegate: watcher)
        try monitor.start()

        try FileManager.default.moveItem(at: from, to: to)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { expectation.fulfill() }
        wait(for: [expectation], timeout: 10)
        monitor.stop()

        XCTAssertEqual(watcher.events(for: from), ["deleted"], "\(watcher.events)")
        XCTAssertEqual(watcher.events(for: to), ["added"], "\(watcher.events)")
    }
}
