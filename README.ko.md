<p align="center"><a href="README.md">English</a> · 한국어</p>

# SysWatt (한국어)

> macOS 실시간 소비 전력을 상태바와 데스크탑 위젯에. 1초 갱신, root 불필요, 서브프로세스 없음.
>
> *A macOS menu bar + desktop widget that shows live power draw (watts) from IOReport & AppleSMC.*

Mac의 실시간 소비 전력(W)을 **상태바**와 **데스크탑 위젯**에 표시하는 메뉴바 앱.

- 데이터: 전부 인프로세스. 외부 바이너리·서브프로세스 없음
  - 부품별 전력: `IOReport` "Energy Model" 채널 (비공개 C API, `/usr/lib/libIOReport.dylib`)
  - 시스템 전력: `AppleSMC` 키 `PSTR` (`IOConnectCallStructMethod`)
  - 입력/충전 전력: `AppleSmartBattery` IORegistry 속성
- 갱신: 소비전력 1초 · 입력/충전전력 **60초 틱** (macOS가 그 주기로만 준다)
- root 불필요. 표시 값 `sys_power = max(PSTR, cpu+gpu+ane)`

## 계측 소스 실측 결과

| 값 | 출처 | 갱신 주기 |
|---|---|---|
| `PSTR` 시스템 전력 (W) | AppleSMC 키 | 1초 |
| `CPU/GPU/ANE/DRAM Energy` (누적 mJ/uJ/nJ) | IOReport Energy Model | 1초 |
| `SystemPowerIn` 벽→Mac 유입 (mW) | `PowerTelemetryData` | **60초** |
| `InstantAmperage × Voltage` 충전(+)·방전(−) | `AppleSmartBattery` | **60초** |
| `AdapterDetails.Watts` 어댑터 정격 | `AppleSmartBattery` | 고정 |
| `ExternalConnected` 어댑터 연결 여부 | `AppleSmartBattery` | 연결 이벤트 시 **즉시**(실측 2~4초 내) |

 항등식 확인됨: `SystemPowerIn = SystemLoad + BatteryPower` (19.05 = 5.85 + 13.2).
 다만 ioreg `SystemLoad`(유휴 5.9W)와 macmon `sys_power`(유휴 12.2W)는 측정 범위가 달라서,
 **소비치 + 충전치로 입력을 유도 계산하면 과대계산**된다. 그래서 입력은 계측값을 그대로 쓴다.

> 콘센트에서 실제로 빨아들이는 wall watt가 아닙니다. 디스플레이·SSD·팬·충전 손실이 일부만 반영된
> 추정치라 `≈`로 씁니다. 정확한 wall watt는 스마트 플러그 측 외부 계량기가 필요합니다.

## 설치

```bash
./package-app.sh             # SysWatt.app 생성
open SysWatt.app
```

`시작 시 실행`은 상태바 메뉴로 켠다. LaunchAgent는 `.app` 경로가 아니라 **내부 실행 파일**을
가리켜야 한다(launchd는 번들 디렉터리를 실행 못 함 — `EX_CONFIG`(78)으로 조용히 죽는다).

## 사용

| 동작 | 방법 |
|---|---|
| 와트 확인 | 상태바 `⚡︎12.4W` / 데스크탑 위젯 |
| 위젯 위치 | 메뉴 → `위치 조정` 후 드래그 |
| 위치 초기화 | 메뉴 → `위젯 위치 초기화` (사과마크 바로 아래) |
| 항상 위에 | 메뉴 → `항상 위에` (끄면 벽지 바로 위로 내려감) |
| 위젯 숨김 | 메뉴 → `위젯 보기` |
| 상세 | 위젯에 CPU/GPU 소비전력, 구성 비율 막대, CPU 최고 온도 |
| 성능 | 유휴 2.5% · 8코어 부하 1.3% CPU, RSS 약 85MB (M2 Max 실측) |
| 입력/충전 전력 | 어댑터를 꽂은 동안만 위젯 하단 전원 행 표시, 뽑으면 행이 사라지며 높이도 줄어듦 |

### 왜 `위치 조정` 모드가 필요한가

위젯은 기본이 **데스크탑 레벨** 창이다. 이 층에서는 마우스 히트테스트를 Finder가 가져버려
드래그가 전혀 동작하지 않는다(실측: 데스크탑 레벨 이동량 0px, floating 레벨 80px).
그래서 조정 중에만 창을 floating으로 올리고, 손을 띤 2초 뒤(아무 조작이 없으면 20초 뒤) 다시 내린다.

