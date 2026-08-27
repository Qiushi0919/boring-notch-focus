//
//  NowPlayingController.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import AppKit
import ApplicationServices
import Combine
import Darwin
import Foundation

final class NowPlayingController: ObservableObject, MediaControllerProtocol {
    func updatePlaybackInfo() async {
        await fetchFavoriteStateIfSupported()
    }

    // MARK: - Properties
    @Published private(set) var playbackState: PlaybackState = .init(
        bundleIdentifier: "com.apple.Music"
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        let bundleID = playbackState.bundleIdentifier
        return bundleID == "com.apple.Music" || bundleID == "com.spotify.client"
    }

    var supportsFavorite: Bool {
        let bundleID = playbackState.bundleIdentifier
        return bundleID == "com.apple.Music"
            || bundleID == "com.tencent.QQMusicMac"
            || nowPlayingSupportsFavorite
    }

    func setFavorite(_ favorite: Bool) async {
        let bundleID = playbackState.bundleIdentifier
        
        if bundleID == "com.apple.Music" {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
            if !runningApps.isEmpty {
                let script = """
                tell application "Music"
                    try
                        set favorited of current track to \(favorite ? "true" : "false")
                    end try
                end tell
                """
                try? await AppleScriptHelper.executeVoid(script)
            }
        } else if bundleID == "com.tencent.QQMusicMac" {
            guard performQQMusicFavoriteAction() else { return }

            let key = favoriteTrackKey(for: playbackState)
            qqMusicFavoriteStates[key] = favorite
            var updated = playbackState
            updated.isFavorite = favorite
            playbackState = updated

            // QQ Music persists the change asynchronously. Reading its database
            // immediately can return the old value and make the heart appear to
            // undo itself, so wait for the requested state to become visible.
            for delay in [600, 900, 1_500, 2_000] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard let confirmed = queryQQMusicFavoriteState(for: playbackState) else {
                    continue
                }
                if confirmed == favorite {
                    qqMusicFavoriteStates[key] = confirmed
                    var confirmedState = playbackState
                    confirmedState.isFavorite = confirmed
                    playbackState = confirmedState
                    NSLog(
                        "QQ Music favorite action confirmed for %@: %@",
                        playbackState.title,
                        confirmed ? "yes" : "no"
                    )
                    return
                }
            }

            // Keep the optimistic state when QQ Music's database is still being
            // written. A later metadata refresh will reconcile it.
            lastQQMusicFavoriteLookupKey = nil
            NSLog("QQ Music favorite action is still awaiting database confirmation for %@", playbackState.title)
            return
        }
        
