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
        italic='Skew="12"' in attr
        spans.append((bold, italic, txt))
def styled(sub,want_bold,want_italic):
    return any(sub in txt and bold==want_bold and italic==want_italic for bold,italic,txt in spans)
def residue(ch):
    return any(ch in txt for _,_,txt in spans)
checks=[
    ("粗体词→FauxBold",      styled("粗体",True,False)),
    ("斜体词(CJK)→Skew(伪斜体)", styled("斜体",False,True)),
    ("无残留 * 分隔符",   not residue("*")),
    ("无残留 _ 分隔符",   not residue("_")),
]
fails=[n for n,okk in checks if not okk]
for n,okk in checks:
    print(("  ✅ " if okk else "  ❌ ")+n)
sys.exit(1 if fails else 0)
PY
[ $? -eq 0 ] && ok "行内强调断言全过" || bad "行内强调断言有失败（见上）"

# 2d. 角色标签导入：标签字面必须被消费，正文段落必须挂到对应中文命名样式。
ROLE_FIX="$TMP/role-tags.md"
printf '一级标题/章名\n越山脉\n\n开节概述\n这里是章节概述。\n\n抽言\n山高水长。\n\n普通正文段落。\n\n参考文献\n[1] 王某. 山地研究.\n' > "$ROLE_FIX"
ROLE_OUT="$TMP/out/role-tags.idml"
if swift run layoutD -- "$ROLE_FIX" --export-idml "$ROLE_OUT" >"$TMP/role-export.log" 2>&1; then
  ok "角色标签 fixture 导出成功"
  unzip -oq "$ROLE_OUT" -d "$TMP/role-u"
  python3 - "$TMP/role-u" <<'PY'
import glob, html, os, re, sys
root=sys.argv[1]
styles_path=os.path.join(root,'Resources','Styles.xml')
styles=open(styles_path,encoding='utf-8').read()
stories=[]
for f in glob.glob(os.path.join(root,'Stories','*.xml')):
    stories.append(open(f,encoding='utf-8').read())
story='\n'.join(stories)

def content_text(body):
    return html.unescape(''.join(re.findall(r'<Content>(.*?)</Content>', body, re.S)))

style_ranges=[]
for m in re.finditer(r'<ParagraphStyleRange([^>]*)>(.*?)</ParagraphStyleRange>', story, re.S):
    attr, body = m.groups()
    style_match = re.search(r'AppliedParagraphStyle="([^"]+)"', attr)
    if style_match:
        style_ranges.append((style_match.group(1), content_text(body)))

def has_style_display_name(name):
    return re.search(r'<ParagraphStyle\b[^>]*\bName="%s"' % re.escape(name), styles) is not None

def paragraph_uses(text, style):
    return any(text in body and applied == style for applied, body in style_ranges)

checks=[
    ("标签字面 一级标题/章名 零漏出", "一级标题" not in story and "章名" not in story),
    ("标签字面 开节概述 零漏出", "开节概述\n" not in ''.join(text for _, text in style_ranges)),
    ("标签字面 抽言 零漏出", not any(text.strip() == "抽言" for _, text in style_ranges)),
    ("标签字面 参考文献 零漏出", not any(text.strip() == "参考文献" for _, text in style_ranges)),
    ("Styles.xml 含中文样式 一级标题", has_style_display_name("一级标题")),
    ("Styles.xml 含中文样式 开节概述", has_style_display_name("开节概述")),
    ("Styles.xml 含中文样式 抽言", has_style_display_name("抽言")),
    ("Styles.xml 含中文样式 参考文献", has_style_display_name("参考文献")),
    ("章名内容→heading1", paragraph_uses("越山脉", "ParagraphStyle/heading1")),
    ("概述内容→introduction", paragraph_uses("这里是章节概述。", "ParagraphStyle/introduction")),
    ("抽言内容→pullQuote", paragraph_uses("山高水长。", "ParagraphStyle/pullQuote")),
    ("参考文献内容→bibliography", paragraph_uses("[1] 王某. 山地研究.", "ParagraphStyle/bibliography")),
    ("后续普通正文→body", paragraph_uses("普通正文段落。", "ParagraphStyle/body")),
]
fails=[name for name, ok in checks if not ok]
for name, ok in checks:
    print(("  ✅ " if ok else "  ❌ ")+name)
