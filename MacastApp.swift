import Cocoa
import SwiftUI
import Combine

// MARK: - Process Manager
class MacastProcessManager: ObservableObject {
    static let shared = MacastProcessManager()
    
    private var process: Process?
    @Published var isRunning = false
    
    func start() {
        guard !isRunning else { return }
        
        let newProcess = Process()
        newProcess.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        
        // Use Resource URL of bundle if available
        if let resourceURL = Bundle.main.resourceURL {
            newProcess.currentDirectoryURL = resourceURL
        } else {
            newProcess.currentDirectoryURL = URL(fileURLWithPath: "/Users/anyi11/vsc/Macast")
        }
        
        newProcess.arguments = [
            "-c",
            "from macast.macast import cli; from Macast import set_mpv_default_path; set_mpv_default_path(); cli()"
        ]
        
        do {
            try newProcess.run()
            self.process = newProcess
            self.isRunning = true
            
            newProcess.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async {
                    self?.isRunning = false
                    self?.process = nil
                }
            }
        } catch {
            print("Failed to start Macast: \(error)")
        }
    }
    
    func stop(completion: (() -> Void)? = nil) {
        guard isRunning, let process = process else {
            completion?()
            return
        }
        
        let oldProcess = process
        self.process = nil
        self.isRunning = false
        
        DispatchQueue.global(qos: .userInitiated).async {
            oldProcess.terminate()
            oldProcess.waitUntilExit()
            DispatchQueue.main.async {
                completion?()
            }
        }
    }
}

// MARK: - Settings Model & Manager
struct MacastSettings: Codable {
    var Additional_Interfaces: [String] = []
    var ApplicationPort: Int = 1068
    var Blocked_Interfaces: [String] = []
    var CheckUpdate: Int = 1
    var DLNA_FriendlyName: String = "Macast"
    var Macast_Protocol: String = "DLNA Protocol"
    var Macast_Renderer: String = "MPV Renderer"
    var MenubarIcon: Int = 1
    var PlayerHW: Int = 1
    var PlayerOntop: Int = 1
    var PlayerPosition: Int = 2
    var PlayerSize: Int = 1
    var StartAtLogin: Int = 0
    var USN: String = UUID().uuidString
    var DownloadPath: String = ""
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var settings = MacastSettings()
    
    private var fileURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("Macast")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("macast_setting.json")
    }
    
    func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            settings = try JSONDecoder().decode(MacastSettings.self, from: data)
        } catch {
            print("Could not load settings, using defaults.")
            save()
        }
    }
    
    func save() {
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: fileURL, options: .atomic)
            
            // Restart helper process to apply new configurations if running
            if MacastProcessManager.shared.isRunning {
                MacastProcessManager.shared.stop {
                    MacastProcessManager.shared.start()
                }
            }
        } catch {
            print("Could not save settings: \(error)")
        }
    }
}

// MARK: - Log & Casted Video Manager
struct LogLine: Identifiable, Equatable {
    let id: Int
    let text: String
}

struct CastedVideo: Identifiable, Equatable {
    let id: String
    let timestamp: String
    let device: String
    let title: String
    let url: String
}

class LogManager: ObservableObject {
    static let shared = LogManager()
    
    @Published var logLines: [LogLine] = []
    @Published var rawLogText = ""
    @Published var castedVideos: [CastedVideo] = []
    private var timer: Timer?
    private var isReading = false
    