        // Update the favorite state locally and fetch updated info
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }

    private var lastMusicItem:
        (title: String, artist: String, album: String, duration: TimeInterval, artworkData: Data?)?
    private var nowPlayingSupportsFavorite = false
    private var qqMusicFavoriteStates: [String: Bool] = [:]
    private var lastQQMusicFavoriteLookupKey: String?

    // MARK: - Media Remote Functions
    private let mediaRemoteBundle: CFBundle
    private let MRMediaRemoteSendCommandFunction: @convention(c) (Int, AnyObject?) -> Void
    private let MRMediaRemoteSetElapsedTimeFunction: @convention(c) (Double) -> Void
    private let MRMediaRemoteSetShuffleModeFunction: @convention(c) (Int) -> Void
    private let MRMediaRemoteSetRepeatModeFunction: @convention(c) (Int) -> Void

    private var process: Process?
    private var pipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?

    // MARK: - Initialization
    init?() {
        guard
            let bundle = CFBundleCreate(
                kCFAllocatorDefault,
                NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")),
            let MRMediaRemoteSendCommandPointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSendCommand" as CFString),
            let MRMediaRemoteSetElapsedTimePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetElapsedTime" as CFString),
            let MRMediaRemoteSetShuffleModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetShuffleMode" as CFString),
            let MRMediaRemoteSetRepeatModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetRepeatMode" as CFString)
            
        else { return nil }

        mediaRemoteBundle = bundle
        MRMediaRemoteSendCommandFunction = unsafeBitCast(
            MRMediaRemoteSendCommandPointer, to: (@convention(c) (Int, AnyObject?) -> Void).self)
        MRMediaRemoteSetElapsedTimeFunction = unsafeBitCast(
            MRMediaRemoteSetElapsedTimePointer, to: (@convention(c) (Double) -> Void).self)
        MRMediaRemoteSetShuffleModeFunction = unsafeBitCast(
            MRMediaRemoteSetShuffleModePointer, to: (@convention(c) (Int) -> Void).self)
        MRMediaRemoteSetRepeatModeFunction = unsafeBitCast(
            MRMediaRemoteSetRepeatModePointer, to: (@convention(c) (Int) -> Void).self)

        Task { await setupNowPlayingObserver() }
    }

    deinit {
        streamTask?.cancel()
        
        if let pipeHandler = self.pipeHandler {
            Task { await pipeHandler.close()
            }
        }
        
        if let process = self.process {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        self.process = nil
        self.pipeHandler = nil
    }

    // MARK: - Protocol Implementation
    func play() async {
        MRMediaRemoteSendCommandFunction(0, nil)
    }

    func pause() async {
        MRMediaRemoteSendCommandFunction(1, nil)
    }

    func togglePlay() async {
        MRMediaRemoteSendCommandFunction(2, nil)
    }

    func nextTrack() async {
        MRMediaRemoteSendCommandFunction(4, nil)
    }

    func previousTrack() async {
        MRMediaRemoteSendCommandFunction(5, nil)
    }

    func seek(to time: Double) async {
        MRMediaRemoteSetElapsedTimeFunction(time)
    }

    func isActive() -> Bool {
        return true
    }
    
    func toggleShuffle() async {
        // MRMediaRemoteSendCommandFunction(6, nil)
        MRMediaRemoteSetShuffleModeFunction(playbackState.isShuffled ? 1 : 3)
        playbackState.isShuffled.toggle()
    }
    
    func toggleRepeat() async {
        // MRMediaRemoteSendCommandFunction(7, nil)
        let newRepeatMode = (playbackState.repeatMode == .off) ? 3 : (playbackState.repeatMode.rawValue - 1)
        playbackState.repeatMode = RepeatMode(rawValue: newRepeatMode) ?? .off
        MRMediaRemoteSetRepeatModeFunction(newRepeatMode)
    }
    
    func setVolume(_ level: Double) async {
        // MediaRemote framework doesn't provide direct volume control for the active audio session
        // As a workaround, try to control the currently active music app directly
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        
        let bundleID = playbackState.bundleIdentifier
        if !bundleID.isEmpty {
            if bundleID == "com.apple.Music" {
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
                if !runningApps.isEmpty {
                    let script = "tell application \"Music\" to set sound volume to \(volumePercentage)"
                    try? await AppleScriptHelper.executeVoid(script)
                }
            } else if bundleID == "com.spotify.client" {
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client")
                if !runningApps.isEmpty {
                    let script = "tell application \"Spotify\" to set sound volume to \(volumePercentage)"
                    try? await AppleScriptHelper.executeVoid(script)
                }
            }
        }
        
        playbackState.volume = clampedLevel
    }
    
    // MARK: - Setup Methods
    private func setupNowPlayingObserver() async {
        let process = Process()
        guard
            let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework")
        else {
            assertionFailure("Could not find mediaremote-adapter.pl script or framework path")
            return
        }
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkPath, "stream"]
        
        let pipeHandler = JSONLinesPipeHandler()
        process.standardOutput = await pipeHandler.getPipe()
        
        self.process = process
        self.pipeHandler = pipeHandler

        do {
            try process.run()
            streamTask = Task { [weak self] in
                await self?.processJSONStream()
            }
        } catch {
            assertionFailure("Failed to launch mediaremote-adapter.pl: \(error)")
        }
    }

    // MARK: - Async Stream Processing
    private func processJSONStream() async {
        guard let pipeHandler = self.pipeHandler else { return }
        
        await pipeHandler.readJSONLines(as: NowPlayingUpdate.self) { [weak self] update in
            await self?.handleAdapterUpdate(update)
        }
    }

    // MARK: - Update Methods
    private func handleAdapterUpdate(_ update: NowPlayingUpdate) async {
        let payload = update.payload
        let diff = update.diff ?? false

        var newPlaybackState = PlaybackState(bundleIdentifier: playbackState.bundleIdentifier)
        
        newPlaybackState.title = payload.title ?? (diff ? self.playbackState.title : "")
        newPlaybackState.artist = payload.artist ?? (diff ? self.playbackState.artist : "")
        newPlaybackState.album = payload.album ?? (diff ? self.playbackState.album : "")
        newPlaybackState.duration = payload.duration ?? (diff ? self.playbackState.duration : 0)
        
        if let elapsedTime = payload.elapsedTime {
            newPlaybackState.currentTime = elapsedTime
        } else if diff {
            if payload.playing == false {
                let timeSinceLastUpdate = Date().timeIntervalSince(self.playbackState.lastUpdated)
                newPlaybackState.currentTime = self.playbackState.currentTime + (self.playbackState.playbackRate * timeSinceLastUpdate)
            } else {
                newPlaybackState.currentTime = self.playbackState.currentTime
            }
        } else {
            newPlaybackState.currentTime = 0
        }

        
        if let shuffleMode = payload.shuffleMode {
            newPlaybackState.isShuffled = shuffleMode != 1
        } else if !diff {
            newPlaybackState.isShuffled = false
        } else {
            newPlaybackState.isShuffled = self.playbackState.isShuffled
        }
        if let repeatModeValue = payload.repeatMode {
            newPlaybackState.repeatMode = RepeatMode(rawValue: repeatModeValue) ?? .off
        } else if !diff {
            newPlaybackState.repeatMode = .off
        } else {
            newPlaybackState.repeatMode = self.playbackState.repeatMode
        }

        if let artworkDataString = payload.artworkData {
            newPlaybackState.artwork = Data(
                base64Encoded: artworkDataString.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else if !diff {
            newPlaybackState.artwork = nil
        }

        if let dateString = payload.timestamp,
           let date = ISO8601DateFormatter().date(from: dateString) {
            newPlaybackState.lastUpdated = date
        } else if !diff {
            newPlaybackState.lastUpdated = Date()
        } else {
            newPlaybackState.lastUpdated = self.playbackState.lastUpdated
        }

        newPlaybackState.playbackRate = payload.playbackRate ?? (diff ? self.playbackState.playbackRate : 1.0)
        newPlaybackState.isPlaying = payload.playing ?? (diff ? self.playbackState.isPlaying : false)
        newPlaybackState.bundleIdentifier = (
            payload.parentApplicationBundleIdentifier ??
            payload.bundleIdentifier ??
            (diff ? self.playbackState.bundleIdentifier : "")
        )

        nowPlayingSupportsFavorite = payload.supportsIsLiked ?? false
        if let isLiked = payload.isLiked {
            newPlaybackState.isFavorite = isLiked
        } else if newPlaybackState.bundleIdentifier == "com.tencent.QQMusicMac" {
            newPlaybackState.isFavorite = qqMusicFavoriteStates[favoriteTrackKey(for: newPlaybackState)] ?? false
        } else if diff {
            newPlaybackState.isFavorite = self.playbackState.isFavorite
        }
        
        newPlaybackState.volume = payload.volume ?? (diff ? self.playbackState.volume : 0.5)
        
        self.playbackState = newPlaybackState

        if newPlaybackState.bundleIdentifier == "com.tencent.QQMusicMac" {
            await refreshQQMusicFavoriteState()
        }
        
        // Fetch favorite state for supported apps asynchronously
        // await fetchFavoriteStateIfSupported()
    }

    private func favoriteTrackKey(for state: PlaybackState) -> String {
        [state.bundleIdentifier, state.title, state.artist, state.album]
            .joined(separator: "\u{1F}")
    }

    private func refreshQQMusicFavoriteState(force: Bool = false) async {
        let state = playbackState
        let key = favoriteTrackKey(for: state)
        guard force || lastQQMusicFavoriteLookupKey != key else { return }
        lastQQMusicFavoriteLookupKey = key

        guard let favorite = queryQQMusicFavoriteState(for: state) else {
            NSLog("QQ Music favorite lookup unavailable for %@", state.title)
            return
        }
        qqMusicFavoriteStates[key] = favorite

        guard favoriteTrackKey(for: playbackState) == key else { return }
        var updated = playbackState
        updated.isFavorite = favorite
        playbackState = updated
        NSLog("QQ Music favorite state for %@: %@", state.title, favorite ? "yes" : "no")
    }

    private func queryQQMusicFavoriteState(for state: PlaybackState) -> Bool? {
        guard !state.title.isEmpty else { return nil }

        guard let passwordEntry = getpwuid(getuid()) else { return nil }
        let accountHomeURL = URL(
            fileURLWithPath: String(cString: passwordEntry.pointee.pw_dir),
            isDirectory: true
        )
        let databaseURL = accountHomeURL
            .appendingPathComponent(
                "Library/Containers/com.tencent.QQMusicMac/Data/Library/Application Support/QQMusicMac/qqmusic.sqlite"
            )
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }

        func escaped(_ value: String) -> String {
            value.replacingOccurrences(of: "'", with: "''")
        }

        let title = escaped(state.title)
        let artist = escaped(state.artist)
        let album = escaped(state.album)
        var identityClauses: [String] = []
        if !artist.isEmpty {
            identityClauses.append("s.singer = '\(artist)' COLLATE NOCASE")
        }
        if !album.isEmpty {
            identityClauses.append("s.album = '\(album)' COLLATE NOCASE")
        }
        let identitySQL = identityClauses.isEmpty
            ? ""
            : " AND (\(identityClauses.joined(separator: " OR ")))"
        let sql = """
        SELECT CASE WHEN EXISTS(
            SELECT 1
            FROM NEWFOLDERS f
            JOIN NEWFOLDERSONGS fs ON fs.seq = f.seq
            JOIN SONGS s ON s.id = fs.id AND s.type = fs.type
            WHERE (f.folderid = 201 OR f.folderName IN ('我喜欢', '我的喜爱', '我的喜愛', 'Favorites'))
              AND s.name = '\(title)' COLLATE NOCASE\(identitySQL)
            LIMIT 1
        ) THEN 1 ELSE 0 END;
        """

        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-noheader", "-batch", databaseURL.path, sql]
        process.standardOutput = pipe
        process.standardError = errorPipe

        do {
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(data: errorOutput, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown sqlite error"
                NSLog("QQ Music favorite database query failed: %@", message)
                return nil
            }
            guard let value = String(data: output, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            else { return nil }
            return value == "1"
        } catch {
            NSLog("QQ Music favorite lookup failed: %@", error.localizedDescription)
            return nil
        }
    }

    /// QQ Music does not expose its favorite action through MediaRemote. Posting
    /// Command-L directly to the background process is unreliable because AppKit
    /// does not always route synthetic key events through its main menu. Trigger
    /// the real "喜欢歌曲" menu item through Accessibility instead, with the
    /// shortcut retained as a compatibility fallback.
    private func performQQMusicFavoriteAction() -> Bool {
        let promptOptions = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(promptOptions)
        NSLog("QQ Music favorite Accessibility trusted: %@", isTrusted ? "yes" : "no")
        guard isTrusted else { return false }
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.tencent.QQMusicMac"
        ).first else { return false }

        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
        var menuBarValue: CFTypeRef?
        let menuBarStatus = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXMenuBarAttribute as CFString,
            &menuBarValue
        )
        NSLog("QQ Music menu bar lookup result: %d", menuBarStatus.rawValue)
        if menuBarStatus == .success,
           let menuBarValue,
           CFGetTypeID(menuBarValue) == AXUIElementGetTypeID()
        {
            let menuBar = unsafeBitCast(menuBarValue, to: AXUIElement.self)
            let acceptedTitles = [
                "喜欢歌曲",
                "取消喜欢歌曲",
                "收藏歌曲",
                "取消收藏歌曲",
                "Like Song",
                "Unlike Song",
                "Love Current Song"
            ]

            if let menuItem = findAccessibilityMenuItem(
                in: menuBar,
                acceptedTitles: acceptedTitles,
                depth: 0
            ) {
                let result = AXUIElementPerformAction(menuItem, kAXPressAction as CFString)
                NSLog("QQ Music favorite menu action result: %d", result.rawValue)
                if result == .success {
                    return true
                }
            } else {
                NSLog("QQ Music favorite menu item was not found; falling back to Command-L")
            }
        }

        NSLog("QQ Music favorite menu action fell back to Command-L")
        return sendQQMusicFavoriteShortcut(to: app)
    }

    private func findAccessibilityMenuItem(
        in element: AXUIElement,
        acceptedTitles: [String],
        depth: Int
    ) -> AXUIElement? {
        guard depth < 10 else { return nil }

        var roleValue: CFTypeRef?
        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)

        if let role = roleValue as? String,
           role == (kAXMenuItemRole as String),
           let title = titleValue as? String,
           acceptedTitles.contains(where: { title.localizedCaseInsensitiveContains($0) })
        {
            return element
        }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenValue
        ) == .success,
              let children = childrenValue as? [AXUIElement]
        else { return nil }

        for child in children {
            if let match = findAccessibilityMenuItem(
                in: child,
                acceptedTitles: acceptedTitles,
                depth: depth + 1
            ) {
                return match
            }
        }
        return nil
    }

    private func sendQQMusicFavoriteShortcut(to app: NSRunningApplication) -> Bool {

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0x25,
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0x25,
                keyDown: false
              )
        else { return false }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(app.processIdentifier)
        keyUp.postToPid(app.processIdentifier)
        return true
    }
    
     private func fetchFavoriteStateIfSupported() async {
         let bundleID = playbackState.bundleIdentifier
        
         if bundleID == "com.apple.Music" {
             let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
             guard !runningApps.isEmpty else { return }
             
             let script = """
             tell application "Music"
                 try
                     return favorited of current track
                 on error
                     return false
                 end try
             end tell
             """
             if let result = try? await AppleScriptHelper.execute(script) {
                 var updated = self.playbackState
                 updated.isFavorite = result.booleanValue
                 self.playbackState = updated
             }
         } else if bundleID == "com.tencent.QQMusicMac" {
             await refreshQQMusicFavoriteState(force: true)
         }
     }
    
}

