import Foundation
import CoreFoundation
import CIOReport

/// SoC 부품별 소비 전력. 필드 이름이 같으면 UI 는 그대로 쓴다.
struct PowerMetrics {
    var sysPower: Double     // 시스템 전체 (SMC PSTR)
    var cpuPower: Double
    var gpuPower: Double
    var ramPower: Double
    var anePower: Double
    var cpuTemp: Double?     // 가장 뜨거운 CPU 센서 (SMC "Tp*")
}

/// "Energy Model" 채널은 누적 에너지(mJ/uJ/nJ)를 준다. 두 스냅샷의 델타를
/// 경과시간으로 나눠 와트로 바꾼다.
///
/// 손으로 선언한 비공개 C 함수들은 Swift 이 소유권을 추론하지 못해 Unmanaged 로
/// 돌아온다. 그래서 이 파일 안에서는 전부 즉시 takeRetainedValue() 로 소비한다.
final class EnergyModel {
    enum Failure: Error, CustomStringConvertible {
        case noChannels, subscribe

        var description: String {
            switch self {
            case .noChannels: return "IOReport Energy Model 채널 없음 (Apple Silicon 전용)"
            case .subscribe: return "IOReportCreateSubscription 실패"
            }
        }
    }

    private let channels: CFMutableDictionary
    private let subscription: UnsafeRawPointer
    // 구독이 이 객체들을 가리키므로 수명을 우리가 책임진다. 로컬로 두면 ARC가 먼저 풀어
    // CreateSamples 에서 걸러지지 않는 크래시가 난다.
    private let retainedAll: CFDictionary
    private let retainedSelection: CFMutableArray
    private var previous: (samples: CFDictionary, at: CFAbsoluteTime)?

    init() throws {
        guard let all = Self.copyAllChannels(), let array = Self.channelArray(of: all) else {
            throw Failure.noChannels
        }

        var valueCallbacks = kCFTypeArrayCallBacks
        let wanted = CFArrayCreateMutable(nil, 0, &valueCallbacks)!
        var count = 0
        for item in Self.items(of: array) where Self.isEnergyChannel(item) {
            CFArrayAppendValue(wanted, Unmanaged.passUnretained(item).toOpaque())
            count += 1
        }
        guard count > 0 else { throw Failure.noChannels }

        let picked = CFDictionaryCreateMutableCopy(nil, CFDictionaryGetCount(all), all)!
        let key = "IOReportChannels" as CFString
        CFDictionarySetValue(
            picked,
            Unmanaged.passUnretained(key).toOpaque(),
            Unmanaged.passUnretained(wanted).toOpaque()
        )

        var ignored: Unmanaged<CFMutableDictionary>?
        guard let subs: UnsafeRawPointer = IOReportCreateSubscription(nil, picked, &ignored, 0, nil) else {
            throw Failure.subscribe
        }

        channels = picked
        retainedAll = all
        retainedSelection = wanted
        subscription = subs
    }

    /// 첫 호출은 기준선만 저장하고 nil, 이후 호출부터 구간 전력(W)을 돌려준다.
    func powers() -> (cpu: Double, gpu: Double, ane: Double, ram: Double)? {
        guard let current = IOReportCreateSamples(subscription, channels, nil)?.takeRetainedValue() else { return nil }
        let now = CFAbsoluteTimeGetCurrent()
        defer { previous = (current, now) }

        guard let baseline = previous else { return nil }
        let elapsed = now - baseline.at
        guard elapsed > 0.05,
              let delta = IOReportCreateSamplesDelta(baseline.samples, current, nil)?.takeRetainedValue(),
              let array = Self.channelArray(of: delta) else { return nil }

        var cpu = 0.0, gpu = 0.0, ane = 0.0, ram = 0.0
        for item in Self.items(of: array) {
            guard Self.text(IOReportChannelGetGroup(item)) == "Energy Model" else { continue }
            let name = Self.text(IOReportChannelGetChannelName(item))
            guard let scale = Self.unitScale(Self.text(IOReportChannelGetUnitLabel(item))) else { continue }
            let watts = Double(IOReportSimpleGetIntegerValue(item, 0)) / elapsed / scale

            if name.hasSuffix("CPU Energy") {        // Ultra 는 "DIE_0_CPU Energy"
                cpu += watts
            } else if name == "GPU Energy" {
                gpu += watts
            } else if name.hasPrefix("ANE") {        // Basic "ANE", Max "ANE0"
                ane += watts
            } else if name.hasPrefix("DRAM") {
                ram += watts
            }
        }
        return (cpu, gpu, ane, ram)
    }

