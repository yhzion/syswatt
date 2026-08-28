import SwiftUI
import AppKit

// MARK: - 설정 상수

private enum Key {
    static let panelOrigin = "panelOrigin"
    static let pinOnTop = "pinOnTop"
    static let widgetVisible = "widgetVisible"
}

// MARK: - 시작 시 실행 (LaunchAgent)

enum LaunchAgent {
    static let plistPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.yhzion.syswatt.plist").path

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistPath) }

    static func enable() {
        // launchd는 .app 디렉터리를 실행할 수 없다(EX_CONFIG) — 내부 실행 파일을 직접 가리킨다.
        guard let exec = Bundle.main.executableURL?.path else { return }
        let plist: [String: Any] = [
            "Label": "com.yhzion.syswatt",
            "ProgramArguments": [exec],
            "RunAtLoad": true,
            "KeepAlive": false
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }
        let url = URL(fileURLWithPath: plistPath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
    }

    static func disable() { try? FileManager.default.removeItem(atPath: plistPath) }
}

// MARK: - ViewModel

@MainActor
final class ViewModel: ObservableObject {
    @Published var metrics: PowerMetrics?
    @Published var input: PowerInput?
    @Published var adjusting = false
    @Published var error: String?

    var wattText: String {
        guard let m = metrics else { return "--" }
        return String(format: "%.1f", m.sysPower)
    }
}

// MARK: - 데스크탑 위젯 뷰

struct WidgetView: View {
    @ObservedObject var vm: ViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.yellow)
                // 숫자 모프 애니메이션(.numericText)은 60프레임 글리프 렌더를 유발한다.
                // 1초 계측 위젯에서 CPU 40%를 먹었으므로 의도적으로 평문 교체만 쓴다.
                Text(vm.wattText)
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                Text("W")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
            }

            PowerBar(metrics: vm.metrics)
                .frame(height: 6)

            HStack(spacing: 8) {
                label("CPU", vm.metrics.map { String(format: "%.0fW", $0.cpuPower) } ?? "--")
                label("GPU", vm.metrics.map { String(format: "%.0fW", $0.gpuPower) } ?? "--")
                if let t = vm.metrics?.cpuTemp {
                    label("온도", String(format: "%.0f°", t))
                }
                Spacer()
            }

            if let input = vm.input {
                Divider().background(Color.primary.opacity(0.08))

                HStack(spacing: 6) {
                    Image(systemName: "powerplug.fill")
                        .font(.system(size: 9))
                        .help(input.adapterWatts.map { "\($0)W 어댑터 연결 중" } ?? "어댑터 연결 중")
                    Text(input.wattsIn > 0 ? String(format: "≈%.1fW", input.wattsIn) : "–")
                        .fontWeight(.semibold)
                    flowBadge(input)
                    Spacer()
                    // 60초 틱 계측값임을 숨기지 않기 위한 데이터 나이
                    Text("· \(Int(input.sampleAge))초")
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundColor(.primary.opacity(0.65))
            }

            if vm.adjusting {
                HStack(spacing: 4) {
                    Image(systemName: "move.3d")
                    Text("드래그해서 옮기고, 손을 띠면 제자리로")
                }
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(.orange)
            }

            if let err = vm.error {
                Text(err)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 220)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func label(_ name: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(name).foregroundColor(.secondary)
            Text(value).foregroundColor(.primary).monospacedDigit()
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
    }

    /// 배터리 유입(▲ 초록) / 유출(▼ 주황). 유지 상태에서는 아무 것도 보여주지 않는다.
    /// 헤드라인의 볼트가 이미 "소비 전력"이라 충전 기호로 볼트를 재사용하지 않는다.
    @ViewBuilder
    private func flowBadge(_ input: PowerInput) -> some View {
        switch input.flow {
        case .idle:
            EmptyView()
        case .charging, .reverse:
            let charging = input.flow == .charging
            HStack(spacing: 2) {
                Image(systemName: charging ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 8))
                    .foregroundColor(charging ? .green : .orange)
                    .accessibilityLabel(charging ? "배터리로 유입, 충전 중" : "배터리로 유출, 어댑터 정격 부족")
                    .help(charging ? "배터리로 유입 — 어댑터에 여유가 있음" : "배터리로 유출 — 어댑터 정격이 부족합니다")
                Text(String(format: "%.1fW", abs(input.batteryWatts)))
            }
        }
    }
}

/// sys_power 안에서 구성 요소가 차지하는 비율을 쌓은 막대
struct PowerBar: View {
    let metrics: PowerMetrics?