    private var logURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("Macast/macast.log")
    }
    
    func startMonitoring() {
        readLog()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.readLog()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func readLog() {
        guard !isReading else { return }
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            DispatchQueue.main.async {
                self.logLines = [LogLine(id: 0, text: "暂无运行记录。")]
                self.rawLogText = "暂无运行记录。"
                self.castedVideos = []
            }
            return
        }
        
        isReading = true
        let url = logURL
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer {
                DispatchQueue.main.async {
                    self?.isReading = false
                }
            }
            
            do {
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) else {
                    DispatchQueue.main.async {
                        self?.logLines = [LogLine(id: 0, text: "解析记录失败。")]
                        self?.rawLogText = "解析记录失败。"
                        self?.castedVideos = []
                    }
                    return
                }
                
                let allLines = text.components(separatedBy: .newlines)
                
                var filtered: [String] = []
                filtered.reserveCapacity(min(allLines.count, 100))
                var videos: [CastedVideo] = []
                
                for line in allLines {
                    if line.isEmpty { continue }
                    if line.contains("[CAST_EVENT]") {
                        var displayLine = line
                        var timestamp = "未知时间"
                        if line.count >= 19 {
                            timestamp = String(line.prefix(19))
                            let start = line.index(line.startIndex, offsetBy: 11)
                            let end = line.index(line.startIndex, offsetBy: 19)
                            let timeStr = String(line[start..<end])
                            
                            if let range = line.range(of: "[CAST_EVENT]") {
                                let eventText = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                                displayLine = "[\(timeStr)] \(eventText)"
                            }
                        }
                        filtered.append(displayLine)
                        
                        // Parse CastedVideo
                        if let eventRange = line.range(of: "[CAST_EVENT]") {
                            let eventContent = String(line[eventRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                            
                            var device = "未知设备"
                            var title = "无标题"
                            var urlStr = ""
                            
                            if let devStart = eventContent.range(of: "设备 "),
                               let devEnd = eventContent.range(of: " 投屏了:") {
                                device = String(eventContent[devStart.upperBound..<devEnd.lowerBound]).trimmingCharacters(in: .whitespaces)
                            }
                            
                            if let titleStart = eventContent.range(of: "投屏了:"),
                               let titleEnd = eventContent.range(of: " | 链接:") {
                                title = String(eventContent[titleStart.upperBound..<titleEnd.lowerBound]).trimmingCharacters(in: .whitespaces)
                            }
                            
                            if let urlStart = eventContent.range(of: "链接: ") {
                                urlStr = String(eventContent[urlStart.upperBound...]).trimmingCharacters(in: .whitespaces)
                            } else if let urlStart = eventContent.range(of: "链接:") {
                                urlStr = String(eventContent[urlStart.upperBound...]).trimmingCharacters(in: .whitespaces)
                            }
                            
                            if !urlStr.isEmpty {
                                let video = CastedVideo(
                                    id: "\(timestamp)-\(urlStr)",
                                    timestamp: timestamp,
                                    device: device,
                                    title: title,
                                    url: urlStr
                                )
                                if !videos.contains(where: { $0.id == video.id }) {
                                    videos.append(video)
                                }
                            }
                        }
                    }
                }
                
                let linesToKeep = 100
                let startIdx = max(0, filtered.count - linesToKeep)
                let finalLines = Array(filtered[startIdx..<filtered.count])
                
                var structuredLines: [LogLine] = []
                structuredLines.reserveCapacity(finalLines.count)
                for (index, lineText) in finalLines.enumerated() {
                    structuredLines.append(LogLine(id: index, text: lineText))
                }
                
                let rawText = finalLines.joined(separator: "\n")
                let finalVideos = Array(videos.reversed())
                
                DispatchQueue.main.async {
                    self?.logLines = structuredLines.isEmpty ? [LogLine(id: 0, text: "暂无投屏记录。")] : structuredLines
                    self?.rawLogText = rawText.isEmpty ? "暂无投屏记录。" : rawText
                    self?.castedVideos = finalVideos
                }
            } catch {
                DispatchQueue.main.async {
                    self?.logLines = [LogLine(id: 0, text: "读取记录失败: \(error.localizedDescription)")]
                    self?.rawLogText = "读取记录失败: \(error.localizedDescription)"
                    self?.castedVideos = []
                }
            }
        }
    }
}

// MARK: - Download Manager
enum DownloadStatus: Equatable {
    case idle
    case downloading(progress: Double)
    case completed(localURL: URL)
    case failed(error: String)
}

class DownloadItem: ObservableObject, Identifiable {
    let id: String
    let title: String
    let url: URL
    
    @Published var status: DownloadStatus = .idle
    private var downloadTask: URLSessionDownloadTask?
    
    init(urlStr: String, title: String) {
        self.id = urlStr
        self.title = title
        self.url = URL(string: urlStr) ?? URL(fileURLWithPath: "")
    }
    
    func startDownload(session: URLSession) {
        switch status {
        case .idle, .failed:
            break
        default:
            return
        }
        status = .downloading(progress: 0.0)
        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()
    }
    
    func cancelDownload() {
        downloadTask?.cancel()
        status = .idle
    }
    
    func updateProgress(_ progress: Double) {
        DispatchQueue.main.async {
            self.status = .downloading(progress: progress)
        }
    }
    
