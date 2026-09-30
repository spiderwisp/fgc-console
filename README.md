# FGC Console

The Framework Gaming Console operating system and home screen. Boot into FGC, browse reviewed games, install GitHub releases, and return to the library when a game closes. Deep Signal is included for offline play.

[Download FGC OS 0.2.0](https://github.com/spiderwisp/fgc-console/releases/tag/v0.2.0)

## Install FGC OS

FGC OS 0.2.0 is a hardware-preview release. USB boot, installation, automatic SSD boot, offline Deep Signal launch and return, display confirmation and rollback, and repair retaining the game and setup were verified in a QEMU virtual machine. Physical Framework Laptop 12 validation, Wi-Fi association, HDMI audio, and GPU performance still need hardware checks.

FGC OS uses Ubuntu 26.04 LTS with a dedicated console session. There is no desktop, browser, or terminal in the normal console interface. The image includes the Linux kernel, firmware, Mesa graphics drivers, audio, networking, FGC, and Deep Signal. Framework provides an [Ubuntu 26.04 guide for the original 13th Gen Intel Laptop 12](https://guides.frame.work/Guide/Ubuntu+26.04+Installation+on+the+Framework+Laptop+12/745?lang=en); the customized FGC image needs its own hardware verification.

1. Download `FGC-OS-0.2.0-amd64.iso` and `SHA256SUMS` from the release assets. The source ZIP is not a bootable image.
2. Flash the ISO onto a USB stick of at least 4 GB using balenaEtcher, or Rufus in DD mode. Flashing erases the selected USB stick.
3. Insert it into the powered-off console and turn it on. Use F12 to choose the USB drive if necessary.
4. Choose the internal SSD and confirm **Erase this SSD & install FGC**. That selected drive is erased; USB drives and mounted drives are excluded. Installation then runs automatically without Internet access.
5. Shut down using the installer, remove the USB stick, and turn the console on. Configure Wi-Fi, display, sound, and controller in FGC, or start playing offline.

The SSD must be at least 32 GiB. Installation creates a 512 MiB EFI partition, a 16 GiB system partition, and a separate data partition using the remaining space. Normal boots go directly to FGC. Settings provides network, audio, resolution, controller mapping, system updates, and power controls. Resolution changes revert automatically unless confirmed. Games keep their own graphics settings.

To recover an existing FGC installation, boot the USB installer, select its SSD, and choose **Repair FGC — keep games & saves**. Repair replaces the system partition and bootloader while retaining the separate data partition. Choosing a fresh installation instead erases the whole selected SSD.

## Standalone launcher

Windows: extract the release and open `FGCConsole.exe`. Linux: extract the release and open `FGCConsole.x86_64`. Godot and Docker are not required. Settings includes fullscreen, controller mapping, and catalog refresh. D-pad/arrows navigate, A/Enter selects, B/Escape goes back.

For Linux desktop startup, run `bash linux/install.sh` from the extracted release as your regular user. It installs FGC into your home directory and starts it after desktop login.

On an existing Linux installation using **LightDM and Openbox**, configure networking, audio, and your display first, then run `sudo bash linux/enable-console-mode.sh "$USER"` after installation. This enables automatic login to a dedicated FGC session. It does not replace the OS or display manager. `sudo bash linux/disable-console-mode.sh` reverses that setting. Use the FGC OS image for a complete fresh console installation.

## Add a game

Keep your game's code and downloads in your own public GitHub repository. This repository holds its listing in the FGC game catalog.

1. **Publish your game.** Upload a ready-to-play Linux x86_64 ZIP to your repository's GitHub Releases. Your game needs an open-source license, controller support, and a way to quit. A Windows build is optional.
2. **Add a listing.** Fork this repository to make your own copy. In [`catalog/games.json`](catalog/games.json), copy Deep Signal's entry and replace its details with yours. Add a cover image at `catalog/artwork/YOUR-ID.jpg`. Expand the checklist below for the download details and file requirements.
3. **Submit it for review.** Open a pull request with your listing and cover image. We check the game, license, controls, and download before approving it.

Once the pull request is merged into `main`, players can find your game by refreshing the catalog. Submit another pull request when you want to offer a new version.

<details>
<summary>Submission checklist: listing fields and ZIP requirements</summary>

**Your listing**

Replace Deep Signal's name, description, repository, tags, and version with your own. Choose a unique lowercase game ID using letters, numbers, and hyphens. Use that same ID for your JPEG cover filename; the image must be at most 2 MiB. Set `license` to your repository's SPDX license identifier, such as `MIT`, and keep `gamepad` set to `true`.

Each download needs these details so FGC can fetch and verify the correct file:

| Field | What to enter |
| --- | --- |
| `release` | The published GitHub release tag, such as `v1.0.0`. |
| `asset` | The exact ZIP filename attached to that release. |
| `size` | The ZIP's exact size in bytes. |
| `sha256` | The ZIP's SHA-256 checksum: a 64-character fingerprint used to verify the download. |
| `executable` | The path to the game's executable inside the ZIP, such as `MyGame/MyGame.x86_64`. |

Keep the `linux-x86_64` build. Remove `windows-x86_64` if you do not offer a Windows build. Change or remove `args` to suit your game. Remove `session_protocol` unless your game implements the optional restart support described under [Develop](#develop).

**Your ZIP**

- Maximum download size: 512 MiB. Maximum size after extraction: 1 GiB.
- Include the executable and the files it needs to run. Find game assets relative to the executable so the game works wherever FGC installs it.
- Use a native Linux executable (ELF), or a Windows executable (PE) for the optional Windows build. No installer scripts, administrator access, or compiling on the player's console.
- Include only regular files and folders. No symbolic links, special files, absolute paths, or paths containing `..`. Use portable ASCII filenames and paths.
- Include an open-source license that matches the listing and the license GitHub detects in your public, active repository.

The automated catalog check compares your download's size and checksum with GitHub's published release information. It does not replace the maintainer's review of the game.

</details>

FGC verifies downloads before extracting them and keeps the previous installation if an update fails. Installed games and the saved catalog work offline. Approved games run with the player's normal user permissions; catalog review does not sandbox them.

## Develop

Open `project.godot` with Godot 4.7.2. Export presets produce standalone Windows and Linux builds. `python tools/validate_catalog.py --online` checks the catalog without building or running submitted game code.

To build the installer, export the Linux launcher, download the pinned Deep Signal Linux ZIP from the catalog, and run `bash os/build.sh /path/to/FGCConsole.x86_64 /path/to/DeepSignal-Linux.zip /path/to/output`. On Windows, use `os/build.ps1 -ConsoleBinary PATH -GameZip PATH -Output PATH`. Building requires Docker with Linux containers, Internet access for Ubuntu packages, and approximately 20 GiB of free working space. Players do not need Docker. The builder verifies the bundled game against its catalog SHA-256 and writes the ISO and checksum file.

Any engine can supply a compatible native package. Games that restart themselves can opt into `session_protocol: "fgc-v1"`: FGC appends `-- --fgc-session=ABSOLUTE_PATH`. Write JSON containing `pid`, `state` (`running`, `restarting`, or `exited`), and Unix `time` to that file once per second. Preserve the argument across restarts. Games without this option must keep their launched process alive until play ends.
