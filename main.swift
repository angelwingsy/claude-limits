// Claude Limits — pixel Claude in the menu bar; click for a glass pop-up with your usage limits.
// Data comes from claude.ai through a hidden web view (sign in once via "Usage page").
// The crab dances while Claude is working anywhere on this Mac: it watches how many bytes arrive
// from Anthropic's servers (never their content) and waits still when nothing is streaming.
import Cocoa
import SwiftUI
import WebKit

let usageURL = URL(string: "https://claude.ai/settings/usage")!
let claudeOrange = NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)

// MARK: - Model

struct Limit { var pct: Double; var resets: Date? }
struct Scoped: Identifiable { let title: String; let limit: Limit; var id: String { title } }

final class Model: ObservableObject {
    @Published var session: Limit?
    @Published var week: Limit?
    @Published var scoped: [Scoped] = []   // per-model weekly limits, e.g. Fable
    @Published var signedIn = true
    @Published var frame = 0
    @Published var blink = false
    @Published var working = false

    var mood: Mascot.Mood {
        guard signedIn else { return .off }
        let top = ([session, week].compactMap { $0?.pct } + scoped.map(\.limit.pct)).max() ?? 0
        return top >= 80 ? .stressed : top >= 50 ? .awake : .chill
    }

    var caption: String {
        if working && signedIn { return "Claude is working…" }
        switch mood {
        case .chill: return "Plenty left. Vibing."
        case .awake: return "Getting busy."
        case .stressed: return "Running hot. Pace yourself."
        case .off: return "Not signed in"
        }
    }
}

// MARK: - Pixel mascot

enum Mascot {
    enum Mood { case chill, awake, stressed, off }

    // o body, b headphones, k eyes, d sweat drop
    static let base = [
        "....bbbbbbbb....",
        "...b........b...",
        "..b..........b..",
        "..boooooooooob..",
        ".bboooooooooobb.",
        ".bboooooooooobb.",
        ".bboooooooooobb.",
        "oooooooooooooooo",
        "oooooooooooooooo",
        "...oooooooooo...",
        "....o.o..o.o....",
        "....o.o..o.o....",
    ]

    // Dance steps: lean (degrees), bob (pixels, negative is up), which arm drops.
    static let dance: [(angle: CGFloat, bob: CGFloat, leftDown: Bool, rightDown: Bool)] = [
        (0, 0, false, false), (8, -1, true, false), (0, 0.5, false, false), (0, 0, false, true),
        (0, 0, false, false), (-8, -1, false, true), (0, 0.5, false, false), (0, 0, true, false),
    ]

    static func image(_ mood: Mood, pixel p: CGFloat, frame: Int = 0, blink: Bool = false) -> NSImage {
        var g = base.map { Array($0) }
        switch mood {
        case _ where blink, .chill, .off:        // eyes closed
            for c in [4, 5, 10, 11] { g[5][c] = "k" }
        case .awake, .stressed:                  // eyes open
            for r in [4, 5] { g[r][5] = "k"; g[r][10] = "k" }
        }
        if mood == .stressed { g[1][14] = "d"; g[2][15] = "d" }

        let step = mood == .off ? dance[0] : dance[frame % dance.count]
        for (down, cols) in [(step.leftDown, 0...2), (step.rightDown, 13...15)] where down {
            for c in cols { g[7][c] = "."; g[9][c] = "o" }
        }

        let body = mood == .off ? NSColor.systemGray : claudeOrange
        let colors: [Character: NSColor] = [
            "o": body,
            "b": NSColor(red: 0.16, green: 0.27, blue: 0.55, alpha: 1),
            "k": NSColor(red: 0.12, green: 0.10, blue: 0.09, alpha: 1),
            "d": NSColor(red: 0.49, green: 0.77, blue: 1.0, alpha: 1),
        ]
        let cols = CGFloat(g[0].count), rows = CGFloat(g.count)
        let size = NSSize(width: (cols + 4) * p, height: (rows + 3) * p)  // room to lean and bob
        return NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: size.width / 2, y: size.height - p + step.bob * p)  // pivot at the feet
            ctx.rotate(by: step.angle * .pi / 180)
            ctx.translateBy(x: -cols * p / 2, y: -rows * p)
            for (ch, color) in colors {
                let path = NSBezierPath()
                for (r, row) in g.enumerated() {
                    for (c, x) in row.enumerated() where x == ch {
                        path.appendRect(NSRect(x: CGFloat(c) * p, y: CGFloat(r) * p, width: p, height: p))
                    }
                }
                color.setFill()
                path.fill()
            }
            return true
        }
    }
}

