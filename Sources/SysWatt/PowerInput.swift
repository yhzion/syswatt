import Foundation
import IOKit

/// 배터리로 흐르는 방향
enum BatteryFlow: Equatable {
    case charging   // 어댑터에 여유가 있음
    case idle       // 만충 등 유입·유출 없음
    case reverse    // 어댑터 정격이 소비에 못 맞춰 배터리가 토해냄
}

/// 어댑터/배터리 측 전력 (AppleSmartBattery IORegistry, 60초 틱으로 갱신됨)
struct PowerInput: Equatable {
    var wattsIn: Double         // 벽 → Mac 유입 (W)
    var batteryWatts: Double    // + 충전 / − 방전 (W)
    var adapterWatts: Int?      // 어댑터 정격 (W)
    var sampleAge: TimeInterval // 마지막 값 변화 후 경과 초

    /// 0.15W 데드존: 계측 지터로 화살표가 깜빡이는 것을 막는다.
    var flow: BatteryFlow {
        if batteryWatts > 0.15 { return .charging }
        if batteryWatts < -0.15 { return .reverse }
        return .idle
    }
}

/// `AppleSmartBattery` 속성을 1초마다 읽는다. 어댑터 미연결이면 nil.
/// `onUpdate`는 스캐너 자기 큐에서 불리므로, UI 갱신은 호출자가 메인 액터로 옮겨야 한다.
final class PowerInputReader {
    var onUpdate: ((PowerInput?) -> Void)?

    private let queue = DispatchQueue(label: "com.yhzion.syswatt.input")
    private var timer: DispatchSourceTimer?
    private var service: io_service_t = IO_OBJECT_NULL
    private var lastRawWattsIn: Int64 = -1
    private var lastChange = Date()

    func start() {
        queue.async { [weak self] in self?.setup() }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func setup() {
        if service == IO_OBJECT_NULL {
            service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        }
        guard service != IO_OBJECT_NULL else {   // 배터리 없는 Mac (mini/Studio)
            onUpdate?(nil)
            return
        }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 1.0)
        t.setEventHandler { [weak self] in self?.poll() }
        timer = t
        t.resume()
    }

    private func poll() {
        guard let p = properties(), Self.flag(p["ExternalConnected"]) else {
            lastRawWattsIn = -1
            onUpdate?(nil)
            return
        }

        let tele = p["PowerTelemetryData"] as? [String: Any] ?? [:]
        let rawWattsIn = Self.int64(tele["SystemPowerIn"])            // mW
        if rawWattsIn != lastRawWattsIn {
            lastRawWattsIn = rawWattsIn
            lastChange = Date()
        }

        let volts = Self.int64(p["Voltage"])                          // mV
        let amps = Self.int64(p["InstantAmperage"])                   // mA (방전은 음수)
        let input = PowerInput(
            wattsIn: Double(rawWattsIn) / 1_000,
            batteryWatts: Double(amps * volts) / 1_000_000,
            adapterWatts: (p["AdapterDetails"] as? [String: Any])?["Watts"].flatMap { ($0 as? NSNumber)?.intValue },
            sampleAge: Date().timeIntervalSince(lastChange)
        )
        onUpdate?(input)
    }

    private func properties() -> [String: Any]? {
        guard service != IO_OBJECT_NULL else { return nil }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return dict
    }

    private static func flag(_ value: Any?) -> Bool {
        if let n = value as? NSNumber { return n.boolValue }
        if let s = value as? String { return s.lowercased() == "yes" }
        return false
    }

    /// u64로 라핑된 음수도 그대로 Int64로 돌려준다.
    private static func int64(_ value: Any?) -> Int64 {
        guard let n = value as? NSNumber else { return 0 }
        return Int64(bitPattern: n.uint64Value)
    }
}
