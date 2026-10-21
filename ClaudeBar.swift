import Cocoa

// Uses the same endpoint Claude Code's /usage reads, authed with Claude Code's OAuth token.
let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

func accessToken() -> String? {
    // Both the Linux-style file and the macOS Keychain item can exist; a stale one must not
    // shadow the other, so take whichever token expires last.
    let file = try? Data(contentsOf: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/.credentials.json"))
    let p = Process(), pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    var keychain: Data?
    if (try? p.run()) != nil {
        keychain = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
    }
    let creds = [file, keychain].compactMap { d -> [String: Any]? in
        guard let d, let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return json["claudeAiOauth"] as? [String: Any]
    }
    let best = creds.max { ($0["expiresAt"] as? Double ?? 0) < ($1["expiresAt"] as? Double ?? 0) }
    return best?["accessToken"] as? String
}

enum Provider: String, CaseIterable {
    case claude = "Claude", codex = "Codex"

    var icon: NSImage? {
        let name = self == .claude ? "claude" : "openai"
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.accessibilityDescription = rawValue
        image.isTemplate = true
        return image
    }
}

func codexExecutable() -> String? {
    let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        + ["/opt/homebrew/bin", "/usr/local/bin", "/Applications/Codex.app/Contents/Resources"]
    return paths.map { $0 + "/codex" }.first { FileManager.default.isExecutableFile(atPath: $0) }
}

struct UsageWindow {
    let title: String
    let percent: Int
    let reset: Date?
}

struct UsageError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// Read-only JSON-RPC session; Codex handles its own credentials and token refresh.
func codexUsage() throws -> [UsageWindow] {
    guard let executable = codexExecutable() else {
        throw UsageError(message: "Install Codex CLI, then choose Connect Codex")
    }
    let process = Process(), input = Pipe(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = ["app-server"]
    process.standardInput = input
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
    defer {
        timeout.cancel()
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        try? output.fileHandleForReading.close()
    }
    func send(_ value: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: value)
        data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }
    func response(_ id: Int) throws -> [String: Any] {
        var line = Data()
        while let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty {
            if byte[0] != 10 { line.append(byte); continue }
            defer { line.removeAll(keepingCapacity: true) }
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  json["id"] as? Int == id else { continue }
            if let error = json["error"] as? [String: Any] {
                throw UsageError(message: error["message"] as? String ?? "Connect Codex with a ChatGPT account")
            }
            if let result = json["result"] as? [String: Any] { return result }
            throw UsageError(message: "Invalid Codex response")
        }
        throw UsageError(message: "Codex unavailable or timed out — try Refresh")
    }
    try send(["id": 0, "method": "initialize", "params": ["clientInfo": ["name": "claude_bar", "version": "1.1.0"]]])
    _ = try response(0)
    try send(["method": "initialized", "params": [:]])
    try send(["id": 1, "method": "account/rateLimits/read"])
    let result = try response(1)
    let buckets = result["rateLimitsByLimitId"] as? [String: Any]
    guard let limits = (buckets?["codex"] ?? result["rateLimits"]) as? [String: Any] else {
        throw UsageError(message: "No Codex usage available for this account")
    }
    let windows = ["primary", "secondary"].compactMap { key -> UsageWindow? in
        guard let window = limits[key] as? [String: Any],
              let percent = window["usedPercent"] as? Double else { return nil }
        let minutes = window["windowDurationMins"] as? Int ?? 0
        let title = minutes == 10080 ? "Weekly" : minutes == 300 ? "5-hour" : minutes > 0 ? "\(minutes)-minute" : key.capitalized
        let reset = (window["resetsAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
        return UsageWindow(title: title, percent: min(100, max(0, Int(percent))), reset: reset)
    }
    guard !windows.isEmpty else { throw UsageError(message: "No Codex usage windows available") }
    return windows
}

func parseDate(_ s: String?) -> Date? {
    guard let s else { return nil }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)
}

func resetText(_ date: Date?) -> String {
    guard let date else { return "" }
    let mins = max(0, Int(date.timeIntervalSinceNow / 60))
    if mins < 24 * 60 { return "resets in \(mins / 60)h \(mins % 60)m" }
    let f = DateFormatter()
    f.dateFormat = "EEE HH:mm"
    return "resets \(f.string(from: date))"
}

// Speedometer dial: a 270° sweep running clockwise from bottom-left (225°) to bottom-right (-45°).
let dialStart: CGFloat = 225, dialSweep: CGFloat = 270

func gaugeColor(_ pct: Int) -> NSColor {
    pct < 50 ? .systemGreen : pct < 80 ? .systemOrange : .systemRed
}

func drawGauge(in rect: NSRect, percent: Int, lineWidth: CGFloat, detailed: Bool) {
    let p = CGFloat(min(max(percent, 0), 100)) / 100
    let center = NSPoint(x: rect.midX, y: rect.midY)
    let radius = min(rect.width, rect.height) / 2 - lineWidth / 2
    func point(_ angle: CGFloat, _ r: CGFloat) -> NSPoint {
        let a = angle * .pi / 180
        return NSPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
    }
    func arc(to fraction: CGFloat, _ color: NSColor) {
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: dialStart,
                       endAngle: dialStart - dialSweep * fraction, clockwise: true)
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    arc(to: 1, .tertiaryLabelColor)
    if p > 0 { arc(to: p, gaugeColor(percent)) }

    if detailed {
        NSColor.secondaryLabelColor.setStroke()
        for i in 0...10 {
            let angle = dialStart - dialSweep * CGFloat(i) / 10
            let tick = NSBezierPath()
            tick.move(to: point(angle, radius - lineWidth / 2 - (i % 5 == 0 ? 10 : 6)))
            tick.line(to: point(angle, radius - lineWidth / 2 - 3))
            tick.lineWidth = i % 5 == 0 ? 1.5 : 1
            tick.stroke()
        }
    }

    let needle = NSBezierPath()
    needle.move(to: center)
    needle.line(to: point(dialStart - dialSweep * p, radius - lineWidth / 2 - (detailed ? 12 : 1)))
    needle.lineWidth = detailed ? 2.5 : 1.5
    needle.lineCapStyle = .round
    NSColor.labelColor.setStroke()
    needle.stroke()
    let hub: CGFloat = detailed ? 5 : 1.5
    NSColor.labelColor.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2)).fill()
}

