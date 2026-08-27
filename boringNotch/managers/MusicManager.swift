//
//  MusicManager.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 03/08/24.
//
import AppKit
import ApplicationServices
import Combine
import CoreAudio
import Defaults
import SwiftUI

let defaultImage: NSImage = .init(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

struct PlaybackSourceSnapshot: Identifiable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    var title: String
    var subtitle: String
    var artwork: NSImage
    var usesAppIconAsArtwork: Bool
    var isPlaying: Bool
    var lastSeen: Date
}

class MusicManager: ObservableObject {
    // MARK: - Properties
    static let shared = MusicManager()
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables = Set<AnyCancellable>()
    private var debounceIdleTask: Task<Void, Never>?
    private var playbackSourceRefreshTask: Task<Void, Never>?
    private let qqMusicBundleIdentifier = "com.tencent.QQMusicMac"

    // Helper to check if macOS has removed support for NowPlayingController
    public private(set) var isNowPlayingDeprecated: Bool = false
    private let mediaChecker = MediaChecker()

    // Active controller
    private var activeController: (any MediaControllerProtocol)?

    // Published properties for UI
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var album: String = "Self Love"
    @Published var isPlayerIdle: Bool = true
    @Published var animations: BoringAnimations = .init()
    @Published var avgColor: NSColor = .white
    @Published var bundleIdentifier: String? = nil
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = .init()
    @Published var playbackRate: Double = 1
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Double = 0.5
    @Published var volumeControlSupported: Bool = true
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Published var usingAppIconForArtwork: Bool = false
    @Published var currentLyrics: String = ""
    @Published var isFetchingLyrics: Bool = false
    @Published var syncedLyrics: [(time: Double, text: String)] = []
    @Published var canFavoriteTrack: Bool = false
    @Published var isFavoriteTrack: Bool = false
    @Published private(set) var playbackSources: [PlaybackSourceSnapshot] = []

    private var artworkData: Data? = nil

    // Store last values at the time artwork was changed
    private var lastArtworkTitle: String = "I'm Handsome"
    private var lastArtworkArtist: String = "Me"
    private var lastArtworkAlbum: String = "Self Love"
    private var lastArtworkBundleIdentifier: String? = nil

    @Published var isFlipping: Bool = false
    private var flipWorkItem: DispatchWorkItem?

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?