struct NowPlayingUpdate: Codable {
    let payload: NowPlayingPayload
    let diff: Bool?
}

struct NowPlayingPayload: Codable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: Double?
    let elapsedTime: Double?
    let shuffleMode: Int?
    let repeatMode: Int?
    let artworkData: String?
    let timestamp: String?
    let playbackRate: Double?
    let playing: Bool?
    let parentApplicationBundleIdentifier: String?
    let bundleIdentifier: String?
    let volume: Double?
    let isLiked: Bool?
    let supportsIsLiked: Bool?
}

actor JSONLinesPipeHandler {
    private let pipe: Pipe
    private let fileHandle: FileHandle
    private var buffer = ""
    
    init() {
        self.pipe = Pipe()
        self.fileHandle = pipe.fileHandleForReading
    }
    
    func getPipe() -> Pipe {
        return pipe
    }
    
    func readJSONLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) async -> Void) async {
        do {
            try await self.processLines(as: type) { decodedObject in
                await onLine(decodedObject)
            }
        } catch {
            print("Error processing JSON stream: \(error)")
        }
    }
    
    private func processLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) async -> Void) async throws {
        while true {
            let data = try await readData()
            guard !data.isEmpty else { break }
            
            if let chunk = String(data: data, encoding: .utf8) {
                buffer.append(chunk)
                
                while let range = buffer.range(of: "\n") {
                    let line = String(buffer[..<range.lowerBound])
                    buffer = String(buffer[range.upperBound...])
                    
                    if !line.isEmpty {
                        await processJSONLine(line, as: type, onLine: onLine)
                    }
                }
            }
        }
    }
    
    private func processJSONLine<T: Decodable>(_ line: String, as type: T.Type, onLine: @escaping (T) async -> Void) async {
        guard let data = line.data(using: .utf8) else {
            return
        }
        do {
            let decodedObject = try JSONDecoder().decode(T.self, from: data)
            await onLine(decodedObject)
        } catch {
            // Ignore lines that can't be decoded
        }
    }
    
    private func readData() async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            
            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                handle.readabilityHandler = nil
                continuation.resume(returning: data)
            }
        }
    }
    
    func close() async {
        do {
            fileHandle.readabilityHandler = nil
            try fileHandle.close()
            try pipe.fileHandleForWriting.close()
        } catch {
            print("Error closing pipe handler: \(error)")
        }
    }
}
