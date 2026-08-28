#!/bin/bash
# 저장소 훅을 git 에 연결합니다. 클론마다 한 번 실행하세요.
#
# .git/hooks 는 버전 관리가 안 되므로 core.hooksPath 로 scripts/git-hooks 를 가리킵니다.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

git config core.hooksPath scripts/git-hooks
chmod +x scripts/git-hooks/*
echo "core.hooksPath → $(git config core.hooksPath)"
echo "설치된 훅: $(ls scripts/git-hooks | tr '\n' ' ')"
