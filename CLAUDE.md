# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FileMonitor is a Swift package that provides a unified API for monitoring file changes in directories across macOS and Linux. It abstracts platform-specific implementations (FSEventStream for macOS, inotify for Linux) behind a common interface.

## Build and Test Commands

```bash
# Build the package
swift build

# Build with verbose output
swift build -v

# Run tests
swift test

# Run tests with verbose output
swift test -v

# Run example executables
swift run FileMonitorDelegateExample
swift run FileMonitorAsyncStreamExample

# Lint code (SwiftLint must be installed)
swiftlint
```

## Architecture

### Platform Abstraction Pattern

The codebase uses conditional compilation to provide platform-specific implementations:

- `FileMonitorShared/`: Platform-agnostic protocols and types
  - `WatcherProtocol`: Defines the interface all platform watchers must implement
  - `FileChangeEvent`: Enum representing file add/change/delete events
  - `Watcher.swift`: Contains shared utility methods for file comparison

- `FileMonitorMacOS/`: macOS implementation using FSEventStream
  - `MacosWatcher`: Conforms to `WatcherProtocol`, wraps `FileWatcher`
  - Uses file list comparison to determine event types since FSEvents doesn't always provide precise event categorization

- `FileMonitorLinux/`: Linux implementation using inotify
  - `LinuxWatcher`: Conforms to `WatcherProtocol`, wraps `FileSystemWatcher`
  - `CInotify`: System library module for inotify bindings
  - Processes inotify event masks directly to determine event types

- `FileMonitor/`: Main public API
  - `FileMonitor.swift`: Facade that instantiates the correct platform watcher
  - Provides both delegate pattern and AsyncStream interfaces
  - Acts as `WatcherDelegate` to bridge platform watchers to public API

### Key Design Decisions

1. **Dual API Surface**: Supports both traditional delegate pattern and modern AsyncStream for file change notifications
2. **Platform Selection at Compile Time**: Uses `#if os(macOS)` / `#if os(Linux)` to select implementations
3. **Event Normalization**: Different platforms provide different granularity of events; the abstraction normalizes these to `.added`, `.changed`, `.deleted`
4. **macOS Event Detection**: macOS implementation compares file lists before/after to accurately classify events, as FSEventStream provides coarse-grained notifications

## SwiftLint Configuration

The project uses SwiftLint with custom rules defined in `.swiftlint.yml`:
- Function body length: warning at 80 lines, error at 120 lines
- File length: warning at 500 lines, error at 1200 lines
- Identifier names: min 3 characters (except `id`, `fn`, `ms`, `i`)
- Force unwrapping is enabled as an opt-in rule (project may use force unwraps)
- Analyzer rules include unused_import and unused_declaration

## Platform Requirements

- Swift 5.9+
- macOS 13+ (for macOS builds)
- Ubuntu 22.04+ (for Linux builds)
- Linux requires inotify system library

## Testing Notes

Tests are located in `Tests/FileMonitorTests/` and cover:
- Explicit file add/change/delete event detection
- File path verification
- Both delegate and AsyncStream interfaces

Tests create temporary directories and files to verify monitoring behavior.
