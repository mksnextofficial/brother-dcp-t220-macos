# brother-pwg-macos

A CUPS driver for Brother budget inkjets on macOS, for the models Brother never
shipped a macOS driver for.

## The problem

Brother's download page for the DCP-T220 lists macOS 13 through 26 and offers
nothing under any of them. Their answer is the *iPrint&Scan* app, which installs
a `com.brother.HttpToUsbBridge` LaunchAgent: it bridges HTTP/IPP to the printer's
USB interface and advertises a synthetic AirPrint service on localhost, so macOS
auto-generates a queue pointing at it.

That arrangement fails in two ways.

**It is fragile.** When the LaunchAgent is not running — and it silently was not,
on the machine this was developed on — every job wedges at `Looking for printer`
forever.

**It throws away most of the printer.** macOS builds the PPD by asking the bridge
what it can do, and the bridge's answers are incomplete. The generated PPD
records its own failure:

```
*% WARNING no URF supported resolutions found.
*DefaultResolution: 300x300dpi
```

Draft, Normal and High all map to 300 dpi. Brother's own filter states the
hardware's real capability as `RResolution={300,600,750,1200,1200x2400}`.

## What this does instead

The printer does not speak a proprietary format. It accepts **PWG Raster**, an
open standard (PWG 5102.4) that **macOS already produces natively**. All that was
missing is the PJL envelope Brother wraps around it.

```
PDF → cgpdftoraster → rastertopwg → rastertobrotherpjl → usb:// → printer
      └──────── stock macOS ──────┘   └── this repo ──┘   └ macOS ┘
```

One component is ours: a ~150-line shell script. No compiled code, no Brother
files redistributed, no reverse engineering — Brother publishes a GPL Linux
driver, and the protocol is legible in it.

## Install

```bash
sudo ./install.sh
```

Preview what it would do, without touching anything:

```bash
./install.sh --dry-run
```

## Uninstall

```bash
sudo ./uninstall.sh
```

It removes the queue it created and its own install directory, and nothing else.
Brother's software is never modified or removed; existing queues are left alone.

## Model support

| Model | Status |
|---|---|
| DCP-T220 | verified on hardware |
| other Brother inkjets reporting `CMD:HBP` | generic profile, unverified |

Unverified models get a conservative profile and a warning at install time.
To qualify yours, see [docs/contributing-a-model.md](docs/contributing-a-model.md).

## Documentation

- [docs/protocol.md](docs/protocol.md) — the PJL vocabulary and how it was obtained
- [docs/contributing-a-model.md](docs/contributing-a-model.md) — qualifying a new model

## Licence

GPL-2.0. See [LICENSE](LICENSE).

Not affiliated with, endorsed by, or supported by Brother Industries, Ltd.
"Brother" is their trademark, used here only to say which printers this drives.
