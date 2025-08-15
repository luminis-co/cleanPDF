#!/bin/bash


set -euo pipefail


DEFAULT_QUALITY="ebook"
DEFAULT_MAX_SIZE="30M"
DEFAULT_SANITIZE_SUB="strong"
DEFAULT_COMPRESS_SUB="scan"

# ---- Logging Functions ----
log_time(){
    date '+%Y-%m-%d %H:%M:%S';
}
log_info (){
    echo -e "\e[32m[INFO]  - \e[0m $*";
}

log_warn(){
    echo -e  "\e[33m[WARN]  - \e[0m $*";
}

log_error(){
    echo -e "\e[31m[ERROR] - \e[0m $*" >&2;
}
# ---- Helpers ----
usage() {
  cat << 'EOF'
  Usage:
  ./cleanpdf.sh sanitize <submode> <input.pdf> <output.pdf> [quality] [--max-size=<size>]
  ./cleanpdf.sh compress <submode> <input.pdf> <output.pdf> [quality] [--max-size=<size>]

  Sanitize modes (membersihkan PDF dari konten berbahaya):
    normal  : Rewrite dengan Ghostscript (pdfwrite). Menghapus metadata, JS, object tak terpakai.
    strong  : PostScript round-trip (ps2write → pdfwrite). Menghapus form, layer, JS sepenuhnya.
    ultra   : Rasterisasi → ubah halaman jadi gambar, lalu buat PDF baru. Aman total, teks hilang.
    pdfa    : [opsi tambahan] Konversi ke PDF/A-2b untuk arsip jangka panjang, bebas konten aktif.

  Compress modes (mengurangi ukuran PDF):
    auto    : Kompres otomatis hingga mendekati target max-size.
    scan    : Kompres PDF hasil scan (300/200 DPI).

  Options:
    quality         : Tingkat kualitas (screen | ebook | printer | prepress). Default: ebook.
    --max-size=<s>  : Target ukuran maksimum (contoh: 5M, 20M). Default: 10M.
  
  Examples:
    ./cleanpdf.sh sanitize normal file.pdf clean.pdf
    ./cleanpdf.sh sanitize strong file.pdf clean.pdf screen
    ./cleanpdf.sh sanitize ultra scan.pdf safe.pdf --max-size=5M
    ./cleanpdf.sh compress auto big.pdf small.pdf --max-size=10M
    ./cleanpdf.sh compress scan scan.pdf scan_small.pdf printer
EOF
}

require_file_readable(){
    local f="$1"
    [[ -r "$f" ]] || { log_error "File tidak dapat dibaca: $f"; exit 1; }
}

ensure_output_dir(){
    local f="$1"; local d; d="$(dirname -- "$f")"
    [[ -d "$d" && -w "$d" ]] || { log_error "Folder output tidak bisa ditulis: $d"; exit 1; }
}

