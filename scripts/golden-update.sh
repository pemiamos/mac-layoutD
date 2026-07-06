#!/usr/bin/env bash
# golden-update.sh —— 重建 golden 基线（带防漂移护栏）。
#
# golden 是导出回归的最后一道网：刷错一次，之后的回归就会带着错误基线继续「全绿」。
# 因此刷新必须过三道闸：
#   1) 必须给 --reason "<为什么这次导出变化是有意的>"——写进 Tests/golden/GOLDEN-LOG.md 留痕；
#   2) 覆盖前强制打印新旧基线 diff——先看到变化才允许覆盖，杜绝盲刷；
#   3) 新旧逐字节一致时拒绝空刷——没有变化就没有理由动基线。
# 禁止绕过本脚本手工覆盖 Tests/golden/sample-idml.snapshot.txt。
#
# 用法：scripts/golden-update.sh --reason "THREAD-1b 段落合并为章级 Story，故事数预期变化"
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GOLDEN="$ROOT/Tests/golden/sample-idml.snapshot.txt"
LOG="$ROOT/Tests/golden/GOLDEN-LOG.md"

REASON=""
while [ $# -gt 0 ]; do
  case "$1" in
    --reason) REASON="${2:-}"; shift 2 ;;
    *) echo "未知参数：$1（用法：scripts/golden-update.sh --reason \"<变化原因>\"）"; exit 2 ;;
  esac
done
if [ -z "$REASON" ]; then
  echo "❌ 缺少 --reason。golden 刷新必须留痕：一句话说明这次导出变化为什么是有意的。"
  echo "   用法：scripts/golden-update.sh --reason \"<变化原因>\""
  exit 2
fi

mkdir -p "$ROOT/Tests/golden"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
bash "$ROOT/scripts/golden-snapshot.sh" "$TMP/new.snapshot.txt"

if [ -f "$GOLDEN" ]; then
  if diff -u "$GOLDEN" "$TMP/new.snapshot.txt" > "$TMP/diff.txt"; then
    echo "⛔ 新旧基线逐字节一致，无需刷新（拒绝空刷）。"
    exit 1
  fi
  # 粗略规模指示（不含 +++/--- 文件头；空行增删可能少计，仅作数量级参考）
  ADDED=$(grep -c '^+[^+]' "$TMP/diff.txt" || true)
  REMOVED=$(grep -c '^-[^-]' "$TMP/diff.txt" || true)
  echo "== 基线变化（约 +${ADDED} / -${REMOVED} 行，前 60 行如下）=="
  head -60 "$TMP/diff.txt"
  echo "== 变化打印完毕（提交前可再用 git diff 复查完整差异）=="
  SCOPE="约 +${ADDED}/-${REMOVED} 行"
else
  echo "（无旧基线，本次为初建。）"
  SCOPE="初建基线"
fi

cp "$TMP/new.snapshot.txt" "$GOLDEN"

{
  echo "## $(date '+%Y-%m-%d %H:%M') | ${SCOPE}"
  echo "- 原因：${REASON}"
  echo ""
} >> "$LOG"

echo "✅ golden 已更新：Tests/golden/sample-idml.snapshot.txt"
echo "   审计已留痕：Tests/golden/GOLDEN-LOG.md（连同基线一起提交）"
echo "   ⚠️ 提交前请核对上面打印的 diff 确实符合本次改动的预期——这一眼就是最后的人审。"
