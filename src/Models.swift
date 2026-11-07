import Foundation
import AppKit
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case en = "EN"
    case zh = "中文"
    
    var id: String { rawValue }
}

enum GameEdition: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case steam = "Steam"
    
    var id: String { rawValue }
}

struct DFMod: Identifiable, Hashable {
    let id: String
    let folderName: String
    let name: String
    let version: String
    let author: String
    let description: String
    let path: String
    let isVanilla: Bool
}

struct DFHackToggleItem: Identifiable {
    let id: String
    let titleEN: String
    let titleZH: String
    let subtitleEN: String
    let subtitleZH: String
    let command: String
    var isEnabled: Bool
}

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var language: AppLanguage = .en {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "df_launcher_lang")
            refreshAll()
        }
    }
    @Published var selectedTab: Int = 0
    @Published var showVanillaMods: Bool = false
    @Published var selectedEdition: GameEdition = .classic {
        didSet {
            UserDefaults.standard.set(selectedEdition.rawValue, forKey: "df_selected_edition")
            refreshAll()
        }
    }
    
    @Published var classicPath: String = ""
    @Published var steamPath: String = ""
    @Published var workshopPath: String = ""
    
    // Runtime status
    @Published var chipModelName: String = "Apple Silicon"
    @Published var isRosettaInstalled: Bool = false
    @Published var isWineReady: Bool = false
    @Published var isPrefixReady: Bool = false
    @Published var isInstallingEnvironment: Bool = false
    @Published var wineVersion: String = "Checking..."
    @Published var isDFHackInstalled: Bool = false
    @Published var isDFHackEnabled: Bool = false
    @Published var dfhackVersion: String = "Not Installed"
    @Published var isDFCNInstalled: Bool = false
    @Published var isDFCNEnabled: Bool = false
    @Published var isGameRunning: Bool = false
    @Published var statusMessage: String = "Ready"
    @Published var liveLogText: String = ""
    
    // Game Init Settings (init.txt)
    @Published var windowedMode: Bool = true
    @Published var windowWidth: String = "1280"
    @Published var windowHeight: String = "800"
    @Published var soundEnabled: Bool = true
    @Published var masterVolume: Double = 255
    @Published var showFPS: Bool = false
    @Published var fpsCap: String = "100"
    @Published var useClassicASCII: Bool = false
    
    // DFHack Toggles
    @Published var dfhackToggles: [DFHackToggleItem] = [
        DFHackToggleItem(id: "autolabor", titleEN: "Auto Labor", titleZH: "自动劳工分配", subtitleEN: "Automatically assign dwarf labors based on skills", subtitleZH: "根据技能与空闲状态自动调配职责", command: "enable autolabor", isEnabled: false),
        DFHackToggleItem(id: "autofarm", titleEN: "Auto Farm", titleZH: "智能农田轮作", subtitleEN: "Automatically manage crop rotation by season", subtitleZH: "按季节与库存自动规划种植", command: "enable autofarm", isEnabled: false),
        DFHackToggleItem(id: "autobutcher", titleEN: "Auto Butcher", titleZH: "自动牧场屠宰", subtitleEN: "Control livestock population caps automatically", subtitleZH: "控制牲畜数量上限，防止卡顿", command: "enable autobutcher", isEnabled: false),
        DFHackToggleItem(id: "autochop", titleEN: "Auto Chop", titleZH: "自动砍伐树木", subtitleEN: "Designate trees when wood stock is low", subtitleZH: "原木低于阈值时自动标记砍树", command: "enable autochop", isEnabled: false),
        DFHackToggleItem(id: "tailor", titleEN: "Auto Tailor", titleZH: "自动缝补衣物", subtitleEN: "Queue cloth orders when worn clothes are detected", subtitleZH: "检测衣物磨损并自动下达制衣工单", command: "enable tailor", isEnabled: false),
        DFHackToggleItem(id: "prioritize", titleEN: "Prioritize", titleZH: "关键任务加速", subtitleEN: "Boost priority for medical, hauling, and construction", subtitleZH: "提升医疗、搬运与紧急建造优先级", command: "enable prioritize", isEnabled: false),
        DFHackToggleItem(id: "fastdwarf", titleEN: "Fast Dwarf", titleZH: "高速矮人模式", subtitleEN: "Increase dwarf movement and job speed", subtitleZH: "提升矮人移动与工作速度", command: "fastdwarf 1 0", isEnabled: false),
        DFHackToggleItem(id: "stonesense", titleEN: "Stonesense 3D", titleZH: "3D 等距视角", subtitleEN: "Open isometric 3D fortress visualizer", subtitleZH: "实时渲染 3D 要塞视图", command: "stonesense", isEnabled: false)
    ]
    @Published var customDFHackInitText: String = ""
    
    // Mods
    @Published var customMods: [DFMod] = []
    @Published var vanillaMods: [DFMod] = []
    
    private var gameProcess: Process?
    private var logTimer: Timer?
    
    func tr(_ en: String, _ zh: String) -> String {
        return language == .en ? en : zh
    }
    
    init() {
        if let savedLang = UserDefaults.standard.string(forKey: "df_launcher_lang"),
           let lang = AppLanguage(rawValue: savedLang) {
            language = lang
        } else {
            language = .en
        }
        resolveDefaultPaths()
        refreshAll()
        statusMessage = tr("Ready", "就绪")
        startLogMonitor()
    }
    
    var activeGameDir: String {
        switch selectedEdition {
        case .classic:
            return classicPath
        case .steam:
            return steamPath
        }
    }
    
    var appSupportRootDir: String {
        let p = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/DwarfFortressMac")
        try? FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
        return p
    }
    
    var runtimeRootDir: String {
        let localRuntime = (classicPath as NSString).appendingPathComponent(".dfmac_runtime")
        if FileManager.default.fileExists(atPath: localRuntime) {
            return localRuntime
        }
        return appSupportRootDir
    }
    
    var wineBinDir: String {
        let candidates = [
            ((classicPath as NSString).appendingPathComponent(".dfmac_runtime/Wine Devel.app/Contents/Resources/wine/bin")),
            ((appSupportRootDir as NSString).appendingPathComponent("Wine Devel.app/Contents/Resources/wine/bin")),
            "/Applications/Wine Devel.app/Contents/Resources/wine/bin",
            "/Applications/Wine Stable.app/Contents/Resources/wine/bin"
        ]
        for c in candidates {
            if FileManager.default.fileExists(atPath: (c as NSString).appendingPathComponent("wine")) {
                return c
            }
        }
        return ((appSupportRootDir as NSString).appendingPathComponent("Wine Devel.app/Contents/Resources/wine/bin"))
    }
    
    var wineExecutable: String {
        return (wineBinDir as NSString).appendingPathComponent("wine")
    }
    
    var wineServerExecutable: String {
        return (wineBinDir as NSString).appendingPathComponent("wineserver")
    }
    
    var winePrefixDir: String {
        let localPrefix = (runtimeRootDir as NSString).appendingPathComponent("prefix")
        let localUserDir = (localPrefix as NSString).appendingPathComponent("drive_c/users/\(NSUserName())")
        if FileManager.default.fileExists(atPath: localUserDir) {
            return localPrefix
        }
        let appSupport = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/DwarfFortressMac/prefix")
        try? FileManager.default.createDirectory(atPath: (appSupport as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        return appSupport
    }
    
    private func resolveDefaultPaths() {
        let fm = FileManager.default
        let bundleParent = ((Bundle.main.bundlePath as NSString).deletingLastPathComponent)
        let bundleExe = (bundleParent as NSString).appendingPathComponent("Dwarf Fortress.exe")
        
        if let savedClassic = UserDefaults.standard.string(forKey: "df_classic_path"),
           !savedClassic.isEmpty,
           fm.fileExists(atPath: (savedClassic as NSString).appendingPathComponent("Dwarf Fortress.exe")) {
            classicPath = savedClassic
        } else if fm.fileExists(atPath: bundleExe) {
            classicPath = bundleParent
        } else {
            let fallbackDownloads = (NSHomeDirectory() as NSString).appendingPathComponent("Downloads/df_53_16_win")
            classicPath = fm.fileExists(atPath: fallbackDownloads) ? fallbackDownloads : (appSupportRootDir as NSString).appendingPathComponent("classic_edition")
        }
        
        let home = NSHomeDirectory()
        let bundledSteamDir = (runtimeRootDir as NSString).appendingPathComponent("steam_edition")
        let macSteamCommon = (home as NSString).appendingPathComponent("Library/Application Support/Steam/steamapps/common/Dwarf Fortress")
        let macSteamDepot = (home as NSString).appendingPathComponent("Library/Application Support/Steam/steamapps/content/app_975370/depot_975371")
        
        if let savedSteam = UserDefaults.standard.string(forKey: "df_steam_path"),
           !savedSteam.isEmpty,
           fm.fileExists(atPath: (savedSteam as NSString).appendingPathComponent("Dwarf Fortress.exe")) {
            steamPath = savedSteam
        } else if fm.fileExists(atPath: (bundledSteamDir as NSString).appendingPathComponent("Dwarf Fortress.exe")) {
            steamPath = bundledSteamDir
        } else if fm.fileExists(atPath: (macSteamDepot as NSString).appendingPathComponent("Dwarf Fortress.exe")) {
            steamPath = macSteamDepot
        } else if fm.fileExists(atPath: (macSteamCommon as NSString).appendingPathComponent("Dwarf Fortress.exe")) {
            steamPath = macSteamCommon
        } else {
            steamPath = bundledSteamDir
        }
        
        let depotWorkshop = (steamPath as NSString).appendingPathComponent("steamapps/workshop/content/975370")
        let globalWorkshop = (home as NSString).appendingPathComponent("Library/Application Support/Steam/steamapps/workshop/content/975370")
        if fm.fileExists(atPath: depotWorkshop) {
            workshopPath = depotWorkshop
        } else {
            workshopPath = globalWorkshop
        }
        
        if let savedEdition = UserDefaults.standard.string(forKey: "df_selected_edition"),
           let ed = GameEdition(rawValue: savedEdition) {
            selectedEdition = ed
        }
    }
    
    func refreshAll() {
        checkRuntimeStatus()
        checkDFHackStatus()
        loadInitSettings()
        loadDFHackInitConfig()
        scanMods()
        refreshLogs()
    }
    
    private static func detectAppleChipName() -> String {
        var size: Int = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        if size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            if sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 {
                let brand = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
                if !brand.isEmpty {
                    return brand
                }
            }
        }
        return "Apple Silicon"
    }
    
    func checkRuntimeStatus() {
        chipModelName = Self.detectAppleChipName()
        let fm = FileManager.default
        #if arch(x86_64)
        isRosettaInstalled = true
        #else
        isRosettaInstalled = fm.fileExists(atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime") ||
                             fm.fileExists(atPath: "/Library/Apple/usr/share/rosetta/rosetta")
        #endif
        
        if fm.fileExists(atPath: wineExecutable) {
            isWineReady = true
            wineVersion = "Wine 11.21 · \(chipModelName)"
        } else {
            isWineReady = false
            wineVersion = tr("Wine Not Installed", "Wine 未安装")
        }
        
        let systemReg = (winePrefixDir as NSString).appendingPathComponent("system.reg")
        isPrefixReady = fm.fileExists(atPath: systemReg)
    }
    
    func checkDFHackStatus() {
        let fm = FileManager.default
        let dir = activeGameDir
        let dfhackDll = (dir as NSString).appendingPathComponent("hack/dfhack.dll")
        let hooksEnabled = (dir as NSString).appendingPathComponent("dfhooks.dll")
        let dfhackIni = (dir as NSString).appendingPathComponent("dfhooks_dfhack.ini")
        let dfhackIniDisabled = (dir as NSString).appendingPathComponent("dfhooks_dfhack.ini.disabled")
        
        if fm.fileExists(atPath: dfhackDll) {
            isDFHackInstalled = true
            isDFHackEnabled = fm.fileExists(atPath: hooksEnabled) && (fm.fileExists(atPath: dfhackIni) || !fm.fileExists(atPath: dfhackIniDisabled))
            dfhackVersion = detectDFHackVersion(in: dir)
        } else {
            isDFHackInstalled = false
            isDFHackEnabled = false
            dfhackVersion = tr("Not Installed", "未安装")
        }
        
        let dfcnDll = (dir as NSString).appendingPathComponent("dfcn/dfhooks_dfcn.dll")
        let dfcnIni = (dir as NSString).appendingPathComponent("dfhooks_dfcn.ini")
        isDFCNInstalled = fm.fileExists(atPath: dfcnDll)
        isDFCNEnabled = isDFCNInstalled && fm.fileExists(atPath: hooksEnabled) && fm.fileExists(atPath: dfcnIni)
    }
    
    func toggleDFCN(enabled: Bool) {
        let fm = FileManager.default
        let dir = activeGameDir
        let hooksEnabled = (dir as NSString).appendingPathComponent("dfhooks.dll")
        let hooksDisabled = (dir as NSString).appendingPathComponent("dfhooks.dll.disabled")
        let dfcnIni = (dir as NSString).appendingPathComponent("dfhooks_dfcn.ini")
        let dfcnIniDisabled = (dir as NSString).appendingPathComponent("dfhooks_dfcn.ini.disabled")
        
        if enabled {
            if !fm.fileExists(atPath: hooksEnabled) && fm.fileExists(atPath: hooksDisabled) {
                try? fm.moveItem(atPath: hooksDisabled, toPath: hooksEnabled)
            }
            if fm.fileExists(atPath: dfcnIniDisabled) {
                try? fm.removeItem(atPath: dfcnIni)
                try? fm.moveItem(atPath: dfcnIniDisabled, toPath: dfcnIni)
            } else if !fm.fileExists(atPath: dfcnIni) {
                try? "dfcn/dfhooks_dfcn.dll\n".write(toFile: dfcnIni, atomically: true, encoding: .utf8)
            }
            statusMessage = tr("Enabled DFCN Chinese Localization (Shift+F1)", "已启用 DFCN 简体中文汉化 (Shift+F1)")
        } else {
            if fm.fileExists(atPath: dfcnIni) {
                try? fm.removeItem(atPath: dfcnIniDisabled)
                try? fm.moveItem(atPath: dfcnIni, toPath: dfcnIniDisabled)
            }
            statusMessage = tr("Disabled DFCN Chinese Localization", "已禁用 DFCN 简体中文汉化")
        }
        checkDFHackStatus()
    }
    
    private func detectDFHackVersion(in dir: String) -> String {
        let stderrPath = (dir as NSString).appendingPathComponent("stderr.log")
        if let content = try? String(contentsOfFile: stderrPath, encoding: .utf8) {
            for line in content.components(separatedBy: .newlines) {
                if line.hasPrefix("DFHack build:") {
                    return line.replacingOccurrences(of: "DFHack build:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        let newsPath = (dir as NSString).appendingPathComponent("hack/news.rst")
        if let content = try? String(contentsOfFile: newsPath, encoding: .utf8) {
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("DFHack ") && trimmed.count < 32 {
                    return trimmed.replacingOccurrences(of: "DFHack ", with: "")
                }
            }
        }
        return "53.16-r3"
    }
    
    func toggleDFHack(enabled: Bool) {
        let fm = FileManager.default
        let dir = activeGameDir
        let hooksEnabled = (dir as NSString).appendingPathComponent("dfhooks.dll")
        let hooksDisabled = (dir as NSString).appendingPathComponent("dfhooks.dll.disabled")
        let dfhackIni = (dir as NSString).appendingPathComponent("dfhooks_dfhack.ini")
        let dfhackIniDisabled = (dir as NSString).appendingPathComponent("dfhooks_dfhack.ini.disabled")
        
        if !isDFHackInstalled {
            installOrRepairDFHack()
            return
        }
        
        do {
            if enabled {
                if !fm.fileExists(atPath: hooksEnabled) && fm.fileExists(atPath: hooksDisabled) {
                    try fm.moveItem(atPath: hooksDisabled, toPath: hooksEnabled)
                }
                if fm.fileExists(atPath: dfhackIniDisabled) {
                    if fm.fileExists(atPath: dfhackIni) {
                        try fm.removeItem(atPath: dfhackIni)
                    }
                    try fm.moveItem(atPath: dfhackIniDisabled, toPath: dfhackIni)
                } else if !fm.fileExists(atPath: dfhackIni) {
                    try "hack/dfhooks_dfhack.dll".write(toFile: dfhackIni, atomically: true, encoding: .utf8)
                }
                statusMessage = tr("Enabled DFHack (\(dfhackVersion))", "已启用 DFHack (\(dfhackVersion))")
            } else {
                if fm.fileExists(atPath: dfhackIni) {
                    if fm.fileExists(atPath: dfhackIniDisabled) {
                        try fm.removeItem(atPath: dfhackIniDisabled)
                    }
                    try fm.moveItem(atPath: dfhackIni, toPath: dfhackIniDisabled)
                }
                statusMessage = tr("Disabled DFHack", "已禁用 DFHack")
            }
        } catch {
            statusMessage = tr("Failed to toggle DFHack: \(error.localizedDescription)", "切换 DFHack 失败: \(error.localizedDescription)")
        }
        checkDFHackStatus()
    }
    
    func installOrRepairDFHack() {
        let fm = FileManager.default
        let dir = activeGameDir
        let cachedZip = (runtimeRootDir as NSString).appendingPathComponent("cache/dfhack-53.16-r3.zip")
        
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        
        if fm.fileExists(atPath: cachedZip) {
            statusMessage = tr("Extracting DFHack 53.16-r3...", "正在解压安装 DFHack 53.16-r3...")
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            proc.arguments = ["-oq", cachedZip, "-d", dir]
            do {
                try proc.run()
                proc.waitUntilExit()
                let disabledPath = (dir as NSString).appendingPathComponent("dfhooks.dll.disabled")
                if fm.fileExists(atPath: disabledPath) {
                    try? fm.removeItem(atPath: disabledPath)
                }
                checkDFHackStatus()
                loadDFHackInitConfig()
                statusMessage = tr("DFHack 53.16-r3 installed!", "DFHack 53.16-r3 安装完成！")
            } catch {
                statusMessage = tr("Failed to install DFHack: \(error.localizedDescription)", "安装 DFHack 失败: \(error.localizedDescription)")
            }
        } else {
            statusMessage = tr("Downloading DFHack 53.16-r3 from GitHub...", "正在从 GitHub 下载 DFHack 53.16-r3...")
            Task.detached {
                let cacheDir = await (self.runtimeRootDir as NSString).appendingPathComponent("cache")
                try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
                let dlProc = Process()
                dlProc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                dlProc.arguments = [
                    "-L",
                    "https://github.com/DFHack/dfhack/releases/download/53.16-r3/dfhack-53.16-r3-Windows-64bit.zip",
                    "-o", cachedZip
                ]
                try? dlProc.run()
                dlProc.waitUntilExit()
                await MainActor.run {
                    self.installOrRepairDFHack()
                }
            }
        }
    }
    
    // MARK: - Init.txt Settings
    
    private var activePrefsInitPath: String {
        let prefsInit = (activeGameDir as NSString).appendingPathComponent("prefs/init.txt")
        if FileManager.default.fileExists(atPath: prefsInit) {
            return prefsInit
        }
        return (activeGameDir as NSString).appendingPathComponent("data/init/init_default.txt")
    }
    
    func loadInitSettings() {
        let path = activePrefsInitPath
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        
        windowedMode = extractToken("WINDOWED", in: content, default: "YES") != "NO"
        windowWidth = extractToken("WINDOWEDX", in: content, default: "1280")
        windowHeight = extractToken("WINDOWEDY", in: content, default: "800")
        soundEnabled = extractToken("SOUND", in: content, default: "YES") == "YES"
        if let vol = Double(extractToken("MASTER_VOLUME", in: content, default: "255")) {
            masterVolume = vol
        }
        showFPS = extractToken("FPS", in: content, default: "NO") == "YES"
        fpsCap = extractToken("FPS_CAP", in: content, default: "100")
        useClassicASCII = extractToken("USE_CLASSIC_ASCII", in: content, default: "NO") == "YES"
    }
    
    func saveInitSettings() {
        let prefsDir = (activeGameDir as NSString).appendingPathComponent("prefs")
        try? FileManager.default.createDirectory(atPath: prefsDir, withIntermediateDirectories: true)
        
        let paths = [
            (activeGameDir as NSString).appendingPathComponent("prefs/init.txt"),
            (activeGameDir as NSString).appendingPathComponent("data/init/init_default.txt")
        ]
        
        for path in paths {
            guard var content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            content = replaceToken("WINDOWED", with: windowedMode ? "YES" : "NO", in: content)
            content = replaceToken("WINDOWEDX", with: windowWidth, in: content)
            content = replaceToken("WINDOWEDY", with: windowHeight, in: content)
            content = replaceToken("SOUND", with: soundEnabled ? "YES" : "NO", in: content)
            content = replaceToken("MASTER_VOLUME", with: "\(Int(masterVolume))", in: content)
            content = replaceToken("FPS", with: showFPS ? "YES" : "NO", in: content)
            content = replaceToken("FPS_CAP", with: fpsCap, in: content)
            content = replaceToken("USE_CLASSIC_ASCII", with: useClassicASCII ? "YES" : "NO", in: content)
            try? content.write(toFile: path, atomically: true, encoding: .utf8)
        }
        statusMessage = tr("Saved settings to init.txt", "已保存设置到 init.txt")
    }
    
    private func extractToken(_ key: String, in content: String, default defVal: String) -> String {
        let pattern = "\\[\(key):([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else {
            return defVal
        }
        return String(content[range])
    }
    
    private func replaceToken(_ key: String, with value: String, in content: String) -> String {
        let pattern = "\\[\(key):[^\\]]+\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return content }
        return regex.stringByReplacingMatches(
            in: content,
            range: NSRange(content.startIndex..., in: content),
            withTemplate: "[\(key):\(value)]"
        )
    }
    
    // MARK: - DFHack Init Config
    
    private var dfhackInitPath: String {
        return (activeGameDir as NSString).appendingPathComponent("dfhack-config/init/dfhack.init")
    }
    
    func loadDFHackInitConfig() {
        let path = dfhackInitPath
        let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        customDFHackInitText = content
        let lines = Set(content.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        for idx in dfhackToggles.indices {
            dfhackToggles[idx].isEnabled = lines.contains(dfhackToggles[idx].command)
        }
    }
    
    func saveDFHackInitConfig() {
        let initDir = (dfhackInitPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: initDir, withIntermediateDirectories: true)
        
        let knownCommands = Set(dfhackToggles.map { $0.command })
        var keptLines: [String] = []
        for line in customDFHackInitText.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !knownCommands.contains(trimmed) && trimmed != "# --- DF Mac Launcher Managed Plugins ---" {
                keptLines.append(line)
            }
        }
        
        while let last = keptLines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            keptLines.removeLast()
        }
        
        let enabledCommands = dfhackToggles.filter { $0.isEnabled }.map { $0.command }
        if !enabledCommands.isEmpty {
            keptLines.append("")
            keptLines.append("# --- DF Mac Launcher Managed Plugins ---")
            keptLines.append(contentsOf: enabledCommands)
        }
        keptLines.append("")
        
        let newContent = keptLines.joined(separator: "\n")
        customDFHackInitText = newContent
        try? newContent.write(toFile: dfhackInitPath, atomically: true, encoding: .utf8)
        statusMessage = tr("Updated dfhack.init", "已更新 dfhack.init")
    }
    
    // MARK: - Mod Management & Workshop Sync
    
    func scanMods() {
        let fm = FileManager.default
        let dir = activeGameDir
        
        var foundCustom: [String: DFMod] = [:]
        let customDirs = [
            (dir as NSString).appendingPathComponent("mods"),
            (dir as NSString).appendingPathComponent("data/installed_mods")
        ]
        
        for cDir in customDirs {
            guard let items = try? fm.contentsOfDirectory(atPath: cDir) else { continue }
            for item in items {
                let modFolder = (cDir as NSString).appendingPathComponent(item)
                let infoPath = (modFolder as NSString).appendingPathComponent("info.txt")
                if let mod = parseModInfo(at: infoPath, folderPath: modFolder, isVanilla: false) {
                    foundCustom[mod.id] = mod
                }
            }
        }
        customMods = foundCustom.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        var foundVanilla: [DFMod] = []
        let vanillaDir = (dir as NSString).appendingPathComponent("data/vanilla")
        if let items = try? fm.contentsOfDirectory(atPath: vanillaDir) {
            for item in items {
                let modFolder = (vanillaDir as NSString).appendingPathComponent(item)
                let infoPath = (modFolder as NSString).appendingPathComponent("info.txt")
                if let mod = parseModInfo(at: infoPath, folderPath: modFolder, isVanilla: true) {
                    foundVanilla.append(mod)
                }
            }
        }
        vanillaMods = foundVanilla.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private func parseModInfo(at infoPath: String, folderPath: String, isVanilla: Bool) -> DFMod? {
        guard FileManager.default.fileExists(atPath: infoPath),
              let content = try? String(contentsOfFile: infoPath, encoding: .utf8) else {
            return nil
        }
        let folderName = (folderPath as NSString).lastPathComponent
        let id = extractToken("ID", in: content, default: folderName)
        let name = extractToken("NAME", in: content, default: folderName)
        let version = extractToken("DISPLAYED_VERSION", in: content, default: "1.0")
        let author = extractToken("AUTHOR", in: content, default: "Unknown")
        let desc = extractToken("DESCRIPTION", in: content, default: "")
        
        return DFMod(
            id: id,
            folderName: folderName,
            name: name,
            version: version,
            author: author,
            description: desc,
            path: folderPath,
            isVanilla: isVanilla
        )
    }
    
    func importModWithPanel() {
        let panel = NSOpenPanel()
        panel.title = tr("Select Mod Folder or .zip Archive", "选择要导入的 Mod 文件夹或 .zip 压缩包")
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        
        if panel.runModal() == .OK {
            var importedCount = 0
            for url in panel.urls {
                if importMod(from: url) {
                    importedCount += 1
                }
            }
            scanMods()
            statusMessage = importedCount > 0
                ? tr("Imported \(importedCount) mod(s)", "已导入 \(importedCount) 个 Mod")
                : tr("No valid mod (with info.txt) found", "未找到包含 info.txt 的有效 Mod")
        }
    }
    
    private func importMod(from url: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        
        if !isDir.boolValue && url.pathExtension.lowercased() == "zip" {
            let tempDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("df_mod_\(UUID().uuidString)")
            try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(atPath: tempDir) }
            
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-oq", url.path, "-d", tempDir]
            try? unzip.run()
            unzip.waitUntilExit()
            
            return installModFoldersFound(in: tempDir)
        } else if isDir.boolValue {
            return installModFoldersFound(in: url.path)
        }
        return false
    }
    
    private func installModFoldersFound(in rootPath: String) -> Bool {
        let fm = FileManager.default
        let directInfo = (rootPath as NSString).appendingPathComponent("info.txt")
        if fm.fileExists(atPath: directInfo) {
            return copyModFolderToGame(rootPath)
        }
        
        guard let children = try? fm.contentsOfDirectory(atPath: rootPath) else { return false }
        var installedAny = false
        for child in children {
            let childPath = (rootPath as NSString).appendingPathComponent(child)
            let childInfo = (childPath as NSString).appendingPathComponent("info.txt")
            if fm.fileExists(atPath: childInfo) {
                if copyModFolderToGame(childPath) {
                    installedAny = true
                }
            }
        }
        return installedAny
    }
    
    private func copyModFolderToGame(_ srcModFolder: String) -> Bool {
        let fm = FileManager.default
        let folderName = (srcModFolder as NSString).lastPathComponent
        if folderName == "3811193379" || folderName == "3613958631" {
            return false
        }
        let destRoot = (activeGameDir as NSString).appendingPathComponent("mods")
        try? fm.createDirectory(atPath: destRoot, withIntermediateDirectories: true)
        let target = (destRoot as NSString).appendingPathComponent(folderName)
        if fm.fileExists(atPath: target) {
            try? fm.removeItem(atPath: target)
        }
        return (try? fm.copyItem(atPath: srcModFolder, toPath: target)) != nil
    }
    
    func syncSteamWorkshopMods() {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let candidates = [
            (steamPath as NSString).appendingPathComponent("steamapps/workshop/content/975370"),
            (home as NSString).appendingPathComponent("Library/Application Support/Steam/steamapps/content/app_975370/depot_975371/steamapps/workshop/content/975370"),
            (home as NSString).appendingPathComponent("Library/Application Support/Steam/steamapps/workshop/content/975370"),
            workshopPath
        ]
        
        var syncedAny = false
        for candidate in candidates {
            guard !candidate.isEmpty, fm.fileExists(atPath: candidate) else { continue }
            if installModFoldersFound(in: candidate) {
                syncedAny = true
                workshopPath = candidate
            }
            let dfcnSrc = (candidate as NSString).appendingPathComponent("3811193379/DFCN/dfcn")
            if fm.fileExists(atPath: dfcnSrc) {
                let targetDFCN = (activeGameDir as NSString).appendingPathComponent("dfcn")
                try? fm.removeItem(atPath: targetDFCN)
                try? fm.copyItem(atPath: dfcnSrc, toPath: targetDFCN)
                let dfcnIni = (activeGameDir as NSString).appendingPathComponent("dfhooks_dfcn.ini")
                if !fm.fileExists(atPath: dfcnIni) {
                    try? "dfcn/dfhooks_dfcn.dll\n".write(toFile: dfcnIni, atomically: true, encoding: .utf8)
                }
            }
        }
        
        if !syncedAny {
            let panel = NSOpenPanel()
            panel.title = tr("Select Steam Workshop 975370 Folder", "选择 Steam 创意工坊 975370 目录")
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            if panel.runModal() == .OK, let url = panel.url {
                workshopPath = url.path
                syncedAny = installModFoldersFound(in: workshopPath)
            }
        }
        
        scanMods()
        checkDFHackStatus()
        statusMessage = syncedAny
            ? tr("Synced \(customMods.count) Workshop mod(s)", "已同步 \(customMods.count) 个创意工坊 Mod")
            : tr("No Workshop mods found", "未找到创意工坊 Mod")
    }
    
    func removeMod(_ mod: DFMod) {
        guard !mod.isVanilla else { return }
        let fm = FileManager.default
        let pathsToRemove = [
            (activeGameDir as NSString).appendingPathComponent("mods/\(mod.folderName)"),
            (activeGameDir as NSString).appendingPathComponent("data/installed_mods/\(mod.folderName)")
        ]
        for p in pathsToRemove {
            if fm.fileExists(atPath: p) {
                try? fm.removeItem(atPath: p)
            }
        }
        scanMods()
        statusMessage = tr("Removed mod: \(mod.name)", "已移除 Mod: \(mod.name)")
    }
    
    // MARK: - Edition Paths & Environment Setup
    
    func chooseClassicEditionDirectory() {
        let panel = NSOpenPanel()
        panel.title = tr("Select Dwarf Fortress Folder (containing Dwarf Fortress.exe)", "选择 Dwarf Fortress 游戏目录")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            classicPath = url.path
            UserDefaults.standard.set(classicPath, forKey: "df_classic_path")
            refreshAll()
            statusMessage = tr("Classic path updated: \(classicPath)", "已绑定 Classic 目录: \(classicPath)")
        }
    }
    
    func installOrRepairRuntimeEnvironment(andThenLaunch: Bool = false) {
        guard !isInstallingEnvironment else { return }
        isInstallingEnvironment = true
        let targetAppSupport = appSupportRootDir
        let targetPrefix = winePrefixDir
        let needsRosetta = !isRosettaInstalled
        let needsWine = !isWineReady
        
        statusMessage = tr("⏳ Checking and installing runtime environment...", "⏳ 正在检测并安装运行环境...")
        
        Task.detached {
            let fm = FileManager.default
            try? fm.createDirectory(atPath: targetAppSupport, withIntermediateDirectories: true)
            
            // Step 1: Rosetta 2
            if needsRosetta {
                await MainActor.run {
                    self.statusMessage = self.tr("⏳ [1/3] Installing Rosetta 2...", "⏳ [1/3] 正在自动安装 Rosetta 2...")
                }
                let rosettaProc = Process()
                rosettaProc.executableURL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
                rosettaProc.arguments = ["--install-rosetta", "--agree-to-license"]
                try? rosettaProc.run()
                rosettaProc.waitUntilExit()
            }
            
            // Step 2: Wine 11.21 Runtime
            if needsWine {
                await MainActor.run {
                    self.statusMessage = self.tr("⏳ [2/3] Downloading Wine 11.21 (~215MB)...", "⏳ [2/3] 正在下载 Wine 11.21 (~215MB)...")
                }
                let archivePath = "/tmp/df_wine_runtime.tar.xz"
                try? fm.removeItem(atPath: archivePath)
                
                let dlProc = Process()
                dlProc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                dlProc.arguments = [
                    "-L",
                    "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.21/wine-devel-11.21-osx64.tar.xz",
                    "-o", archivePath
                ]
                try? dlProc.run()
                dlProc.waitUntilExit()
                
                await MainActor.run {
                    self.statusMessage = self.tr("⏳ [2/3] Extracting Wine 11.21...", "⏳ [2/3] 正在解压配置 Wine 11.21...")
                }
                let tarProc = Process()
                tarProc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                tarProc.arguments = ["-xf", archivePath, "-C", targetAppSupport]
                try? tarProc.run()
                tarProc.waitUntilExit()
                try? fm.removeItem(atPath: archivePath)
                
                let xattrProc = Process()
                xattrProc.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                xattrProc.arguments = ["-cr", (targetAppSupport as NSString).appendingPathComponent("Wine Devel.app")]
                try? xattrProc.run()
                xattrProc.waitUntilExit()
            }
            
            // Step 3: Initialize Wine Prefix
            await MainActor.run {
                self.checkRuntimeStatus()
                self.statusMessage = self.tr("⏳ [3/3] Initializing Wine prefix (wineboot)...", "⏳ [3/3] 正在初始化 Wine 容器 (wineboot)...")
            }
            let resolvedWineBin = await self.wineBinDir
            let winebootPath = (resolvedWineBin as NSString).appendingPathComponent("wineboot")
            if fm.fileExists(atPath: winebootPath) {
                let bootProc = Process()
                bootProc.executableURL = URL(fileURLWithPath: winebootPath)
                bootProc.arguments = ["-u"]
                var env = ProcessInfo.processInfo.environment
                env["WINEPREFIX"] = targetPrefix
                env["WINEDLLOVERRIDES"] = "mscoree,mshtml="
                bootProc.environment = env
                try? bootProc.run()
                bootProc.waitUntilExit()
            }
            
            await MainActor.run {
                self.isInstallingEnvironment = false
                self.checkRuntimeStatus()
                if self.isRosettaInstalled && self.isWineReady {
                    self.statusMessage = self.tr("✅ Runtime environment is ready!", "✅ 运行环境已安装就绪！")
                    if andThenLaunch {
                        self.launchGame()
                    }
                } else {
                    self.statusMessage = self.tr("⚠️ Runtime setup incomplete. Check network and retry.", "⚠️ 环境安装未完成，请检查网络重试")
                }
            }
        }
    }
    
    func installDFCNLocalization() {
        let dir = activeGameDir
        let fm = FileManager.default
        guard fm.fileExists(atPath: (dir as NSString).appendingPathComponent("Dwarf Fortress.exe")) else {
            statusMessage = tr("Please select a valid game folder first", "请先选择有效的游戏目录")
            return
        }
        statusMessage = tr("⏳ Downloading DFCN Chinese Localization...", "⏳ 正在下载安装 DFCN 中文汉化...")
        Task.detached {
            let zipPath = "/tmp/dfcn_minimal_auto.zip"
            try? FileManager.default.removeItem(atPath: zipPath)
            let dl = Process()
            dl.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            dl.arguments = [
                "-L",
                "https://github.com/pokemonchw/dfcn/releases/latest/download/DFCN-Windows-x64-minimal.zip",
                "-o", zipPath
            ]
            try? dl.run()
            dl.waitUntilExit()
            
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-oq", zipPath, "-d", dir]
            try? unzip.run()
            unzip.waitUntilExit()
            try? FileManager.default.removeItem(atPath: zipPath)
            
            let dfcnIni = (dir as NSString).appendingPathComponent("dfhooks_dfcn.ini")
            try? "dfcn/dfhooks_dfcn.dll\n".write(toFile: dfcnIni, atomically: true, encoding: .utf8)
            let cfgDst = (dir as NSString).appendingPathComponent("dfcn_config.ini")
            let cfgSrc = (dir as NSString).appendingPathComponent("dfcn/data/runtime/config.ini")
            if !FileManager.default.fileExists(atPath: cfgDst) && FileManager.default.fileExists(atPath: cfgSrc) {
                try? FileManager.default.copyItem(atPath: cfgSrc, toPath: cfgDst)
            }
            await MainActor.run {
                self.checkDFHackStatus()
                self.statusMessage = self.tr("✅ DFCN Chinese Localization installed!", "✅ DFCN 中文汉化已安装并启用！")
            }
        }
    }
    
    func chooseSteamEditionDirectory() {
        let panel = NSOpenPanel()
        panel.title = tr("Select Steam Dwarf Fortress Folder", "选择 Steam 版 Dwarf Fortress 目录")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            steamPath = url.path
            UserDefaults.standard.set(steamPath, forKey: "df_steam_path")
            ensureSteamAppIdFile(in: steamPath)
            refreshAll()
            statusMessage = tr("Steam path updated: \(steamPath)", "已绑定 Steam 目录: \(steamPath)")
        }
    }
    
    private func ensureSteamAppIdFile(in dir: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir) else { return }
        let appIdFile = (dir as NSString).appendingPathComponent("steam_appid.txt")
        if !fm.fileExists(atPath: appIdFile) {
            try? "975370\n".write(toFile: appIdFile, atomically: true, encoding: .utf8)
        }
    }
    
    func openMacSteamConsoleDepotDownload() {
        let home = NSHomeDirectory()
        let depotDir = (home as NSString).appendingPathComponent("Library/Application Support/Steam/steamapps/content/app_975370/depot_975371")
        try? FileManager.default.createDirectory(atPath: depotDir, withIntermediateDirectories: true)
        steamPath = depotDir
        UserDefaults.standard.set(steamPath, forKey: "df_steam_path")
        ensureSteamAppIdFile(in: depotDir)
        
        let cmd = "download_depot 975370 975371"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
        
        if let url = URL(string: "steam://open/console") {
            NSWorkspace.shared.open(url)
        }
        refreshAll()
        statusMessage = tr("Opened Steam Console & copied '\(cmd)' (Press Cmd+V in Steam)", "已打开 Steam 控制台并复制「\(cmd)」，按 Cmd+V 回车即可下载")
    }
    
    func downloadSteamEditionViaTerminal() {
        let targetDir = steamPath.isEmpty ? (runtimeRootDir as NSString).appendingPathComponent("steam_edition") : steamPath
        try? FileManager.default.createDirectory(atPath: targetDir, withIntermediateDirectories: true)
        steamPath = targetDir
        UserDefaults.standard.set(steamPath, forKey: "df_steam_path")
        
        let steamCmdDir = (runtimeRootDir as NSString).appendingPathComponent("steamcmd")
        let scriptPath = (runtimeRootDir as NSString).appendingPathComponent("download_steam_df.command")
        let escapedSteamCmdDir = steamCmdDir.replacingOccurrences(of: "'", with: "'\\''")
        let escapedTargetDir = targetDir.replacingOccurrences(of: "'", with: "'\\''")
        
        let scriptContent = """
        #!/bin/zsh
        set -e
        STEAMCMD_DIR='\(escapedSteamCmdDir)'
        TARGET_DIR='\(escapedTargetDir)'
        mkdir -p "$STEAMCMD_DIR" "$TARGET_DIR"
        cd "$STEAMCMD_DIR"
        if [ ! -f "./steamcmd.sh" ]; then
            curl -fsSL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz" | tar zxf -
        fi
        echo -n "Steam Username: "
        read -r STEAM_USER
        ./steamcmd.sh +@sSteamCmdForcePlatformType windows +force_install_dir "$TARGET_DIR" +login "$STEAM_USER" +app_update 975370 validate +quit
        echo "975370" > "$TARGET_DIR/steam_appid.txt"
        echo "✅ Download complete: $TARGET_DIR"
        """
        
        try? scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        NSWorkspace.shared.open(URL(fileURLWithPath: scriptPath))
        statusMessage = tr("Launched SteamCMD terminal downloader", "已打开 SteamCMD 终端下载")
    }
    
    // MARK: - Unify Wine AppData & Launch Game
    
    private func unifyAppDataSymlinks(for gameDir: String) {
        let fm = FileManager.default
        let user = NSUserName()
        let appDataDF = (winePrefixDir as NSString).appendingPathComponent("drive_c/users/\(user)/AppData/Roaming/Bay 12 Games/Dwarf Fortress")
        try? fm.createDirectory(atPath: (appDataDF as NSString).appendingPathComponent("data"), withIntermediateDirectories: true)
        
        let folders = ["save", "prefs"]
        for folder in folders {
            let gameSub = (gameDir as NSString).appendingPathComponent(folder)
            try? fm.createDirectory(atPath: gameSub, withIntermediateDirectories: true)
            let linkPath = (appDataDF as NSString).appendingPathComponent(folder)
            if fm.fileExists(atPath: linkPath) || (try? fm.destinationOfSymbolicLink(atPath: linkPath)) != nil {
                try? fm.removeItem(atPath: linkPath)
            }
            try? fm.createSymbolicLink(atPath: linkPath, withDestinationPath: gameSub)
        }
        
        for nonLink in ["mods", "data/installed_mods"] {
            let p = (appDataDF as NSString).appendingPathComponent(nonLink)
            if (try? fm.destinationOfSymbolicLink(atPath: p)) != nil {
                try? fm.removeItem(atPath: p)
            }
            try? fm.createDirectory(atPath: p, withIntermediateDirectories: true)
        }
        try? fm.createDirectory(atPath: (gameDir as NSString).appendingPathComponent("mods"), withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: (gameDir as NSString).appendingPathComponent("data/installed_mods"), withIntermediateDirectories: true)
    }
    
    func launchGame() {
        let fm = FileManager.default
        let gameDir = activeGameDir
        let exePath = (gameDir as NSString).appendingPathComponent("Dwarf Fortress.exe")
        
        guard fm.fileExists(atPath: exePath) else {
            statusMessage = tr("Game executable not found: \(exePath)", "未找到游戏程序: \(exePath)")
            return
        }
        checkRuntimeStatus()
        if !isRosettaInstalled || !isWineReady || !isPrefixReady {
            installOrRepairRuntimeEnvironment(andThenLaunch: true)
            return
        }
        
        saveInitSettings()
        saveDFHackInitConfig()
        ensureSteamAppIdFile(in: gameDir)
        unifyAppDataSymlinks(for: gameDir)
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: wineExecutable)
        proc.currentDirectoryURL = URL(fileURLWithPath: gameDir)
        proc.arguments = [exePath]
        
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = winePrefixDir
        env["WINEDLLOVERRIDES"] = "dfhooks=n,b;SDL2=n,b;SDL2_image=n,b;fmod=n,b;mscoree,mshtml="
        proc.environment = env
        
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.isGameRunning = false
                self?.statusMessage = self?.tr("Game exited", "游戏已退出") ?? "Game exited"
                self?.refreshLogs()
            }
        }
        
        do {
            try proc.run()
            gameProcess = proc
            isGameRunning = true
            statusMessage = tr("Running Dwarf Fortress (\(selectedEdition.rawValue))", "正在运行 Dwarf Fortress (\(selectedEdition.rawValue))")
        } catch {
            statusMessage = tr("Launch failed: \(error.localizedDescription)", "启动失败: \(error.localizedDescription)")
        }
    }
    
    func stopGameAndWine() {
        gameProcess?.terminate()
        gameProcess = nil
        
        if FileManager.default.fileExists(atPath: wineServerExecutable) {
            let killProc = Process()
            killProc.executableURL = URL(fileURLWithPath: wineServerExecutable)
            killProc.arguments = ["-k"]
            var env = ProcessInfo.processInfo.environment
            env["WINEPREFIX"] = winePrefixDir
            killProc.environment = env
            try? killProc.run()
            killProc.waitUntilExit()
        }
        isGameRunning = false
        statusMessage = tr("Stopped game and Wine processes", "已停止游戏与 Wine 进程")
    }
    
    func openWineCfg() {
        guard FileManager.default.fileExists(atPath: wineExecutable) else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: wineExecutable)
        proc.arguments = ["winecfg"]
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = winePrefixDir
        proc.environment = env
        try? proc.run()
        statusMessage = tr("Opened winecfg", "已打开 winecfg")
    }
    
    func openFolder(_ subPath: String = "") {
        let path = subPath.isEmpty ? activeGameDir : (activeGameDir as NSString).appendingPathComponent(subPath)
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
    
    private func startLogMonitor() {
        logTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshLogs()
            }
        }
    }
    
    func refreshLogs() {
        let stderrPath = (activeGameDir as NSString).appendingPathComponent("stderr.log")
        let stdoutPath = (activeGameDir as NSString).appendingPathComponent("stdout.log")
        var combined = ""
        if let out = try? String(contentsOfFile: stdoutPath, encoding: .utf8), !out.isEmpty {
            combined += "=== stdout.log ===\n" + out + "\n"
        }
        if let err = try? String(contentsOfFile: stderrPath, encoding: .utf8), !err.isEmpty {
            let lines = err.components(separatedBy: .newlines)
            let tail = lines.suffix(80).joined(separator: "\n")
            combined += "=== stderr.log (Last 80 lines) ===\n" + tail
        }
        if combined.isEmpty {
            combined = tr("No logs yet.", "暂无运行日志。")
        }
        if combined != liveLogText {
            liveLogText = combined
        }
    }
}