sys.exit(1 if fails else 0)
PY
  [ $? -eq 0 ] && ok "角色标签断言全过" || bad "角色标签断言有失败（见上）"
else
  bad "角色标签 fixture 导出失败（见 $TMP/role-export.log）"
fi

# 2e. DOCX 导入链路：最小 OOXML 覆盖粗斜体、图片和脚注，避免 DOCX 只靠单测兜底。
DOCX_FIX="$TMP/docx-fixture.docx"
python3 - "$DOCX_FIX" <<'PY'
import sys, zipfile
out=sys.argv[1]
document='''<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
            xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
            xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">
  <w:body>
    <w:p><w:r><w:t>DOCX正文</w:t></w:r><w:r><w:rPr><w:b/></w:rPr><w:t>粗体</w:t></w:r><w:r><w:rPr><w:i/></w:rPr><w:t>斜体</w:t></w:r><w:r><w:footnoteReference w:id="2"/></w:r></w:p>
    <w:p><w:drawing><wp:extent cx="12700" cy="12700"/><a:blip r:embed="rId4"/></w:drawing></w:p>
  </w:body>
</w:document>'''
rels='''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.png"/>
</Relationships>'''
footnotes='''<?xml version="1.0" encoding="UTF-8"?>
<w:footnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:footnote w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:footnote>
  <w:footnote w:id="2"><w:p><w:r><w:t>DOCX脚注内容</w:t></w:r></w:p></w:footnote>
</w:footnotes>'''
png=bytes([
    0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
    0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
    0x89,0x00,0x00,0x00,0x0D,0x49,0x44,0x41,0x54,0x78,0x9C,0x63,0x60,0x60,0x60,0x00,
    0x00,0x00,0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,
    0x44,0xAE,0x42,0x60,0x82
])
with zipfile.ZipFile(out,'w',zipfile.ZIP_STORED) as z:
    z.writestr('word/document.xml', document)
    z.writestr('word/_rels/document.xml.rels', rels)
    z.writestr('word/footnotes.xml', footnotes)
    z.writestr('word/media/image1.png', png)
PY
DOCX_OUT="$TMP/out/docx-fixture.idml"
if swift run layoutD -- "$DOCX_FIX" --export-idml "$DOCX_OUT" >"$TMP/docx-export.log" 2>&1; then
  ok "DOCX fixture 导出成功"
  unzip -oq "$DOCX_OUT" -d "$TMP/docx-u"
  python3 - "$TMP/docx-u" "$TMP/out/Links" <<'PY'
import glob, html, os, re, sys
root=sys.argv[1]
links_dir=sys.argv[2]
story='\n'.join(open(f,encoding='utf-8').read() for f in glob.glob(os.path.join(root,'Stories','*.xml')))
spreads='\n'.join(open(f,encoding='utf-8').read() for f in glob.glob(os.path.join(root,'Spreads','*.xml')))
spans=[]
for m in re.finditer(r'<CharacterStyleRange([^>]*)>(.*?)</CharacterStyleRange>', story, re.S):
    attr,body=m.groups()
    txt=html.unescape(''.join(re.findall(r'<Content>(.*?)</Content>',body,re.S)))
    spans.append(('FauxBold="true"' in attr, 'Skew="12"' in attr, txt))
story_text=''.join(txt for _,_,txt in spans)
def styled(sub,want_bold,want_italic):
    return any(sub in txt and bold==want_bold and italic==want_italic for bold,italic,txt in spans)
checks=[
    ("DOCX 正文进入 Story", "DOCX" in story_text and "正文" in story_text),
    ("DOCX 粗体→FauxBold", styled("粗体", True, False)),
    ("DOCX 斜体→Skew", styled("斜体", False, True)),
    ("DOCX 脚注→原生 Footnote", "<Footnote>" in story and "DOCX脚注内容" in story),
    ("DOCX 脚注上标不残留", "<Content>¹</Content>" not in story),
    ("DOCX 图片→Links 打包", os.path.exists(os.path.join(links_dir, "image1.png")) and "file:Links/image1.png" in spreads),
]
fails=[name for name, ok in checks if not ok]
for name, ok in checks:
    print(("  ✅ " if ok else "  ❌ ")+name)
