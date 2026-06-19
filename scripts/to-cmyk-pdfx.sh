#!/usr/bin/env bash
set -euo pipefail

# Convert a LayoutD-exported RGB proof PDF into a local press-delivery
# CMYK PDF/X-1a file through Ghostscript.
#
# Licensing note: Ghostscript is AGPL. This helper is intended for local/personal
# delivery workflows only. Do not bundle or redistribute Ghostscript with the app
# without first recording an explicit licensing decision.
#
# K-only note: plain ICC conversion maps RGB black text to rich black. On
# Ghostscript 10.03, the tested fix is -dBlackText=true, which keeps black text
# pixels at C=M=Y=0, K=100 while images still convert through the target CMYK ICC.

usage() {
    cat <<'USAGE'
Usage:
  scripts/to-cmyk-pdfx.sh [options] INPUT.pdf OUTPUT.pdf [CMYK.icc]

Options:
  --icc PATH              Target CMYK ICC profile. Overrides the optional third argument.
  --gs PATH               Ghostscript binary. Default: /opt/local/bin/gs, then gs in PATH.
  --probe-page N          Page rendered for the K-only text probe. Default: 1.
  --probe-box L,T,R,B     Probe rectangle in PDF points from the top-left of the page.
                          Default: full page. Use this to target a known body-text area.
  --probe-dpi N           Render DPI for the K-only probe. Default: 72.
  --min-k-pixels N        Minimum pure-K dark pixels required in the probe. Default: 100.
  --cmy-tolerance N       Maximum C/M/Y byte value for pure-K pixels. Default: 3.
  --k-min N               Minimum K byte value for dark text pixels. Default: 220.
  --no-verify             Convert only; skip validation.
  -h, --help              Show this help.

Default ICC lookup order:
  /Library/Application Support/Adobe/Color/Profiles/JapanColor2011Coated.icc
  /Library/Application Support/Adobe/Color/Profiles/EuroscaleCoated.icc
  /Library/Application Support/Adobe/Color/Profiles/Recommended/CoatedFOGRA39.icc
  /Library/Application Support/Adobe/Color/Profiles/Recommended/USWebCoatedSWOP.icc
  /System/Library/ColorSync/Profiles/Generic CMYK Profile.icc
USAGE
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

info() {
    printf '%s\n' "$*" >&2
}

find_gs() {
    if [[ -x /opt/local/bin/gs ]]; then
        printf '%s\n' /opt/local/bin/gs
        return
    fi
    command -v gs || return 1
}

find_python() {
    command -v python3 || command -v /usr/bin/python3 || return 1
}

find_default_icc() {
    local candidate
    for candidate in \
        "/Library/Application Support/Adobe/Color/Profiles/JapanColor2011Coated.icc" \
        "/Library/Application Support/Adobe/Color/Profiles/EuroscaleCoated.icc" \
        "/Library/Application Support/Adobe/Color/Profiles/Recommended/CoatedFOGRA39.icc" \
        "/Library/Application Support/Adobe/Color/Profiles/Recommended/USWebCoatedSWOP.icc" \
        "/System/Library/ColorSync/Profiles/Generic CMYK Profile.icc" \
        "/opt/local/share/ghostscript/10.03.0/iccprofiles/default_cmyk.icc"; do
        if [[ -r "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return
        fi
    done
    return 1
}

abs_path() {
    "$PYTHON" -c 'import os, sys; print(os.path.abspath(sys.argv[1]))' "$1"
}

ps_escape() {
    "$PYTHON" -c 'import sys; print(sys.argv[1].replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)"))' "$1"
}

VERIFY=1
GS=""
PYTHON=""
ICC=""
PROBE_PAGE=1
PROBE_BOX=""
PROBE_DPI=72
MIN_K_PIXELS=100
CMY_TOLERANCE=3
K_MIN=220
POSITIONAL=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --icc)
            [[ $# -ge 2 ]] || die "--icc requires a path"
            ICC=$2
            shift 2
            ;;
        --gs)
            [[ $# -ge 2 ]] || die "--gs requires a path"
            GS=$2
            shift 2
            ;;
        --probe-page)
            [[ $# -ge 2 ]] || die "--probe-page requires a number"
            PROBE_PAGE=$2
            shift 2
            ;;
        --probe-box)
            [[ $# -ge 2 ]] || die "--probe-box requires L,T,R,B"
            PROBE_BOX=$2
            shift 2
            ;;
        --probe-dpi)
            [[ $# -ge 2 ]] || die "--probe-dpi requires a number"
            PROBE_DPI=$2
            shift 2
            ;;
        --min-k-pixels)
            [[ $# -ge 2 ]] || die "--min-k-pixels requires a number"
            MIN_K_PIXELS=$2
            shift 2
            ;;
        --cmy-tolerance)
            [[ $# -ge 2 ]] || die "--cmy-tolerance requires a number"
            CMY_TOLERANCE=$2
            shift 2
            ;;
        --k-min)
            [[ $# -ge 2 ]] || die "--k-min requires a number"
            K_MIN=$2
            shift 2
            ;;
        --no-verify)
            VERIFY=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            while [[ $# -gt 0 ]]; do
                POSITIONAL+=("$1")
                shift
            done
            ;;
        -*)
            die "unknown option: $1"
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

[[ ${#POSITIONAL[@]} -ge 2 && ${#POSITIONAL[@]} -le 3 ]] || {
    usage >&2
    exit 2
}

PYTHON=${PYTHON:-$(find_python)} || die "python3 is required for path handling and validation"
GS=${GS:-$(find_gs)} || die "Ghostscript not found; set --gs or install gs"

INPUT=$(abs_path "${POSITIONAL[0]}")
OUTPUT=$(abs_path "${POSITIONAL[1]}")

if [[ -z "$ICC" && ${#POSITIONAL[@]} -eq 3 ]]; then
    ICC=${POSITIONAL[2]}
fi
ICC=${ICC:-$(find_default_icc)} || die "no default CMYK ICC profile found; pass --icc PATH"
ICC=$(abs_path "$ICC")

[[ -r "$INPUT" ]] || die "input PDF is not readable: $INPUT"
[[ -r "$ICC" ]] || die "ICC profile is not readable: $ICC"
mkdir -p "$(dirname "$OUTPUT")"

TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/layoutd-cmyk-pdfx.XXXXXX")
cleanup() {
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

PDFX_DEF="$TMPDIR/pdfx1a_def.ps"
PAM="$TMPDIR/probe.pam"
ICC_PS=$(ps_escape "$ICC")
ICC_NAME=$(basename "$ICC")
ICC_NAME_PS=$(ps_escape "$ICC_NAME")

cat > "$PDFX_DEF" <<EOF
%!
[ /GTS_PDFXVersion (PDF/X-1:2001)
  /GTS_PDFXConformance (PDF/X-1a:2001)
  /Title (LayoutD CMYK PDF/X-1a)
  /Trapped /False
/DOCINFO pdfmark

/ICCProfile ($ICC_PS) def

[/_objdef {icc_PDFX} /type /stream /OBJ pdfmark
[{icc_PDFX} << /N 4 >> /PUT pdfmark
[{icc_PDFX} ICCProfile (r) file /PUT pdfmark

[/_objdef {OutputIntent_PDFX} /type /dict /OBJ pdfmark
[{OutputIntent_PDFX} <<
  /Type /OutputIntent
  /S /GTS_PDFX
  /OutputCondition ($ICC_NAME_PS)
  /Info ($ICC_NAME_PS)
  /OutputConditionIdentifier ($ICC_NAME_PS)
  /RegistryName (http://www.color.org)
  /DestOutputProfile {icc_PDFX}
>> /PUT pdfmark
[{Catalog} <</OutputIntents [ {OutputIntent_PDFX} ]>> /PUT pdfmark
EOF

info "Converting to CMYK PDF/X-1a"
info "  input:  $INPUT"
info "  output: $OUTPUT"
info "  icc:    $ICC"

"$GS" \
    -dSAFER \
    "--permit-file-read=$INPUT" \
    "--permit-file-read=$ICC" \
    -dBATCH \
    -dNOPAUSE \
    -q \
    -sDEVICE=pdfwrite \
    -dCompatibilityLevel=1.3 \
    -dPDFX \
    -dPDFSETTINGS=/prepress \
    -dEmbedAllFonts=true \
    -dSubsetFonts=true \
    -dCompressFonts=true \
    -dAutoRotatePages=/None \
    -dColorConversionStrategy=/CMYK \
    -dProcessColorModel=/DeviceCMYK \
    "-sOutputICCProfile=$ICC" \
    "-sVectorICCProfile=$ICC" \
    -dBlackText=true \
    "-sOutputFile=$OUTPUT" \
    "$PDFX_DEF" \
    "$INPUT"

if [[ $VERIFY -eq 0 ]]; then
    info "Verification skipped (--no-verify)."
    exit 0
fi

info "Validating PDF/X markers, CMYK-only content, boxes, and font safety"
"$PYTHON" - "$OUTPUT" <<'PY'
import re
import sys
from pathlib import Path

pdf = Path(sys.argv[1]).read_bytes()
has_font_resource = re.search(rb"/Type\s*/Font\b|/Font\s*<<", pdf) is not None
has_embedded_font_program = any(token in pdf for token in (b"/FontFile", b"/FontFile2", b"/FontFile3"))
checks = {
    "PDF/X-1 version": b"/GTS_PDFXVersion" in pdf and b"PDF/X-1:2001" in pdf,
    "PDF/X-1a conformance": b"/GTS_PDFXConformance" in pdf and b"PDF/X-1a:2001" in pdf,
    "OutputIntent": b"/OutputIntents" in pdf and b"/GTS_PDFX" in pdf,
    "No DeviceRGB": b"/DeviceRGB" not in pdf and b"/CalRGB" not in pdf,
    "No unembedded fonts": has_embedded_font_program or not has_font_resource,
    "TrimBox present": b"/TrimBox" in pdf,
    "BleedBox present": b"/BleedBox" in pdf,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"  {name}: {'pass' if ok else 'FAIL'}")
if failed:
    raise SystemExit("PDF structure validation failed: " + ", ".join(failed))
if has_embedded_font_program:
    print("  font mode: embedded font programs present")
else:
    print("  font mode: no remaining font resources; text is outlined by Ghostscript")

for box in ("TrimBox", "BleedBox"):
    match = re.search(rb"/" + box.encode() + rb"\s*\[([^\]]+)\]", pdf)
    if match:
        values = " ".join(match.group(1).decode("latin1", "replace").split())
        print(f"  {box}: [{values}]")
PY

info "Ghostscript ink coverage by page"
"$GS" -dSAFER -dBATCH -dNOPAUSE -q -sDEVICE=inkcov -o - "$OUTPUT"

info "Rendering page $PROBE_PAGE for K-only body-text probe"
"$GS" \
    -dSAFER \
    -dBATCH \
    -dNOPAUSE \
    -q \
    -sDEVICE=pamcmyk32 \
    "-r$PROBE_DPI" \
    "-dFirstPage=$PROBE_PAGE" \
    "-dLastPage=$PROBE_PAGE" \
    "-sOutputFile=$PAM" \
    "$OUTPUT"

"$PYTHON" - "$PAM" "$PROBE_DPI" "$PROBE_BOX" "$MIN_K_PIXELS" "$CMY_TOLERANCE" "$K_MIN" <<'PY'
import sys
from pathlib import Path

pam_path = Path(sys.argv[1])
dpi = float(sys.argv[2])
probe_box = sys.argv[3]
min_pixels = int(sys.argv[4])
cmy_tolerance = int(sys.argv[5])
k_min = int(sys.argv[6])

raw = pam_path.read_bytes()
header, data = raw.split(b"ENDHDR\n", 1)
meta = {}
for line in header.splitlines()[1:]:
    if b" " in line:
        key, value = line.split(b" ", 1)
        meta[key.decode()] = value.decode()

width = int(meta["WIDTH"])
height = int(meta["HEIGHT"])
depth = int(meta["DEPTH"])
if depth != 4 or meta.get("TUPLTYPE") != "CMYK":
    raise SystemExit(f"unexpected PAM format: {meta}")
if len(data) != width * height * 4:
    raise SystemExit("unexpected PAM data length")

if probe_box:
    try:
        left, top, right, bottom = [float(part) for part in probe_box.split(",")]
    except ValueError as exc:
        raise SystemExit("--probe-box must be L,T,R,B in PDF points from top-left") from exc
    scale = dpi / 72.0
    x0 = max(0, min(width, int(round(left * scale))))
    y0 = max(0, min(height, int(round(top * scale))))
    x1 = max(0, min(width, int(round(right * scale))))
    y1 = max(0, min(height, int(round(bottom * scale))))
else:
    x0, y0, x1, y1 = 0, 0, width, height

if x1 <= x0 or y1 <= y0:
    raise SystemExit(f"empty probe box after rasterization: {(x0, y0, x1, y1)}")

pure_k = 0
max_c = max_m = max_y = 0
min_k = 255
max_k = 0
sample_points = []
for row in range(y0, y1):
    base = row * width * 4
    for col in range(x0, x1):
        i = base + col * 4
        c, m, y, k = data[i:i + 4]
        if c <= cmy_tolerance and m <= cmy_tolerance and y <= cmy_tolerance and k >= k_min:
            pure_k += 1
            max_c = max(max_c, c)
            max_m = max(max_m, m)
            max_y = max(max_y, y)
            min_k = min(min_k, k)
            max_k = max(max_k, k)
            if len(sample_points) < 5:
                sample_points.append((col, row, c, m, y, k))

print(f"  probe raster: {width}x{height}px at {dpi:g} dpi")
print(f"  probe box px: {x0},{y0},{x1},{y1}")
print(f"  pure-K dark pixels: {pure_k} (required >= {min_pixels})")
if pure_k:
    print(f"  observed max CMY: {max_c},{max_m},{max_y}; K range: {min_k}-{max_k}")
    print("  sample pixels: " + "; ".join(f"({x},{y})={c},{m},{yy},{k}" for x, y, c, m, yy, k in sample_points))

if pure_k < min_pixels:
    raise SystemExit(
        "K-only probe failed: not enough C=M=Y~0, high-K text pixels. "
        "Try --probe-box over a known black body-text area, or inspect whether "
        "the source text is not black text."
    )
PY

info "Done: CMYK PDF/X-1a conversion and K-only probe passed."
