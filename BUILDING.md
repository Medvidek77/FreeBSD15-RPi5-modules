# Building and Installing the RPi5 Hardware Support Modules

This repository builds a set of FreeBSD/arm64 kernel modules for the
Raspberry Pi 5 (BCM2712 SoC + RP1 I/O controller). All modules are built
from a single top-level `Makefile`.

## Modules

| Module            | Purpose                                                        | Runtime depends on |
|-------------------|---------------------------------------------------------------|--------------------|
| `bcm2712`         | Common BCM2712 hardware: RP1 PWM controller, thermal sensor    | —                  |
| `rpi5`            | Pi 5 board support: cooling-fan thermal management            | `bcm2712`          |
| `rp1_eth`         | RP1 Gigabit Ethernet (Cadence GEM) NIC                        | `bcm2712_pcie`     |
| `bcm2712_pcie`    | BCM2712 PCIe2 / RP1 interrupt router                          | `acpi`             |
| `rp1_pcie2_recon` | RP1 PCIe2 reconnaissance / bring-up helper                    | —                  |
| `rp1_gpio`        | RP1 GPIO / pinctrl controller                                 | `gpiobus`          |
| `cyw43455`        | CYW43455 SDIO WiFi NIC                                        | `sdiob`, `wlan`, `firmware` |

Runtime dependencies are resolved automatically by `kldload` via
`MODULE_DEPEND` — e.g. loading `rpi5` pulls in `bcm2712`.

## Prerequisites

- **OS**: FreeBSD 15.0+ / 16.0-CURRENT on arm64 (aarch64)
- **Hardware**: Raspberry Pi 5
- **Kernel sources**: the full tree under `/usr/src` (the build reads
  `/usr/src/sys` for headers and generated kobj interface files). Verify:
  ```sh
  ls /usr/src/sys/conf/kmod.mk    # must exist
  ```
  If absent, install matching sources with `git`/`svnlite` or
  `freebsd-update`, or set `SYSDIR` to point at your kernel source tree.
- **Toolchain**: the base-system `clang` and `make` (bmake).

## Building

```sh
make                # build every module (default target)
make cyw43455       # build a single module
make clean          # remove all build artifacts
make help           # list all targets
```

Each module compiles through `bsd.kmod.mk`, so per-source header
dependencies (e.g. `bcm2712_var.h`, `rp1_eth_hw.h`) are tracked
automatically — editing a shared header rebuilds the affected modules on
the next `make`.

A successful `make` produces one `.ko` per module in the repository root
(`bcm2712.ko`, `rpi5.ko`, `rp1_eth.ko`, …).

## Installing and Loading

```sh
sudo make install       # install every module under /boot/modules
sudo make install-rpi5  # install a single module
sudo make load          # load the runtime module set
sudo make unload        # unload (in dependency-safe order)
make status             # show load state + sysctl interface
```

`make load` loads the runtime set (`bcm2712`, `rpi5`, `rp1_eth`,
`rp1_gpio`, `cyw43455`); `bcm2712_pcie` auto-loads as an `rp1_eth`
dependency. `make unload` tears down leaf-first so dependants release
before their providers.

### Auto-load at boot

Add to `/boot/loader.conf`:

```
rpi5_load="YES"        # auto-loads bcm2712
rp1_eth_load="YES"
rp1_gpio_load="YES"
cyw43455_load="YES"    # optional: WiFi (see firmware note below)
```

## cyw43455 Firmware

The `cyw43455.ko` does **not** embed firmware. The firmware binary, NVRAM,
and regulatory CLM blob are obtained at attach time through the FreeBSD
`firmware(9)` subsystem from `/boot/firmware/cyw43455/`, so the regulatory
blob can be swapped per-deployment without rebuilding the driver.

`make install-cyw43455` downloads the three firmware files from GitHub
(RPi-Distro/firmware-nonfree) and installs them into `/boot/firmware/cyw43455/`:

```
brcmfmac43455-sdio.bin        # firmware binary       (required)
brcmfmac43455-sdio.txt        # NVRAM config          (required)
brcmfmac43455-sdio.clm_blob   # regulatory CLM blob   (optional)
```