데스크탑 우클릭 → **위젯 편집** 모드에서 이 위젯이 사라지는 것은 버그가 아니다. 시스템 위젯이
아니라 일반 창이라 편집 모드 레이어에 가려지는 것일 뿐, 모드를 나오면 돌아온다.

전원 행은 `🔌 ≈19.2W`(벽 유입) · 방향 화살표 · 우측 `· 42초`(데이터 나이) 세 부분이다.
나이를 붙인 이유는 값이 60초 틱이라, 안 붙이면 "지금 입력"으로 오해되기 때문이다.
플러그 아이콘 툴팁에는 어댑터 정격(`20W 어댑터 연결 중`)이 뜬다.

### 배터리 흐름 화살표

| 표시 | 의미 |
|---|---|
| ▲ 초록 | 배터리로 유입(충전) — 어댑터에 여유가 있음 |
| ▼ 주황 | 배터리로 유출 — **어댑터 정격이 소비를 못 따라옴** |
| (없음) | 만충 등 유입·유출 없음 |

헤드라인의 볼트는 이미 "소비 전력"이라 충전 기호로 재사용하지 않았다.
역류는 어댑터를 작게 쓸 때 보인다(실측: 20W 어댑터 + 8코어 풀로드 → 벽 19.1W + 배터리 44.9W = 64W,
macmon `sys_power` 63.3W와 일치).

## 진단

```bash
.build/debug/syswatt --dump      # GUI 없이 5초간 와트를 터미널에 출력
.build/debug/syswatt --channels  # 이 기기의 IOReport Energy Model 채널 목록
```

다른 Apple Silicon(M1~M4/Ultra)에서도 채널 이름 규칙은 같다(`*CPU Energy`, `GPU Energy`,
`ANE*`, `DRAM*`). 이상하면 `--channels`로 실제 이름/단위를 확인한다.

macmon을 개발 중 검증 도구로 쓸 수 있다(의존성은 없다):

```bash
brew install macmon        # 검증 전용. 앱은 macmon 을 찾지 않는다
macmon pipe -i 1000        # 한 창에서
# 다른 창에서 .build/debug/syswatt --dump  → 초 단위 값 비교
```
M2 Max 실측(8코어 부하): `sys` 64.6W vs 64.6W(오차 0.0%), `cpu` 41.2 vs 41.1W(0.2%).

macmon 경로는 우선순위: `$POWER_WIDGET_MACMON` → 앱 번들 `Contents/Resources/macmon` → `/opt/homebrew/bin/macmon` → `/usr/local/bin/macmon`

## 구조

```
Package.swift
Sources/
  CIOReport/include/CIOReport.h      # 비공개 IOReport 10개 함수 선언 (-lIOReport)
  CSmc/include/CSmc.h                # AppleSMC KeyData 구조체 + 요청 헬퍼
  SysWatt/
    SysWattApp.swift                 # ViewModel / 상태바 / 데스크탑 패널 / 메뉴 / LaunchAgent
    PowerSampler.swift               # Energy Model 델타 → 부품별 W, PSTR → 시스템 W (1초)
    PowerInput.swift                 # AppleSmartBattery → 입력/충전 전력 + 어댑터 게이팅
    SMC.swift                        # AppleSMC 읽기 전용 클라이언트 (키 열거/디코딩 포함)
    TempProbe.swift                  # --temps: 칩별 온도 키 탐색 진단
package-app.sh                       # release 빌드 + .app 번들링 + ad-hoc 서명
```

### 아직 안 된 것

- **CPU 온도**: 예전엔 macmon이 IOHID 센서로 읽던 값이다. 네이티브 전환에서 빠졌고
  위젯에서는 자동으로 안 보인다(`PowerMetrics.cpuTemp` 가 nil). SMC 온도 키(`sp78` 타입)를
  읽는 경로로 되살릴 수 있다.
- **사설 API 리스크**: IOReport·SMC 는 공개 API가 아니다. macOS 메이저 업그레이드에서
  시그니처/키 이름이 바뀌면 깨질 수 있다. `Sources/CIOReport/include/CIOReport.h` 가
  유일한 선언 파일이라 거기서 잡는다.