    // MARK: - Initialization
    init() {
        // Listen for changes to the default controller preference
        NotificationCenter.default.publisher(for: Notification.Name.mediaControllerChanged)
            .sink { [weak self] _ in
                self?.setActiveControllerBasedOnPreference()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didTerminateApplicationNotification
        )
        .compactMap { notification in
            (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication)?.bundleIdentifier
        }
        .receive(on: DispatchQueue.main)
        .sink { [weak self] terminatedBundleIdentifier in
            self?.playbackSources.removeAll {
                $0.bundleIdentifier == terminatedBundleIdentifier
            }
        }
        .store(in: &cancellables)

        playbackSourceRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self?.pruneInactivePlaybackSources()
                }
            }
        }

        // Initialize deprecation check asynchronously
        Task { @MainActor in
            do {
                self.isNowPlayingDeprecated = try await self.mediaChecker.checkDeprecationStatus()
                print("Deprecation check completed: \(self.isNowPlayingDeprecated)")
            } catch {
                print("Failed to check deprecation status: \(error). Defaulting to false.")
                self.isNowPlayingDeprecated = false
            }
            
            // Initialize the active controller after deprecation check
            self.setActiveControllerBasedOnPreference()
        }
    }

    deinit {
        destroy()
    }
    
    public func destroy() {
        debounceIdleTask?.cancel()
        playbackSourceRefreshTask?.cancel()
        cancellables.removeAll()
        controllerCancellables.removeAll()
        flipWorkItem?.cancel()
        transitionWorkItem?.cancel()

        // Release active controller
        activeController = nil
    }

    // MARK: - Setup Methods
    private func createController(for type: MediaControllerType) -> (any MediaControllerProtocol)? {
        // Cleanup previous controller
        if activeController != nil {
            controllerCancellables.removeAll()
            activeController = nil
        }

        let newController: (any MediaControllerProtocol)?

        switch type {
        case .nowPlaying:
            // Only create NowPlayingController if not deprecated on this macOS version
            if !self.isNowPlayingDeprecated {
                newController = NowPlayingController()
            } else {
                return nil
            }
        case .appleMusic:
            newController = AppleMusicController()
        case .spotify:
            newController = SpotifyController()
        case .youtubeMusic:
            newController = YouTubeMusicController()
        }

        // Set up state observation for the new controller
        if let controller = newController {
            controller.playbackStatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self = self,
                          self.activeController === controller else { return }
                    self.updateFromPlaybackState(state)
                }
                .store(in: &controllerCancellables)
        }

        return newController
    }

    private func setActiveControllerBasedOnPreference() {
        let preferredType = Defaults[.mediaController]
        print("Preferred Media Controller: \(preferredType)")

        // If NowPlaying is deprecated but that's the preference, use Apple Music instead
        let controllerType = (self.isNowPlayingDeprecated && preferredType == .nowPlaying)
            ? .appleMusic
            : preferredType

        if let controller = createController(for: controllerType) {
            setActiveController(controller)
        } else if controllerType != .appleMusic, let fallbackController = createController(for: .appleMusic) {
            // Fallback to Apple Music if preferred controller couldn't be created
            setActiveController(fallbackController)
        }
    }

    private func setActiveController(_ controller: any MediaControllerProtocol) {
        // Cancel any existing flip animation
        flipWorkItem?.cancel()

        // Set new active controller
        activeController = controller
        
        self.canFavoriteTrack = controller.supportsFavorite

        // Get current state from active controller
        forceUpdate()
    }

    // MARK: - Update Methods
    @MainActor
    private func updateFromPlaybackState(_ state: PlaybackState) {
        updatePlaybackSources(with: state)

        // Controller capabilities can change when the active Now Playing app changes.
        // Reading this only once during controller creation leaves QQ Music disabled.
        self.canFavoriteTrack = (activeController?.supportsFavorite ?? false)
            || state.bundleIdentifier == "com.tencent.QQMusicMac"

        // Check for playback state changes (playing/paused)
        if state.isPlaying != self.isPlaying {
            NSLog("Playback state changed: \(state.isPlaying ? "Playing" : "Paused")")
            withAnimation(.smooth) {
                self.isPlaying = state.isPlaying
                self.updateIdleState(state: state.isPlaying)
            }

            if state.isPlaying && !state.title.isEmpty && !state.artist.isEmpty {
                self.updateSneakPeek()
            }
        }

        // Check for changes in track metadata using last artwork change values
        let titleChanged = state.title != self.lastArtworkTitle
        let artistChanged = state.artist != self.lastArtworkArtist
        let albumChanged = state.album != self.lastArtworkAlbum
        let bundleChanged = state.bundleIdentifier != self.lastArtworkBundleIdentifier

        // Check for artwork changes
        let artworkChanged = state.artwork != nil && state.artwork != self.artworkData
        let hasContentChange = titleChanged || artistChanged || albumChanged || artworkChanged || bundleChanged

        // Handle artwork and visual transitions for changed content
        if hasContentChange {
            self.triggerFlipAnimation()

            if artworkChanged, let artwork = state.artwork {
                self.updateArtwork(artwork)
            } else if state.artwork == nil {
                // Try to use app icon if no artwork but track changed
                if let appIconImage = AppIconAsNSImage(for: state.bundleIdentifier) {
                    self.usingAppIconForArtwork = true
                    self.updateAlbumArt(newAlbumArt: appIconImage)
                }
            }
            self.artworkData = state.artwork

            if artworkChanged || state.artwork == nil {
                // Update last artwork change values
                self.lastArtworkTitle = state.title
                self.lastArtworkArtist = state.artist
                self.lastArtworkAlbum = state.album
                self.lastArtworkBundleIdentifier = state.bundleIdentifier
            }

            // Only update sneak peek if there's actual content and something changed
            if !state.title.isEmpty && !state.artist.isEmpty && state.isPlaying {
                self.updateSneakPeek()
            }

            // Fetch lyrics on content change
            self.fetchLyricsIfAvailable(bundleIdentifier: state.bundleIdentifier, title: state.title, artist: state.artist)
        }

        let timeChanged = state.currentTime != self.elapsedTime
        let durationChanged = state.duration != self.songDuration
        let playbackRateChanged = state.playbackRate != self.playbackRate
        let shuffleChanged = state.isShuffled != self.isShuffled
        let repeatModeChanged = state.repeatMode != self.repeatMode
        let volumeChanged = state.volume != self.volume
        
        if state.title != self.songTitle {
            self.songTitle = state.title
        }

        if state.artist != self.artistName {
            self.artistName = state.artist
        }

        if state.album != self.album {
            self.album = state.album
        }

        if timeChanged {
            self.elapsedTime = state.currentTime
        }

        if durationChanged {
            self.songDuration = state.duration
        }

        if playbackRateChanged {
            self.playbackRate = state.playbackRate
        }
        
        if shuffleChanged {
            self.isShuffled = state.isShuffled
        }

        if state.bundleIdentifier != self.bundleIdentifier {
            self.bundleIdentifier = state.bundleIdentifier
            // Update volume control support from active controller
            self.volumeControlSupported = activeController?.supportsVolumeControl ?? false
        }

        if repeatModeChanged {
            self.repeatMode = state.repeatMode
        }
        if state.isFavorite != self.isFavoriteTrack {
            self.isFavoriteTrack = state.isFavorite
        }
        
        if volumeChanged {
            self.volume = state.volume
        }
        
        self.timestampDate = state.lastUpdated
    }

    @MainActor
    private func updatePlaybackSources(with state: PlaybackState) {
        let bundleID = state.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty, !title.isEmpty, title != "I'm Handsome" else { return }

        let existingIndex = playbackSources.firstIndex {
            $0.bundleIdentifier == bundleID
        }
        let trackChanged = existingIndex.map {
            playbackSources[$0].title != title
        } ?? true

        let resolvedArtwork: NSImage
        let usesAppIcon: Bool
        if let artworkData = state.artwork, let artworkImage = NSImage(data: artworkData) {
            resolvedArtwork = artworkImage
            usesAppIcon = false
        } else if let existingIndex, !trackChanged {
            resolvedArtwork = playbackSources[existingIndex].artwork
            usesAppIcon = playbackSources[existingIndex].usesAppIconAsArtwork
        } else if let icon = AppIconAsNSImage(for: bundleID) {
            resolvedArtwork = icon
            usesAppIcon = true
        } else {
            resolvedArtwork = defaultImage
            usesAppIcon = true
        }

        let artist = state.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let albumName = state.album.trimmingCharacters(in: .whitespacesAndNewlines)
        let applicationName = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleID
        ).first?.localizedName ?? bundleID
        let subtitle = !artist.isEmpty ? artist : (!albumName.isEmpty ? albumName : applicationName)

        let snapshot = PlaybackSourceSnapshot(
            bundleIdentifier: bundleID,
            title: title,
            subtitle: subtitle,
            artwork: resolvedArtwork,
            usesAppIconAsArtwork: usesAppIcon,
            isPlaying: state.isPlaying,
            lastSeen: Date()
        )

        if let existingIndex {
            playbackSources[existingIndex] = snapshot
        } else {
            playbackSources.append(snapshot)
        }

        let runningBundleIdentifiers = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )
        playbackSources.removeAll {
            !runningBundleIdentifiers.contains($0.bundleIdentifier)
        }
        playbackSources.sort { lhs, rhs in
            let lhsIsQQMusic = lhs.bundleIdentifier == qqMusicBundleIdentifier
            let rhsIsQQMusic = rhs.bundleIdentifier == qqMusicBundleIdentifier
            if lhsIsQQMusic != rhsIsQQMusic { return lhsIsQQMusic }
            if lhs.bundleIdentifier == bundleID { return true }
            if rhs.bundleIdentifier == bundleID { return false }
            if lhs.isPlaying != rhs.isPlaying { return lhs.isPlaying }
            return lhs.lastSeen > rhs.lastSeen
        }
        if playbackSources.count > 4 {
            playbackSources = Array(playbackSources.prefix(4))
        }
    }

    var hasMultiplePlaybackSources: Bool {
        playbackSources.count >= 2
    }

    @MainActor
    private func pruneInactivePlaybackSources() {
        let now = Date()
        let activeBundleIdentifier = bundleIdentifier
        playbackSources.removeAll { source in
            guard NSWorkspace.shared.runningApplications.contains(where: {
                $0.bundleIdentifier == source.bundleIdentifier
            }) else { return true }

            // QQ Music is the preferred player. Keep its last known snapshot
            // while the app is open, even when paused, so it remains the first
            // row and becomes the single-player view after other audio stops.
            if source.bundleIdentifier == qqMusicBundleIdentifier {
                return false
            }

            if source.bundleIdentifier == activeBundleIdentifier {
                return false
            }

            // Keep a newly discovered source briefly so the two-row transition
            // does not flicker. Afterwards, retain it only while that process is
            // still producing audio. When it stops, the UI falls back to one row.
            let recentlySeen = now.timeIntervalSince(source.lastSeen) < 8
            return !recentlySeen && !isAudioOutputRunning(
                bundleIdentifier: source.bundleIdentifier
            )
        }
    }

    private func isAudioOutputRunning(bundleIdentifier: String) -> Bool {
        guard let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first else { return false }

        var pid = application.processIdentifier
        var processObjectID = kAudioObjectUnknown
        var processObjectSize = UInt32(MemoryLayout<AudioObjectID>.size)
        var translateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let translateStatus = withUnsafePointer(to: &pid) { pidPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &translateAddress,
                UInt32(MemoryLayout<pid_t>.size),
                pidPointer,
                &processObjectSize,
                &processObjectID
            )
        }
        guard translateStatus == noErr, processObjectID != kAudioObjectUnknown else {
            return false
        }

        var isRunningOutput: UInt32 = 0
        var runningOutputSize = UInt32(MemoryLayout<UInt32>.size)
        var runningOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(processObjectID, &runningOutputAddress) else {
            return false
        }
        let status = AudioObjectGetPropertyData(
            processObjectID,
            &runningOutputAddress,
            0,
            nil,
            &runningOutputSize,
            &isRunningOutput
        )
        return status == noErr && isRunningOutput != 0
    }

    func openMusicApp(bundleIdentifier: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else { return }
        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    func togglePlayback(for bundleIdentifier: String) {
        let sourceIsPlaying = playbackSources.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        })?.isPlaying

        // QQ Music is pinned to the first row, so its UI position is no longer
        // evidence that it is also macOS's current Now Playing client. Always
        // use QQ Music's own app-scoped Accessibility command and never the
        // global controller, even when the bundle identifiers happen to match.
        if bundleIdentifier != qqMusicBundleIdentifier,
           bundleIdentifier == self.bundleIdentifier {
            togglePlay()
            updateCachedPlaybackState(for: bundleIdentifier, toggled: true)
            return
        }

        Task { [weak self] in
            guard let self,
                  await self.runSourceCommand(
                      for: bundleIdentifier,
                      kind: .togglePlay,
                      sourceIsPlaying: sourceIsPlaying
                  )
            else { return }

            await MainActor.run {
                self.updateCachedPlaybackState(
                    for: bundleIdentifier,
                    toggled: true
                )
            }
        }
    }

    func nextTrack(for bundleIdentifier: String) {
        if bundleIdentifier != qqMusicBundleIdentifier,
           bundleIdentifier == self.bundleIdentifier {
            nextTrack()
            return
        }
        Task { [weak self] in
            guard let self else { return }
            _ = await self.runSourceCommand(
                for: bundleIdentifier,
                kind: .nextTrack,
                sourceIsPlaying: nil
            )
        }
    }

    @MainActor
    private func updateCachedPlaybackState(for bundleIdentifier: String, toggled: Bool) {
        guard toggled,
              let index = playbackSources.firstIndex(where: {
                  $0.bundleIdentifier == bundleIdentifier
              })
        else { return }
        playbackSources[index].isPlaying.toggle()
    }

    private enum SourceCommand {
        case togglePlay
        case nextTrack
    }

    private func runSourceCommand(
        for bundleIdentifier: String,
        kind: SourceCommand,
        sourceIsPlaying: Bool?
    ) async -> Bool {
        if bundleIdentifier == "com.apple.Music" {
            let command = kind == .togglePlay ? "playpause" : "next track"
            do {
                try await AppleScriptHelper.executeVoid(
                    "tell application \"Music\" to \(command)"
                )
                return true
            } catch {
                NSLog("Apple Music source command failed: %@", error.localizedDescription)
                return false
            }
        }

        if bundleIdentifier == "com.spotify.client" {
            let command = kind == .togglePlay ? "playpause" : "next track"
            do {
                try await AppleScriptHelper.executeVoid(
                    "tell application \"Spotify\" to \(command)"
                )
                return true
            } catch {
                NSLog("Spotify source command failed: %@", error.localizedDescription)
                return false
            }
        }

        // Never fall back to a global media command for a non-current row: on
        // macOS it is redirected to the system's current Now Playing client and
        // can pause QQ Music instead. Accessibility keeps the command inside the
        // intended app. If no matching control is exposed, safely do nothing.
        return performAccessibilitySourceCommand(
            bundleIdentifier: bundleIdentifier,
            kind: kind,
            sourceIsPlaying: sourceIsPlaying
        )
    }

    private func performAccessibilitySourceCommand(
        bundleIdentifier: String,
        kind: SourceCommand,
        sourceIsPlaying: Bool?
    ) -> Bool {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(
                  withBundleIdentifier: bundleIdentifier
              ).first
        else { return false }

        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
        let acceptedTitles: [String]
        if bundleIdentifier == qqMusicBundleIdentifier, kind == .togglePlay {
            // QQ Music stays pinned after another source becomes the system Now
            // Playing client, so the row's cached state can legitimately be
            // stale. Its native menu item is an exact, app-scoped action; accept
            // both possible titles and let QQ Music perform the actual toggle.
            acceptedTitles = [
                "播放", "暂停", "播放/暂停", "播放或暂停",
                "Play", "Pause", "Play/Pause", "Play or Pause"
            ]
        } else {
            acceptedTitles = accessibilityActionTitles(
                for: kind,
                sourceIsPlaying: sourceIsPlaying
            )
        }

        // Native players such as QQ Music commonly expose their commands as
        // menu items. This path also works for a browser if it supplies a media
        // command in its own menu.
        var menuBarValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            applicationElement,
            kAXMenuBarAttribute as CFString,
            &menuBarValue
        ) == .success,
           let menuBarValue,
           CFGetTypeID(menuBarValue) == AXUIElementGetTypeID()
        {
            let menuBar = unsafeBitCast(menuBarValue, to: AXUIElement.self)
            if let menuItem = findAccessibilityMenuItem(
                in: menuBar,
                acceptedTitles: acceptedTitles,
                depth: 0
            ), AXUIElementPerformAction(
                menuItem,
                kAXPressAction as CFString
            ) == .success {
                NSLog("Accessibility menu command succeeded for %@", bundleIdentifier)
                return true
            }
        }

        // Chromium/Electron apps normally expose the visible page/player
        // controls as AX buttons rather than menu items. Search only this app's
        // windows and require a state-specific label (Play versus Pause).
        var roots: [AXUIElement] = []
        var focusedWindowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        ) == .success,
           let focusedWindowValue,
           CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID()
        {
            roots.append(unsafeBitCast(focusedWindowValue, to: AXUIElement.self))
        }

        var windowsValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            applicationElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        ) == .success,
           let windows = windowsValue as? [AXUIElement]
        {
            roots.append(contentsOf: windows)
        }

        var remainingNodes = 4_000
        for root in roots {
            if performMatchingAccessibilityAction(
                in: root,
                acceptedTitles: acceptedTitles,
                depth: 0,
                remainingNodes: &remainingNodes
            ) {
                NSLog("Accessibility window command succeeded for %@", bundleIdentifier)
                return true
            }
            if remainingNodes <= 0 { break }
        }

        NSLog("No safe app-specific media control found for %@", bundleIdentifier)
        return false
    }

    private func accessibilityActionTitles(
        for kind: SourceCommand,
        sourceIsPlaying: Bool?
    ) -> [String] {
        switch kind {
        case .togglePlay:
            let toggleTitles = [
                "播放/暂停", "播放或暂停", "Play/Pause", "Play or Pause"
            ]
            if sourceIsPlaying == true {
                return [
                    "暂停", "暂停播放", "点击暂停", "Pause", "Pause video"
                ] + toggleTitles
            }
            if sourceIsPlaying == false {
                return [
                    "播放", "继续播放", "播放视频", "点击播放", "Play", "Play video"
                ] + toggleTitles
            }
            return toggleTitles
        case .nextTrack:
            return [
                "下一首", "下一曲", "下一个", "下一条视频",
                "Next", "Next Track", "Next video"
            ]
        }
    }

    private func performMatchingAccessibilityAction(
        in element: AXUIElement,
        acceptedTitles: [String],
        depth: Int,
        remainingNodes: inout Int
    ) -> Bool {
        guard depth < 24, remainingNodes > 0 else { return false }
        remainingNodes -= 1

        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleValue
        )
        let role = roleValue as? String
        let actionableRoles = [
            kAXButtonRole as String,
            kAXMenuItemRole as String,
            "AXLink"
        ]

        if let role, actionableRoles.contains(role) {
            var enabledValue: CFTypeRef?
            AXUIElementCopyAttributeValue(
                element,
                kAXEnabledAttribute as CFString,
                &enabledValue
            )
            let isEnabled = (enabledValue as? Bool) ?? true
            if isEnabled {
                let labelAttributes = [
                    kAXTitleAttribute,
                    kAXDescriptionAttribute,
                    kAXHelpAttribute,
                    kAXValueAttribute
                ]
                let labels = labelAttributes.compactMap { attribute -> String? in
                    var value: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(
                        element,
                        attribute as CFString,
                        &value
                    ) == .success else { return nil }
                    return value as? String
                }

                if labels.contains(where: {
                    accessibilityLabel($0, matchesAny: acceptedTitles)
                }), AXUIElementPerformAction(
                    element,
                    kAXPressAction as CFString
                ) == .success {
                    return true
                }
            }
        }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenValue
        ) == .success,
              let children = childrenValue as? [AXUIElement]
        else { return false }

        for child in children {
            if performMatchingAccessibilityAction(
                in: child,
                acceptedTitles: acceptedTitles,
                depth: depth + 1,
                remainingNodes: &remainingNodes
            ) {
                return true
            }
            if remainingNodes <= 0 { break }
        }
        return false
    }

    private func accessibilityLabel(
        _ label: String,
        matchesAny acceptedTitles: [String]
    ) -> Bool {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        return acceptedTitles.contains { acceptedTitle in
            if normalized.caseInsensitiveCompare(acceptedTitle) == .orderedSame {
                return true
            }

            // Web players often append their shortcut, for example
            // "Pause (k)" or "播放 (k)". Match that suffix without accepting
            // unrelated controls such as playlists or playback-speed menus.
            let lowered = normalized.lowercased()
            let accepted = acceptedTitle.lowercased()
            return lowered.hasPrefix(accepted + " (")
                || lowered.hasPrefix(accepted + "（")
        }
    }

    private func findAccessibilityMenuItem(
        in element: AXUIElement,
        acceptedTitles: [String],
        depth: Int
    ) -> AXUIElement? {
        guard depth < 10 else { return nil }

        var roleValue: CFTypeRef?
        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleValue
        )
        AXUIElementCopyAttributeValue(
            element,
            kAXTitleAttribute as CFString,
            &titleValue
        )

        if let role = roleValue as? String,
           role == (kAXMenuItemRole as String),
           let title = titleValue as? String
        {
            let normalizedTitle = title.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if acceptedTitles.contains(where: {
                normalizedTitle.caseInsensitiveCompare($0) == .orderedSame
            }) {
                return element
            }
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

    func toggleFavoriteTrack() {
        guard canFavoriteTrack || bundleIdentifier == "com.tencent.QQMusicMac" else { return }
        // Toggle based on current state
        setFavorite(!isFavoriteTrack)
    }

    @MainActor
    private func toggleAppleMusicFavorite() async {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
        guard !runningApps.isEmpty else { return }

        let script = """
        tell application \"Music\"
            if it is running then
                try
                    set loved of current track to (not loved of current track)
                    return loved of current track
                on error
                    return false
                end try
            else
                return false
            end if
        end tell
        """

        if let result = try? await AppleScriptHelper.execute(script) {
            let loved = result.booleanValue
            self.isFavoriteTrack = loved
            self.forceUpdate()
        }
    }

    func setFavorite(_ favorite: Bool) {
        guard canFavoriteTrack else { return }
        guard let controller = activeController else { return }

        Task { @MainActor in
            await controller.setFavorite(favorite)
            try? await Task.sleep(for: .milliseconds(150))
            await controller.updatePlaybackInfo()
        }
    }

    /// Placeholder dislike function
    func dislikeCurrentTrack() {
        setFavorite(false)
    }

    // MARK: - Lyrics
    private func fetchLyricsIfAvailable(bundleIdentifier: String?, title: String, artist: String) {
        guard Defaults[.enableLyrics], !title.isEmpty else {
            DispatchQueue.main.async {
                self.isFetchingLyrics = false
                self.currentLyrics = ""
            }
            return
        }

        // Prefer native Apple Music lyrics when available
        if let bundleIdentifier = bundleIdentifier, bundleIdentifier.contains("com.apple.Music") {
            Task { @MainActor in
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
                guard !runningApps.isEmpty else {
                    await self.fetchLyricsFromWeb(title: title, artist: artist)
                    return
                }

                self.isFetchingLyrics = true
                self.currentLyrics = ""
                do {
                    let script = """
                    tell application \"Music\"
                        if it is running then
                            if player state is playing or player state is paused then
                                try
                                    set l to lyrics of current track
                                    if l is missing value then
                                        return \"\"
                                    else
                                        return l
                                    end if
                                on error
                                    return \"\"
                                end try
                            else
                                return \"\"
                            end if
                        else
                            return \"\"
                        end if
                    end tell
                    """
                    if let result = try await AppleScriptHelper.execute(script), let lyricsString = result.stringValue, !lyricsString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.currentLyrics = lyricsString.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.isFetchingLyrics = false
                        self.syncedLyrics = []
                        return
                    }
                } catch {
                    // fall through to web lookup
                }
                await self.fetchLyricsFromWeb(title: title, artist: artist)
            }
        } else {
            Task { @MainActor in
                self.isFetchingLyrics = true
                self.currentLyrics = ""
                await self.fetchLyricsFromWeb(title: title, artist: artist)
            }
        }
    }

    private func normalizedQuery(_ string: String) -> String {
        string
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "\u{FFFD}", with: "")
    }

    @MainActor
    private func fetchLyricsFromWeb(title: String, artist: String) async {
        let cleanTitle = normalizedQuery(title)
        let cleanArtist = normalizedQuery(artist)
        guard let encodedTitle = cleanTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedArtist = cleanArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            self.currentLyrics = ""
            self.isFetchingLyrics = false
            return
        }

        // LRCLIB simple search (no auth): https://lrclib.net/api/search?track_name=...&artist_name=...
        let urlString = "https://lrclib.net/api/search?track_name=\(encodedTitle)&artist_name=\(encodedArtist)"
        guard let url = URL(string: urlString) else {
            self.currentLyrics = ""
            self.isFetchingLyrics = false
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                self.currentLyrics = ""
                self.isFetchingLyrics = false
                return
            }
            if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let first = jsonArray.first {
                // Prefer plain lyrics (syncedLyrics may also be present)
                let plain = (first["plainLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let synced = (first["syncedLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let resolved = plain.isEmpty ? synced : plain
                self.currentLyrics = resolved
                self.isFetchingLyrics = false
                if !synced.isEmpty {
                    self.syncedLyrics = self.parseLRC(synced)
                } else {
                    self.syncedLyrics = []
                }
            } else {
                self.currentLyrics = ""
                self.isFetchingLyrics = false
                self.syncedLyrics = []
            }
        } catch {
            self.currentLyrics = ""
            self.isFetchingLyrics = false
            self.syncedLyrics = []
        }
    }

    // MARK: - Synced lyrics helpers
    private func parseLRC(_ lrc: String) -> [(time: Double, text: String)] {
        var result: [(Double, String)] = []
        lrc.split(separator: "\n").forEach { lineSub in
            let line = String(lineSub)
            // Match [mm:ss.xx] or [m:ss]
            let pattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,2}))?\]"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let nsLine = line as NSString
            if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) {
                let minStr = nsLine.substring(with: match.range(at: 1))
                let secStr = nsLine.substring(with: match.range(at: 2))
                let csRange = match.range(at: 3)
                let centiStr = csRange.location != NSNotFound ? nsLine.substring(with: csRange) : "0"
                let minutes = Double(minStr) ?? 0
                let seconds = Double(secStr) ?? 0
                let centis = Double(centiStr) ?? 0
                let time = minutes * 60 + seconds + centis / 100.0
                let textStart = match.range.location + match.range.length
                let text = nsLine.substring(from: textStart).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    result.append((time, text))
                }
            }
        }
        return result.sorted { $0.0 < $1.0 }
    }

    func lyricLine(at elapsed: Double) -> String {
        guard !syncedLyrics.isEmpty else { return currentLyrics }
        // Binary search for last line with time <= elapsed
        var low = 0
        var high = syncedLyrics.count - 1
        var idx = 0
        while low <= high {
            let mid = (low + high) / 2
            if syncedLyrics[mid].time <= elapsed {
                idx = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return syncedLyrics[idx].text
    }

    private func triggerFlipAnimation() {
        // Cancel any existing animation
        flipWorkItem?.cancel()

        // Create a new animation
        let workItem = DispatchWorkItem { [weak self] in
            self?.isFlipping = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.isFlipping = false
            }
        }

        flipWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func updateArtwork(_ artworkData: Data) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let artworkImage = NSImage(data: artworkData) {
                DispatchQueue.main.async { [weak self] in
                    self?.usingAppIconForArtwork = false
                    self?.updateAlbumArt(newAlbumArt: artworkImage)
                }
            }
        }
    }

    private func updateIdleState(state: Bool) {
        if state {
            isPlayerIdle = false
            debounceIdleTask?.cancel()
        } else {
            debounceIdleTask?.cancel()
            debounceIdleTask = Task { [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(for: .seconds(Defaults[.waitInterval]))
                withAnimation {
                    self.isPlayerIdle = !self.isPlaying
                }
            }
        }
    }

    private var workItem: DispatchWorkItem?

    func updateAlbumArt(newAlbumArt: NSImage) {
        workItem?.cancel()
        withAnimation(.smooth) {
            self.albumArt = newAlbumArt
            if Defaults[.coloredSpectrogram] {
                self.calculateAverageColor()
            }
        }
    }

    // MARK: - Playback Position Estimation
    public func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return min(elapsedTime, songDuration) }

        let timeDifference = date.timeIntervalSince(timestampDate)
        let estimated = elapsedTime + (timeDifference * playbackRate)
        return min(max(0, estimated), songDuration)
    }

    func calculateAverageColor() {
        albumArt.averageColor { [weak self] color in
            DispatchQueue.main.async {
                withAnimation(.smooth) {
                    self?.avgColor = color ?? .white
                }
            }
        }
    }

    private func updateSneakPeek() {
        if isPlaying && Defaults[.enableSneakPeek] {
            if Defaults[.sneakPeekStyles] == .standard {
                coordinator.toggleSneakPeek(status: true, type: .music, duration: 3.0)
            } else {
                coordinator.toggleExpandingView(status: true, type: .music)
            }
        }
    }

    // MARK: - Public Methods for controlling playback
    func playPause() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func play() {
        Task {
            await activeController?.play()
        }
    }

    func pause() {
        Task {
            await activeController?.pause()
        }
    }

    func toggleShuffle() {
        Task {
            await activeController?.toggleShuffle()
        }
    }

    func toggleRepeat() {
        Task {
            await activeController?.toggleRepeat()
        }
    }
    
    func togglePlay() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func nextTrack() {
        Task {
            await activeController?.nextTrack()
        }
    }

    func previousTrack() {
        Task {
            await activeController?.previousTrack()
        }
    }

    func seek(to position: TimeInterval) {
        Task {
            await activeController?.seek(to: position)
        }
    }
    func skip(seconds: TimeInterval) {
        let newPos = min(max(0, elapsedTime + seconds), songDuration)
        seek(to: newPos)
    }
    
    func setVolume(to level: Double) {
        if let controller = activeController {
            Task {
                await controller.setVolume(level)
            }
        }
    }
    func openMusicApp() {
        guard let bundleID = bundleIdentifier else {
            print("Error: appBundleIdentifier is nil")
            return
        }

        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { (app, error) in
                if let error = error {
                    print("Failed to launch app with bundle ID: \(bundleID), error: \(error)")
                } else {
                    print("Launched app with bundle ID: \(bundleID)")
                }
            }
        } else {
            print("Failed to find app with bundle ID: \(bundleID)")
        }
    }

    func forceUpdate() {
        // Request immediate update from the active controller
        Task { [weak self] in
            if self?.activeController?.isActive() == true {
                if let youtubeController = self?.activeController as? YouTubeMusicController {
                    await youtubeController.pollPlaybackState()
                } else {
                    await self?.activeController?.updatePlaybackInfo()
                }
            }
        }
    }
    
    
    func syncVolumeFromActiveApp() async {
        // Check if bundle identifier is valid and if the app is actually running
        guard let bundleID = bundleIdentifier, !bundleID.isEmpty,
              NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleID }) else { return }
        
        var script: String?
        if bundleID == "com.apple.Music" {
            script = """
            tell application "Music"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else if bundleID == "com.spotify.client" {
            script = """
            tell application "Spotify"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else {
            // For unsupported apps, don't sync volume
            return
        }
        
        if let volumeScript = script,
           let result = try? await AppleScriptHelper.execute(volumeScript) {
            let volumeValue = result.int32Value
            let currentVolume = Double(volumeValue) / 100.0
            
            await MainActor.run {
                if abs(currentVolume - self.volume) > 0.01 {
                    self.volume = currentVolume
                }
            }
        }
    }
}