The download is handled by `tools/cyw43455_fw_fetch.sh`, which maps the
upstream Cypress names (`cypress/cyfmac43455-sdio-standard.bin`,
`cypress/cyfmac43455-sdio.clm_blob`) and the Pi NVRAM
(`brcm/brcmfmac43455-sdio.txt`) onto the `brcmfmac43455-sdio.*` names the
driver requests. Files are cached under `CYW43455_FW_CACHE` (default
`./fw`); already-present files are not re-fetched.

```bash
make fetch-cyw43455-fw                 # pre-stage the cache (no root needed)
sudo make install-cyw43455             # fetch (if needed) + install to /boot
```

Override the source release branch or a pre-populated cache directory, e.g.:

```bash
make fetch-cyw43455-fw CYW43455_FW_BRANCH=bookworm
sudo make install-cyw43455 CYW43455_FW_CACHE=/path/to/fw
```

When `cyw43455` is preloaded by the boot loader (loaded before the root
filesystem is mounted), the firmware images must be preloaded too. Add the
preload block to `/boot/loader.conf`:

```
cyw43455_load="YES"
brcm_fw_bin_load="YES"
brcm_fw_bin_name="/boot/firmware/cyw43455/brcmfmac43455-sdio.bin"
brcm_fw_bin_type="firmware"
brcm_fw_nvram_load="YES"
brcm_fw_nvram_name="/boot/firmware/cyw43455/brcmfmac43455-sdio.txt"
brcm_fw_nvram_type="firmware"
brcm_fw_clm_load="YES"
brcm_fw_clm_name="/boot/firmware/cyw43455/brcmfmac43455-sdio.clm_blob"
brcm_fw_clm_type="firmware"
```

See `cyw43455.4` and `doc/cyw43455.md` for the full firmware-delivery
rationale and the two delivery paths (kldload lazy-load vs loader preload).

## Testing

`make status` reports module load state and probes the
`hw.rpi5.fan.*` and `hw.rp1_eth.cfg.*` sysctl trees.

```sh
sysctl hw.rpi5.fan              # cooling-fan thermal state
sysctl hw.cyw43455              # WiFi driver state (chip id, fw version, MAC)
sysctl hw.rp1_eth.cfg           # Ethernet config-register decode
```

The shell-driven integration suite lives in `test/` and is reachable from
the top-level Makefile:

```sh
make test-suite     # full integration suite
make dev-test       # quick validation
make stress-test    # load/unload stress cycles
```

## Building Remotely (project workflow)

Per `CLAUDE.md`, this repository is developed on a non-FreeBSD host and
built/tested on the FreeBSD target `dunn`:

```sh
# edit locally, commit, then on dunn:
ssh dunn 'cd rpi5_modules.git && git reset --hard'   # clean the worktree
git push dunn <branch>
ssh dunn 'cd rpi5_modules.git && make'               # build over ssh
```

Low-level operations (firmware, loader, panic capture) use the UART
console; see `CLAUDE.md` and the `tools/` scripts.

## Troubleshooting

**`Unable to locate the kernel source tree. Set SYSDIR to override.`**
`/usr/src/sys` is missing or not mounted. Restore the kernel sources, or
build with `make SYSDIR=/path/to/sys`.

**`kldload: can't load <module>.ko: No such file or directory`**
Build/install first (`make && sudo make install`), or load by absolute
path: `kldload /boot/modules/<module>.ko`.

**`sysctl: unknown oid 'hw.rpi5.fan'`**
The module isn't loaded. Check `kldstat | grep rpi5`, inspect `dmesg` for
attach errors, and reload (`sudo make unload && sudo make load`).

**cyw43455 panics or fails to find firmware at boot**
Ensure the firmware files exist in `/boot/firmware/cyw43455/` and, for the
boot-preload path, that the `brcm_fw_*` preload block is present in
`/boot/loader.conf`. See `cyw43455.4` DIAGNOSTICS.

## References

- `INTEGRATION_GUIDE.md` — architecture and integration details
- `doc/` — per-driver debugging and development notes
- `cyw43455.4` — WiFi driver man page
- FreeBSD Architecture Handbook (kernel modules): <https://docs.freebsd.org/>