sys.exit(1 if fails else 0)
PY
  [ $? -eq 0 ] && ok "DOCX 导入断言全过" || bad "DOCX 导入断言有失败（见上）"
else
  bad "DOCX fixture 导出失败（见 $TMP/docx-export.log）"
fi

# 2f. GUARD-4 串接文流：连续纯正文合成一条串接流 Story、逐页框 Previous/NextTextFrame
# 首尾相连（FRAME-SPLIT：标题/抽言等独立框会断流；60 段连续正文=恰好 1 条流）。
# 断言链条完整（能从任一链头走到链尾、覆盖该 Story 的全部框、无孤儿）、story 数按流计不按段计。
THREAD_FIX="$TMP/thread-fixture.md"
python3 - "$THREAD_FIX" <<'PY'
import sys
path = sys.argv[1]
paras = ["# 串接文流探针章节\n"]
base = "这是正文段落，用来撑满多页版面，验证串接文流的框链是否完整覆盖、无孤儿、无断裂。反复堆叠中文文字直到超过单页可用高度，从而制造跨页跨栏拆分的场景。"
for i in range(60):
    paras.append(f"第{i+1}段。{base}")
open(path, "w").write("\n\n".join(paras))
PY
THREAD_OUT="$TMP/out/thread-fixture.idml"
if swift run layoutD -- "$THREAD_FIX" --export-idml "$THREAD_OUT" >"$TMP/thread-export.log" 2>&1; then
  ok "串接探针 fixture 导出成功"
  unzip -oq "$THREAD_OUT" -d "$TMP/thread-u"
  python3 - "$TMP/thread-u" <<'PY'
import glob, os, re, sys
root = sys.argv[1]

designmap = open(os.path.join(root, "designmap.xml"), encoding="utf-8").read()
story_list = re.search(r'StoryList="([^"]*)"', designmap).group(1).split()
chapter_stories = [s for s in story_list if s.startswith("uStoryFlow")]

spreads = "\n".join(open(f, encoding="utf-8").read() for f in glob.glob(os.path.join(root, "Spreads", "*.xml")))
frames = re.findall(
    r'<TextFrame Self="(uFlowTF[^"]*)" ParentStory="([^"]*)"[^>]*PreviousTextFrame="([^"]*)" NextTextFrame="([^"]*)"',
    spreads)

checks = []
checks.append(("连续正文合成一条流 Story（60 段连续正文应恰好 1 个 uStoryFlow）", len(chapter_stories) == 1))
checks.append(("串接框存在（至少跨 2 页/栏）", len(frames) >= 2))

by_story = {}
for self_id, parent, prev, nxt in frames:
    by_story.setdefault(parent, []).append((self_id, prev, nxt))

chain_ok = True
for parent, entries in by_story.items():
    ids = {e[0] for e in entries}
    prev_map = {e[0]: e[1] for e in entries}
    next_map = {e[0]: e[2] for e in entries}
    heads = [i for i in ids if prev_map[i] == "n"]
    tails = [i for i in ids if next_map[i] == "n"]
    if len(heads) != 1 or len(tails) != 1:
        chain_ok = False
        continue
    # 从链头顺着 Next 走一遍，必须不重复、不漏、恰好覆盖该 Story 的全部框。
    visited = []
    cur = heads[0]
    seen = set()
    while cur != "n":
        if cur in seen:
            chain_ok = False
            break
        seen.add(cur)
        visited.append(cur)
        cur = next_map.get(cur, "n")
    if seen != ids:
        chain_ok = False
    # 反向从链尾顺着 Previous 走，必须原路对称。
    cur = tails[0]
    seen_back = set()
    while cur != "n":
        if cur in seen_back:
            chain_ok = False
            break
        seen_back.add(cur)
        cur = prev_map.get(cur, "n")
    if seen_back != ids:
        chain_ok = False

