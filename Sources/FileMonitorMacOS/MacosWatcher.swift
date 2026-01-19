//
// aus der Technik, on 15.05.23.
// https://www.ausdertechnik.de
//
// Updated by Ben Davis 16.01.26.
//

import Foundation
import FileMonitorShared

#if os(macOS)
public final class MacosWatcher: WatcherProtocol {
  public var delegate: WatcherDelegate?
  let fileWatcher: FileWatcher
  private var lastFiles: [String] = []
  private var pendingRenameOtherFile = false

  required public init(directory: URL) throws {

    fileWatcher = FileWatcher([directory.path])
    fileWatcher.queue = DispatchQueue.global()
    lastFiles = try getCurrentFiles(in: directory)

    fileWatcher.callback = { [self] event throws in
      let url = URL(fileURLWithPath: event.path)
      guard !url.isDSStore else { return }
      guard event.path != fileWatcher.filePaths.first else { return }

      let currentFiles = try getCurrentFiles(in: directory)

      let removedFiles = getDifferencesInFiles(lhs: lastFiles, rhs: currentFiles)
      let addedFiles = getDifferencesInFiles(lhs: currentFiles, rhs: lastFiles)
      let changeSetCount = addedFiles.count - removedFiles.count

      if (event.fileRemoved || event.dirRemoved) {
        guard removedFiles.contains(event.path) else { return }
        self.delegate?.fileDidChanged(event: FileChangeEvent.deleted(file: url))
        pendingRenameOtherFile = false
      }
      else if event.fileRenamed || event.dirRenamed {
        // Renamed can mean added or removed depending on file list changes
        if addedFiles.contains(event.path) {
          self.delegate?.fileDidChanged(event: FileChangeEvent.added(file: url))
        } else if removedFiles.contains(event.path) {
          self.delegate?.fileDidChanged(event: FileChangeEvent.deleted(file: url))
        }
        if pendingRenameOtherFile {
          pendingRenameOtherFile = false
        } else {
          pendingRenameOtherFile = true
          DispatchQueue.main.async {
            if self.pendingRenameOtherFile {
              self.lastFiles = currentFiles
              self.pendingRenameOtherFile = false
            }
          }
          return
        }
      }
      else if (event.fileCreated || event.dirCreated) {
        guard addedFiles.contains(event.path) else { return }
        self.delegate?.fileDidChanged(event: FileChangeEvent.added(file: url))
        pendingRenameOtherFile = false
      }
      else if (event.fileModified || event.dirModified || event.fileChange) && changeSetCount == 0 {
        self.delegate?.fileDidChanged(event: FileChangeEvent.changed(file: url))
        pendingRenameOtherFile = false
      }

      lastFiles = currentFiles
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
}
#endif
