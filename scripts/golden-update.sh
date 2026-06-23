#!/usr/bin/env bash
# golden-update.sh —— 重建 golden 基线。**导出有意改动后**运行本脚本，
# 然后 git diff 审一眼变化是否符合预期，再连同代码一起提交。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/Tests/golden"
bash "$ROOT/scripts/golden-snapshot.sh" "$ROOT/Tests/golden/sample-idml.snapshot.txt"
echo "✅ golden 已更新：Tests/golden/sample-idml.snapshot.txt"
echo "   请 git diff 审核导出变化是否符合预期，再提交。"