// MARK: - Pop-up

struct LimitRow: View {
    let title: String
    let limit: Limit?

    var body: some View {
        let pct = limit?.pct ?? 0
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(limit.map { "\(Int($0.pct.rounded()))%" } ?? "–")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.12))
                    Capsule()
                        .fill(pct >= 80 ? Color.red : Color(nsColor: claudeOrange))
                        .frame(width: max(6, geo.size.width * min(pct / 100, 1)))
                }
            }
            .frame(height: 6)
            Text(Self.resetText(limit?.resets)).font(.caption).foregroundStyle(.secondary)
        }
    }

    static func resetText(_ date: Date?) -> String {
        guard let date else { return " " }
        let s = Int(date.timeIntervalSinceNow)
        if s <= 0 { return "Resetting now" }
        if s < 86_400 {
            let h = s / 3600, m = s % 3600 / 60
            return h > 0 ? "Resets in \(h) hr \(m) min" : "Resets in \(m) min"
        }
        let f = DateFormatter()
        f.dateFormat = "EEE HH:mm"
        return "Resets \(f.string(from: date))"
    }
}

struct PopupView: View {
    @ObservedObject var model: Model
    let openPage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: Mascot.image(model.mood, pixel: 3, frame: model.frame, blink: model.blink))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude limits").font(.headline)
                    Text(model.caption).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if model.signedIn {
                LimitRow(title: "Current session", limit: model.session)
                LimitRow(title: "This week", limit: model.week)
                ForEach(model.scoped) { LimitRow(title: $0.title, limit: $0.limit) }
            } else {
                Text("Sign in to claude.ai to see your limits.").font(.callout)
            }
            HStack {
                Button(model.signedIn ? "Usage page" : "Sign in", action: openPage)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 270)
    }
}

// MARK: - Claude activity

// Watches every TCP and UDP (QUIC) connection to Anthropic (claude.ai, the API, Claude Code, Claude Design, the desktop
// app, any browser) with nettop, once a second. A streaming reply feeds one connection every second;
// idle traffic (heartbeats, polling) arrives in single blips, so "busy in 3 of the last 4 seconds" means working.
final class ActivityMonitor {
    static let window = 4, needed = 3       // seconds looked at, busy seconds required
    static let minBytes = 20                // bytes in a second that count as busy (thinking pings are ~40)
    static let linger: TimeInterval = 10    // keep dancing through pauses (tool runs, file edits)
    static let debug = CommandLine.arguments.contains("--debug")  // logs each sample to the log file

    var onChange: ((Bool) -> Void)?
    var debugLog: ((String) -> Void)?
    var quietUntil = Date.distantPast       // ignore our own claude.ai requests
    private var history: [String: [Bool]] = [:]   // per connection, busy flag for the last `window` seconds
    private var current: [String: Int] = [:]
    private var buffer = "", proc = ""
    private var samples = 0
    private var lastActive = Date.distantPast
    private var working = false

