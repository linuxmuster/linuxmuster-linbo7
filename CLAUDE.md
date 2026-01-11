# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

linuxmuster-linbo7 is a free and open-source Linux-based network boot (LINBO) imaging solution for linuxmuster.net 7. It provides a complete system for managing client computers via PXE boot, handling Windows 10 and Linux 64-bit operating systems with features like differential imaging, qcow2 image format, and remote management capabilities.

**Key Components:**
- **linbofs**: The client-side boot filesystem (initramfs) that runs on PXE-booted clients
- **serverfs**: Server-side scripts and configuration files
- **build**: Build system for compiling kernels and creating the package
- **src**: Source code for third-party components (busybox, kexec, opentracker, chntpw, pv, etc.)
- **debian**: Debian packaging files (changelog, control, rules, etc.)
- **.github**: GitHub Actions workflows and configuration
- **cache**: Build cache directory
- **tmp**: Temporary build files

**Important Note:** The code in this repository is not yet for production use. The stable version is in the [4.0 branch](https://github.com/linuxmuster/linuxmuster-linbo7/tree/4.0).

### Key Features

- **Multiple Kernel Versions**: 6.1.\* (legacy), 6.12.\* (longterm), and 6.18.\* (stable) kernels available
- **qcow2 Image Format**: Modern image format with compression and sparse file support
- **Differential Images**: Incremental images using qcow2 backing stores (`.qdiff` extension)
- **Complete linbo_cmd Refactoring**: Modular command structure with 54 individual scripts
- **NTFS3 Driver**: Native kernel driver enables file-level sync for Windows partitions
- **WiFi Support**: Built-in wpa_supplicant for wireless network connections
- **Image Distribution**: Multiple methods - rsync, multicast (udpcast), or BitTorrent
- **Remote Management**: SSH-based control via linbo-remote with tmux sessions
- **Nogui Mode**: Text-based console menu for resource-constrained scenarios
- **Custom Firmware Integration**: Easy firmware addition via configuration file

### Migration from linuxmuster.net 7.1

To upgrade from 7.1 to 7.2/7.3:

1. Perform two-step Ubuntu upgrade: 18.04 → 20.04 → 22.04 using `do-release-upgrade`
2. Reconfigure linuxmuster packages: `dpkg-reconfigure sophomorix-samba linuxmuster-base7 linuxmuster-webui7`
3. Reactivate lmn71 repo: `/etc/apt/sources-list.d/lmn71.list.distUpgrade`
4. Add lmn72 repo according to [setup instructions](https://github.com/linuxmuster/deb/blob/main/README.md#setup)
5. Perform dist-upgrade

## Build Commands

### Initial Setup
```bash
# Install all build dependencies (uses sudo)
./get-depends.sh

# Build the Debian package
./buildpackage.sh
```

The build output will be placed in the parent directory (`..`), and a build log is created at `../build.log`.

For better convenience, use the [linbo-build-docker](https://github.com/linuxmuster/linbo-build-docker) environment instead of building directly on your system.

### Build Artifacts
- The package is built using `dpkg-buildpackage`
- Build scripts are located in `build/run.d/` and are numbered to control execution order:
  - `0_busybox`: Builds busybox (version 1.37.0)
  - `1_kernels`: Compiles kernel versions (6.1.*, 6.12.*, 6.18.*)
  - `2a_r8168`, `2b_r8812`, `2c_r8125`: Network driver modules
  - `2z_archive-modules`: Archives kernel modules
  - `3_serverfs`: Prepares server filesystem
  - `4_opentracker`: Builds opentracker for BitTorrent distribution
  - `5_kexec`: Builds kexec-tools for kernel loading
  - `6_chntpw`: Builds chntpw for Windows password reset
  - `7_pv`: Builds pipe viewer utility
  - `99_linbofs`: Creates the final linbofs initramfs

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
- **Init System**: Custom init script (`linbofs/init.sh`) using busybox
- **Shell Environment**: Complete environment with variables like `$LINBOSERVER`, `$IP`, `$HOSTNAME`, etc.
- **Command Suite**: 54 `linbo_*` and utility commands in `/usr/bin/` for all operations
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

Located in `serverfs/usr/sbin/`:
- **`linbo-remote`**: Execute commands on clients via SSH (uses tmux for background jobs)
- **`linbo-torrent`**: Manage BitTorrent distribution of images
- **`linbo-multicast`**: Manage multicast distribution sessions
- **`linbo-cloop2qcow2`**: Convert legacy cloop images to qcow2 format
- **`update-linbofs`**: Rebuild linbofs with customizations (firmware, kernel, scripts)

### Configuration System

**start.conf format**: INI-style configuration with sections:
- `[LINBO]`: Global settings (server, cache partition, download type, GUI options)
- `[Partition]`: Partition definitions (device, size, filesystem, bootable flag)
- `[OS]`: Operating system definitions (name, image file, kernel, autostart behavior)

Example configurations are in `serverfs/srv/linbo/examples/start.conf.*`

## Development Patterns

### Adding Custom Boot Scripts

1. Create your script in `/root/linbofs/mybootscript.sh`
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

Edit `/etc/linuxmuster/linbo/custom_kernel`:
```bash
# Use Linbo's alternative kernels
KERNELPATH="legacy"    # for 6.1.159 kernel (longterm support)
KERNELPATH="longterm"  # for 6.12.64 kernel
KERNELPATH="stable"    # for 6.18.* kernel (current stable)

# Or use custom kernel
KERNELPATH="/path/to/vmlinuz"
MODULESPATH="/path/to/lib/modules/x.x.x"
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
Important parameters for troubleshooting:
- `debug`: Boot into debug shell
- `forcegrub`: Force GRUB boot for UEFI systems
- `restoremode=dd|ooo`: Control qemu-img writing performance
- `vncserver`: Start VNC server on port 9999 (accessible from server)
- `linbocmd=cmd1,cmd2,...`: Execute commands during boot

## File Locations

### On Server (when installed)
- Configuration: `/etc/linuxmuster/linbo/`
- Images: `/srv/linbo/`
- LINBO files: `/srv/linbo/` (linbofs, kernels, grub)
- Scripts: `/usr/share/linuxmuster/linbo/`
- Logs: `/var/log/linuxmuster/linbo/`
- Hooks: `/var/lib/linuxmuster/hooks/update-linbofs.{pre,post}.d/`

### In Repository
- Client filesystem: `linbofs/` (installed to initramfs)
- Server files: `serverfs/` (installed to root filesystem)
- Build configuration: `build/conf.d/`, `build/config/`
- Build scripts: `build/run.d/`

## Testing and Debugging

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

Version format: `X.Y.Z-N` (e.g., 4.3.30-0)

- **Current Version**: 4.3.30-0 "Psycho Killer"
- Version stored in `debian/changelog` and `linbofs/etc/linbo-version`
- Current development targets linuxmuster.net 7.3 (Ubuntu 22.04 server)
- Supports multiple kernel versions simultaneously:
  - **Legacy**: 6.1.159 (longterm support)
  - **Longterm**: 6.12.64
  - **Stable**: 6.18.* (current stable)
- Package published in the [lmn73 testing repository](https://github.com/linuxmuster/deb)

### Recent Changes (4.3.30-0)

- Added Dell x86 platform drivers to stable kernel config
- Switched to stable kernel version 6.18.*
- Made number of kernel build jobs configurable via `DISTCC_JOBS` environment variable
- Added IOMMU feature to stable kernel config for Dell Pro 16 laptop support
- Updated longterm kernel to 6.12.64
- Updated legacy kernel to 6.1.159
- Added zstd to package dependencies
- Improved firmware handling in update-linbofs

## Build Environment

### Source Tree Structure

```text
linbo73-src/
├── build/                  # Build system components
│   ├── bin/               # Helper scripts (kernel archive retrieval, etc.)
│   ├── conf.d/            # Environment variables for build components
│   ├── config/            # Configuration files (busybox, kernel configs)
│   ├── initramfs.d/       # Initramfs configurations from Ubuntu build system
│   ├── patches/           # Source patches (r8125, r8168 drivers)
│   └── run.d/             # Numbered build scripts (0-99)
├── debian/                # Debian packaging files
│   └── changelog          # Version history and release notes
├── linbofs/               # Client initramfs filesystem
│   ├── .env               # Environment variable definitions
│   ├── .profile           # Shell profile for client environment
│   ├── init.sh            # Main init script (busybox-based)
│   ├── linbo.sh           # Common linbo functions
│   ├── etc/               # Configuration files
│   │   └── linbo-version  # Version identifier
│   └── usr/bin/           # 54 linbo_* command scripts
├── serverfs/              # Server-side files
│   ├── etc/               # Server configuration files
│   ├── srv/linbo/         # LINBO server data (icons, examples)
│   ├── usr/sbin/          # Server management tools (5 scripts)
│   └── var/               # Variable data directories
├── src/                   # Third-party source code
│   ├── busybox-1.37.0/    # Busybox utilities
│   ├── chntpw/            # Windows password reset tool
│   ├── kexec-tools/       # Kernel execution tools
│   ├── legacy/            # 6.1.159 kernel build
│   ├── longterm/          # 6.12.64 kernel build
│   ├── stable/            # 6.18.* kernel build
│   ├── opentracker/       # BitTorrent tracker
│   └── pv/                # Pipe viewer utility
├── cache/                 # Build cache directory
├── tmp/                   # Temporary build files
├── .github/               # GitHub Actions workflows
├── buildpackage.sh        # Main build script
├── get-depends.sh         # Dependency installation script
├── get-pkg.sh             # Package retrieval script
└── README.md              # Main documentation
```

### Build Process Details

The build system is modular and executes scripts in numerical order from `build/run.d/`:

1. **Component Compilation** (0-7): Each script builds a specific component
2. **Final Assembly** (99): Creates the complete linbofs initramfs
3. **Package Creation**: Uses dpkg-buildpackage to create .deb package

Configuration files in `build/config/` define compilation options for kernels and busybox. The `build/conf.d/` directory contains environment variables sourced during the build process.

### Development Environment Setup

For Ubuntu 22.04:

```bash
# Install dpkg development tools
sudo apt install dpkg-dev

# Install all build dependencies
./get-depends.sh

# Build the package
./buildpackage.sh
```

**Recommended**: Use [linbo-build-docker](https://github.com/linuxmuster/linbo-build-docker) for isolated, reproducible builds.
