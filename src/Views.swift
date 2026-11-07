import SwiftUI
import AppKit

struct MainLauncherView: View {
    @StateObject private var vm = LauncherViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            HeaderBannerView(vm: vm)
            
            TabView(selection: $vm.selectedTab) {
                LaunchDashboardTab(vm: vm)
                    .tabItem {
                        Label(vm.tr("Launch", "启动"), systemImage: "play.circle.fill")
                    }
                    .tag(0)
                
                DFHackCenterTab(vm: vm)
                    .tabItem {
                        Label("DFHack", systemImage: "terminal.fill")
                    }
                    .tag(1)
                
                ModsManagerTab(vm: vm)
                    .tabItem {
                        Label("Mods (\(vm.customMods.count))", systemImage: "puzzlepiece.extension.fill")
                    }
                    .tag(2)
                
                SettingsAndLogsTab(vm: vm)
                    .tabItem {
                        Label(vm.tr("Settings & Logs", "设置与日志"), systemImage: "slider.horizontal.3")
                    }
                    .tag(3)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            
            FooterStatusBar(vm: vm)
        }
        .frame(minWidth: 860, minHeight: 600)
    }
}

struct HeaderBannerView: View {
    @ObservedObject var vm: LauncherViewModel
    
    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 48, height: 48)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Dwarf Fortress Mac Launcher")
                        .font(.system(size: 19, weight: .bold))
                    Text(vm.chipModelName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.18))
                        .cornerRadius(6)
                }
                Text(vm.tr("Classic & Steam · DFHack · Localization · Mod Manager", "Classic / Steam · DFHack · 中文汉化 · Mod 管理"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Picker("", selection: $vm.selectedEdition) {
                ForEach(GameEdition.allCases) { ed in
                    Text(ed.rawValue).tag(ed)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 170)
            
            Picker("", selection: $vm.language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.rawValue).tag(lang)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 96)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
    }
}

struct LaunchDashboardTab: View {
    @ObservedObject var vm: LauncherViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Status Cards Row
                HStack(spacing: 12) {
                    StatusCardView(
                        title: "Rosetta 2",
                        value: vm.isRosettaInstalled ? vm.tr("Ready", "已就绪") : vm.tr("Not Installed", "待安装"),
                        icon: "cpu.fill",
                        isOK: vm.isRosettaInstalled
                    )
                    StatusCardView(
                        title: vm.tr("Wine Container", "Wine 容器"),
                        value: (vm.isWineReady && vm.isPrefixReady)
                            ? vm.tr("Wine 11.21 Ready", "Wine 11.21 就绪")
                            : (vm.isInstallingEnvironment ? vm.tr("Installing...", "配置中...") : vm.tr("Not Ready", "待安装")),
                        icon: "cube.box.fill",
                        isOK: vm.isWineReady && vm.isPrefixReady
                    )
                    StatusCardView(
                        title: "DFHack",
                        value: vm.isDFHackEnabled
                            ? vm.tr("Enabled (\(vm.dfhackVersion))", "已启用 (\(vm.dfhackVersion))")
                            : (vm.isDFHackInstalled ? vm.tr("Disabled", "已禁用") : vm.tr("Not Installed", "未安装")),
                        icon: "bolt.shield.fill",
                        isOK: vm.isDFHackEnabled
                    )
                    StatusCardView(
                        title: "Mods",
                        value: vm.tr("Custom \(vm.customMods.count) · Vanilla \(vm.vanillaMods.count)", "自定义 \(vm.customMods.count) · 原版 \(vm.vanillaMods.count)"),
                        icon: "ShippingBox.fill",
                        isOK: true
                    )
                }
                