    func start() {
        let p = Process()
        // `script` gives nettop a terminal, so it prints every second instead of buffering.
        p.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        p.arguments = ["-q", "/dev/null", "/usr/bin/nettop",
                       "-n", "-x", "-d", "-s", "1", "-L", "0", "-J", "bytes_in"]
        let pipe = Pipe()
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let text = String(decoding: h.availableData, as: UTF8.self)
            DispatchQueue.main.async { self?.consume(text) }
        }
        p.terminationHandler = { [weak self] _ in   // restart if nettop ever exits
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self?.samples = 0; self?.start() }
        }
        try? p.run()
    }

    private func consume(_ text: String) {
        buffer += text.replacingOccurrences(of: "\r", with: "")   // the terminal ends lines with \r\n
        while let nl = buffer.firstIndex(of: "\n") {
            let line = buffer[..<nl]
            buffer.removeSubrange(...nl)
            if line.hasPrefix(",bytes_in") {            // header: a new one-second sample starts
                if samples > 1 { finishSample() }       // sample 1 holds totals, not deltas
                samples += 1
                current = [:]
                continue
            }
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            guard line.hasPrefix("tcp") || line.hasPrefix("udp") else { proc = String(parts.first ?? ""); continue }
            guard line.contains("<->160.79.10") || line.contains("<->2607:6bc0:"),
                  parts.count > 1, let bytes = Int(parts[1]) else { continue }
            current[proc + parts[0], default: 0] += bytes
        }
    }

    private func finishSample() {
        for key in Set(history.keys).union(current.keys) {
            var h = (history[key] ?? []) + [(current[key] ?? 0) >= Self.minBytes]
            h = Array(h.suffix(Self.window))
            history[key] = h.contains(true) ? h : nil
        }
        let streaming = history.values.contains { $0.filter { $0 }.count >= Self.needed }
        if streaming && Date() > quietUntil { lastActive = Date() }
        let now = Date().timeIntervalSince(lastActive) < Self.linger
        if Self.debug { debugLog?("bytes=\(current.values.reduce(0, +)) streaming=\(streaming) working=\(now)") }
        if now != working { working = now; onChange?(now) }
    }
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    let model = Model()
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let popover = NSPopover()
    let activity = ActivityMonitor()
    var idleTicks = 0
    var drawnIcon = ""
    var window: NSWindow!
    var web: WKWebView!

    func applicationDidFinishLaunching(_ n: Notification) {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()  // keeps the login between launches
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 440, height: 620), configuration: cfg)
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        web.navigationDelegate = self
        web.load(URLRequest(url: usageURL))

        window = NSWindow(contentRect: web.frame, styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Claude Limits"
        window.contentView = web
        window.isReleasedWhenClosed = false
        window.center()

        // Edit menu so Cmd+C / Cmd+V / Cmd+A work in the sign-in fields.
        let main = NSMenu(), editItem = NSMenuItem(), edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main

        popover.behavior = .transient
        let host = NSHostingController(rootView: PopupView(model: model) { [weak self] in self?.openPage() })
        host.sizingOptions = .preferredContentSize  // size is known before showing, so it opens right under the icon
        popover.contentViewController = host

        item.button?.target = self
        item.button?.action = #selector(togglePopup)
        item.button?.imagePosition = .imageLeft
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        updateButton()

        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.refresh() }
        activity.onChange = { [weak self] working in self?.model.working = working }
        activity.debugLog = { [weak self] in self?.log($0) }
        activity.start()
        scheduleDance()
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.togglePopup() }
        }
    }

    // Dances while Claude is working, faster the closer you are to a limit; otherwise waits and blinks.
    func scheduleDance() {
        var delay = 0.5
        if model.working && model.mood != .off {
            delay = switch model.mood {
            case .stressed: 0.12
            case .awake: 0.2
            default: 0.3
            }
            model.frame += 1
        } else {
            if model.frame != 0 { model.frame = 0 }
            idleTicks += 1
            if idleTicks % 9 == 0 { blink() }
        }
        drawIcon()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.scheduleDance() }
    }

    func blink() {
        model.blink = true
        drawIcon()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.model.blink = false
            self?.drawIcon()
        }
    }

    func drawIcon() {
        let key = "\(model.mood)\(model.frame % Mascot.dance.count)\(model.blink)"
        guard key != drawnIcon else { return }
        drawnIcon = key
        item.button?.image = Mascot.image(model.mood, pixel: 1.4, frame: model.frame, blink: model.blink)
    }

    @objc func togglePopup() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            refresh()
            let iconWidth = (button.image?.size.width ?? 0) + 8
            let anchor = NSRect(x: 0, y: 0, width: min(iconWidth, button.bounds.width), height: button.bounds.height)
            popover.show(relativeTo: anchor, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func openPage() {
        popover.performClose(nil)
        if web.url?.host == "claude.ai", !(web.url?.path.hasPrefix("/login") ?? false) {
            web.load(URLRequest(url: usageURL))
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(web)
    }

    func updateButton() {
        drawIcon()
        if model.signedIn, let s = model.session, let w = model.week {
            item.button?.title = " \(Int(s.pct.rounded()))% · \(Int(w.pct.rounded()))%"
        } else {
            item.button?.title = ""
        }
    }

    // Refresh whenever a claude.ai page finishes loading (e.g. right after sign-in).
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { refresh() }

    // Our own page loads come from claude.ai too; keep them from counting as Claude working.
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        activity.quietUntil = Date().addingTimeInterval(10)
    }

    func log(_ msg: String) {
        let line = "\(Date()) \(msg)\n"
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/ClaudeLimits.log")
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }

    @objc func refresh() {
        guard web.url?.host == "claude.ai" else { return }
        activity.quietUntil = max(activity.quietUntil, Date().addingTimeInterval(6))
        // Try the active organization first, then any other one that has usage.
        let js = """
        const orgs = await (await fetch('/api/organizations')).json();
        const active = (document.cookie.match(/lastActiveOrg=([^;]+)/) || [])[1];
        orgs.sort((a, b) => (b.uuid === active) - (a.uuid === active));
        for (const org of orgs) {
            const t = await (await fetch(`/api/organizations/${org.uuid}/usage`)).text();
            try { const u = JSON.parse(t); if (u.five_hour || u.seven_day) return t; } catch (e) {}
        }
        return '{}';
        """
        web.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            if case .failure(let e) = result { self.log("error: \(e)") }
            guard case .success(let value) = result,
                  let data = (value as? String)?.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["five_hour"] != nil || json["seven_day"] != nil
            else {
                self.model.signedIn = false
                self.updateButton()
                return
            }
            self.model.signedIn = true
            self.model.session = Self.limit(json["five_hour"])
            self.model.week = Self.limit(json["seven_day"])
            let list = json["limits"] as? [[String: Any]] ?? []
            self.model.scoped = list.filter { $0["kind"] as? String == "weekly_scoped" }.compactMap { l in
                let scope = l["scope"] as? [String: Any]
                let name = (scope?["model"] as? [String: Any])?["display_name"] as? String
                    ?? scope?["surface"] as? String ?? "Other"
                guard let lim = Self.limit(["utilization": l["percent"] as Any, "resets_at": l["resets_at"] as Any])
                else { return nil }
                return Scoped(title: "\(name) this week", limit: lim)
            }
            self.updateButton()
        }
    }

    static func limit(_ any: Any?) -> Limit? {
        guard let w = any as? [String: Any], let pct = w["utilization"] as? NSNumber else { return nil }
        var date: Date?
        if let s = w["resets_at"] as? String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = iso.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        }
        // Round to the minute so 11:59:59.9 shows as 12:00, like claude.ai does.
        let rounded = date.map { Date(timeIntervalSinceReferenceDate: ($0.timeIntervalSinceReferenceDate / 60).rounded() * 60) }
        return Limit(pct: pct.doubleValue, resets: rounded)
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
app.run()