    /// 이 기기에서 어떤 에너지 채널이 보이는지 (진단용)
    static func dumpChannels() {
        guard let all = copyAllChannels(), let array = channelArray(of: all) else {
            print("IOReport 채널을 읽을 수 없습니다")
            return
        }
        var groups: [String: Int] = [:]
        var energy: [(String, String)] = []
        var degrees: [(String, String)] = []

        for item in Self.items(of: array) {
            let group = text(IOReportChannelGetGroup(item))
            let name = text(IOReportChannelGetChannelName(item))
            let unit = text(IOReportChannelGetUnitLabel(item))
            groups[group, default: 0] += 1
            if group == "Energy Model" { energy.append((name, unit)) }
            if unit.contains("C") { degrees.append(("\(group)/\(name)", unit)) }
        }

        print("--- 그룹 \(groups.count)종 ---")
        for (g, c) in groups.sorted(by: { $0.value > $1.value }) { print("  \(g): \(c)") }
        print("--- Energy Model 채널 \(energy.count)개 ---")
        for (n, u) in energy { print("  \(n) [\(u)]") }
        print("--- 단위 'C' 포함 채널 \(degrees.count)개 (온도 후보) ---")
        for (n, u) in degrees.prefix(30) { print("  \(n) [\(u)]") }
    }

    // MARK: - unmanaged 감싸기

    private static func copyAllChannels() -> CFDictionary? {
        IOReportCopyAllChannels(0, 0)?.takeRetainedValue()
    }

    // MARK: - helpers

    private static func isEnergyChannel(_ item: CFDictionary) -> Bool {
        guard text(IOReportChannelGetGroup(item)) == "Energy Model" else { return false }
        let name = text(IOReportChannelGetChannelName(item))
        guard unitScale(text(IOReportChannelGetUnitLabel(item))) != nil else { return false }
        return name.hasSuffix("CPU Energy") || name == "GPU Energy"
            || name.hasPrefix("ANE") || name.hasPrefix("DRAM") || name.hasPrefix("GPU SRAM")
    }

    /// mJ → 1e3, uJ → 1e6, nJ → 1e9 (초당 W 로 바꾸는 제수)
    private static func unitScale(_ unit: String) -> Double? {
        switch unit {
        case "mJ": return 1e3
        case "uJ": return 1e6
        case "nJ": return 1e9
        default: return nil
        }
    }

    private static func text(_ value: Unmanaged<CFString>?) -> String {
        guard let raw = value?.takeUnretainedValue() as String? else { return "" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func channelArray(of dict: CFDictionary) -> CFArray? {
        let key = "IOReportChannels" as CFString
        guard let raw = CFDictionaryGetValue(dict, Unmanaged.passUnretained(key).toOpaque()) else { return nil }
        return Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue()
    }

    private static func items(of array: CFArray) -> [CFDictionary] {
        (0..<CFArrayGetCount(array)).compactMap { index in
            CFArrayGetValueAtIndex(array, index).map { Unmanaged<CFDictionary>.fromOpaque($0).takeUnretainedValue() }
        }
    }
}

// MARK: - 샘플러 (1초 주기, 외부 프로세스 없음)

final class PowerSampler {
    var onUpdate: ((PowerMetrics) -> Void)?
    var onError: ((String?) -> Void)?

    private let queue = DispatchQueue(label: "com.yhzion.syswatt.sampler")
    private var timer: DispatchSourceTimer?
    private var energy: EnergyModel?
    private var smc: SMC?
    private var tempKeys: [String] = []

    func start() {
        queue.async { [weak self] in self?.setup() }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func setup() {
        do {
            energy = try EnergyModel()
            smc = try SMC()
        } catch {
            onError?("\(error)")
            return
        }
        onError?(nil)
        // M 시리즈에서 "Tp*" 계열이 프로세서 접합부 온도다. 키 이름은 칩마다 달라서
        // 접두어로열거하고, 매 tick 그중 최고값을 쓴다.
        tempKeys = smc?.keys(prefixedBy: "Tp") ?? []
        _ = energy?.powers()   // 기준선 확보 → 첫 tick 부터 1초 구간값

        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + 1, repeating: 1.0)
        source.setEventHandler { [weak self] in self?.tick() }
        timer = source
        source.resume()
    }

    private func hottestTemp() -> Double? {
        var best: Double?
        for key in tempKeys {
            guard let value = smc?.reading(key)?.value, value > 5, value < 130 else { continue }
            best = max(best ?? value, value)
        }
        return best
    }

    private func tick() {
        guard let p = energy?.powers() else { return }
        let package = p.cpu + p.gpu + p.ane     // SoC 안에서 측정된 합
        let board = smc?.float("PSTR") ?? 0     // 보드 단위 측정치
        onUpdate?(PowerMetrics(
            sysPower: max(board, package),      // PSTR 없는 기종 대비
            cpuPower: p.cpu, gpuPower: p.gpu, ramPower: p.ram, anePower: p.ane,
            cpuTemp: hottestTemp()
        ))
    }
}