func miniGauge(_ pct: Int) -> NSImage {
    NSImage(size: NSSize(width: 16, height: 16), flipped: false) { r in
        drawGauge(in: r, percent: pct, lineWidth: 2.5, detailed: false)
        return true
    }
}

func drawCentered(_ text: String, x: CGFloat, y: CGFloat, font: NSFont, color: NSColor = .labelColor) {
    let s = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    s.draw(at: NSPoint(x: x - s.size().width / 2, y: y))
}

final class GaugeView: NSView {
    var title = "" { didSet { needsDisplay = true } }
    var subtitle = "" { didSet { needsDisplay = true } }
    var percent = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let dial = NSRect(x: (bounds.width - 120) / 2, y: 34, width: 120, height: 120)
        drawGauge(in: dial, percent: percent, lineWidth: 10, detailed: true)
        drawCentered("\(percent)%", x: dial.midX, y: dial.midY - 44, font: .monospacedDigitSystemFont(ofSize: 18, weight: .semibold))
        drawCentered(title, x: bounds.midX, y: 18, font: .systemFont(ofSize: 12, weight: .medium))
        drawCentered(subtitle, x: bounds.midX, y: 3, font: .systemFont(ofSize: 10), color: .secondaryLabelColor)
    }
}

final class Controller: NSObject {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let fiveHour = GaugeView(frame: NSRect(x: 10, y: 0, width: 150, height: 160))
    let weekly = GaugeView(frame: NSRect(x: 160, y: 0, width: 150, height: 160))
    let updated = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    var provider = Provider(rawValue: UserDefaults.standard.string(forKey: "provider") ?? "") ?? .claude
    var providerItems: [Provider: NSMenuItem] = [:]
    var requestID = UUID()

