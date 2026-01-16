//
// aus der Technik, on 15.05.23.
// https://www.ausdertechnik.de
//
// Updated by Ben Davis 16.01.26.
//

import Foundation

public protocol WatcherDelegate {
  func fileDidChanged(event: FileChangeEvent)
}

public protocol WatcherProtocol {
  var delegate: WatcherDelegate? { set get }
  
  init(directory: URL) throws
  func observe() throws
  func stop()
}

public extension WatcherProtocol {
  func getCurrentFiles(in directory: URL) throws -> [String] {
    guard let enumerator = FileManager.default.enumerator(
      at: directory,
      includingPropertiesForKeys: [.creationDateKey, .typeIdentifierKey],
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }
    
    var content: [URL] = []
    for case let fileURL as URL in enumerator {
      content.append(fileURL)
    }
    return content
      .filter { !$0.isDSStore }
      .map { $0.path(percentEncoded: false) }
      .map { $0.removingTrailingSlash }
  }
  
  func getDifferencesInFiles(lhs: [String], rhs: [String]) -> Set<String> {
    Set(lhs).subtracting(rhs)
  }
}

public extension URL {
  var isDSStore: Bool {
    lastPathComponent == ".DS_Store"
  }
}

extension String {
  var removingTrailingSlash: String {
    last == "/" ? String(dropLast()) : self
  }
}
