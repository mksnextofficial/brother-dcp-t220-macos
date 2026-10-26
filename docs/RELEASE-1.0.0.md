# Version 1.0.0 release validation

Environment: macOS 27.0.1 (26A434), Apple Silicon, Brother DCP-T220 USB.

- 115 inherited hardware-free assertions passed.
- Eight package tests passed: connection detection, offline install, own-queue update, unrelated queue preservation, different-device preservation, failed queue setup guidance, OS target and quality labels.
- Native CUPS PDF-to-600 dpi color PWG conversion passed; filter preserves complete raster bytes.
- A test page sent through the installed core driver completed, and the user confirmed physical printing.
- Product archive parsed by Apple's Installer; selectable component enabled for this Mac.
- Graphical welcome screen opened in Installer. Actual authenticated GUI installation of this package has not been tested yet; the existing driver was installed using the CLI.
- Package payload and root/wheel ownership inspected; DMG verified and checksums generated.
- Independent of the printed page, Fine/EcoMode, borderless, photo, copies and other apps have not received a full physical test matrix.
- Unsigned, not notarized. No Developer ID Installer identity available on the build host.

No claims are made about Intel hardware, Windows, iOS, other Brother models or future macOS releases. CI runners may use a different macOS version; their results validate source/build behavior only, not physical compatibility.
