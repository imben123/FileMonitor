//
// aus der Technik, on 15.05.23.
// https://www.ausdertechnik.de
//
// Updated by Ben Davis 16.01.26.
//

import Foundation
import FileMonitorShared

#if os(macOS)
/// Turns FSEvents into added / deleted / changed on the strength of the filesystem rather than
/// of the event flags.
///
/// The flags cannot be trusted to say what happened: FSEvents accumulates them per path, so a
/// plain append to a file that was once renamed still arrives as `[Renamed Modified …]`, the
/// source of a clone carries whatever its last write left behind, and one operation is often
/// several events — an atomic write is the temp file, then the target, then the target again.
/// What is reliable is what the path looked like before the event and what it looks like
/// after it. An event is an invitation to look, and only that.
public final class MacosWatcher: WatcherProtocol {
  public var delegate: WatcherDelegate?
  let fileWatcher: FileWatcher

  /// What was at each path the last time we looked. Updated one path at a time, by the event
  /// for that path, and never wholesale from a listing: the events for one operation arrive
  /// one after another, each with the directory already in its final state, and the second
  /// event of a rename has to still see its own path as new.
  private var lastFiles: [String: Fingerprint] = [:]

  required public init(directory: URL) throws {
    fileWatcher = FileWatcher([directory.path])
    fileWatcher.queue = DispatchQueue(label: "FileMonitor.MacosWatcher")
    lastFiles = try Self.fingerprints(in: directory)

    fileWatcher.callback = { [self] event throws in
      let url = URL(fileURLWithPath: event.path)
      guard !url.isDSStore else { return }
      guard event.path != fileWatcher.filePaths.first else { return }

      let currentFiles = try Self.fingerprints(in: directory)
      let before = lastFiles[event.path]
      let after = currentFiles[event.path]

      switch (before, after) {
      case (nil, let after?):
        // A directory arriving brings its contents, which FSEvents does not report one by one.
        lastFiles.merge(currentFiles.filter { $0.key.isInside(event.path) }) { _, new in new }
        lastFiles[event.path] = after
        self.delegate?.fileDidChanged(event: FileChangeEvent.added(file: url))

      case (.some, nil):
        lastFiles = lastFiles.filter { !$0.key.isInside(event.path) }
        lastFiles[event.path] = nil
        self.delegate?.fileDidChanged(event: FileChangeEvent.deleted(file: url))

      case (let before?, let after?):
        // Still there. A write in place, or a new file renamed or cloned over it, has left a
        // different file; the source of a clone, or a trailing event for a change already
        // reported, has not.
        guard before != after else { return }
        lastFiles[event.path] = after
        self.delegate?.fileDidChanged(event: FileChangeEvent.changed(file: url))

      case (nil, nil):
        // A temporary file, gone before we looked.
        return
      }
    }
  }

  deinit {
    stop()
  }

  public func observe() throws {
    fileWatcher.start()
  }

  public func stop() {
    fileWatcher.stop();
  }

  // MARK: - Fingerprints

  /// Enough of a file's metadata to tell whether an event left a different file at its path.
  /// The identifier catches a rename or clone over the path, the date and size a write in
  /// place.
  private struct Fingerprint: Equatable {
    let identifier: NSObject?
    let modified: Date?
    let size: Int?

    init(_ url: URL) {
      let values = try? url.resourceValues(forKeys: [
        .fileResourceIdentifierKey, .contentModificationDateKey, .fileSizeKey,
      ])
      identifier = values?.fileResourceIdentifier as? NSObject
      modified = values?.contentModificationDate
      size = values?.fileSize
    }
  }

  private static func fingerprints(in directory: URL) throws -> [String: Fingerprint] {
    guard let enumerator = FileManager.default.enumerator(
      at: directory,
      includingPropertiesForKeys: [.fileResourceIdentifierKey, .contentModificationDateKey, .fileSizeKey],
      options: [.skipsHiddenFiles]
    ) else {
      return [:]
    }
    var files: [String: Fingerprint] = [:]
    for case let url as URL in enumerator where !url.isDSStore {
      files[url.path(percentEncoded: false).removingTrailingSlash] = Fingerprint(url)
    }
    return files
  }
}

private extension String {
  /// Whether this path is somewhere under `directory`.
  func isInside(_ directory: String) -> Bool {
    hasPrefix(directory + "/")
  }

  var removingTrailingSlash: String {
    last == "/" ? String(dropLast()) : self
  }
}
#endif
