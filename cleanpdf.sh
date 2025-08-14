#!/bin/bash


DEFAULT_QUALITY="ebook"
DEFAULT_MAX_SIZE="30M"
DEFAULT_SANITIZE_SUB="strong"
DEFAULT_COMPRESS_SUB="scan"

# --- Fungsi Sanitize ---
sanitize_normal() {
    local in_file="$1"
    local out_file="$2"
    gs -dNOPAUSE -dBATCH -dSAFER \
       -sDEVICE=pdfwrite \
       -dCompatibilityLevel=1.4 \
       -dDetectDuplicateImages=true \
       -dCompressFonts=true \
       -dNOPLATFONTS \
       -sOutputFile="$out_file" \
       "$in_file" >/dev/null 2>&1
}

sanitize_strong() {
    local in_file="$1"
    local out_file="$2"
    local temp_ps=$(mktemp /tmp/pdf_sanitize.XXXXXX.ps)
    local temp_pdf=$(mktemp /tmp/pdf_sanitize.XXXXXX.pdf)
    trap 'rm -f "$temp_ps" "$temp_pdf"' RETURN

    echo "  [1/3] Flatten ke PostScript..."
    gs -dNOPAUSE -dBATCH -dSAFER \
       -sDEVICE=ps2write \
       -sOutputFile="$temp_ps" \
       "$in_file" >/dev/null 2>&1

    echo "  [2/3] Konversi kembali ke PDF..."
    gs -dNOPAUSE -dBATCH -dSAFER \
       -sDEVICE=pdfwrite \
       -dCompatibilityLevel=1.4 \
       -sOutputFile="$temp_pdf" \
       "$temp_ps" >/dev/null 2>&1

    echo "  [3/3] Simpan hasil akhir..."
    mv "$temp_pdf" "$out_file"
}

