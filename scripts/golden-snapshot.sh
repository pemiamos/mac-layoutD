#!/usr/bin/env bash
# golden-snapshot.sh —— 把「内置样章 BookProject.sample 的 IDML 导出」拍成一份
# 确定性文本快照（解包后所有内部文件按名排序拼接），写到 $1。
# 导出已确定（见 testExportIsByteDeterministic），故同输入快照可逐字节复现。
set -euo pipefail
OUT="${1:?用法: golden-snapshot.sh <输出文件>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build >/dev/null 2>&1
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# CLI 不带稿件 → 导出内置 BookProject.sample。
swift run layoutD -- --export-idml "$TMP/golden.idml" >/dev/null 2>&1
unzip -oq "$TMP/golden.idml" -d "$TMP/unz"

: > "$OUT"
( cd "$TMP/unz" && find . -type f | LC_ALL=C sort ) | while read -r rel; do
  rel="${rel#./}"
  printf '===== %s =====\n' "$rel" >> "$OUT"
  cat "$TMP/unz/$rel" >> "$OUT"
  printf '\n' >> "$OUT"
done
