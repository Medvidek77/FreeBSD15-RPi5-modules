#!/bin/sh
# tools/cyw43455_fw_fetch.sh — download CYW43455 firmware from GitHub
#
# Fetches the three images the cyw43455 driver loads via firmware(9) from
# /boot/firmware/cyw43455/:
#
#   brcmfmac43455-sdio.bin       — ARM firmware binary (required)
#   brcmfmac43455-sdio.txt       — NVRAM configuration  (required)
#   brcmfmac43455-sdio.clm_blob  — regulatory CLM blob  (optional)
#
# The files are NOT embedded in the .ko; `make install-cyw43455` calls this
# script to populate them, or run it standalone to pre-stage a cache.
#
# Source: RPi-Distro/firmware-nonfree (Debian firmware-brcm80211 packaging).
# That repo now stores the Cypress binary and CLM blob under cypress/ with
# "cyfmac" names (the binary split into -minimal/-standard variants) and the
# Raspberry Pi NVRAM under brcm/.  We download them under the brcmfmac*-sdio.*
# names the driver requests; the -standard binary is the full-feature build.
#
# Usage:
#   sh tools/cyw43455_fw_fetch.sh [output-dir]        # default output: .
#   CYW43455_FW_BRANCH=bookworm sh tools/cyw43455_fw_fetch.sh ./fw
#   CYW43455_FW_FORCE=1 sh tools/cyw43455_fw_fetch.sh ./fw   # re-download

set -e

BRANCH="${CYW43455_FW_BRANCH:-bookworm}"
BASE_URL="${CYW43455_FW_URL:-https://raw.githubusercontent.com/RPi-Distro/firmware-nonfree/${BRANCH}/debian/config/brcm80211}"
OUTDIR="${1:-.}"
FETCH="${FETCH:-fetch -q}"

# "<install-name> <repo-relative source path>"
MAP="brcmfmac43455-sdio.bin cypress/cyfmac43455-sdio-standard.bin
brcmfmac43455-sdio.txt brcm/brcmfmac43455-sdio.txt
brcmfmac43455-sdio.clm_blob cypress/cyfmac43455-sdio.clm_blob"

mkdir -p "$OUTDIR"

echo "$MAP" | while read dst src; do
	[ -n "$dst" ] || continue
	if [ -f "$OUTDIR/$dst" ] && [ -z "$CYW43455_FW_FORCE" ]; then
		echo "  $dst: cached ($(wc -c < "$OUTDIR/$dst" | tr -d ' ') bytes)"
		continue
	fi
	echo "Fetching $dst <- $src"
	$FETCH -o "$OUTDIR/$dst" "$BASE_URL/$src"
	echo "  $dst: $(wc -c < "$OUTDIR/$dst" | tr -d ' ') bytes"
done

echo "Done. Install with: sudo make install-cyw43455"
