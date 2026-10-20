import Cocoa

// Uses the same endpoint Claude Code's /usage reads, authed with Claude Code's OAuth token.
let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

func accessToken() -> String? {
    // Linux-style file first, then the macOS Keychain item Claude Code writes.
    var data = try? Data(contentsOf: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/.credentials.json"))
    if data == nil {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return nil }
        data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
    }
    guard let d = data,
          let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
          let oauth = json["claudeAiOauth"] as? [String: Any] else { return nil }
    return oauth["accessToken"] as? String
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

    override init() {
        super.init()
        item.button?.title = "Claude …"
        item.button?.toolTip = "5-hour · Weekly usage"
        fiveHour.title = "5-hour"
        weekly.title = "Weekly"
        let gauges = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 166))
        gauges.addSubview(fiveHour)
        gauges.addSubview(weekly)
        let gaugeItem = NSMenuItem()
        gaugeItem.view = gauges
        let menu = NSMenu()
        [gaugeItem, .separator(), updated, .separator()].forEach(menu.addItem)
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        refresh()
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.refresh() }
    }

    @objc func refresh() {
        guard let token = accessToken() else { return show(error: "No Claude Code login found") }
        var req = URLRequest(url: usageURL)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            DispatchQueue.main.async {
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200, let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return self.show(error: status == 401 ? "Token expired – run claude once" : "HTTP \(status)") }
                self.show(json)
            }
        }.resume()
    }

    func window(_ json: [String: Any], _ key: String) -> (Int, Date?) {
        let w = json[key] as? [String: Any]
        return (Int((w?["utilization"] as? Double) ?? 0), parseDate(w?["resets_at"] as? String))
    }

    func show(_ json: [String: Any]) {
        let (h, hReset) = window(json, "five_hour")
        let (w, wReset) = window(json, "seven_day")
        let title = NSMutableAttributedString()
        for (pct, text) in [(h, " \(h)%  "), (w, " \(w)%")] {
            let icon = NSTextAttachment()
            icon.image = miniGauge(pct)
            icon.bounds = NSRect(x: 0, y: -3, width: 16, height: 16)
            title.append(NSAttributedString(attachment: icon))
            title.append(NSAttributedString(string: text, attributes: [
                .font: NSFont.menuBarFont(ofSize: 0), .foregroundColor: NSColor.labelColor]))
        }
        item.button?.attributedTitle = title
        (fiveHour.percent, fiveHour.subtitle) = (h, resetText(hReset))
        (weekly.percent, weekly.subtitle) = (w, resetText(wReset))
        updated.title = "Updated \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))"
    }

    func show(error: String) {
        item.button?.title = "Claude ⚠︎"
        updated.title = error
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
app.run()