    func completeDownload(temporaryURL: URL) {
        let fileManager = FileManager.default
        let destDir: URL
        if !SettingsManager.shared.settings.DownloadPath.isEmpty {
            destDir = URL(fileURLWithPath: SettingsManager.shared.settings.DownloadPath)
        } else {
            destDir = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        }
        
        let pathExtension = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let safeTitle = title.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "_")
        let fileName = "\(safeTitle)_\(Int(Date().timeIntervalSince1970)).\(pathExtension)"
        let destinationURL = destDir.appendingPathComponent(fileName)
        
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            DispatchQueue.main.async {
                self.status = .completed(localURL: destinationURL)
            }
        } catch {
            DispatchQueue.main.async {
                self.status = .failed(error: error.localizedDescription)
            }
        }
    }
    
    func failDownload(errorDescription: String) {
        DispatchQueue.main.async {
            self.status = .failed(error: errorDescription)
        }
    }
}

class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = DownloadManager()
    
    @Published var downloads: [String: DownloadItem] = [:]
    private var session: URLSession!
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    func download(urlStr: String, title: String) {
        let item = getItem(for: urlStr, title: title)
        item.startDownload(session: session)
    }
    
    func getItem(for urlStr: String, title: String) -> DownloadItem {
        if let item = downloads[urlStr] {
            return item
        }
        let newItem = DownloadItem(urlStr: urlStr, title: title)
        downloads[urlStr] = newItem
        return newItem
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let urlStr = downloadTask.originalRequest?.url?.absoluteString,
              let item = downloads[urlStr] else { return }
        
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0
        item.updateProgress(progress)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let urlStr = downloadTask.originalRequest?.url?.absoluteString,
              let item = downloads[urlStr] else { return }
        
        item.completeDownload(temporaryURL: location)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let urlStr = task.originalRequest?.url?.absoluteString,
              let item = downloads[urlStr] else { return }
        
        if let error = error {
            if (error as NSError).code != NSURLErrorCancelled {
                item.failDownload(errorDescription: error.localizedDescription)
            }
        }
    }
}

// MARK: - Popover View
struct PopoverView: View {
    @ObservedObject var processManager = MacastProcessManager.shared
    @ObservedObject var settingsManager = SettingsManager.shared
    
    var onOpenSettings: () -> Void
    var onOpenLogs: () -> Void
    var onQuit: () -> Void
    