    var body: some View {
        GeometryReader { geo in
            let cpu = metrics?.cpuPower ?? 0
            let gpu = metrics?.gpuPower ?? 0
            let ram = metrics?.ramPower ?? 0
            let ane = metrics?.anePower ?? 0
            let sys = max(metrics?.sysPower ?? 0, 0.001)
            let parts: [(Double, Color)] = [
                (cpu, .blue), (gpu, .green), (ram, .orange), (ane, .purple)
            ]
            HStack(spacing: 1) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Rectangle()
                        .fill(part.1)
                        .frame(width: max(0, geo.size.width * CGFloat(part.0 / sys)))
                }
                Spacer(minLength: 0)
            }
            .clipShape(Capsule())
            .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
    }
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let vm = ViewModel()
    private let sampler = PowerSampler()
    private let inputReader = PowerInputReader()
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!

    private let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPanel()
        startSampling()
        startInputReading()
    }

    func applicationWillTerminate(_ notification: Notification) {
        sampler.stop()
        inputReader.stop()
    }

    // MARK: 상태바

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusTitle()

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "위젯 보기", action: #selector(toggleWidget), keyEquivalent: "w").target = self
        menu.addItem(withTitle: "항상 위에", action: #selector(togglePin), keyEquivalent: "").target = self
        menu.addItem(withTitle: "위젯 위치 초기화", action: #selector(resetWidgetPosition), keyEquivalent: "").target = self
        menu.addItem(withTitle: "위치 조정", action: #selector(startRepositioning), keyEquivalent: "m").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "시작 시 실행", action: #selector(toggleLaunchAgent), keyEquivalent: "").target = self
        menu.addItem(withTitle: "SysWatt 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func updateStatusTitle() {
        statusItem.button?.title = "⚡︎\(vm.wattText)W"
    }

    @objc private func toggleWidget() {
        let visible = !(defaults.object(forKey: Key.widgetVisible) as? Bool ?? true)
        defaults.set(visible, forKey: Key.widgetVisible)
        visible ? panel.makeKeyAndOrderFront(nil) : panel.orderOut(nil)
    }

    @objc private func togglePin() {
        defaults.set(!(defaults.bool(forKey: Key.pinOnTop)), forKey: Key.pinOnTop)
        applyPanelLevel()
    }

    @objc private func resetWidgetPosition() {
        defaults.removeObject(forKey: Key.panelOrigin)
        defaultOrigin()
    }

    // MARK: 위치 조정 모드
    // 데스크탑 레벨에서는 마우스 이벤트가 Finder에 가로채여 드래그가 안 된다.
    // 그래서 조정 중에만창을 띄워 받고, 드래그를 멈추면 원래 레벨로 되돌린다.

    private var repositionMonitor: Any?
    private var repositionTimer: Timer?

    @objc private func startRepositioning() {
        guard !vm.adjusting else { return }
        vm.adjusting = true
        resizePanelToContent()
        panel.level = .floating
        panel.orderFrontRegardless()
        scheduleRepositionEnd(after: 20)

        repositionMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseUp]) { [weak self] event in
            self?.scheduleRepositionEnd(after: 2)
            return event
        }
    }

    private func scheduleRepositionEnd(after seconds: TimeInterval) {
        repositionTimer?.invalidate()
        repositionTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            // release 빌드에서는 [weak self]를 Task 안에서 바로 닿으면
            // "captured var in concurrently-executing code" 로 에러가 난다.
            guard let self else { return }
            Task { @MainActor in self.endRepositioning() }
        }
    }

    private func endRepositioning() {
        repositionTimer?.invalidate()
        repositionTimer = nil
        if let monitor = repositionMonitor {
            NSEvent.removeMonitor(monitor)
            repositionMonitor = nil
        }
        guard vm.adjusting else { return }
        vm.adjusting = false
        applyPanelLevel()
        resizePanelToContent()
    }

    @objc private func toggleLaunchAgent() {
        LaunchAgent.isEnabled ? LaunchAgent.disable() : LaunchAgent.enable()
    }

    // MARK: 데스크탑 패널

    private func setupPanel() {
        let hosting = NSHostingView(rootView: WidgetView(vm: vm))

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: measuredContentSize()),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        applyPanelLevel()

        if let saved = defaults.dictionary(forKey: Key.panelOrigin),
           let x = saved["x"] as? Double, let y = saved["y"] as? Double {
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            defaultOrigin()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(panelMoved(_:)),
            name: NSWindow.didMoveNotification, object: panel
        )

        if defaults.object(forKey: Key.widgetVisible) as? Bool ?? true {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// 창 크기의 진짜 기준. 절대로 패널에 붙은 뷰에서 재지 않는다 —
    /// 그렇게 하면 "창이 커짐 → contentView 커짐 → fittingSize 커짐" 피드백 루프에 빠진다.
    /// 항상 분리된 호스팅 뷰로 측정한다.
    private func measuredContentSize() -> NSSize {
        NSHostingView(rootView: WidgetView(vm: vm)).fittingSize
    }

    /// 기본 위치 = 사과마크 바로 아래(좌측 상단, 메뉴막대 밑 6pt).
    private func defaultOrigin() {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.minX + 8, y: f.maxY - panel.frame.height - 6))
    }

    private func applyPanelLevel() {
        // 기본: 벽지 바로 위(데스크탑). "항상 위에" 켜면 일반 창 위.
        panel.level = defaults.bool(forKey: Key.pinOnTop)
            ? .floating
            : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
    }

    @objc private func panelMoved(_ note: Notification) {
        guard defaults.object(forKey: Key.widgetVisible) as? Bool ?? true else { return }
        let o = panel.frame.origin
        defaults.set(["x": o.x, "y": o.y], forKey: Key.panelOrigin)
    }

    /// 전원 행(또는 에러 문구)이 나갔다 들어올 때만 높이를 맞춘다. 위쪽 가장자리는 고정.
    private func resizePanelToContent() {
        let height = measuredContentSize().height
        guard height > 20, abs(height - panel.frame.height) > 0.5 else { return }
        var frame = panel.frame
        let delta = height - frame.height
        frame.size.height = height
        frame.origin.y -= delta
        panel.setFrame(frame, display: true, animate: false)
        defaults.set(["x": frame.origin.x, "y": frame.origin.y], forKey: Key.panelOrigin)
    }

    // MARK: 샘플링

    private func startSampling() {
        sampler.onUpdate = { [weak self] metrics in
            guard let self else { return }
            Task { @MainActor in
                self.vm.metrics = metrics
                self.updateStatusTitle()
            }
        }
        sampler.onError = { [weak self] error in
            guard let self else { return }
            Task { @MainActor in
                self.vm.error = error
                if error != nil { self.statusItem.button?.title = "⚡︎–" } else { self.updateStatusTitle() }
            }
        }
        sampler.start()
    }

    private func startInputReading() {
        inputReader.onUpdate = { [weak self] input in
            guard let self else { return }
            Task { @MainActor in
                let rowWasVisible = self.vm.input != nil
                self.vm.input = input
                if (self.vm.input != nil) != rowWasVisible { self.resizePanelToContent() }
            }
        }
        inputReader.start()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            switch item.action {
            case #selector(toggleWidget):
                item.title = (defaults.object(forKey: Key.widgetVisible) as? Bool ?? true) ? "✓ 위젯 보기" : "위젯 보기"
            case #selector(togglePin):
                item.title = defaults.bool(forKey: Key.pinOnTop) ? "✓ 항상 위에" : "항상 위에"
            case #selector(resetWidgetPosition):
                item.isHidden = !(defaults.object(forKey: Key.widgetVisible) as? Bool ?? true)
            case #selector(toggleLaunchAgent):
                item.title = LaunchAgent.isEnabled ? "✓ 시작 시 실행" : "시작 시 실행"
            default:
                break
            }
        }
    }
}