# ---- Dependency Check ----
check_tools(){
    local tools=("gs" "pdfid" "pdftoppm" "img2pdf" "exiftool" "stat" "numfmt")
  local missing=()
  for tool in "${tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done
  if [ ${#missing[@]} -ne 0 ]; then
    log_error "Tool berikut tidak ditemukan: ${missing[*]}"
    echo "Install (Debian/Ubuntu): sudo apt install ghostscript poppler-utils img2pdf exiftool coreutils"
    exit 1
  fi
}

# ---- Sanitize (Normal/Strong/Ultra) ----
sanitize_normal(){
    local in_file="$1"; local out_file="$2"
    log_info "  [*] Ghostscript Rewrite"
    gs -dNOPAUSE -dBATCH -dSAFER \
       -sDEVICE=pdfwrite \
       -dCompatibilityLevel=1.4 \
       -dDetectDuplicateImages=true \
       -dCompressFonts=true \
       -dNOPLATFONTS \
       -sOutputFile="$out_file" \
       "$in_file" >/dev/null 2>&1
}
sanitize_strong(){
    local in_file="$1"; local out_file="$2"
    local temp_ps=$(mktemp /tmp/pdf_sanitize.XXXXXX.ps)
    local temp_pdf=$(mktemp /tmp/pdf_sanitize.XXXXXX.pdf)
    trap 'rm -f "$temp_ps" "$temp_pdf"' RETURN
    log_info "  [*] PostScript Round-Trip"

    log_info "  [1/3] Flatten ke PostScript..."
    gs -dNOPAUSE -dBATCH -dSAFER \
       -sDEVICE=ps2write \
       -sOutputFile="$temp_ps" \
       "$in_file" >/dev/null 2>&1

    log_info "  [2/3] Konversi kembali ke PDF..."
    gs -dNOPAUSE -dBATCH -dSAFER \
       -sDEVICE=pdfwrite \
       -dCompatibilityLevel=1.4 \
       -sOutputFile="$temp_pdf" \
       "$temp_ps" >/dev/null 2>&1

    log_info "  [3/3] Simpan hasil akhir..."
    mv -f "$temp_pdf" "$out_file"
}

sanitize_ultra(){
    local in_file="$1"; local out_file="$2"; local dpi="${3:-300}"
    local tmp_dir; tmp_dir=$(mktemp -d /tmp/pdf_ultra.XXXXXX)

    trap 'rm -f "$tmp_dir"' RETURN

    log_info "  [1/4] Ekstrak halaman jadi gambar PNG..."
    pdftoppm -r "$dpi" -png "$in_file" "$tmp_dir/page" >/dev/null 2>&1

    log_info "  [2/4] Buat PDF dari gambar..."
    img2pdf "$tmp_dir"/*.png -o "$tmp_dir/image_only.pdf"

    log_info "  [3/4] Bersihkan metadata..."
    gs -dNOPAUSE -dBATCH -dSAFER \
       -sDEVICE=pdfwrite \
       -dCompatibilityLevel=1.4 \
       -dDetectDuplicateImages=true \
       -dCompressFonts=true \
       -sOutputFile="$tmp_dir/clean.pdf" \
       "$tmp_dir/image_only.pdf" >/dev/null 2>&1

    log_info "  [4/4] Simpan hasil akhir..."
    mv -f "$tmp_dir/clean.pdf" "$out_file"
}

sanitize_pdfa(){
  local in_file="$1"
  local out_file="$2"
  local temp_pdf=$(mktemp /tmp/pdf_sanitize.XXXXXX.pdf)
  trap 'rm -f "$temp_pdf"' RETURN

  log_info "  [*] Converting to PDF/A (GhostScript)..."
  gs -dPDFA=2 \
      -dBATCH -dNOPAUSE -dNOOUTERSAVE -dNOSAFER \
      -sProcessColorModel=DeviceRGB \
      -sDEVICE=pdfwrite \
      -dPDFACompatibilityPolicy=1 \
      -sOutputFile="$temp_pdf" \
      "$in_file" >/dev/null 2>&1
    log_info "  [3/3] Simpan hasil akhir..."
    mv -f "$temp_pdf" "$out_file"
}

# ---- Compress ----
compress_scan(){
    local in_file="$1"; local out_file="$2"; local dpi="${3:-200}"
    local tmp_pdf=$(mktemp /tmp/pdf_scan_compress.XXXXXX.pdf)

    # Kompres gambar hasil scan
    gs -sDEVICE=pdfwrite \
       -dCompatibilityLevel=1.4 \
       -dNOPAUSE -dQUIET -dBATCH \
       -dDetectDuplicateImages=true \
       -dColorImageDownsampleType=/Bicubic \
       -dColorImageResolution=$dpi \
       -dGrayImageDownsampleType=/Bicubic \
       -dGrayImageResolution=$dpi \
       -dMonoImageDownsampleType=/Subsample \
       -dMonoImageResolution=600 \
       -dAutoFilterColorImages=false \
       -dAutoFilterGrayImages=false \
       -dColorImageFilter=/DCTEncode \
       -dGrayImageFilter=/DCTEncode \
       -dJPEGQ=85 \
       -sOutputFile="$tmp_pdf" "$in_file" >/dev/null 2>&1

        log_info "  [3/3] Simpan hasil akhir..."
        mv "$tmp_pdf" "$out_file"
}

auto_size_limit(){
    local file="$1"; local max_size="${2:-$DEFAULT_MAX_SIZE}"; local dpi_start="${3:-300}"
    local size_bytes; size_bytes=$(stat -c%s "$file")
    local size_limit_bytes; size_limit_bytes=$(numfmt --from=iec "$max_size")

    local temp_pdf=$(mktemp /tmp/pdf_autosize.XXXXXX.pdf)
    local dpi=$dpi_start

    while (( size_bytes > size_limit_bytes && dpi > 72 )); do
        log_info "  Ukuran saat ini: $(numfmt --to=iec $size_bytes), menurunkan resolusi ke $dpi dpi..."
        dpi=$(( dpi - 20 ))
        resize_pdf_hq "$file" "$temp_pdf" "$dpi"
        mv "$temp_pdf" "$file"
        size_bytes=$(stat -c%s "$file")
    done
}

# ---- Arg Parsing ----
if [ $# -lt 3 ]; then
    usage; exit 1
fi

MODE_MAIN="$1"

if [[ "$MODE_MAIN" == "sanitize" ]]; then
  if [[ "${2:-}" == "normal" || "${2:-}" == "strong" || "${2:-}" == "ultra" || "${2:-}" ==  "pdfa" ]]; then
    MODE_SUB="$2"; INPUT="$3"; OUTPUT="$4"; QUALITY="${5:-$DEFAULT_QUALITY}"
    [[ "${6:-}" == --max-size=* ]] && MAX_SIZE="${6#--max-size=}" || MAX_SIZE="$DEFAULT_MAX_SIZE"
  else
    MODE_SUB="$DEFAULT_SANITIZE_SUB"; INPUT="$2"; OUTPUT="$3"; QUALITY="${4:-$DEFAULT_QUALITY}"
    [[ "${5:-}" == --max-size=* ]] && MAX_SIZE="${5#--max-size=}" || MAX_SIZE="$DEFAULT_MAX_SIZE"
  fi
elif [[ "$MODE_MAIN" ==  "compress" ]]; then
  if [[ "${2:-}" == "auto" || "${2-}" == "scan" ]]; then
    MODE_SUB="$2"; INPUT="$3"; OUTPUT="$4"; QUALITY="${5:-$DEFAULT_QUALITY}"
    [[ "${6:-}" == --max-size=* ]] && MAX_SIZE="${6#--max-size=}" || MAX_SIZE="$DEFAULT_MAX_SIZE"
  else
    MODE_SUB="$DEFAULT_COMPRESS_SUB"; INPUT="$2"; OUTPUT="$3"; QUALITY="${4:-$DEFAULT_QUALITY}"
    [[ "${5:-}" == --max-size=* ]] && MAX_SIZE="${5#--max-size=}" || MAX_SIZE="$DEFAULT_MAX_SIZE"
  fi
else
  log_error "Mode harus 'sanitize' atau 'compress'"; usage; exit 1  
fi

# ---- Validasi ----
check_tools
require_file_readable "$INPUT"
ensure_output_dir "$OUTPUT"

log_time

log_info "Mode: $MODE_MAIN | Module: $MODE_SUB | Quality: $QUALITY | Max: $MAX_SIZE"
log_info "Size awal: $(numfmt --to=iec "$(stat -c%s "$INPUT")")"


# --- Main ----
case "$MODE_MAIN" in 
  sanitize)
    case "$MODE_SUB" in
      normal) sanitize_normal "$INPUT" "$OUTPUT" ;;
      strong) sanitize_strong "$INPUT" "$OUTPUT" ;;
      ultra) sanitize_ultra "$INPUT" "$OUTPUT" ;;
      pdfa) sanitize_pdfa "$INPUT" "$OUTPUT" ;;
      *) log_error "Mode tidak tersedia. Hanya mode ini 'normal' | 'strong' | 'ultra' | 'pdfa' | 'flatten' yang tersedia";;
    esac
    ;;
  compress)
    case "$MODE_SUB" in
      auto)  auto_size_limit "$OUTPUT" "$MAX_SIZE" 300 ;;
      scan) compress_scan "$INPUT" "$OUTPUT" 200 ;;
      *) log_error "Mode Compress harus 'auto' | 'scan'"; exit 1;;
    esac
    ;;
esac
### ===== Metadata Clean + Rewrite =====
log_info "Remove metadata dengan ExifTool..."
exiftool -all= -overwrite_original "$OUTPUT" >/dev/null 2>&1

### ===== Post Info =====
log_info "Ukuran akhir: $(numfmt --to=iec "$(stat -c%s "$OUTPUT")")"
log_info "Post-scan dengan pdfid..."
pdfid "$OUTPUT" || true
log_info "✅ Selesai! File disimpan sebagai: $OUTPUT"