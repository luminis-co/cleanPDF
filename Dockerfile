FROM parrotsec/security:6

RUN apt-get update && apt-get install -y \
    ghostscript \
    poppler-utils \
    img2pdf \
    exiftool \
    ocrmypdf \
    coreutils \
    pdfid \
    && rm -rf /var/lib/apt/lists/*

# Tambah user sandbox
RUN useradd -ms /bin/bash sandbox

# Copy script dulu (sebagai root), lalu kasih izin eksekusi
COPY cleanpdf.sh /usr/local/bin/cleanpdf.sh
RUN chmod +x /usr/local/bin/cleanpdf.sh

# Baru switch user
USER sandbox
WORKDIR /app

ENTRYPOINT ["/usr/local/bin/cleanpdf.sh"]
FROM parrotsec/security:6

RUN apt-get update && apt-get install -y \
    ghostscript \
    poppler-utils \
    img2pdf \
    exiftool \
    ocrmypdf \
    coreutils \
    pdfid \
    && rm -rf /var/lib/apt/lists/*

    # Tambah user sandbox
RUN useradd -ms /bin/bash sandbox
# Set working directory

WORKDIR /app

# Copy script PDF cleaner ke dalam container
COPY cleanpdf.sh /usr/local/bin/cleanpdf.sh
RUN chmod 755 /usr/local/bin/cleanpdf.sh && chown sandbox:sandbox /usr/local/bin/cleanpdf.sh

# Jalankan sebagai user non-root
USER sandbox

# Default command
ENTRYPOINT ["cleanpdf.sh"]
