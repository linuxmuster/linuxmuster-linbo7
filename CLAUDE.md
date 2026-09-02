# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

linuxmuster-linbo7 is a free and open-source Linux-based network boot (LINBO) imaging solution for linuxmuster.net 7. It provides a complete system for managing client computers via PXE boot, handling Windows 10 and Linux 64-bit operating systems with features like differential imaging, qcow2 image format, and remote management capabilities.

**Key Components:**
- **src/linbofs**: The client-side boot filesystem (initramfs) that runs on PXE-booted clients
- **src/serverfs**: Server-side scripts and configuration files
- **src/linbo-splash**: The plymouth boot splash theme
- **build**: Build system that harvests the stock Ubuntu kernel/modules and prebuilt host binaries and assembles them into the linbofs package (no component is compiled from source anymore, see [Build Environment](#build-environment))
- **debian**: Debian packaging files (changelog, control, rules, etc.)
- **.github**: GitHub Actions workflows and configuration
- **cache**: Build cache directory (harvested kernel/modules, dev reference files)
- **tmp**: Temporary build files

### Key Features

- **Stock Ubuntu Kernel**: Uses the stock Ubuntu 26.04 kernel (currently 7.0.x), harvested directly from the build host rather than compiled in-tree
- **qcow2 Image Format**: Modern image format with compression and sparse file support
- **Differential Images**: Incremental images using qcow2 backing stores (`.qdiff` extension)
- **Complete linbo_cmd Refactoring**: Modular command structure (57 scripts in `src/linbofs/usr/bin/`: 56 `linbo_*` commands plus `gui_ctl`)
- **NTFS3 Driver**: Native kernel driver enables file-level sync for Windows partitions
- **WiFi Support**: Built-in wpa_supplicant for wireless network connections
- **Image Distribution**: Multiple methods - rsync, multicast (udpcast), or BitTorrent
- **Remote Management**: SSH-based control via linbo-remote with tmux sessions
- **Nogui Mode**: Text-based console menu for resource-constrained scenarios
- **Custom Firmware Integration**: Easy firmware addition via configuration file

### Migration from linuxmuster.net 7.3

To upgrade from 7.3 to 7.4: perform a distribution upgrade of the server from Ubuntu 24.04 to 26.04 using `linuxmuster-release-upgrade`. See the [README's Migration section](README.md#migration-from-linuxmusternet-73) for the current, authoritative steps — don't duplicate them here, they change with every release line.

## Build Commands

### Initial Setup
```bash
# Install all build dependencies (uses sudo)
./get-depends.sh

# Build the Debian package
./buildpackage.sh
```

The build output will be placed in the parent directory (`..`), and a build log is created at `../build.log`.

For better convenience, use the [lmndev-runner](https://github.com/linuxmuster/lmndev-runner) environment instead of building directly on your system.

### Build Artifacts
- The package is built using `dpkg-buildpackage`
- Build scripts are located in `build/run.d/` and are numbered to control execution order:
  - `0_linbofs-root`: Creates the linbofs root directory tree, copies `src/linbofs`, sets the version banner
  - `1_linbofs-links`: Creates the symlinks required inside linbofs
  - `2_linbofs-plymouth`: Installs the plymouth boot splash
  - `3_linbofs-apps`: Pulls prebuilt binaries listed in `build/config/linbofs.apps` from the Ubuntu build host into linbofs, resolving their shared library dependencies via `ldd`
  - `4_linbofs-busybox`: Symlinks busybox's applets (busybox itself was already copied by `3_linbofs-apps`) — no compilation involved
  - `5_linbofs-archive`: Packs the assembled linbofs tree into the final archive
  - `6_kernel-modules`: Runs `build/bin/kernel-harvester.sh` to copy the kernel image and the modules listed under `build/config/modules.d/` out of the Ubuntu build environment, then archives them
  - `7_serverfs`: Copies `src/serverfs` into the server package

## Architecture

### Client-Server Communication Flow

1. **Boot Process**: Client PXE boots → downloads linbofs via TFTP → boots into LINBO environment
2. **Configuration**: Client reads `start.conf` from server (defines partitions, OS images, boot options)
3. **Remote Management**: Server uses `linbo-remote` to execute commands on clients via SSH
4. **Image Distribution**: Images can be distributed via rsync, multicast (udpcast), or BitTorrent

### Image Management System

LINBO uses **qcow2 format with differential imaging**:
- **Base Image**: `image.qcow2` - full system image
- **Differential Image**: `image.qdiff` - incremental changes based on base image
- Differential images use qcow2's backing store feature
- Images are mounted via `qemu-nbd` for file-level operations
- Both Linux (ext4) and Windows (ntfs3 driver) are supported

### Client Filesystem (linbofs)

The client environment is a minimal initramfs with:
- **Init System**: Custom init script (`src/linbofs/init.sh`) using busybox
- **Shell Environment**: Complete environment with variables like `$LINBOSERVER`, `$IP`, `$HOSTNAME`, etc.
- **Command Suite**: 57 commands (56 `linbo_*` plus `gui_ctl`) in `/usr/bin/` for all operations
- **Configuration Parsing**: `start.conf` is split into parseable chunks in `/conf/` (e.g., `/conf/linbo`, `/conf/os.1`, `/conf/part.1.sda1`)
- **Helper Scripts**: `linbo.sh` for common functions, `.profile` for shell initialization

Key client commands:
- `linbo_cmd`: Legacy wrapper for GUI compatibility
- `linbo_create_image`: Create base or differential images
- `linbo_sync`: Synchronize OS from image
- `linbo_start`: Start an installed OS
- `linbo_partition_format`: Partition and format disks
- `linbo_initcache`: Initialize local cache with images

### Server Management Tools

Located in `src/serverfs/usr/sbin/`:
- **`linbo-remote`**: Execute commands on clients via SSH (uses tmux for background jobs)
- **`linbo-torrent`**: Manage BitTorrent distribution of images
- **`linbo-multicast`**: Manage multicast distribution sessions
- **`update-linbofs`**: Rebuild linbofs with customizations (firmware, kernel, scripts)

### Configuration System

**start.conf format**: INI-style configuration with sections:
- `[LINBO]`: Global settings (server, cache partition, download type, GUI options)
- `[Partition]`: Partition definitions (device, size, filesystem, bootable flag)
- `[OS]`: Operating system definitions (name, image file, kernel, autostart behavior)

Example configurations are in `src/serverfs/srv/linbo/examples/start.conf.*`

## Development Patterns

### Adding Custom Boot Scripts

1. Create your script, e.g. under `/root/linbofs/mybootscript.sh`
2. Create a pre-hook in `/var/lib/linuxmuster/hooks/update-linbofs.pre.d/` to copy it:
   ```bash
   #!/bin/bash
   echo "### copy mybootscript.sh ###"
   cp /root/linbofs/mybootscript.sh usr/bin
   ```
3. Add to `/etc/linuxmuster/linbo/inittab`:
   ```
   ::wait:/usr/bin/mybootscript.sh
   ```
4. Run `update-linbofs` to apply changes

### Integrating Custom Kernels

There are no more bundled kernel variants to pick from — Linbo harvests a single stock Ubuntu kernel at build time. To use a different kernel, edit `/etc/linuxmuster/linbo/custom_kernel` (see `src/serverfs/etc/linuxmuster/linbo/custom_kernel.ex`):
```bash
# path to kernel image
KERNELPATH="/path/to/my/kernelimage"
# path to the corresponding modules directory
MODULESPATH="/path/to/my/lib/modules/n.n.n"
```

Then run `update-linbofs`.

### Adding Firmware

Edit `/etc/linuxmuster/linbo/firmware`:
```
# Whole directory
rtl_nic

# Single file
iwlwifi-cc-a0-77.ucode
```

Paths are relative to `/lib/firmware`. Run `update-linbofs` to apply.

### WiFi Support

Configure `/etc/linuxmuster/linbo/wpa_supplicant.conf`:
```
network={
  ssid="NETWORK_NAME"
  scan_ssid=1
  key_mgmt=WPA-PSK
  psk="passphrase"
}
```

Run `update-linbofs` and add WiFi MAC address to `devices.csv`.

## Important Technical Details

### Session Management
- Background jobs use **tmux** (not screen)
- Detach tmux sessions with `[CTRL+B]+[D]`
- The `linbo-remote` script can attach to client sessions with `-a <hostname>`

### Security
- Server's root SSH public key is embedded in linbofs for passwordless SSH
- LINBO password hash (from `/etc/rsyncd.secrets`) is integrated into linbofs
- Clients establish SSH connections back to server for remote operations

### GUI Modes
- **Full GUI**: Default graphical interface (linuxmuster-linbo-gui7)
- **nogui mode**: Text-based console menu (kernel parameter `nogui`)
- **nomenu mode**: Remote-only mode, no console menu (kernel parameters `nogui nomenu`)

### Kernel Parameters
A few important ones for troubleshooting (see the [README's full table](README.md#linbo-kernel-parameters) for all of them):
- `debug`: Boot into debug shell
- `forcegrub`: Force GRUB boot for UEFI systems
- `restoremode=dd|ooo`: Control qemu-img writing performance
- `vncserver`: Start VNC server on port 9999 (accessible from server)
- `linbocmd=cmd1,cmd2,...`: Execute commands during boot

## File Locations

### On Server (when installed)
- Configuration: `/etc/linuxmuster/linbo/`
- Images: `/srv/linbo/`
- LINBO files: `/srv/linbo/` (linbofs, kernel, grub)
- Scripts: `/usr/share/linuxmuster/linbo/`
- Logs: `/var/log/linuxmuster/linbo/`
- Hooks: `/var/lib/linuxmuster/hooks/update-linbofs.{pre,post}.d/`

### In Repository
- Client filesystem: `src/linbofs/` (installed to initramfs)
- Server files: `src/serverfs/` (installed to root filesystem)
- Build configuration: `build/config/`
- Build scripts: `build/run.d/`

## Testing and Debugging

### Shell test harness
Unit tests for individual functions inside `src/linbofs/usr/bin/` scripts, using shunit2, run under both `dash` and `busybox ash` (see `tests/shell/README.md`):
```sh
sh tests/shell/run.sh            # against dash / whatever /bin/sh is
busybox ash tests/shell/run.sh   # against busybox ash
```
CI runs these via `.github/workflows/shell-tests.yml`.

### Python test harness
Unit tests (pytest) for the pure-function parts of the `linbo-remote` Python rewrite (issue [#169](https://github.com/linuxmuster/linuxmuster-linbo7/issues/169), branch `linbo-remote-refactor`), currently `linbo_remote_lib.py`'s command-string parser and host resolution (see `tests/python/README.md`):
```sh
pytest tests/python
```
CI runs these via `.github/workflows/python-tests.yml`.

### Python Naming Convention
Same org-wide convention as `linuxmuster-base7`: **snake_case for variables, camelCase for functions** (e.g. `parseCommandString()`, `getGroupRoomDevices()`), including private/underscore-prefixed helpers (e.g. `_extractNr()`). Class names stay PascalCase. This applies even though it isn't PEP 8 - don't default to plain snake_case functions just because this repo historically had little Python.

### Client Debug Mode
Boot with `debug` kernel parameter to get a shell before GUI starts. Environment variables are available in `/.env`.

### Checking Firmware Issues
On a LINBO client:
```bash
dmesg | grep firmware
```

### Monitoring Remote Operations
```bash
# List running sessions
linbo-remote -l

# Attach to a client session
linbo-remote -a <hostname>

# View torrent sessions
linbo-torrent status
linbo-torrent attach <image_name>

# Monitor multicast logs
tail -f /var/log/linuxmuster/linbo/<image>_mcast.log
```

## Version Information

Version format: `X.Y.Z` (e.g., `7.4.11`) — no build-suffix in the current scheme.

- Version and release codename are read from `debian/changelog` (version) and `debian/releasename` (codename) at build time and baked into `src/linbofs/etc/linbo-version`; don't hardcode either here, check those two files for the current values.
- Current development targets linuxmuster.net 7.4 (Ubuntu 26.04 server), on the `7.4` branch
- Uses the stock Ubuntu 26.04 kernel, harvested at build time rather than compiled — see [Build Environment](#build-environment)
- Package published in the [lmn74 repository](https://github.com/linuxmuster/deb)

For the current changelog, read `debian/changelog` directly — don't duplicate a "recent changes" snapshot here, it goes stale immediately.

## Build Environment

### Source Tree Structure

```text
linuxmuster-linbo7/
├── build/                  # Build system components
│   ├── bin/                # Helper scripts (kernel-harvester.sh, reset-root.sh)
│   ├── config/              # Build config: build.env, serverfs.env, linbofs.apps, modules.d/
│   └── run.d/               # Numbered build scripts (0-7), see Build Artifacts above
├── debian/                 # Debian packaging files
│   └── changelog           # Version history and release notes
├── src/
│   ├── linbofs/             # Client initramfs filesystem
│   │   ├── .env             # Environment variable definitions
│   │   ├── .profile         # Shell profile for client environment
│   │   ├── init.sh          # Main init script (busybox-based)
│   │   ├── linbo.sh         # Common linbo functions
│   │   ├── etc/              # Configuration files
│   │   │   └── linbo-version # Version identifier (generated at build time)
│   │   └── usr/bin/          # linbo_* command scripts + gui_ctl
│   ├── linbo-splash/         # Plymouth boot splash theme
│   └── serverfs/             # Server-side files
│       ├── etc/               # Server configuration files
│       ├── srv/linbo/         # LINBO server data (icons, examples)
│       └── usr/sbin/          # Server management tools
├── cache/                  # Build cache (harvested kernel/modules, dev reference files)
├── tmp/                    # Temporary build files
├── docs/                   # Additional documentation
├── tests/shell/            # Shell test harness (shunit2)
├── .github/                # GitHub Actions workflows
├── buildpackage.sh         # Main build script
├── get-depends.sh          # Dependency installation script
└── README.md               # Main documentation
```

### Build Process Details

The build system no longer compiles anything from source. It harvests a prebuilt kernel and prebuilt host binaries from the Ubuntu 26.04 build environment and assembles them, in order, via `build/run.d/0` through `7` (see Build Artifacts above), then uses `dpkg-buildpackage` to create the `.deb` package.

`build/config/linbofs.apps` lists the host binaries/directories pulled into linbofs (with their shared library dependencies resolved automatically). `build/config/modules.d/` lists the kernel modules to harvest, split per subsystem — this is a manually curated subset of everything Ubuntu ships for that kernel, not the full module tree; keep that in mind when diagnosing hardware issues that could be a missing-module gap.

### Development Environment Setup

For Ubuntu 26.04:

```bash
# Install dpkg development tools
sudo apt install dpkg-dev

# Install all build dependencies
./get-depends.sh

# Build the package
./buildpackage.sh
```

**Recommended**: Use [lmndev-runner](https://github.com/linuxmuster/lmndev-runner) for isolated, reproducible builds.
