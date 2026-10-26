# Brother DCP-T220 community driver for macOS

Print from **Word, Excel, Preview and other Mac apps** using Command-P, without exporting each document to Brother iPrint&Scan.

**[Download the installer and DMG](https://github.com/mksnextofficial/brother-dcp-t220-macos/releases/latest)** · [Report a problem](https://github.com/mksnextofficial/brother-dcp-t220-macos/issues)

Independent GPL-2.0 software, based on [zama-tui/brother-pwg-macos](https://github.com/zama-tui/brother-pwg-macos). Not affiliated with or supported by Brother. The original authors implemented the printer protocol; this distribution adds a graphical installer, DMG, clearer quality labels and release documentation.

## Install — no Terminal required

1. Download the `.dmg` from Releases and open it.
2. Connect your **Brother DCP-T220** by USB and turn it on.
3. Open the `.pkg` inside. Follow **Continue → Agree → Install** and authenticate with your Mac administrator account.
4. In your app, press **Command-P** and select **Brother DCP-T220 PWG / Brother_PWG**.

The `.pkg` can also be downloaded directly. Dragging a file into Applications cannot install a system printer filter, so this uses Apple's standard Installer.

**Version 1.0.0 is unsigned and not notarized.** If macOS blocks it, inspect the source/checksums and, if you trust this release, use **System Settings → Privacy & Security → Open Anyway** for this installer. Follow [Apple's instructions](https://support.apple.com/102445). Do not disable Gatekeeper. A Developer ID Installer certificate and Apple notarization are needed for a future signed release.

The installer does not print anything automatically or change your default printer. It preserves unrelated queues and updates its own matching queue in place.

### Printer not connected during installation

The driver still installs. Later, connect the printer and open **System Settings → Printers & Scanners → Add Printer**. Select the USB DCP-T220. Under **Use → Select Software**, search for **Brother DCP-T220 PWG**. If necessary, choose **Other** and select:

```
/Library/Printers/BrotherPWG/brother-pwg.ppd
```

The graphical package intentionally sets up only DCP-T220. Other models require separate validation; the upstream CLI has experimental generic profiles.

## Compatibility and evidence

| Item | Status |
|---|---|
| Brother DCP-T220 over USB | User confirmed a physical print on 26 October 2026 |
| macOS 27.0.1, Apple Silicon | Native PDF-to-PWG conversion and installed driver tested |
| Graphical package | Built and structurally validated; see release notes for actual GUI-install coverage |
| macOS 27 or later | Installer allows it; only 27.0.1 tested, future versions not guaranteed |
| Intel Macs | No architecture-specific driver binary; not hardware tested |
| Earlier macOS | Graphical installer requires 27; older versions not qualified here |
| Windows / iPhone / iPad | Not supported; macOS is different from iOS |
| Scanning, network AirPrint service, ink-level monitoring | Not provided |
| Advanced photo and borderless output | Upstream options retained; not locally validated |

A printed page confirms the basic path, not every paper size, application, quality mode or ink-saving claim. The tested printer's serial number and private documents are not included in this repository.

## Quality selection

Open the full print dialog, select this printer and look under **Printer Features → Print Quality**. Some applications arrange the controls differently. Save your preferred choice using the print dialog's **Presets** menu.

| Displayed option | Raster resolution | Printer command | Intended use |
|---|---:|---|---|
| EcoMode (Draft) | 300 dpi | `DRAFT` | Fast draft documents |
| Normal | 600 dpi | `NORMAL` | Everyday documents; default |
| Fine (Best) | 600 dpi | `HIGH` | Higher-quality rendering of text and graphics |
| Photo | 1200 dpi | `HIGH` | Optional; no local evidence of better output |

**EcoMode is a label for Draft, not a verified implementation of Brother's proprietary economy mode.** Normal and Fine send the same raster resolution but request different printer rendering modes. Exact ink use, pass counts and speed differences have not been measured. The internal option names remain `Draft`, `Normal`, `Best`, `Photo` for compatibility.

## Reinstall after resetting or moving to another Mac

Keep the DMG, or download the same tagged release again. Install on the new Mac and connect its printer; there is no hard-coded personal printer serial number. If `Brother_PWG` belongs to a different device, the installer preserves it and asks you to add the new device manually. Do not copy only the PPD; the matching filter is also required.

## Troubleshooting

- **No printer:** check USB cable, hub and power; use the manual Add Printer steps above.
- **No quality control:** confirm you selected this driver, then expand/scroll the system print dialog. Include the app name and a redacted screenshot in an issue.
- **Job stuck:** check paper, ink and printer error lights, then inspect the queue in Printers & Scanners. Do not reset the whole printing system as a first step.
- **Wrong output:** try A4/Plain/Normal first. Report macOS version, printer model, paper size, quality and a non-private reproduction document. Redact printer serials from diagnostics.
- **Scanner:** continue using Brother's scanning software separately.

## Remove

From a downloaded or cloned source checkout, run:

```sh
sudo /bin/bash ./uninstall.sh --all
```

This removes only queues that reference this filter, this driver's files, its selectable PPD and its package receipt. It preserves Brother iPrint&Scan and unrelated queues. Administrator authentication is required.

## Build and validate

On macOS with Python 3 available for tests:

```sh
bash test/run-all.sh
python3 test/test_package.py
bash packaging/build.sh
```

The build itself needs only macOS's bundled shell, CUPS utilities, `pkgbuild`, `productbuild`, and `hdiutil`. Outputs are `dist/Brother-DCP-T220-macOS-1.0.0.pkg`, `.dmg`, and `SHA256SUMS.txt`. Build scripts do not install or print. Release source is available in the tag; `LICENSE` is included in both installers and installed files.

The filter is a small shell program wrapping PWG Raster in Brother PJL. macOS's existing CUPS conversion handles document rasterization. No kernel extension, Rosetta, background service, network upload or firmware modification is required. See [protocol details](docs/protocol.md) and the [original README](docs/UPSTREAM-README.md).

## Attribution and license

GPL-2.0-only; see [LICENSE](LICENSE). Based on upstream commit `50010e5743b6b91580b9c8c85ec5f0e9c68108d5`. Original copyright and source history are preserved. Distribution/packaging maintained by [mksnextofficial](https://github.com/mksnextofficial). Brother is its owner's trademark; no official endorsement is implied.
