import Foundation
import CSmc

/// SMC를 통째로 스캔해서, CPU 부하를 주는 전/후 값이 같이 오르는 키가 뭔지 찾아낸다.
/// (`--temps` 진단용. 온도 키 이름은 칩마다 다르다.)
enum TempProbe {
    static func run() {
        setbuf(stdout, nil)
        guard let smc = try? SMC(), let count = smc.keyCount else {
            print("SMC 키를 열거할 수 없습니다")
            return
        }
        print("SMC 키 \(count)개 스캔 중…")

        // 애플 센서 키는 전부 'T'로 시작한다 (Tp=프로세서, TG=GPU, TB=배터리, Ta=주변).
        let names = (0..<count).compactMap { smc.keyName(at: $0) }.filter { $0.hasPrefix("T") }
        print("'T' 접두어 센서 키 \(names.count)개")

        let before = measure(smc, names)
        print("측정된 온도 후보 \(before.count)개 → 8초간 CPU 부하 적용")

        spinCores(for: 8)
        let after = measure(smc, names)

        let rows = before.compactMap { (key, from) -> (String, Double, Double)? in
            guard let to = after[key] else { return nil }
            return (key, from, to)
        }
        .sorted { ($0.2 - $0.1) > ($1.2 - $1.1) }

        print(String(format: "%-9@ %7@ %7@ %8@", "KEY" as NSString, "before" as NSString, "after" as NSString, "delta" as NSString))
        for (key, from, to) in rows.prefix(20) {
            print(String(format: "%-9@ %7.1f %7.1f %+8.1f", key as NSString, from, to, to - from))
        }
    }

    private static func measure(_ smc: SMC, _ names: [String]) -> [String: Double] {
        var result: [String: Double] = [:]
        for name in names {
            guard let r = smc.reading(name), let value = r.value, value > 3, value < 120 else { continue }
            result[name] = value
        }
        return result
    }

    private static func spinCores(for seconds: TimeInterval) {
        let stop = Date().addingTimeInterval(seconds)
        let group = DispatchGroup()
        for _ in 0..<ProcessInfo.processInfo.activeProcessorCount {
            group.enter()
            DispatchQueue.global(qos: .userInteractive).async {
                defer { group.leave() }
                while Date() < stop { _ = (1...300_000).reduce(0, +) }
            }
        }
        group.wait()
    }
}
