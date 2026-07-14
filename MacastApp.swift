//
//  MacastApp.swift
//  Macast
//
//  Modified & optimized by anyi11 (https://github.com/anyi11/mac-cast)
//

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
        
        var env = ProcessInfo.processInfo.environment
        if let resourceURL = Bundle.main.resourceURL {
            let sitePackagesPath = resourceURL.appendingPathComponent("site-packages").path
            if let existingPythonPath = env["PYTHONPATH"] {
                env["PYTHONPATH"] = "\(sitePackagesPath):\(existingPythonPath)"
            } else {
                env["PYTHONPATH"] = sitePackagesPath
            }
        }
        newProcess.environment = env
        
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
    var PlayerLockSize: Int = 0
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
            if settings.Macast_Renderer == "MPV" {
                settings.Macast_Renderer = "MPV Renderer"
            }
        } catch {
            print("Could not load settings, using defaults.")
            save()
        }
    }
    
    func save() {
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: fileURL, options: .atomic)
            
            // Update tooltip on status bar button
            DispatchQueue.main.async {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.updateStatusItemTooltip()
                }
            }
            
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

struct CastedVideo: Identifiable, Equatable, Codable {
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
    
    private var logBackupURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("Macast/macast.log.1")
    }
    
    private var historyURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("Macast/history.json")
    }
    
    init() {
        self.castedVideos = loadCastedVideos()
    }
    
    private func loadCastedVideos() -> [CastedVideo] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        return (try? JSONDecoder().decode([CastedVideo].self, from: data)) ?? []
    }
    
    private func saveCastedVideos(_ videos: [CastedVideo]) {
        if let data = try? JSONEncoder().encode(videos) {
            try? data.write(to: historyURL, options: .atomic)
        }
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
    
    func readLog() {
        guard !isReading else { return }
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            DispatchQueue.main.async {
                self.logLines = [LogLine(id: 0, text: "暂无运行记录。")]
                self.rawLogText = "暂无运行记录。"
            }
            return
        }
        
        isReading = true
        let url = logURL
        let backupUrl = logBackupURL
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer {
                DispatchQueue.main.async {
                    self?.isReading = false
                }
            }
            
            do {
                var backupText = ""
                if FileManager.default.fileExists(atPath: backupUrl.path) {
                    if let backupData = try? Data(contentsOf: backupUrl),
                       let text = String(data: backupData, encoding: .utf8) {
                        backupText = text
                    }
                }
                
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) else {
                    DispatchQueue.main.async {
                        self?.logLines = [LogLine(id: 0, text: "解析记录失败。")]
                        self?.rawLogText = "解析记录失败。"
                    }
                    return
                }
                
                let combinedText = backupText + text
                let allLines = combinedText.components(separatedBy: .newlines)
                
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
                
                let linesToKeep = 50
                let startIdx = max(0, filtered.count - linesToKeep)
                let finalLines = Array(filtered[startIdx..<filtered.count])
                
                var structuredLines: [LogLine] = []
                structuredLines.reserveCapacity(finalLines.count)
                for (index, lineText) in finalLines.enumerated() {
                    structuredLines.append(LogLine(id: index, text: lineText))
                }
                
                let rawText = finalLines.joined(separator: "\n")
                
                // Load existing videos from file and merge them with newly parsed ones
                var mergedVideos = self?.loadCastedVideos() ?? []
                for video in videos {
                    if !mergedVideos.contains(where: { $0.id == video.id }) {
                        mergedVideos.append(video)
                    }
                }
                
                // Sort by timestamp (newest first)
                mergedVideos.sort(by: { $0.timestamp > $1.timestamp })
                
                // Keep only the latest 50 videos
                if mergedVideos.count > 50 {
                    mergedVideos = Array(mergedVideos.prefix(50))
                }
                
                // Save updated list
                self?.saveCastedVideos(mergedVideos)
                
                DispatchQueue.main.async {
                    self?.logLines = structuredLines.isEmpty ? [LogLine(id: 0, text: "暂无投屏记录。")] : structuredLines
                    self?.rawLogText = rawText.isEmpty ? "暂无投屏记录。" : rawText
                    self?.castedVideos = mergedVideos
                }
            } catch {
                DispatchQueue.main.async {
                    self?.logLines = [LogLine(id: 0, text: "读取记录失败: \(error.localizedDescription)")]
                    self?.rawLogText = "读取记录失败: \(error.localizedDescription)"
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

// MARK: - Playback Manager
class PlaybackManager: ObservableObject {
    static let shared = PlaybackManager()
    
    @Published var hasActiveVideo = false
    @Published var currentTitle = ""
    @Published var currentURI = ""
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = false
    
    var isDragging = false
    private var timer: Timer?
    
    private var port: Int {
        return SettingsManager.shared.settings.ApplicationPort
    }
    
    func startPolling() {
        guard timer == nil else { return }
        pollStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollStatus()
        }
    }
    
    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
    
    func pollStatus() {
        guard MacastProcessManager.shared.isRunning else {
            DispatchQueue.main.async {
                if self.hasActiveVideo {
                    self.hasActiveVideo = false
                }
            }
            return
        }
        
        let port = self.port
        let endpoint = "http://127.0.0.1:\(port)/AVTransport/action"
        guard let requestURL = URL(string: endpoint) else { return }
        
        // 1. GetPositionInfo
        var posRequest = URLRequest(url: requestURL)
        posRequest.httpMethod = "POST"
        posRequest.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        posRequest.setValue("\"urn:schemas-upnp-org:service:AVTransport:1#GetPositionInfo\"", forHTTPHeaderField: "SOAPACTION")
        
        let posBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:GetPositionInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
            </u:GetPositionInfo>
          </s:Body>
        </s:Envelope>
        """
        posRequest.httpBody = posBody.data(using: .utf8)
        
        URLSession.shared.dataTask(with: posRequest) { [weak self] data, response, error in
            guard let self = self else { return }
            if let data = data, let xmlString = String(data: data, encoding: .utf8) {
                let trackURI = self.extractTagValue(from: xmlString, tag: "TrackURI") ?? ""
                let relTimeStr = self.extractTagValue(from: xmlString, tag: "RelTime") ?? "00:00:00"
                let durationStr = self.extractTagValue(from: xmlString, tag: "TrackDuration") ?? "00:00:00"
                
                DispatchQueue.main.async {
                    if !trackURI.isEmpty && trackURI != "NOT_IMPLEMENTED" {
                        self.currentURI = trackURI
                        self.duration = self.parseTime(durationStr)
                        if !self.isDragging {
                            self.currentTime = self.parseTime(relTimeStr)
                        }
                        
                        // Find matching title from castedVideos
                        if let matched = LogManager.shared.castedVideos.first(where: { $0.url == trackURI }) {
                            self.currentTitle = matched.title
                        } else {
                            if let urlObj = URL(string: trackURI) {
                                self.currentTitle = urlObj.lastPathComponent
                            } else {
                                self.currentTitle = "投屏视频"
                            }
                        }
                        self.hasActiveVideo = true
                    } else {
                        self.hasActiveVideo = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.hasActiveVideo = false
                }
            }
        }.resume()
        
        // 2. GetTransportInfo
        var stateRequest = URLRequest(url: requestURL)
        stateRequest.httpMethod = "POST"
        stateRequest.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        stateRequest.setValue("\"urn:schemas-upnp-org:service:AVTransport:1#GetTransportInfo\"", forHTTPHeaderField: "SOAPACTION")
        
        let stateBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:GetTransportInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
            </u:GetTransportInfo>
          </s:Body>
        </s:Envelope>
        """
        stateRequest.httpBody = stateBody.data(using: .utf8)
        
        URLSession.shared.dataTask(with: stateRequest) { [weak self] data, response, error in
            guard let self = self else { return }
            if let data = data, let xmlString = String(data: data, encoding: .utf8) {
                let transportState = self.extractTagValue(from: xmlString, tag: "CurrentTransportState") ?? "STOPPED"
                DispatchQueue.main.async {
                    self.isPlaying = (transportState == "PLAYING")
                }
            }
        }.resume()
    }
    
    func play() {
        sendAction("Play", body: """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <Speed>1</Speed>
            </u:Play>
          </s:Body>
        </s:Envelope>
        """) { [weak self] success in
            if success {
                DispatchQueue.main.async {
                    self?.isPlaying = true
                }
            }
        }
    }
    
    func pause() {
        sendAction("Pause", body: """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:Pause xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
            </u:Pause>
          </s:Body>
        </s:Envelope>
        """) { [weak self] success in
            if success {
                DispatchQueue.main.async {
                    self?.isPlaying = false
                }
            }
        }
    }
    
    func seek(to seconds: Double) {
        let timeString = formatTimeForSeek(seconds)
        sendAction("Seek", body: """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:Seek xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <Unit>REL_TIME</Unit>
              <Target>\(timeString)</Target>
            </u:Seek>
          </s:Body>
        </s:Envelope>
        """) { [weak self] success in
            if success {
                DispatchQueue.main.async {
                    self?.currentTime = seconds
                }
            }
        }
    }
    
    func previousVideo() {
        let videos = LogManager.shared.castedVideos
        guard !videos.isEmpty, !currentURI.isEmpty else { return }
        if let currentIdx = videos.firstIndex(where: { $0.url == currentURI }) {
            let targetIdx = currentIdx + 1
            if targetIdx < videos.count {
                playVideo(videos[targetIdx])
            }
        } else {
            if let first = videos.first {
                playVideo(first)
            }
        }
    }
    
    func nextVideo() {
        let videos = LogManager.shared.castedVideos
        guard !videos.isEmpty, !currentURI.isEmpty else { return }
        if let currentIdx = videos.firstIndex(where: { $0.url == currentURI }) {
            let targetIdx = currentIdx - 1
            if targetIdx >= 0 {
                playVideo(videos[targetIdx])
            }
        }
    }
    
    private func playVideo(_ video: CastedVideo) {
        let escapedURI = video.url.replacingOccurrences(of: "&", with: "&amp;")
                                 .replacingOccurrences(of: "<", with: "&lt;")
                                 .replacingOccurrences(of: ">", with: "&gt;")
        
        let escapedTitle = video.title.replacingOccurrences(of: "&", with: "&amp;")
                                      .replacingOccurrences(of: "<", with: "&lt;")
                                      .replacingOccurrences(of: ">", with: "&gt;")
        
        let meta = """
        &lt;DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"&gt;&lt;item id="0" parentID="-1" restricted="1"&gt;&lt;dc:title&gt;\(escapedTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.videoItem&lt;/upnp:class&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
        """
        
        let setURIBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <CurrentURI>\(escapedURI)</CurrentURI>
              <CurrentURIMetaData>\(meta)</CurrentURIMetaData>
            </u:SetAVTransportURI>
          </s:Body>
        </s:Envelope>
        """
        
        sendAction("SetAVTransportURI", body: setURIBody) { [weak self] success in
            if success {
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3) {
                    self?.play()
                }
            }
        }
    }
    
    private func sendAction(_ action: String, body: String, completion: ((Bool) -> Void)? = nil) {
        let port = self.port
        let endpoint = "http://127.0.0.1:\(port)/AVTransport/action"
        guard let requestURL = URL(string: endpoint) else {
            completion?(false)
            return
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"urn:schemas-upnp-org:service:AVTransport:1#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = body.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Failed to send action \(action): \(error)")
                completion?(false)
                return
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                completion?(true)
            } else {
                completion?(false)
            }
        }.resume()
    }
    
    private func extractTagValue(from xml: String, tag: String) -> String? {
        let pattern = "<\(tag)>([^<]*)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        if let match = regex.firstMatch(in: xml, options: [], range: range) {
            if let subRange = Range(match.range(at: 1), in: xml) {
                return String(xml[subRange])
            }
        }
        return nil
    }
    
    private func parseTime(_ timeStr: String) -> Double {
        let parts = timeStr.components(separatedBy: ":")
        var seconds: Double = 0
        if parts.count == 3 {
            let h = Double(parts[0]) ?? 0
            let m = Double(parts[1]) ?? 0
            let s = Double(parts[2]) ?? 0
            seconds = h * 3600 + m * 60 + s
        } else if parts.count == 2 {
            let m = Double(parts[0]) ?? 0
            let s = Double(parts[1]) ?? 0
            seconds = m * 60 + s
        } else if let s = Double(timeStr) {
            seconds = s
        }
        return seconds
    }
    
    private func formatTimeForSeek(_ seconds: Double) -> String {
        let s = Int(seconds) % 60
        let m = (Int(seconds) / 60) % 60
        let h = Int(seconds) / 3600
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

// MARK: - Playback Control Card View
struct PlaybackControlCardView: View {
    @ObservedObject var playbackManager = PlaybackManager.shared
    @State private var localTime: Double = 0
    
    var body: some View {
        VStack(spacing: 12) {
            // Title
            HStack {
                Image(systemName: "play.tv")
                    .foregroundColor(Color(red: 0.0, green: 0.68, blue: 0.93))
                    .font(.system(size: 14, weight: .bold))
                
                Text(playbackManager.currentTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer()
            }
            
            // Slider with time labels
            VStack(spacing: 4) {
                Slider(value: $localTime, in: 0...max(playbackManager.duration, 1.0), onEditingChanged: { editing in
                    if editing {
                        playbackManager.isDragging = true
                    } else {
                        playbackManager.seek(to: localTime)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            playbackManager.isDragging = false
                        }
                    }
                })
                .accentColor(Color(red: 0.0, green: 0.68, blue: 0.93))
                
                HStack {
                    Text(formatTime(localTime))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(formatTime(playbackManager.duration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            // Controls
            HStack(spacing: 24) {
                Spacer()
                
                // Previous
                Button(action: {
                    playbackManager.previousVideo()
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 16))
                        .foregroundColor(hasPreviousVideo ? .primary : .secondary.opacity(0.5))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!hasPreviousVideo)
                
                // Play/Pause
                Button(action: {
                    if playbackManager.isPlaying {
                        playbackManager.pause()
                    } else {
                        playbackManager.play()
                    }
                }) {
                    Image(systemName: playbackManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(Color(red: 0.0, green: 0.68, blue: 0.93))
                }
                .buttonStyle(PlainButtonStyle())
                
                // Next
                Button(action: {
                    playbackManager.nextVideo()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16))
                        .foregroundColor(hasNextVideo ? .primary : .secondary.opacity(0.5))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!hasNextVideo)
                
                Spacer()
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            localTime = playbackManager.currentTime
        }
        .onChange(of: playbackManager.currentTime) { newTime in
            if !playbackManager.isDragging {
                localTime = newTime
            }
        }
    }
    
    private var hasPreviousVideo: Bool {
        let videos = LogManager.shared.castedVideos
        guard !videos.isEmpty, !playbackManager.currentURI.isEmpty else { return false }
        if let currentIdx = videos.firstIndex(where: { $0.url == playbackManager.currentURI }) {
            return currentIdx + 1 < videos.count
        }
        return false
    }
    
    private var hasNextVideo: Bool {
        let videos = LogManager.shared.castedVideos
        guard !videos.isEmpty, !playbackManager.currentURI.isEmpty else { return false }
        if let currentIdx = videos.firstIndex(where: { $0.url == playbackManager.currentURI }) {
            return currentIdx - 1 >= 0
        }
        return false
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds) % 60
        let m = (Int(seconds) / 60) % 60
        let h = Int(seconds) / 3600
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
}

// MARK: - Popover View
struct PopoverView: View {
    @ObservedObject var processManager = MacastProcessManager.shared
    @ObservedObject var settingsManager = SettingsManager.shared
    @ObservedObject var playbackManager = PlaybackManager.shared
    
    var onOpenSettings: () -> Void
    var onOpenLogs: () -> Void
    var onQuit: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text(settingsManager.settings.DLNA_FriendlyName.isEmpty ? "Macast" : settingsManager.settings.DLNA_FriendlyName)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                
                // Status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(processManager.isRunning ? Color(red: 51/255.0, green: 199/255.0, blue: 89/255.0) : Color(red: 235/255.0, green: 87/255.0, blue: 87/255.0))
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
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: processManager.isRunning ?
                            [Color(red: 240/255.0, green: 97/255.0, blue: 97/255.0), Color(red: 224/255.0, green: 72/255.0, blue: 72/255.0)] :
                            [Color(red: 0/255.0, green: 186/255.0, blue: 255/255.0), Color(red: 0/255.0, green: 148/255.0, blue: 224/255.0)]
                        ),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Playback Control Card
            if playbackManager.hasActiveVideo {
                PlaybackControlCardView()
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
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                // Tab 1: General Settings
                Form {
                    HStack(alignment: .center, spacing: 12) {
                        Text("投屏名称:")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 80, alignment: .trailing)
                        TextField("例如: 客厅的Mac", text: $settingsManager.settings.DLNA_FriendlyName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    .padding(.top, 8)
                    
                    HStack(alignment: .center, spacing: 12) {
                        Text("服务端口:")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 80, alignment: .trailing)
                        TextField("默认 1068", value: $settingsManager.settings.ApplicationPort, formatter: NumberFormatter())
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 100)
                        Spacer()
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("开机自启", isOn: Binding(
                            get: { settingsManager.settings.StartAtLogin == 1 },
                            set: { settingsManager.settings.StartAtLogin = $0 ? 1 : 0 }
                        ))
                        Toggle("自动检查更新", isOn: Binding(
                            get: { settingsManager.settings.CheckUpdate == 1 },
                            set: { settingsManager.settings.CheckUpdate = $0 ? 1 : 0 }
                        ))
                        Toggle("哔哩必连 (Bilibili 私有投屏协议)", isOn: Binding(
                            get: { settingsManager.settings.Macast_Protocol == "NVA Protocol" },
                            set: { settingsManager.settings.Macast_Protocol = $0 ? "NVA Protocol" : "DLNA Protocol" }
                        ))
                    }
                    .padding(.leading, 96)
                }
                .padding(20)
                .tabItem {
                    Label("通用", systemImage: "gearshape")
                }
                .tag(0)
                
                // Tab 2: Player Settings
                Form {
                    Picker("选择播放器:", selection: $settingsManager.settings.Macast_Renderer) {
                        Text("内置 MPV 播放器 (默认)").tag("MPV Renderer")
                        Text("系统默认关联播放器 (open)").tag("System Default Player")
                        Text("IINA 播放器").tag("IINA Player")
                        Text("QuickTime Player").tag("QuickTime Player")
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(.top, 4)
                    
                    if settingsManager.settings.Macast_Renderer == "MPV Renderer" {
                        Divider()
                            .padding(.vertical, 8)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("硬件解码", isOn: Binding(
                                get: { settingsManager.settings.PlayerHW == 1 },
                                set: { settingsManager.settings.PlayerHW = $0 ? 1 : 0 }
                            ))
                            Toggle("播放窗口置顶", isOn: Binding(
                                get: { settingsManager.settings.PlayerOntop == 1 },
                                set: { settingsManager.settings.PlayerOntop = $0 ? 1 : 0 }
                            ))
                            Toggle("固定播放器窗口大小", isOn: Binding(
                                get: { settingsManager.settings.PlayerLockSize == 1 },
                                set: { settingsManager.settings.PlayerLockSize = $0 ? 1 : 0 }
                            ))
                        }
                        .padding(.leading, 20)
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        Picker("播放器大小:", selection: $settingsManager.settings.PlayerSize) {
                            Text("小").tag(0)
                            Text("中").tag(1)
                            Text("大").tag(2)
                            Text("自动").tag(3)
                            Text("全屏").tag(4)
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
                }
                .padding(20)
                .tabItem {
                    Label("播放器", systemImage: "play.tv")
                }
                .tag(1)
                
                // Tab 3: Downloads Settings
                Form {
                    HStack(alignment: .top, spacing: 12) {
                        Text("保存路径:")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 80, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(settingsManager.settings.DownloadPath.isEmpty ? "Downloads (默认)" : settingsManager.settings.DownloadPath)
                                .foregroundColor(.secondary)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Button("选择保存目录...") {
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
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(20)
                .tabItem {
                    Label("下载", systemImage: "square.and.arrow.down")
                }
                .tag(2)
            }
            .frame(width: 480, height: 310)
            
            Divider()
            
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
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .padding(.top, 12)
        }
        .frame(width: 480, height: 380)
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

struct ParsedLogEntry: Identifiable {
    let id: Int
    let timestamp: String
    let device: String
    let title: String
    let url: String?
}

func parseLogLine(_ line: LogLine) -> ParsedLogEntry {
    let text = line.text
    var time = ""
    
    if text.hasPrefix("[") && text.contains("]") {
        if let closeBracketIdx = text.firstIndex(of: "]") {
            let start = text.index(after: text.startIndex)
            time = String(text[start..<closeBracketIdx])
        }
    }
    
    let content = text.contains("]") ? String(text[text.index(after: text.firstIndex(of: "]")!)...]).trimmingCharacters(in: .whitespaces) : text
    
    if content.contains("设备 ") && content.contains(" 投屏了:") {
        var device = "未知设备"
        var title = "无标题"
        var urlStr: String? = nil
        
        if let devStart = content.range(of: "设备 "),
           let devEnd = content.range(of: " 投屏了:") {
            device = String(content[devStart.upperBound..<devEnd.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        
        if let titleStart = content.range(of: "投屏了:") {
            if let titleEnd = content.range(of: " | 链接:") {
                title = String(content[titleStart.upperBound..<titleEnd.lowerBound]).trimmingCharacters(in: .whitespaces)
                let rawUrl = String(content[titleEnd.upperBound...])
                urlStr = rawUrl.replacingOccurrences(of: " 链接: ", with: "")
                    .replacingOccurrences(of: "链接:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                title = String(content[titleStart.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        
        return ParsedLogEntry(id: line.id, timestamp: time, device: device, title: title, url: urlStr)
    } else {
        return ParsedLogEntry(id: line.id, timestamp: time, device: "", title: content, url: nil)
    }
}

struct LogRowView: View {
    let entry: ParsedLogEntry
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Time Badge
            if !entry.timestamp.isEmpty {
                Text(entry.timestamp)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)
            }
            
            // Icon & Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if !entry.device.isEmpty {
                        Image(systemName: "play.tv")
                            .font(.system(size: 9))
                            .foregroundColor(Color(red: 0.0, green: 0.68, blue: 0.93))
                        Text(entry.device)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(red: 0.0, green: 0.68, blue: 0.93))
                    } else {
                        Image(systemName: "info.circle")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text("系统")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(entry.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 8)
            
            // Action Button
            if let url = entry.url, !url.isEmpty {
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.declareTypes([.string], owner: nil)
                    pasteboard.setString(url, forType: .string)
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                        Text("复制链接")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(Color(red: 0.0, green: 0.68, blue: 0.93))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.0, green: 0.68, blue: 0.93).opacity(0.12))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .help("复制视频链接")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

// MARK: - Log View
struct LogView: View {
    @ObservedObject var logManager = LogManager.shared
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                CastingLogsPaneView()
                    .tabItem {
                        Label("投屏日志", systemImage: "list.bullet.rectangle")
                    }
                    .tag(0)
                
                VideoDownloaderPaneView()
                    .tabItem {
                        Label("视频下载", systemImage: "arrow.down.circle")
                    }
                    .tag(1)
            }
        }
        .frame(minWidth: 500, maxWidth: .infinity, minHeight: 380, maxHeight: .infinity)
        .onAppear {
            logManager.readLog()
        }
    }
}

struct CastingLogsPaneView: View {
    @ObservedObject var logManager = LogManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(logManager.logLines) { line in
                            LogRowView(entry: parseLogLine(line))
                        }
                        
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(2)
                }
                .background(Color.clear)
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
                
                // Realtime Update indicator
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color(red: 51/255.0, green: 199/255.0, blue: 89/255.0))
                        .frame(width: 5, height: 5)
                    Text("实时更新")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(red: 51/255.0, green: 199/255.0, blue: 89/255.0))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(red: 51/255.0, green: 199/255.0, blue: 89/255.0).opacity(0.12))
                .cornerRadius(6)
                
                Spacer()
                
                Button(action: {
                    let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                    let logURL = paths[0].appendingPathComponent("Macast/macast.log")
                    try? "".write(to: logURL, atomically: true, encoding: .utf8)
                    let historyURL = paths[0].appendingPathComponent("Macast/history.json")
                    try? FileManager.default.removeItem(at: historyURL)
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
                        .font(.system(size: 13, weight: .semibold))
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
            
            // Copy Link Button
            Button(action: {
                let pasteboard = NSPasteboard.general
                pasteboard.declareTypes([.string], owner: nil)
                pasteboard.setString(video.url, forType: .string)
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 16))
                    Text("复制")
                        .font(.system(size: 9, weight: .semibold))
                }
                .frame(width: 50, height: 45)
                .background(Color.primary.opacity(0.05))
                .foregroundColor(.primary.opacity(0.8))
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
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
        PlaybackManager.shared.startPolling()
        LogManager.shared.startMonitoring()
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            // Using modern TV icon which matches the screen-casting theme
            button.image = NSImage(systemSymbolName: "play.tv.fill", accessibilityDescription: "Macast")
            button.action = #selector(togglePopover(_:))
            button.target = self
            updateStatusItemTooltip()
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
    
    func updateStatusItemTooltip() {
        if let button = statusItem?.button {
            let friendlyName = SettingsManager.shared.settings.DLNA_FriendlyName
            button.toolTip = friendlyName.isEmpty ? "Macast" : friendlyName
        }
    }
    
    func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
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
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 450),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false)
            window.center()
            window.title = "Macast 投屏历史"
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
        PlaybackManager.shared.stopPolling()
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