sanitize_ultra(){
    local in_file="$1"
    local out_file="$2"
    local dpi="${3:-300}"
    local tmp_dir
    tmp_dir=$(mktemp -d /tmp/pdf_ultra.XXXXXX)

    trap 'rm -rm "$tmp_dir"' RETURN

    echo "  [1/4] Ekstrak halaman jadi gambar PNG..."
    pdftoppm -r "$dpi" -png "$in_file" "$tmp_dir/page" >/dev/null 2>&1

    echo "  [2/4] Buat PDF dari gambar..."
    img2pdf "$tmp_dir"/*.png -o "$tmp_dir/image_only.pdf"

    echo "  [3/4] Bersihkan metadata..."
    gs -dNOPAUSE -dBATCH -dSAFER \
       -sDEVICE=pdfwrite \
       -dCompatibilityLevel=1.4 \
       -dDetectDuplicateImages=true \
       -dCompressFonts=true \
       -sOutputFile="$tmp_dir/clean.pdf" \
       "$tmp_dir/image_only.pdf" >/dev/null 2>&1

    echo "  [4/4] Simpan hasil akhir..."
    mv "$tmp_dir/clean.pdf" "$out_file"
}
# --- Fungsi Compress ---
resize_pdf_hq() {
    local in_file="$1"
    local out_file="$2"
    local dpi="${3:-300}"
    gs -sDEVICE=pdfwrite \
       -dCompatibilityLevel=1.4 \
       -dNOPAUSE -dQUIET -dBATCH \
       -dDetectDuplicateImages=true \
       -dCompressFonts=true \
       -dSubsetFonts=true \
       -dColorImageDownsampleType=/Bicubic \
       -dColorImageResolution=$dpi \
       -dGrayImageDownsampleType=/Bicubic \
       -dGrayImageResolution=$dpi \
       -dMonoImageDownsampleType=/Subsample \
       -dMonoImageResolution=600 \
       -sOutputFile="$out_file" "$in_file" >/dev/null 2>&1
}

compress_keepdpi() {
    local in_file="$1"
    local out_file="$2"
    gs -sDEVICE=pdfwrite \
       -dCompatibilityLevel=1.4 \
       -dNOPAUSE -dQUIET -dBATCH \
       -dDetectDuplicateImages=true \
       -dCompressFonts=true \
       -dSubsetFonts=true \
       -dColorImageDownsampleType=/None \
       -dGrayImageDownsampleType=/None \
       -dMonoImageDownsampleType=/None \
       -dAutoFilterColorImages=false \
       -dAutoFilterGrayImages=false \
       -dColorImageFilter=/DCTEncode \
       -dGrayImageFilter=/DCTEncode \
       -dJPEGQ=85 \
       -sOutputFile="$out_file" "$in_file" >/dev/null 2>&1
}

compress_scan() {
    local in_file="$1"
    local out_file="$2"
    local dpi="${3:-200}"
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

        echo "  [3/3] Simpan hasil akhir..."
        mv "$tmp_pdf" "$out_file"

}

auto_size_limit() {
    local file="$1"
    local max_size="${2:-$DEFAULT_MAX_SIZE}"
    local dpi_start="${3:-300}"

    local size_bytes
    size_bytes=$(stat -c%s "$file")
    local size_limit_bytes
    size_limit_bytes=$(numfmt --from=iec "$max_size")

    local temp_pdf=$(mktemp /tmp/pdf_autosize.XXXXXX.pdf)
    local dpi=$dpi_start

    while (( size_bytes > size_limit_bytes && dpi > 72 )); do
        echo "  Ukuran saat ini: $(numfmt --to=iec $size_bytes), menurunkan resolusi ke $dpi dpi..."
        dpi=$(( dpi - 20 ))
        resize_pdf_hq "$file" "$temp_pdf" "$dpi"
        mv "$temp_pdf" "$file"
        size_bytes=$(stat -c%s "$file")
    done
}

check_tools(){
    local tools=("gs" "pdfid" "pdftoppm" "img2pdf")
    local missing=()

    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        echo "Error: Tool berikut tidak di temukan: ${missing[*]}"
        echo "Silahkan install tool yang tidak tersedia...."
        echo "  sudo apt install ghostscript poppler-utils img2pdf python3-pip"
        exit 1
    fi
}

# --- Parsing argumen ---
if [ $# -lt 3 ]; then
    echo "Usage:"
    echo "  $0 sanitize [normal|strong|ultra] <input.pdf> <output.pdf> [quality] [--max-size=10M]"
    echo "  $0 compress [auto|scan] <input.pdf> <output.pdf> [quality] [--max-size=10M]"
    exit 1
fi

MODE_MAIN="$1"

if [[ "$MODE_MAIN" == "sanitize" ]]; then
    if [[ "$2" == "normal" || "$2" == "strong" || "$2" ==  "ultra" ]]; then
        MODE_SUB="$2"
        INPUT="$3"
        OUTPUT="$4"
        QUALITY="${5:-$DEFAULT_QUALITY}"
        [[ "$6" == --max-size=* ]] && MAX_SIZE="${6#--max-size=}" || MAX_SIZE="$DEFAULT_MAX_SIZE"
    else
        MODE_SUB="$DEFAULT_SANITIZE_SUB"
        INPUT="$2"
        OUTPUT="$3"
        QUALITY="${4:-$DEFAULT_QUALITY}"
        [[ "$5" == --max-size=* ]] && MAX_SIZE="${5#--max-size=}" || MAX_SIZE="$DEFAULT_MAX_SIZE"
    fi
elif [[ "$MODE_MAIN" == "compress" ]]; then
    if [[ "$2" == "auto" || "$2" == "scan" ]]; then
        MODE_SUB="$2"
        INPUT="$3"
        OUTPUT="$4"
        QUALITY="${5:-$DEFAULT_QUALITY}"
        [[ "$6" == --max-size=* ]] && MAX_SIZE="${6#--max-size=}" || MAX_SIZE="$DEFAULT_MAX_SIZE"
    else
        MODE_SUB="$DEFAULT_COMPRESS_SUB"
        INPUT="$2"
        OUTPUT="$3"
        QUALITY="${4:-$DEFAULT_QUALITY}"
        [[ "$5" == --max-size=* ]] && MAX_SIZE="${5#--max-size=}" || MAX_SIZE="$DEFAULT_MAX_SIZE"
    fi
else
    echo "Error: Mode harus 'sanitize' atau 'compress'"
    exit 1
fi

# --- Validasi ---
check_tools

echo "[INFO] Mode: $MODE_MAIN | Submode: $MODE_SUB | Quality: $QUALITY | Max size: $MAX_SIZE"
echo "[INFO] Ukuran awal: $(numfmt --to=iec $(stat -c%s "$INPUT"))"

# --- Eksekusi ---
if [[ "$MODE_MAIN" == "sanitize" ]]; then
    case "$MODE_SUB" in
        normal) sanitize_normal "$INPUT" "$OUTPUT" ;;
        strong) sanitize_strong "$INPUT" "$OUTPUT" ;;
        ultra ) sanitize_ultra "$INPUT" "$OUTPUT" ;;
        *) echo "Error: Submode sanitize harus 'normal' atau 'strong'"; exit 1 ;;
    esac
elif [[ "$MODE_MAIN" == "compress" ]]; then
    case "$MODE_SUB" in
        auto) resize_pdf_hq "$INPUT" "$OUTPUT" 300; auto_size_limit "$OUTPUT" "$MAX_SIZE" 300 ;;
        scan) compress_scan "$INPUT" "$OUTPUT" 200 ;;
        *) echo "Error: Submode compress harus 'auto' atau 'scan'"; exit 1 ;;
    esac
fi
echo "[INFO] Remove metadata with ExifTool"
exiftool -all= -overwrite_original "$OUTPUT"
echo "[INFO] Ukuran akhir: $(numfmt --to=iec $(stat -c%s "$OUTPUT"))"
echo "[INFO] Mengecek hasil dengan pdfid..."
pdfid "$OUTPUT"
echo "✅ Selesai! File disimpan sebagai: $OUTPUT"