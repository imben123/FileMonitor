import XCTest

@testable import FileMonitor
import FileMonitorShared

/// A Finder Duplicate or copy/paste on APFS is a clone, which FSEvents reports differently from
/// a plain create: the new file first appears with only the `Cloned` flag, and the source file
/// gets an event too.
final class FileMonitorExplicitCloneTests: XCTestCase {

    let tmp = FileManager.default.temporaryDirectory
    let dir = String.random(length: 10)

    override func setUpWithError() throws {
        super.setUp()
        let directory = tmp.appendingPathComponent(dir)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        try FileManager.default.removeItem(at: tmp.appendingPathComponent(dir))
    }

    final class CloneWatcher: FileDidChangeDelegate {
        var events: [FileChangeEvent] = []
        let callback: () -> Void
        let file: URL

        init(on file: URL, completion: @escaping () -> Void) {
            self.file = file
            callback = completion
        }

        func fileDidChanged(event: FileChangeEvent) {
            events.append(event)
            if case .added(let added) = event, added.lastPathComponent == file.lastPathComponent {
                callback()
            }
        }
    }

    func testCloneIsReportedAsAdded() throws {
        let directory = tmp.appendingPathComponent(dir)
        let source = directory.appendingPathComponent("source.txt")
        let copy = directory.appendingPathComponent("source copy.txt")
        try "hello".write(to: source, atomically: false, encoding: .utf8)

        let expectation = expectation(description: "Wait for the clone to be reported")
        expectation.assertForOverFulfill = false
        let watcher = CloneWatcher(on: copy) { expectation.fulfill() }

        let monitor = try FileMonitor(directory: directory, delegate: watcher)
        try monitor.start()

        // `copyItem` clones on APFS, as Finder does.
        try FileManager.default.copyItem(at: source, to: copy)
        wait(for: [expectation], timeout: 10)

        // Give any trailing events for the same operation time to arrive.
        Thread.sleep(forTimeInterval: 1)

        let added = watcher.events.filter { if case .added = $0 { return true } else { return false } }
        XCTAssertEqual(added.count, 1, "Expected exactly one addition, got \(watcher.events)")
        XCTAssertFalse(watcher.events.contains { event in
            if case .changed(let url) = event { return url.lastPathComponent == copy.lastPathComponent }
            return false
        }, "The clone was reported as a change: \(watcher.events)")
        XCTAssertFalse(watcher.events.contains { event in
            if case .added(let url) = event { return url.lastPathComponent == source.lastPathComponent }
            return false
        }, "The source was reported as added: \(watcher.events)")
    }
}