    @State private var inputName = ""
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Macast")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                
                // Status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(processManager.isRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(processManager.isRunning ? "正在运行" : "已停止")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(12)
            }
            
            Divider()
            
            // Service Controls
            Button(action: {
                if processManager.isRunning {
                    processManager.stop()
                } else {
                    processManager.start()
                }
            }) {
                HStack {
                    Image(systemName: processManager.isRunning ? "stop.fill" : "play.fill")
                    Text(processManager.isRunning ? "停止服务" : "启动服务")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(processManager.isRunning ? Color.red : Color.blue)
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Device Name Configuration Card
            VStack(alignment: .leading, spacing: 6) {
                Text("投屏名称 (Device Name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    TextField("例如: 客厅的Mac", text: $inputName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button("应用") {
                        settingsManager.settings.DLNA_FriendlyName = inputName
                        settingsManager.save()
                    }
                    .disabled(inputName == settingsManager.settings.DLNA_FriendlyName || inputName.isEmpty)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .onAppear {
                inputName = settingsManager.settings.DLNA_FriendlyName
            }
            
            Divider()
            
            // Footer Actions
            HStack(spacing: 12) {
                Button(action: onOpenSettings) {
                    Label("设置", systemImage: "gearshape")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                
                Button(action: onOpenLogs) {
                    Label("日志", systemImage: "doc.text")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: onQuit) {
                    Text("退出")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var settingsManager = SettingsManager.shared
    
    var body: some View {
        Form {
            Section(header: Text("通用设置").font(.headline)) {
                Toggle("开机自启", isOn: Binding(
                    get: { settingsManager.settings.StartAtLogin == 1 },
                    set: { settingsManager.settings.StartAtLogin = $0 ? 1 : 0 }
                ))
                Toggle("自动检查更新", isOn: Binding(
                    get: { settingsManager.settings.CheckUpdate == 1 },
                    set: { settingsManager.settings.CheckUpdate = $0 ? 1 : 0 }
                ))
                
                HStack {
                    Text("服务端口:")
                    TextField("默认 1068", value: $settingsManager.settings.ApplicationPort, formatter: NumberFormatter())
                        .frame(width: 80)
                }
            }
            
            Divider()
                .padding(.vertical, 4)
            
            Section(header: Text("投屏播放器选择").font(.headline)) {
                Picker("选择播放器:", selection: $settingsManager.settings.Macast_Renderer) {
                    Text("内置 MPV 播放器 (默认)").tag("MPV Renderer")
                    Text("系统默认关联播放器 (open)").tag("System Default Player")
                    Text("IINA 播放器").tag("IINA Player")
                    Text("QuickTime Player").tag("QuickTime Player")
                }
                .pickerStyle(MenuPickerStyle())
            }
            
            Divider()
                .padding(.vertical, 4)
            
            Section(header: Text("播放器选项 (仅适用于内置 MPV)").font(.headline)) {
                Toggle("硬件解码", isOn: Binding(
                    get: { settingsManager.settings.PlayerHW == 1 },
                    set: { settingsManager.settings.PlayerHW = $0 ? 1 : 0 }
                ))
                Toggle("播放窗口置顶", isOn: Binding(
                    get: { settingsManager.settings.PlayerOntop == 1 },
                    set: { settingsManager.settings.PlayerOntop = $0 ? 1 : 0 }
                ))
                
                Picker("播放器大小:", selection: $settingsManager.settings.PlayerSize) {
                    Text("小").tag(0)
                    Text("中").tag(1)
                    Text("大").tag(2)
                    Text("全屏").tag(3)
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Picker("播放器位置:", selection: $settingsManager.settings.PlayerPosition) {
                    Text("左上").tag(0)
                    Text("左下").tag(1)
                    Text("右上").tag(2)
                    Text("右下").tag(3)
                    Text("中央").tag(4)
                }
            }
            .disabled(settingsManager.settings.Macast_Renderer != "MPV Renderer")
            .opacity(settingsManager.settings.Macast_Renderer == "MPV Renderer" ? 1.0 : 0.5)
            
            Divider()
                .padding(.vertical, 4)
            
            Section(header: Text("下载设置").font(.headline)) {
                HStack {
                    Text("保存路径:")
                    Text(settingsManager.settings.DownloadPath.isEmpty ? "Downloads (默认)" : settingsManager.settings.DownloadPath)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("选择...") {
                        let openPanel = NSOpenPanel()
                        openPanel.canChooseFiles = false
                        openPanel.canChooseDirectories = true
                        openPanel.allowsMultipleSelection = false
                        openPanel.prompt = "选择"
                        
                        if openPanel.runModal() == .OK {
                            if let url = openPanel.url {
                                settingsManager.settings.DownloadPath = url.path
                                settingsManager.save()
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            HStack {
                Spacer()
                Button("保存并重启服务") {
                    settingsManager.save()
                    if let window = NSApp.keyWindow {
                        window.close()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 450, height: 500)
    }
}

// MARK: - Visual Effect View
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Log View
struct LogView: View {
    @ObservedObject var logManager = LogManager.shared
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Selector Header
            HStack(spacing: 20) {
                Button(action: { selectedTab = 0 }) {
                    VStack(spacing: 4) {
                        Text("投屏日志")
                            .font(.system(size: 13, weight: selectedTab == 0 ? .bold : .regular))
                            .foregroundColor(selectedTab == 0 ? .primary : .secondary)
                        Rectangle()
                            .fill(selectedTab == 0 ? Color.blue : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { selectedTab = 1 }) {
                    VStack(spacing: 4) {
                        Text("视频下载")
                            .font(.system(size: 13, weight: selectedTab == 1 ? .bold : .regular))
                            .foregroundColor(selectedTab == 1 ? .primary : .secondary)
                        Rectangle()
                            .fill(selectedTab == 1 ? Color.blue : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                if selectedTab == 0 {
                    Text("实时更新")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
            
            Divider()
            
            if selectedTab == 0 {
                CastingLogsPaneView()
            } else {
                VideoDownloaderPaneView()
            }
        }
        .frame(minWidth: 500, maxWidth: .infinity, minHeight: 380, maxHeight: .infinity)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .onAppear {
            logManager.startMonitoring()
        }
        .onDisappear {
            logManager.stopMonitoring()
        }
    }
}

struct CastingLogsPaneView: View {
    @ObservedObject var logManager = LogManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(logManager.logLines) { line in
                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.85))
                                .multilineTextAlignment(.leading)
                                .lineLimit(nil)
                                .padding(.vertical, 2)
                        }
                        
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(10)
                }
                .background(Color.clear)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .onChange(of: logManager.logLines) { _ in
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onAppear {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            
            HStack {
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.declareTypes([.string], owner: nil)
                    pasteboard.setString(logManager.rawLogText, forType: .string)
                }) {
                    Label("复制记录", systemImage: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: {
                    let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                    let logURL = paths[0].appendingPathComponent("Macast/macast.log")
                    try? "".write(to: logURL, atomically: true, encoding: .utf8)
                    logManager.logLines = []
                    logManager.rawLogText = ""
                    logManager.castedVideos = []
                }) {
                    Label("清除记录", systemImage: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
    }
}

struct VideoDownloaderPaneView: View {
    @ObservedObject var logManager = LogManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if logManager.castedVideos.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("暂无可下载的投屏视频")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(logManager.castedVideos) { video in
                            VideoDownloadRowView(video: video)
                        }
                    }
                    .padding(4)
                }
            }
        }
        .padding(16)
    }
}

struct VideoDownloadRowView: View {
    let video: CastedVideo
    @ObservedObject var item: DownloadItem
    
    init(video: CastedVideo) {
        self.video = video
        self.item = DownloadManager.shared.getItem(for: video.url, title: video.title)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(video.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(video.timestamp)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Text(video.url)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack {
                    Text("来自设备: \(video.device)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    switch item.status {
                    case .idle:
                        EmptyView()
                    case .downloading(let progress):
                        ProgressView(value: progress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(width: 120)
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.blue)
                    case .completed:
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 11))
                            Text("已完成")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.green)
                        }
                    case .failed(let error):
                        Text("失败: \(error)")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 6)
            
            Divider()
            
            // Download Button
            Button(action: {
                if case .completed(let localURL) = item.status {
                    NSWorkspace.shared.activateFileViewerSelecting([localURL])
                } else {
                    DownloadManager.shared.download(urlStr: video.url, title: video.title)
                }
            }) {
                VStack(spacing: 4) {
                    Image(systemName: downloadButtonImage)
                        .font(.system(size: 16))
                    Text(downloadButtonText)
                        .font(.system(size: 9, weight: .semibold))
                }
                .frame(width: 50, height: 45)
                .background(downloadButtonBgColor)
                .foregroundColor(downloadButtonFgColor)
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isDownloadDisabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }
    
    private var downloadButtonImage: String {
        switch item.status {
        case .idle: return "arrow.down.circle"
        case .downloading: return "arrow.clockwise.circle"
        case .completed: return "folder.circle"
        case .failed: return "exclamationmark.arrow.triangle.2.circlepath"
        }
    }
    
    private var downloadButtonText: String {
        switch item.status {
        case .idle: return "下载"
        case .downloading: return "下载中"
        case .completed: return "打开"
        case .failed: return "重试"
        }
    }
    
    private var downloadButtonBgColor: Color {
        switch item.status {
        case .idle: return Color.blue.opacity(0.15)
        case .downloading: return Color.gray.opacity(0.1)
        case .completed: return Color.green.opacity(0.15)
        case .failed: return Color.orange.opacity(0.15)
        }
    }
    
    private var downloadButtonFgColor: Color {
        switch item.status {
        case .idle: return Color.blue
        case .downloading: return Color.secondary
        case .completed: return Color.green
        case .failed: return Color.orange
        }
    }
    
    private var isDownloadDisabled: Bool {
        if case .downloading = item.status {
            return true
        }
        return false
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover = NSPopover()
    
    var settingsWindow: NSWindow?
    var logWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        SettingsManager.shared.load()
        MacastProcessManager.shared.start()
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            // Using modern TV icon which matches the screen-casting theme
            button.image = NSImage(systemSymbolName: "play.tv.fill", accessibilityDescription: "Macast")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        popover.contentViewController = NSHostingController(rootView: PopoverView(
            onOpenSettings: { [weak self] in self?.openSettings() },
            onOpenLogs: { [weak self] in self?.openLogs() },
            onQuit: { [weak self] in self?.quitApp() }
        ))
        popover.behavior = .transient
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = statusItem?.button {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }
    
    func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 500),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            window.center()
            window.title = "Macast 设置"
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func openLogs() {
        if logWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 420),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.center()
            window.title = "Macast 投屏历史"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.contentViewController = NSHostingController(rootView: LogView())
            window.isReleasedWhenClosed = false
            logWindow = window
        }
        logWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func quitApp() {
        MacastProcessManager.shared.stop {
            NSApp.terminate(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NSApp.terminate(nil)
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        MacastProcessManager.shared.stop()
    }
}

// MARK: - App Main
@main
struct MacastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
