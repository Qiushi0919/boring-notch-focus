//
//  Constants.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 10. 17..
//

import SwiftUI
import Defaults

enum AppLanguage: String, CaseIterable, Identifiable {
    static let storageKey = "appLanguage"

    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return AppL10n.text("Follow System")
        case .simplifiedChinese:
            return "简体中文"
        case .english:
            return "English"
        }
    }

    var languageIdentifiers: [String]? {
        switch self {
        case .system:
            return nil
        case .simplifiedChinese:
            return ["zh-Hans"]
        case .english:
            return ["en"]
        }
    }
}

enum AppL10n {
    static var selectedLanguage: AppLanguage {
        guard
            let rawValue = UserDefaults.standard.string(forKey: AppLanguage.storageKey),
            let language = AppLanguage(rawValue: rawValue)
        else {
            return .system
        }
        return language
    }

    private static var usesSimplifiedChinese: Bool {
        switch selectedLanguage {
        case .simplifiedChinese:
            return true
        case .english:
            return false
        case .system:
            break
        }
        guard let language = Locale.preferredLanguages.first?.lowercased() else { return false }
        return language.hasPrefix("zh-hans") || language.hasPrefix("zh-cn")
    }

    static func setLanguage(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
        if let identifiers = language.languageIdentifiers {
            UserDefaults.standard.set(identifiers, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }

    private static let simplifiedChinese: [String: String] = [
        // Settings navigation and common actions
        "General": "通用",
        "Appearance": "外观",
        "Media": "媒体",
        "Calendar": "日历",
        "Focus Timer": "番茄钟",
        "HUDs": "系统浮窗",
        "Battery": "电池",
        "Shelf": "文件架",
        "Shortcuts": "快捷键",
        "Advanced": "高级",
        "About": "关于",
        "Version": "版本",
        "Permissions": "权限中心",
        "Settings": "设置",
        "Restart Boring Notch Focus": "重新启动 Boring Notch Focus",
        "Quit": "退出",

        // General settings
        "Show menu bar icon": "显示菜单栏图标",
        "Launch at login": "登录时启动",
        "Show on all displays": "在所有显示器上显示",
        "Preferred display": "首选显示器",
        "Automatically switch displays": "自动切换显示器",
        "System features": "系统功能",
        "Notch height on notch displays": "刘海屏上的灵动岛高度",
        "Notch height on non-notch displays": "非刘海屏上的灵动岛高度",
        "Match real notch height": "匹配真实刘海高度",
        "Match menu bar height": "匹配菜单栏高度",
        "Match menubar height": "匹配菜单栏高度",
        "Custom height": "自定义高度",
        "Notch sizing": "灵动岛尺寸",
        "Quit app": "退出应用",
        "Enable gestures": "启用手势",
        "Change media with horizontal gestures": "横向手势切换媒体",
        "Close gesture": "关闭手势",
        "Gesture sensitivity": "手势灵敏度",
        "High": "高",
        "Medium": "中",
        "Low": "低",
        "Gesture control": "手势控制",
        "Open notch on hover": "悬停时打开灵动岛",
        "Enable haptic feedback": "启用触觉反馈",
        "Remember last tab": "记住上次打开的标签页",
        "Hover delay": "悬停延迟",
        "Language": "语言",
        "Follow System": "跟随系统",
        "Changing the language restarts the app automatically.": "切换语言后，应用会自动重新启动。",

        // First launch and permissions
        "Welcome": "欢迎",
        "Get started": "开始设置",
        "Choose your language": "选择语言",
        "You can change this later in Settings.": "稍后可以在设置中更改。",
        "Continue": "继续",
        "Permission Center": "权限中心",
        "Grant only the permissions needed by the features you use. You can change them later in System Settings.": "只需授予你所使用功能需要的权限，之后可以随时在系统设置中更改。",
        "Refresh Status": "重新检测",
        "Request Access": "请求权限",
        "Open Settings": "打开设置",
        "Allowed": "已允许",
        "Not Requested": "未请求",
        "Not Allowed": "未允许",
        "Requested When Used": "使用时询问",
        "Calendar Access": "日历权限",
        "Shows your upcoming events in the calendar area.": "在日历区域显示即将开始的日程。",
        "Reminders Access": "提醒事项权限",
        "Shows scheduled reminders together with calendar events.": "将有日期的提醒事项与日历日程一起显示。",
        "QQ Music Controls": "QQ 音乐控制",
        "Accessibility access lets the heart button control QQ Music.": "辅助功能权限用于让红心按钮控制 QQ 音乐收藏。",
        "System HUD Controls": "系统浮窗控制",
        "The helper needs Accessibility access only when replacing the macOS volume and brightness HUD.": "仅在替换 macOS 音量和亮度浮窗时，辅助程序需要辅助功能权限。",
        "Notifications": "通知",
        "Shows an alert when a focus or break session ends.": "在专注或休息阶段结束时发送提醒。",
        "Camera Access": "相机权限",
        "Optional. Used only for the notch mirror preview.": "可选，仅用于灵动岛镜子预览。",
        "Music Automation": "音乐自动化",
        "macOS asks when the app first controls Apple Music or Spotify. QQ Music uses Accessibility instead.": "首次控制 Apple Music 或 Spotify 时，macOS 会询问；QQ 音乐使用辅助功能权限。",
        "If macOS blocks the app before it opens, go to System Settings → Privacy & Security and choose Open Anyway.": "如果 macOS 在应用打开前进行拦截，请前往“系统设置 → 隐私与安全性”，选择“仍要打开”。",
        "Choose a Music Source": "选择音乐来源",
        "Select the music source you want to use. You can change this later in the app settings.": "选择要使用的音乐来源，稍后可以在应用设置中更改。",
        "Works with most media apps, including browsers, to detect what's playing. Note: This may be removed in a future macOS version.": "可识别大多数音乐应用和浏览器中正在播放的内容。此接口未来可能被 macOS 移除。",
        "Connects directly to the Spotify app.": "直接连接 Spotify 应用。",
        "Connects directly to the Apple Music app.": "直接连接 Apple Music 应用。",
        "Requires a third-party client with API plugin enabled.": "需要启用了 API 插件的第三方客户端。",
        "You're All Set!": "设置完成！",
        "You can now enjoy the app. If you want to tweak things further, you can always visit the settings.": "现在可以开始使用了，之后仍可随时进入设置进行调整。",
        "Customize in Settings": "进入设置继续调整",
        "Finish": "完成",
        "Not Now": "暂不",
        "Allow Access": "允许访问",

        // Focus timer
        "Home": "主页",
        "Focus": "专注",
        "Break": "休息",
        "%lld completed": "已完成 %lld 次",
        "RUNNING": "计时中",
        "READY": "准备就绪",
        "Pause": "暂停",
        "Start": "开始",
        "Reset": "重置",
        "Skip": "跳过",
        "Enable focus timer": "启用番茄钟",
        "Adds a timer tab to the notch.": "在灵动岛中添加番茄钟标签页。",
        "Focus duration": "专注时长",
        "Break duration": "休息时长",
        "%lld min": "%lld 分钟",
        "Automatically start the next session": "自动开始下一阶段",
        "Timing": "计时设置",
        "Changing a duration resets the current session when the timer is paused.": "暂停计时后修改时长，会重置当前阶段。",
        "Show countdown in the closed notch": "灵动岛收起时显示倒计时",
        "Notify when a session ends": "阶段结束时通知",
        "Feedback": "提醒",
        "Completed focus sessions": "已完成的专注次数",
        "Reset timer and session count": "重置计时器和完成次数",
        "Focus session complete": "专注阶段已完成",
        "Break complete": "休息结束",
        "Nice work. Time for a short break.": "做得不错，休息一下吧。",
        "Ready for another focus session?": "准备好开始下一轮专注了吗？",
        "Add to Favorites": "收藏当前歌曲",
        "Remove from Favorites": "取消收藏当前歌曲",
        "Play": "播放",
        "Next Track": "下一首",

        // Shelf settings and context menus
        "Enable shelf": "启用文件架",
        "Open shelf by default if items are present": "有文件时默认打开文件架",
        "Expanded drag detection area": "扩大拖放检测区域",
        "Copy items on drag": "拖出时复制项目",
        "Remove from shelf after dragging": "拖出后从文件架移除",
        "Quick Share Service": "快速分享服务",
        "Quick Share": "快速分享",
        "Currently selected: %@": "当前选择：%@",
        "Files dropped on the shelf will be shared via this service": "拖到文件架的文件将通过此服务分享",
        "Choose which service to use when sharing files from the shelf. Click the shelf button to select files, or drag files onto it to share immediately.": "选择文件架使用的分享服务。点击文件架按钮选择文件，或将文件拖入后立即分享。",
        "Open": "打开",
        "Open With": "打开方式",
        "No Compatible Apps Found": "未找到兼容的应用",
        "Other…": "其他…",
        " (default)": "（默认）",
        "Show in Finder": "在访达中显示",
        "Quick Look": "快速查看",
        "Share…": "分享…",
        "Image Actions": "图像操作",
        "Remove Background": "移除背景",
        "Convert Image…": "转换图像…",
        "Create PDF": "创建 PDF",
        "Compress": "压缩",
        "Rename": "重命名",
        "Copy": "复制",
        "Copy Path": "复制路径",
        "Remove": "移除",
        "Delete Selected": "移除所选项目",
        "Clear Shelf": "清空文件架",
        "Select item": "选择项目",
        "Deselect item": "取消选择项目",
        "Choose Application": "选择应用",
        "Choose an application to open the document \"%@\".": "选择用于打开“%@”的应用。",
        "Enable:": "启用：",
        "Recommended Applications": "推荐的应用",
        "All Applications": "所有应用",
        "Always Open With": "始终用此应用打开",
        "Rename File": "重命名文件",
        "Background Removal Failed": "移除背景失败",
        "PDF Creation Failed": "创建 PDF 失败",
        "Convert Image": "转换图像",
        "Convert": "转换",
        "Cancel": "取消",
        "Format:": "格式：",
        "Image Size:": "图像尺寸：",
        "Actual Size": "实际尺寸",
        "Large": "大",
        "Small": "小",
        "Custom...": "自定义…",
        "Preserve Metadata": "保留元数据",
        "Compression:": "压缩质量：",
        "Image Conversion Failed": "图像转换失败",
        "OK": "好",

        // About
        "Automatic updates are disabled for this custom focus-timer build.": "此番茄钟定制版已关闭自动更新。",
        "Updates are delivered automatically from the Boring Notch Focus release channel.": "更新将通过 Boring Notch Focus 发布通道自动推送。",
        "Custom build": "定制版本"
    ]

    static func text(_ english: String) -> String {
        guard usesSimplifiedChinese else { return english }
        return simplifiedChinese[english] ?? english
    }

    static func format(_ englishFormat: String, _ arguments: CVarArg...) -> String {
        String(
            format: text(englishFormat),
            locale: Locale.current,
            arguments: arguments
        )
    }
}

private let availableDirectories = FileManager
    .default
    .urls(for: .documentDirectory, in: .userDomainMask)
let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

let temporaryDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
let spacing: CGFloat = 16

struct CustomVisualizer: Codable, Hashable, Equatable, Defaults.Serializable {
    let UUID: UUID
    var name: String
    var url: URL
    var speed: CGFloat = 1.0
}

enum CalendarSelectionState: Codable, Defaults.Serializable {
    case all
    case selected(Set<String>)
}

enum HideNotchOption: String, Defaults.Serializable {
    case always
    case nowPlayingOnly
    case never
}

// Define notification names at file scope
extension Notification.Name {
    static let mediaControllerChanged = Notification.Name("mediaControllerChanged")
}

// Media controller types for selection in settings
enum MediaControllerType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case nowPlaying = "Now Playing"
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case youtubeMusic = "YouTube Music"
    
    var id: String { self.rawValue }
}

// Sneak peek styles for selection in settings
enum SneakPeekStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case standard = "Default"
    case inline = "Inline"
    
