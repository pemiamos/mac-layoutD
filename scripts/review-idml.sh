#!/usr/bin/env bash
# review-idml.sh — 一条命令做「机器可硬验证」的审核。
#
# 用途：Claude 批量审核 Codex 的 IDML/排版改动时，对每个分支跑这一套，得到统一 PASS/FAIL。
# 专治「单测全绿但功能坏」——除了 build/test，还做端到端导出探针（导 IDML→解包→断言结构与行内样式）。
# InDesign 里的视觉效果本脚本验证不了（无头），那一关仍由人/Antigravity 在集成批次里做。
#
# 用法：
#   scripts/review-idml.sh            # 审当前工作区/HEAD
#   退出码 0 = 全过；非 0 = 有 FAIL（明细见输出）。

set -uo pipefail
cd "$(dirname "$0")/.."

PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
sec()  { echo; echo "== $1 =="; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- 1. 构建 + 测试（回显 XCTest 真实汇总行，绕开 relay「0 tests」假象）---
sec "build + test"
if swift build >"$TMP/build.log" 2>&1; then ok "swift build"; else bad "swift build（见 $TMP/build.log）"; fi
if swift test >"$TMP/test.log" 2>&1; then
  SUM="$(grep -E 'Executed [0-9]+ tests' "$TMP/test.log" | tail -1)"
  ok "swift test — ${SUM:-(无汇总行)}"
else
  bad "swift test — $(grep -E 'failure|error:' "$TMP/test.log" | head -3)"
fi

# --- 2. 端到端导出探针 ---
# 导出一个含中英文行内强调的 fixture，解包后断言结构与 FontStyle。
sec "IDML 端到端探针"
FIX="$TMP/fix.md"
# 斜体两侧都贴汉字（前*斜体*后）——这是 CJK intraword 回归点，分隔符两侧若被当词内会失效。
printf '# 标题\n\n前**粗体**后段落里*斜体*都要保真，中文紧贴 `code` 与 ABC。\n' > "$FIX"
OUT="$TMP/out/book.idml"
if swift run layoutD -- "$FIX" --export-idml "$OUT" >"$TMP/export.log" 2>&1; then
  ok "导出成功"
else
  bad "导出失败（见 $TMP/export.log）"; echo; echo "结果：$PASS 过 / $FAIL 坏"; exit 1
fi

unzip -oq "$OUT" -d "$TMP/u"

# 2a. mimetype 首条 + Stored（用 zipfile，避开 unzip -lv 列解析的脆弱）
if python3 - "$OUT" <<'PY'
import sys,zipfile
z=zipfile.ZipFile(sys.argv[1])
infos=z.infolist()
assert infos[0].filename=="mimetype", "首条不是 mimetype 而是 "+infos[0].filename
assert infos[0].compress_type==zipfile.ZIP_STORED, "mimetype 未 Stored"
PY
then ok "mimetype 首条且 Stored"; else bad "mimetype 首条/Stored 校验失败"; fi

# 2b. 全部 XML well-formed
MAL=0
while IFS= read -r f; do xmllint --noout "$f" 2>/dev/null || MAL=$((MAL+1)); done \
  < <(find "$TMP/u" -name '*.xml')
[ "$MAL" -eq 0 ] && ok "全部 XML well-formed" || bad "$MAL 个 XML malformed"

# 2c. 行内强调：解析 Story 的 CharacterStyleRange → 收集 (FontStyle,内容)
python3 - "$TMP/u" <<'PY'
import glob,os,re,sys
root=sys.argv[1]
spans=[]
for f in glob.glob(os.path.join(root,'Stories','*.xml')):
    s=open(f,encoding='utf-8').read()
    for m in re.finditer(r'<CharacterStyleRange([^>]*)>(.*?)</CharacterStyleRange>',s,re.S):
        attr,body=m.groups()
        txt=''.join(re.findall(r'<Content>(.*?)</Content>',body,re.S))
        if not txt.strip(): continue
        bold='FauxBold="true"' in attr
        italic='FauxItalic="true"' in attr
        spans.append((bold, italic, txt))
def styled(sub,want_bold,want_italic):
    return any(sub in txt and bold==want_bold and italic==want_italic for bold,italic,txt in spans)
def residue(ch):
    return any(ch in txt for _,_,txt in spans)
checks=[
    ("粗体词→FauxBold",      styled("粗体",True,False)),
    ("斜体词(CJK)→FauxItalic", styled("斜体",False,True)),
    ("无残留 * 分隔符",   not residue("*")),
    ("无残留 _ 分隔符",   not residue("_")),
]
fails=[n for n,okk in checks if not okk]
for n,okk in checks:
    print(("  ✅ " if okk else "  ❌ ")+n)
sys.exit(1 if fails else 0)
PY
[ $? -eq 0 ] && ok "行内强调断言全过" || bad "行内强调断言有失败（见上）"

sec "结论"
echo "通过 $PASS / 失败 $FAIL"
[ "$FAIL" -eq 0 ] && echo "REVIEW: PASS ✅" || echo "REVIEW: FAIL ❌"
exit "$FAIL"