                // Environment Auto-Installer Banner
                if !vm.isRosettaInstalled || !vm.isWineReady || !vm.isPrefixReady || vm.isInstallingEnvironment {
                    GroupBox {
                        HStack(spacing: 12) {
                            if vm.isInstallingEnvironment {
                                ProgressView()
                                    .controlSize(.regular)
                            } else {
                                Image(systemName: "sparkles.rectangle.stack.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vm.isInstallingEnvironment
                                     ? vm.tr("Installing runtime environment...", "正在自动配置运行环境...")
                                     : vm.tr("Runtime environment required", "运行环境未就绪"))
                                    .font(.headline)
                                Text(vm.tr(
                                    "Rosetta 2 (\(vm.isRosettaInstalled ? "OK" : "Missing")) · Wine 11.21 (\(vm.isWineReady ? "OK" : "Missing")) · Prefix (\(vm.isPrefixReady ? "OK" : "Missing"))",
                                    "Rosetta 2 (\(vm.isRosettaInstalled ? "已装" : "待装")) · Wine 11.21 (\(vm.isWineReady ? "已装" : "待装")) · 容器 (\(vm.isPrefixReady ? "已就绪" : "待初始化"))"
                                ))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(vm.isInstallingEnvironment
                                   ? vm.tr("Installing...", "安装中...")
                                   : vm.tr("Auto-Install Runtime", "一键安装环境")) {
                                vm.installOrRepairRuntimeEnvironment()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            .disabled(vm.isInstallingEnvironment)
                        }
                        .padding(6)
                    }
                }
                
                // Game Path & Steam Download
                GroupBox(label: Label(vm.tr("Game Directory", "游戏路径"), systemImage: "folder.badge.gearshape").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(vm.activeGameDir)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(vm.tr("Open", "打开目录")) {
                                vm.openFolder()
                            }
                            Button(vm.tr("Browse...", "选择目录...")) {
                                if vm.selectedEdition == .classic {
                                    vm.chooseClassicEditionDirectory()
                                } else {
                                    vm.chooseSteamEditionDirectory()
                                }
                            }
                            Button(vm.isInstallingEnvironment
                                   ? vm.tr("Checking...", "检测中...")
                                   : vm.tr("Repair Runtime", "修复环境")) {
                                vm.installOrRepairRuntimeEnvironment()
                            }
                            .disabled(vm.isInstallingEnvironment)
                        }
                        
                        if vm.selectedEdition == .steam {
                            Divider()
                            HStack(spacing: 10) {
                                Text("Steam:")
                                    .fontWeight(.medium)
                                Button(vm.tr("Open Steam Console (Copy Depot Cmd)", "唤起 Steam 控制台 (复制下载指令)")) {
                                    vm.openMacSteamConsoleDepotDownload()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                
                                Button(vm.tr("Download via Official SteamCMD", "使用官方 SteamCMD 下载")) {
                                    vm.downloadSteamEditionViaTerminal()
                                }
                                .buttonStyle(.bordered)
                                
                                Spacer()
                            }
                        }
                    }
                    .padding(8)
                }
                
                // Quick Settings & Shortcuts
                HStack(alignment: .top, spacing: 14) {
                    GroupBox(label: Label(vm.tr("Launch Options", "启动选项"), systemImage: "switch.2").font(.headline)) {
                        VStack(alignment: .leading, spacing: 9) {
                            Toggle(vm.tr("Enable DFHack", "启用 DFHack 插件框架"), isOn: Binding(
                                get: { vm.isDFHackEnabled },
                                set: { vm.toggleDFHack(enabled: $0) }
                            ))
                            
                            if vm.isDFCNInstalled {
                                Toggle(vm.tr("Enable DFCN Chinese Localization (Shift+F1)", "启用 DFCN 简体中文汉化 (Shift+F1)"), isOn: Binding(
                                    get: { vm.isDFCNEnabled },
                                    set: { vm.toggleDFCN(enabled: $0) }
                                ))
                            } else {
                                HStack {
                                    Text(vm.tr("DFCN Chinese Localization", "DFCN 中文汉化"))
                                    Spacer()
                                    Button(vm.tr("Install", "一键安装")) {
                                        vm.installDFCNLocalization()
                                    }
                                    .controlSize(.small)
                                }
                            }
                            
                            Toggle(vm.tr("Windowed Mode", "窗口化模式"), isOn: $vm.windowedMode)
                                .onChange(of: vm.windowedMode) { _, _ in vm.saveInitSettings() }
                            
                            Toggle(vm.tr("Enable Sound & Music", "开启音效与音乐"), isOn: $vm.soundEnabled)
                                .onChange(of: vm.soundEnabled) { _, _ in vm.saveInitSettings() }
                            
                            Toggle(vm.tr("Classic ASCII Mode", "经典 ASCII 模式"), isOn: $vm.useClassicASCII)
                                .onChange(of: vm.useClassicASCII) { _, _ in vm.saveInitSettings() }
                            
                            Toggle(vm.tr("Show FPS Counter", "显示实时帧率 (FPS)"), isOn: $vm.showFPS)
                                .onChange(of: vm.showFPS) { _, _ in vm.saveInitSettings() }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    GroupBox(label: Label(vm.tr("Quick Tools", "快捷工具"), systemImage: "wrench.and.screwdriver.fill").font(.headline)) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Button {
                                    vm.openFolder("save")
                                } label: {
                                    Label(vm.tr("Saves (save)", "存档目录 (save)"), systemImage: "externaldrive.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                Button {
                                    vm.openFolder("mods")
                                } label: {
                                    Label(vm.tr("Mods (mods)", "Mod 目录 (mods)"), systemImage: "folder.fill.badge.plus")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            HStack(spacing: 10) {
                                Button {
                                    vm.openFolder("prefs")
                                } label: {
                                    Label(vm.tr("Prefs (prefs)", "配置目录 (prefs)"), systemImage: "doc.text.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                Button {
                                    vm.openWineCfg()
                                } label: {
                                    Label("Winecfg", systemImage: "gearshape.2.fill")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            Divider()
                            Text(vm.tr(
                                "Shortcuts: `Ctrl+Shift+D` DFHack Launcher · `Ctrl+Shift+E` Control Panel · `Shift+F1` DFCN",
                                "快捷键：`Ctrl+Shift+D` 命令终端 · `Ctrl+Shift+E` 控制面板 · `Shift+F1` 汉化设置"
                            ))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                
                // Launch Buttons
                HStack(spacing: 14) {
                    Button {
                        vm.launchGame()
                    } label: {
                        HStack(spacing: 10) {
                            if vm.isInstallingEnvironment {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: vm.isGameRunning ? "checkmark.circle.fill" : "play.fill")
                                    .font(.title2)
                            }
                            Text(
                                vm.isInstallingEnvironment
                                    ? vm.tr("Installing Runtime...", "正在配置环境...")
                                    : (vm.isGameRunning
                                        ? vm.tr("Game Running (Click to Relaunch)", "游戏运行中 (点击重开)")
                                        : ((!vm.isRosettaInstalled || !vm.isWineReady || !vm.isPrefixReady)
                                            ? vm.tr("Setup Runtime & Launch", "自动配置环境并启动")
                                            : vm.tr("Launch Dwarf Fortress", "启动 Dwarf Fortress")))
                            )
                            .font(.title3)
                            .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(vm.isGameRunning ? .green : .orange)
                    .disabled(vm.isInstallingEnvironment)
                    
                    Button(role: .destructive) {
                        vm.stopGameAndWine()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.circle.fill")
                            Text(vm.tr("Stop Game", "停止游戏"))
                                .fontWeight(.semibold)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 8)
        }
    }
}

struct StatusCardView: View {
    let title: String
    let value: String
    let icon: String
    let isOK: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(isOK ? .green : .orange)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Circle()
                    .fill(isOK ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
            }
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct DFHackCenterTab: View {
    @ObservedObject var vm: LauncherViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox {
                HStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Text("DFHack:")
                            .font(.headline)
                        Text(vm.isDFHackEnabled
                             ? vm.tr("Enabled (\(vm.dfhackVersion))", "已启用 (\(vm.dfhackVersion))")
                             : (vm.isDFHackInstalled ? vm.tr("Disabled", "已禁用") : vm.tr("Not Installed", "未安装")))
                            .font(.headline)
                            .foregroundColor(vm.isDFHackEnabled ? .green : .orange)
                    }
                    Spacer()
                    Toggle(vm.tr("Enable", "启用"), isOn: Binding(
                        get: { vm.isDFHackEnabled },
                        set: { vm.toggleDFHack(enabled: $0) }
                    ))
                    .toggleStyle(.switch)
                    
                    Button(vm.tr("Install / Repair DFHack", "安装 / 修复 DFHack")) {
                        vm.installOrRepairDFHack()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(8)
            }
            
            HStack(alignment: .top, spacing: 14) {
                GroupBox(label: Label(vm.tr("Startup Plugins (dfhack.init)", "自启插件 (dfhack.init)"), systemImage: "sparkles").font(.headline)) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach($vm.dfhackToggles) { $item in
                                HStack(alignment: .top) {
                                    Toggle("", isOn: $item.isEnabled)
                                        .labelsHidden()
                                        .onChange(of: item.isEnabled) { _, _ in
                                            vm.saveDFHackInitConfig()
                                        }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(vm.language == .en ? item.titleEN : item.titleZH)
                                            .fontWeight(.medium)
                                        Text(vm.language == .en ? item.subtitleEN : item.subtitleZH)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(item.command)
                                        .font(.system(.caption, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.15))
                                        .cornerRadius(4)
                                }
                                Divider()
                            }
                        }
                        .padding(8)
                    }
                }
                .frame(maxWidth: .infinity)
                
                GroupBox(label: Label(vm.tr("Custom Script & Shortcuts", "自定义脚本与快捷键"), systemImage: "text.and.command.macwindow").font(.headline)) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $vm.customDFHackInitText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 180)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                        
                        HStack {
                            Button(vm.tr("Save Script", "保存脚本")) {
                                try? FileManager.default.createDirectory(
                                    atPath: (vm.activeGameDir as NSString).appendingPathComponent("dfhack-config/init"),
                                    withIntermediateDirectories: true
                                )
                                let path = (vm.activeGameDir as NSString).appendingPathComponent("dfhack-config/init/dfhack.init")
                                try? vm.customDFHackInitText.write(toFile: path, atomically: true, encoding: .utf8)
                                vm.loadDFHackInitConfig()
                                vm.statusMessage = vm.tr("Saved dfhack.init", "已保存 dfhack.init")
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button(vm.tr("Open Config Folder", "配置目录")) {
                                vm.openFolder("dfhack-config")
                            }
                            Spacer()
                        }
                        
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text(vm.tr("• `Ctrl+Shift+D` : Command Launcher (gui/launcher)", "• `Ctrl+Shift+D` : 命令终端 (gui/launcher)"))
                                .font(.caption)
                            Text(vm.tr("• `Ctrl+Shift+E` : Control Panel (gui/control-panel)", "• `Ctrl+Shift+E` : 插件总控台 (gui/control-panel)"))
                                .font(.caption)
                            Text(vm.tr("• `Ctrl+Shift+Q` : Quickfort Blueprints (gui/quickfort)", "• `Ctrl+Shift+Q` : 蓝图建造器 (gui/quickfort)"))
                                .font(.caption)
                            Text(vm.tr("• `Ctrl+D` : Shape Designer (gui/design)", "• `Ctrl+D` : 几何挖掘设计器 (gui/design)"))
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    .padding(8)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct ModsManagerTab: View {
    @ObservedObject var vm: LauncherViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("", selection: $vm.showVanillaMods) {
                    Text(vm.tr("Custom Mods (\(vm.customMods.count))", "自定义 Mod (\(vm.customMods.count))")).tag(false)
                    Text(vm.tr("Vanilla (\(vm.vanillaMods.count))", "原版模块 (\(vm.vanillaMods.count))")).tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 280)
                
                Spacer()
                
                Button {
                    vm.importModWithPanel()
                } label: {
                    Label(vm.tr("Import Mod", "导入 Mod"), systemImage: "plus.square.on.square")
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    vm.syncSteamWorkshopMods()
                } label: {
                    Label(vm.tr("Sync Workshop", "同步创意工坊"), systemImage: "arrow.triangle.2.circlepath.circle")
                }
                .buttonStyle(.bordered)
                
                Button(vm.tr("Open Folder", "打开目录")) {
                    vm.openFolder("mods")
                }
                
                Button {
                    vm.scanMods()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            
            let displayedMods = vm.showVanillaMods ? vm.vanillaMods : vm.customMods
            
            if displayedMods.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "shippingbox")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text(vm.tr("No Mods Found", "暂无 Mod"))
                        .font(.headline)
                    Text(vm.tr("Import a .zip / folder or sync from local Steam Workshop", "支持导入 .zip / 文件夹，或从本机 Steam 创意工坊一键同步"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(displayedMods) { mod in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: mod.isVanilla ? "checkmark.seal.fill" : "puzzlepiece.extension.fill")
                            .foregroundColor(mod.isVanilla ? .blue : .orange)
                            .font(.title3)
                            .padding(.top, 2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(mod.name)
                                    .font(.headline)
                                Text("v\(mod.version)")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.15))
                                    .cornerRadius(4)
                                Text(mod.id)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            if !mod.description.isEmpty {
                                Text(mod.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        if !mod.isVanilla {
                            Button(role: .destructive) {
                                vm.removeMod(mod)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
                .cornerRadius(8)
            }
        }
    }
}

struct SettingsAndLogsTab: View {
    @ObservedObject var vm: LauncherViewModel
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            GroupBox(label: Label(vm.tr("Display & Audio (init.txt)", "显示与音频 (init.txt)"), systemImage: "display").font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(vm.tr("Windowed Mode", "窗口模式"), isOn: $vm.windowedMode)
                    
                    HStack {
                        Text(vm.tr("Resolution:", "分辨率:"))
                        TextField("1280", text: $vm.windowWidth)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 75)
                        Text("×")
                        TextField("800", text: $vm.windowHeight)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 75)
                    }
                    
                    Divider()
                    
                    Toggle(vm.tr("Enable Sound & Music", "启用音效与音乐"), isOn: $vm.soundEnabled)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vm.tr("Volume (\(Int(vm.masterVolume)) / 255)", "主音量 (\(Int(vm.masterVolume)) / 255)"))
                        Slider(value: $vm.masterVolume, in: 0...255, step: 5)
                    }
                    
                    Divider()
                    
                    Toggle(vm.tr("Show FPS", "显示实时帧率 (FPS)"), isOn: $vm.showFPS)
                    
                    HStack {
                        Text(vm.tr("FPS Cap:", "帧率上限:"))
                        TextField("100", text: $vm.fpsCap)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 75)
                    }
                    
                    Toggle(vm.tr("Classic ASCII Mode", "经典 ASCII 渲染模式"), isOn: $vm.useClassicASCII)
                    
                    Spacer()
                    
                    HStack {
                        Button(vm.tr("Save", "保存设置")) {
                            vm.saveInitSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button(vm.tr("Open prefs", "打开 prefs")) {
                            vm.openFolder("prefs")
                        }
                    }
                }
                .padding(10)
            }
            .frame(width: 300)
            
            GroupBox(label: Label(vm.tr("Live Logs", "运行日志"), systemImage: "doc.plaintext").font(.headline)) {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView {
                        Text(vm.liveLogText)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    
                    HStack {
                        Button(vm.tr("Refresh", "刷新")) {
                            vm.refreshLogs()
                        }
                        Button(vm.tr("Reveal stderr.log", "定位 stderr.log")) {
                            let p = (vm.activeGameDir as NSString).appendingPathComponent("stderr.log")
                            NSWorkspace.shared.selectFile(p, inFileViewerRootedAtPath: vm.activeGameDir)
                        }
                        Spacer()
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct FooterStatusBar: View {
    @ObservedObject var vm: LauncherViewModel
    
    var body: some View {
        HStack {
            Circle()
                .fill(vm.isGameRunning ? Color.green : Color.blue)
                .frame(width: 8, height: 8)
            Text(vm.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(vm.wineVersion)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(Divider(), alignment: .top)
    }
}