    var id: String { self.rawValue }
}

// Action to perform when Option (⌥) is held while pressing media keys
enum OptionKeyAction: String, CaseIterable, Identifiable, Defaults.Serializable {
    case openSettings = "Open System Settings"
    case showHUD = "Show HUD"
    case none = "No Action"

    var id: String { self.rawValue }
}

extension Defaults.Keys {
    // MARK: General
    // Distribution defaults captured from the maintainer's preferred setup.
    static let menubarIcon = Key<Bool>("menubarIcon", default: false)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: true)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: true)
    static let releaseName = Key<String>("releaseName", default: "Focus Timer 🍅")
    
    // MARK: Behavior
    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
    static let extendHoverArea = Key<Bool>("extendHoverArea", default: false)
    static let notchHeightMode = Key<WindowHeightMode>(
        "notchHeightMode",
        default: WindowHeightMode.matchRealNotchSize
    )
    static let nonNotchHeightMode = Key<WindowHeightMode>(
        "nonNotchHeightMode",
        default: WindowHeightMode.matchMenuBar
    )
    static let nonNotchHeight = Key<CGFloat>("nonNotchHeight", default: 32)
    static let notchHeight = Key<CGFloat>("notchHeight", default: 32)
    //static let openLastTabByDefault = Key<Bool>("openLastTabByDefault", default: false)
    static let showOnLockScreen = Key<Bool>("showOnLockScreen", default: false)
    static let hideFromScreenRecording = Key<Bool>("hideFromScreenRecording", default: false)
    
    // MARK: Appearance
    static let showEmojis = Key<Bool>("showEmojis", default: false)
    //static let alwaysShowTabs = Key<Bool>("alwaysShowTabs", default: true)
    static let showMirror = Key<Bool>("showMirror", default: false)
    static let mirrorShape = Key<MirrorShapeEnum>("mirrorShape", default: MirrorShapeEnum.rectangle)
    static let settingsIconInNotch = Key<Bool>("settingsIconInNotch", default: true)
    static let lightingEffect = Key<Bool>("lightingEffect", default: true)
    static let enableShadow = Key<Bool>("enableShadow", default: true)
    static let cornerRadiusScaling = Key<Bool>("cornerRadiusScaling", default: true)

    static let showNotHumanFace = Key<Bool>("showNotHumanFace", default: false)
    static let tileShowLabels = Key<Bool>("tileShowLabels", default: false)
    static let showCalendar = Key<Bool>("showCalendar", default: true)
    static let hideCompletedReminders = Key<Bool>("hideCompletedReminders", default: true)
    static let sliderColor = Key<SliderColorEnum>(
        "sliderUseAlbumArtColor",
        default: SliderColorEnum.white
    )
    static let playerColorTinting = Key<Bool>("playerColorTinting", default: true)
    static let useMusicVisualizer = Key<Bool>("useMusicVisualizer", default: true)
    static let customVisualizers = Key<[CustomVisualizer]>("customVisualizers", default: [])
    static let selectedVisualizer = Key<CustomVisualizer?>("selectedVisualizer", default: nil)

    // MARK: Pomodoro
    static let pomodoroEnabled = Key<Bool>("pomodoroEnabled", default: true)
    static let pomodoroFocusMinutes = Key<Int>("pomodoroFocusMinutes", default: 25)
    static let pomodoroBreakMinutes = Key<Int>("pomodoroBreakMinutes", default: 5)
    static let pomodoroAutoStartNextSession = Key<Bool>("pomodoroAutoStartNextSession", default: false)
    static let pomodoroShowLiveActivity = Key<Bool>("pomodoroShowLiveActivity", default: true)
    static let pomodoroNotificationsEnabled = Key<Bool>("pomodoroNotificationsEnabled", default: true)
    
    // MARK: Gestures
    static let enableGestures = Key<Bool>("enableGestures", default: true)
    static let closeGestureEnabled = Key<Bool>("closeGestureEnabled", default: true)
    static let gestureSensitivity = Key<CGFloat>("gestureSensitivity", default: 200.0)
    
    // MARK: Media playback
    static let coloredSpectrogram = Key<Bool>("coloredSpectrogram", default: true)
    static let enableSneakPeek = Key<Bool>("enableSneakPeek", default: true)
    static let sneakPeekStyles = Key<SneakPeekStyle>("sneakPeekStyles", default: .standard)
    static let waitInterval = Key<Double>("waitInterval", default: 3)
    static let showShuffleAndRepeat = Key<Bool>("showShuffleAndRepeat", default: false)
    static let enableLyrics = Key<Bool>("enableLyrics", default: false)
    static let musicControlSlots = Key<[MusicControlButton]>(
        "musicControlSlots",
        default: MusicControlButton.defaultLayout
    )
    static let musicControlSlotLimit = Key<Int>(
        "musicControlSlotLimit",
        default: MusicControlButton.defaultLayout.count
    )
    
    // MARK: Battery
    static let showPowerStatusNotifications = Key<Bool>("showPowerStatusNotifications", default: true)
    static let showBatteryIndicator = Key<Bool>("showBatteryIndicator", default: true)
    static let showBatteryPercentage = Key<Bool>("showBatteryPercentage", default: true)
    static let showPowerStatusIcons = Key<Bool>("showPowerStatusIcons", default: true)
    
    // MARK: Downloads
    static let enableDownloadListener = Key<Bool>("enableDownloadListener", default: true)
    static let enableSafariDownloads = Key<Bool>("enableSafariDownloads", default: true)
    static let selectedDownloadIndicatorStyle = Key<DownloadIndicatorStyle>("selectedDownloadIndicatorStyle", default: DownloadIndicatorStyle.progress)
    static let selectedDownloadIconStyle = Key<DownloadIconStyle>("selectedDownloadIconStyle", default: DownloadIconStyle.onlyAppIcon)
    
    // MARK: HUD
    static let hudReplacement = Key<Bool>("hudReplacement", default: false)
    static let inlineHUD = Key<Bool>("inlineHUD", default: false)
    static let enableGradient = Key<Bool>("enableGradient", default: false)
    static let systemEventIndicatorShadow = Key<Bool>("systemEventIndicatorShadow", default: false)
    static let systemEventIndicatorUseAccent = Key<Bool>("systemEventIndicatorUseAccent", default: false)
    static let showOpenNotchHUD = Key<Bool>("showOpenNotchHUD", default: true)
    static let showOpenNotchHUDPercentage = Key<Bool>("showOpenNotchHUDPercentage", default: true)
    static let showClosedNotchHUDPercentage = Key<Bool>("showClosedNotchHUDPercentage", default: false)
    // Option key modifier behaviour for media keys
    static let optionKeyAction = Key<OptionKeyAction>("optionKeyAction", default: OptionKeyAction.openSettings)
    
    // MARK: Shelf
    static let boringShelf = Key<Bool>("boringShelf", default: true)
    static let openShelfByDefault = Key<Bool>("openShelfByDefault", default: true)
    static let shelfTapToOpen = Key<Bool>("shelfTapToOpen", default: true)
    static let quickShareProvider = Key<String>("quickShareProvider", default: QuickShareProvider.defaultProvider.id)
    static let copyOnDrag = Key<Bool>("copyOnDrag", default: false)
    static let autoRemoveShelfItems = Key<Bool>("autoRemoveShelfItems", default: false)
    static let expandedDragDetection = Key<Bool>("expandedDragDetection", default: true)
    
    // MARK: Calendar
    static let calendarSelectionState = Key<CalendarSelectionState>("calendarSelectionState", default: .all)
    static let hideAllDayEvents = Key<Bool>("hideAllDayEvents", default: false)
    static let showFullEventTitles = Key<Bool>("showFullEventTitles", default: false)
    static let autoScrollToNextEvent = Key<Bool>("autoScrollToNextEvent", default: true)
    
    // MARK: Fullscreen Media Detection
    static let hideNotchOption = Key<HideNotchOption>("hideNotchOption", default: .nowPlayingOnly)
    
    // MARK: Media Controller
    static let mediaController = Key<MediaControllerType>("mediaController", default: .nowPlaying)
    
    // MARK: Advanced Settings
    static let useCustomAccentColor = Key<Bool>("useCustomAccentColor", default: false)
    static let customAccentColorData = Key<Data?>("customAccentColorData", default: nil)
    // Show or hide the title bar
    static let hideTitleBar = Key<Bool>("hideTitleBar", default: true)
    
    // Helper to determine the default media controller based on NowPlaying deprecation status
    static var defaultMediaController: MediaControllerType {
        if MusicManager.shared.isNowPlayingDeprecated {
            return .appleMusic
        } else {
            return .nowPlaying
        }
    }

    static let didClearLegacyURLCacheV1 = Key<Bool>("didClearLegacyURLCache_v1", default: false)
}