// MARK: - 진단용 (--dump): GUI 없이 5초간 와트 출력

enum PowerDump {
    static func run() {
        let sampler = PowerSampler()
        let reader = PowerInputReader()
        let done = DispatchSemaphore(value: 0)
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        reader.onUpdate = { i in
            if let i {
                let flow: String
                switch i.flow {
                case .charging: flow = "▲ 유입"
                case .reverse:  flow = "▼ 유출(정격 부족)"
                case .idle:     flow = "− 유지"
                }
                print(String(format: "  입력 ≈%.1fW · %@ %@ %.1fW · %.0f초 전 측정", i.wattsIn, flow,
                             i.adapterWatts.map { "(\($0)W 어댑터)" } ?? "", abs(i.batteryWatts), i.sampleAge))
                fflush(stdout)
            } else {
                print("  입력 없음 (배터리 전용)")
                fflush(stdout)
            }
        }
        sampler.onUpdate = { m in
            print("\(fmt.string(from: Date()))  sys=\(String(format: "%.1f", m.sysPower))W  "
                + "cpu=\(String(format: "%.1f", m.cpuPower)) gpu=\(String(format: "%.1f", m.gpuPower)) "
                + "ram=\(String(format: "%.1f", m.ramPower)) temp=\(m.cpuTemp.map { String(format: "%.0f°C", $0) } ?? "-")")
            fflush(stdout)
        }
        sampler.onError = { e in
            guard let e else { return }
            FileHandle.standardError.write(Data("error: \(e)\n".utf8))
            done.signal()
        }
        sampler.start()
        reader.start()
        _ = done.wait(timeout: .now() + 5)
        sampler.stop()
        reader.stop()
    }
}

// MARK: - App

@main
struct SysWattApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        if CommandLine.arguments.contains("--channels") {
            EnergyModel.dumpChannels()
            exit(EXIT_SUCCESS)
        }
        if CommandLine.arguments.contains("--temps") {
            TempProbe.run()
            exit(EXIT_SUCCESS)
        }
        if CommandLine.arguments.contains("--dump") {
            PowerDump.run()
            exit(EXIT_SUCCESS)
        }
    }

    var body: some Scene {
        Settings { EmptyView() }
    }
}