checks.append(("串接链完整（单头单尾、正反遍历都覆盖全部框、无孤儿无环）", chain_ok))

fails = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(("  ✅ " if ok else "  ❌ ") + name)
sys.exit(1 if fails else 0)
PY
  [ $? -eq 0 ] && ok "GUARD-4 串接文流断言全过" || bad "GUARD-4 串接文流断言有失败（见上）"
else
  bad "串接探针 fixture 导出失败（见 $TMP/thread-export.log）"
fi

# 2g. SAMPLE-1 掩码确定性：PDF 导出的「重跑确定性」不能在字节级直接验——Quartz PDFContext
# 每份 PDF 都盖 /CreationDate、/ModDate（精确到秒）和随机 /ID，连朴素 --export-pdf 两次都不一致。
# 但版面/内容本身是确定的。故导出两次、抹掉这三处易变元数据后应「逐字节一致」，以此证明确定性
# 而不去改 PDF 字节本身（改字节要保等长否则毁 xref、且遇压缩对象流会静默失效，见 DECISIONS）。
sec "PDF 掩码确定性探针（SAMPLE-1）"
DET1="$TMP/det1.pdf"; DET2="$TMP/det2.pdf"
if swift run layoutD -- Samples/fixture-standard-chapter.md --export-pdf "$DET1" >"$TMP/det1.log" 2>&1 \
   && swift run layoutD -- Samples/fixture-standard-chapter.md --export-pdf "$DET2" >"$TMP/det2.log" 2>&1; then
  python3 - "$DET1" "$DET2" <<'PY'
import re, sys
def mask(path):
    data = open(path, 'rb').read()
    data = re.sub(rb'/CreationDate\s*\(D:[^)]*\)', b'/CreationDate(MASKED)', data)
    data = re.sub(rb'/ModDate\s*\(D:[^)]*\)',      b'/ModDate(MASKED)',      data)
    data = re.sub(rb'/ID\s*\[\s*<[0-9A-Fa-f]+>\s*<[0-9A-Fa-f]+>\s*\]', b'/ID[MASKED]', data)
    return data
a, b = mask(sys.argv[1]), mask(sys.argv[2])
if a == b:
    print("  ✅ 掩码 CreationDate/ModDate/ID 后两次导出逐字节一致")
    sys.exit(0)
n = min(len(a), len(b)); i = next((k for k in range(n) if a[k] != b[k]), n)
print(f"  ❌ 掩码后仍不一致（len {len(a)} vs {len(b)}，首个差异 @ 偏移 {i}）")
print("     …%r\n     vs %r" % (a[max(0,i-24):i+24], b[max(0,i-24):i+24]))
sys.exit(1)
PY
  [ $? -eq 0 ] && ok "SAMPLE-1 掩码确定性断言全过" || bad "SAMPLE-1 掩码确定性有失败（见上）"
else
  bad "PDF 掩码确定性探针导出失败（见 $TMP/det1.log / det2.log）"
fi

# --- golden 回归（防漂移网）。仅本地跑：CI runner 的字体解析与本机有差异会误报，
# 见 .github/workflows/ci.yml 注释；本地跑本脚本即自动带上，堵住「忘了单独跑」的洞。
if [ -z "${CI:-}" ]; then
  sec "golden 回归（本地）"
  if bash scripts/golden-check.sh >"$TMP/golden.log" 2>&1; then
    ok "golden 基线逐字节一致"
  else
    bad "golden 基线漂移——若变化是本次改动的预期结果，跑 scripts/golden-update.sh --reason \"<原因>\" 刷新留痕"
    tail -20 "$TMP/golden.log"
  fi
else
  sec "golden 回归"
  echo "  ⏭ CI 环境跳过（字体环境差异会误报；本地跑本脚本时必查）"
fi

sec "结论"
echo "通过 $PASS / 失败 $FAIL"
[ "$FAIL" -eq 0 ] && echo "REVIEW: PASS ✅" || echo "REVIEW: FAIL ❌"
exit "$FAIL"
