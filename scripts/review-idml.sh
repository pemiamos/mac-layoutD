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

sec "结论"
echo "通过 $PASS / 失败 $FAIL"
[ "$FAIL" -eq 0 ] && echo "REVIEW: PASS ✅" || echo "REVIEW: FAIL ❌"
exit "$FAIL"
