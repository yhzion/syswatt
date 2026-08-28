#!/usr/bin/env python3
"""CHANGELOG 에서 한 릴리스에 해당하는 마디 본문만 뽑아 출력한다.

발행 메시지로 쓸 조각이 필요하다. 그런데 머리글 형식이 두 갈래다.

    ## 0.1.0 (2026-08-28)                                 ← 손으로 만든 기준 릴리스
    ### [0.1.1](.../compare/v0.1.0...v0.1.1) (2026-08-28)  ← standard-version 이 쓴 것

접두 문자열만 보는 awk 는 두 번째 형식을 못 봐서, 0.1.1 은 노트가 빈 채로 나갔다.
머리글 안에서 버전 번호는 항상 처음에 오므로(링크 안의 비교 대상보다 앞선다),
그 순서를 이용한다.
"""

from __future__ import annotations

import re
import sys

HEAD = re.compile(r"^#{2,3} ")
VER = re.compile(r"\d+\.\d+\.\d+")


def section(lines: list[str], version: str) -> list[str]:
    for i, line in enumerate(lines):
        if not HEAD.match(line):
            continue
        found = VER.search(line)
        if found and found.group(0) == version:
            out = []
            for body in lines[i + 1 :]:
                # 같은 ### 을 쓰는 「### Fixed」 같은 분류 머리글은 본문이다.
                # 다음 릴리스는 버전 번호를 품고 있으므로 그걸 경계로 본다.
                if HEAD.match(body) and VER.search(body):
                    break
                out.append(body)
            return out
    raise SystemExit(f"CHANGELOG 에 {version} 마디가 없다")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: changelog-notes.py <version>")
    with open("CHANGELOG.md", encoding="utf-8") as handle:
        print("\n".join(section(handle.read().splitlines(), sys.argv[1])).strip())
