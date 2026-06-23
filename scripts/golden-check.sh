#!/usr/bin/env bash
# golden-check.sh —— 回归基线校验：重新导出内置样章，与已检入的 golden 逐字节比对。
# 不一致即 FAIL（说明导出结果漂移了）。本地/CI 通用。
# 若变化是有意的：跑 scripts/golden-update.sh 重建基线、审 diff、再提交。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GOLDEN="$ROOT/Tests/golden/sample-idml.snapshot.txt"

if [ ! -f "$GOLDEN" ]; then
  echo "⚠️ 缺少 golden 基线（$GOLDEN）。先跑 scripts/golden-update.sh 生成。"
  exit 1
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
bash "$ROOT/scripts/golden-snapshot.sh" "$TMP/current.snapshot.txt"

if diff -u "$GOLDEN" "$TMP/current.snapshot.txt" > "$TMP/diff.txt"; then
  echo "✅ golden 回归 PASS：导出与基线逐字节一致。"
else
  echo "❌ golden 回归 FAIL：导出与基线不一致。差异（前 60 行）："
  head -60 "$TMP/diff.txt"
  echo "…若此变化是有意的，运行 scripts/golden-update.sh 重建基线、审 diff 后提交。"
  exit 1
fi
