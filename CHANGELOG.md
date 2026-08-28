# CHANGELOG

버전은 시멘틱 버저닝을 따른다. `VERSION` 파일이 단일 진실이고, 릴리스는 `vX.Y.Z` 태그다.
항목은 커밋 제목에서 생성되므로 `commit-msg` 훅의 Conventional Commits 검증이 곧 이 파일의 스키마다.

### [0.1.1](https://github.com/yhzion/syswatt/compare/v0.1.0...v0.1.1) (2026-08-28)


### Fixed

* **설치:** 임시 볼륨에서 실행 중이면 시작 시 실행 저장을 거부한다 ([66d4da3](https://github.com/yhzion/syswatt/commit/66d4da3af889cd359676cf6d112799216ebd6391))

## 0.1.0 (2026-08-28)

초기 구현은 컨벤션 도입 이전 커밋(`dd91cc2`)에 담겨 있어 자동으로 나오지 않는다. 그래서 아래
Added 는 그 당시 내용을 손으로 옮겨 적었다. 0.1.0 이후 릴리스는 전부 커밋 제목에서 생성된다.

### Added

* 메뉴막대 상태 항목과 데스크탑 위젯에 1초 갱신 소비 전력 표시
* IOReport Energy Model + AppleSMC 네이티브 샘플러 (root·서브프로세스 없음)
* 어댑터가 붙어 있을 때만 나오는 전력 행: 벽 유입, 배터리 유입·유출 방향, 값의 나이
* CPU 접점 온도 (SMC `Tp*` 계열 중 최댓값)
* 위젯 위치 저장, 그리고 데스크탑 레벨에서는 드래그가 불가능한 문제를 우회하는 위치 조정
* 커밋 게이트: 서식 검사(swift-format 140열)와 release 빌드(경고=에러), Conventional Commits 제목 검증 (`./scripts/install-hooks.sh`)
* 버전의 단일 진실인 `VERSION` 파일과, 커밋 제목에서 생성되는 이 파일
* 태그 릴리스마다 DMG 를 만들어 GitHub Releases 에 올리는 파이프라인

### Fixed

* release 빌드 실패 두 곳 + CI 를 warnings-as-errors 게이트로 ([a37bd20](https://github.com/yhzion/syswatt/commit/a37bd2088e1ad1093eb00255b216d0a7c3eea0d2))