    override init() {
        super.init()
        item.button?.title = "…"
        item.button?.toolTip = "5-hour · Weekly usage"
        fiveHour.title = "5-hour"
        weekly.title = "Weekly"
        let gauges = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 166))
        gauges.addSubview(fiveHour)
        gauges.addSubview(weekly)
        let gaugeItem = NSMenuItem()
        gaugeItem.view = gauges
        let menu = NSMenu()
        for provider in Provider.allCases {
            let choice = NSMenuItem(title: provider.rawValue, action: #selector(selectProvider(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = provider.rawValue
            providerItems[provider] = choice
            menu.addItem(choice)
        }
        menu.addItem(.separator())
        [gaugeItem, .separator(), updated, .separator()].forEach(menu.addItem)
        for provider in Provider.allCases {
            let connect = NSMenuItem(title: "Connect \(provider.rawValue)…", action: #selector(connectProvider(_:)), keyEquivalent: "")
            connect.target = self
            connect.representedObject = provider.rawValue
            menu.addItem(connect)
        }
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        refresh()
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.refresh() }
    }

    @objc func selectProvider(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let selected = Provider(rawValue: name) else { return }
        provider = selected
        UserDefaults.standard.set(selected.rawValue, forKey: "provider")
        refresh()
    }

    @objc func connectProvider(_ sender: NSMenuItem) {
        selectProvider(sender)
        let command = provider == .codex ? "codex login" : "claude auth login"
        let alert = NSAlert()
        alert.messageText = "Connect \(provider.rawValue)"
        alert.informativeText = "Run ‘\(command)’ in Terminal to sign in, then choose Refresh. Existing CLI logins are connected automatically. Codex usage requires a ChatGPT account."
        alert.addButton(withTitle: "Copy login command")
        alert.addButton(withTitle: "Close")
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        }
    }

    @objc func refresh() {
        let id = UUID()
        requestID = id
        let selected = provider
        providerItems.forEach { $0.value.state = $0.key == selected ? .on : .off }
        item.button?.image = selected.icon
        item.button?.imagePosition = .imageLeading
        item.button?.setAccessibilityLabel(selected.rawValue + " usage")
        item.button?.attributedTitle = NSAttributedString(string: " …")
        item.button?.toolTip = "\(selected.rawValue) usage"
        updated.title = "Connecting to \(selected.rawValue)…"
        fiveHour.isHidden = true
        weekly.isHidden = true
        DispatchQueue.global(qos: .utility).async {
            if selected == .codex {
                let result = Result { try codexUsage() }
                DispatchQueue.main.async {
                    guard self.requestID == id else { return }
                    switch result {
                    case .success(let windows): self.show(windows)
                    case .failure(let error): self.show(error: error.localizedDescription)
                    }
                }
                return
            }
            guard let token = accessToken() else {
                DispatchQueue.main.async {
                    if self.requestID == id { self.show(error: "No Claude Code login found — choose Connect Claude") }
                }
                return
            }
            var req = URLRequest(url: usageURL, timeoutInterval: 30)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            URLSession.shared.dataTask(with: req) { data, resp, error in
                DispatchQueue.main.async {
                    guard self.requestID == id else { return }
                    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200, let data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else { return self.show(error: status == 401 ? "Token expired – run claude once" : error?.localizedDescription ?? "HTTP \(status)") }
                    let (h, hr) = self.window(json, "five_hour")
                    let (w, wr) = self.window(json, "seven_day")
                    self.show([UsageWindow(title: "5-hour", percent: h, reset: hr), UsageWindow(title: "Weekly", percent: w, reset: wr)])
                }
            }.resume()
        }
    }

    func window(_ json: [String: Any], _ key: String) -> (Int, Date?) {
        let w = json[key] as? [String: Any]
        return (Int((w?["utilization"] as? Double) ?? 0), parseDate(w?["resets_at"] as? String))
    }

    func show(_ windows: [UsageWindow]) {
        let title = NSMutableAttributedString(string: " ", attributes: [
            .font: NSFont.menuBarFont(ofSize: 0), .foregroundColor: NSColor.labelColor])
        for window in windows {
            let icon = NSTextAttachment()
            icon.image = miniGauge(window.percent)
            icon.bounds = NSRect(x: 0, y: -3, width: 16, height: 16)
            title.append(NSAttributedString(attachment: icon))
            title.append(NSAttributedString(string: " \(window.percent)%  ", attributes: [
                .font: NSFont.menuBarFont(ofSize: 0), .foregroundColor: NSColor.labelColor]))
        }
        item.button?.attributedTitle = title
        for (index, gauge) in [fiveHour, weekly].enumerated() {
            gauge.isHidden = index >= windows.count
            guard index < windows.count else { continue }
            let window = windows[index]
            (gauge.title, gauge.percent, gauge.subtitle) = (window.title, window.percent, resetText(window.reset))
        }
        item.button?.toolTip = provider.rawValue + " · " + windows.map { "\($0.title): \($0.percent)% used" }.joined(separator: " · ")
        updated.title = "Updated \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))"
    }

    func show(error: String) {
        item.button?.attributedTitle = NSAttributedString(string: " ⚠︎")
        fiveHour.isHidden = true
        weekly.isHidden = true
        updated.title = error
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
app.run()
