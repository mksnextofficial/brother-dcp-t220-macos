# brother-pwg-macos

[![tests](https://github.com/zama-tui/brother-pwg-macos/actions/workflows/test.yml/badge.svg)](https://github.com/zama-tui/brother-pwg-macos/actions/workflows/test.yml)
[![lint](https://github.com/zama-tui/brother-pwg-macos/actions/workflows/lint.yml/badge.svg)](https://github.com/zama-tui/brother-pwg-macos/actions/workflows/lint.yml)
[![licence: GPL-2.0](https://img.shields.io/badge/licence-GPL--2.0-blue.svg)](LICENSE)

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
files redistributed, no disassembly and no traffic capture — Brother publishes a
GPL Linux driver, and the protocol is legible in it.

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

## Print quality

Quality and raster resolution ship as **one** control, because on this hardware
they are coupled: 600 dpi raster sent at `PRINTQUALITY=NORMAL` prints coarser
than the raster it was given. Two knobs would only let you pair them wrongly.

| Setting | Raster | Use for |
|---|---|---|
| Draft | 300 dpi | proofs, maximum speed |
| **Normal** (default) | 600 dpi | everyday text |
| Best | 600 dpi | line art, small type, anything detailed |
| Photo | 1200 dpi | photographs |

On the DCP-T220, `Photo` did not resolve any finer than `Best` in either axis
and costs roughly four times the data over USB 2.0. It is offered, not
recommended. The measurements behind all of this are in
[docs/protocol.md](docs/protocol.md).

## Model support

| Model | Status |
|---|---|
| DCP-T220 | verified on hardware |
| other Brother inkjets reporting `CMD:HBP` | generic profile, unverified |

Unverified models get a conservative profile — no borderless, no Photo — and a
warning at install time. Qualifying yours takes about twenty minutes and four
sheets of paper: [docs/contributing-a-model.md](docs/contributing-a-model.md).

## Troubleshooting

**Jobs sit at "Looking for printer" forever.** This is almost always the *old*
Brother queue, not this one. Brother's `com.brother.HttpToUsbBridge` LaunchAgent
has to be running for their queue to work, and when it is not, jobs queue up
indefinitely — one of the machines this was developed on had a job stuck for over
a month.

```bash
lpstat -o                      # what is queued, and since when
lpstat -l -p Brother_PWG       # queue state and any alerts
cancel -a                      # clear everything stuck
```

**Nothing prints, no error.** Check the printer is on the USB bus at all:

```bash
/usr/sbin/lpinfo -v | grep -i brother
```

**Diagnose a job.** The filter logs its resolved settings for every job:

```bash
sudo grep rastertobrotherpjl /var/log/cups/error_log | tail
```

**Check the whole install.** Runs the round trip and prints one page:

```bash
./test/verify-hardware.sh
```

## Going back to iPrint&Scan

Nothing here modifies or removes Brother's software, so it is still there.
Remove this driver and start their bridge:

```bash
sudo ./uninstall.sh
sudo launchctl load /Library/LaunchAgents/com.brother.HttpToUsbBridge.plist
```

## Testing

Everything except the hardware checks runs on any Mac, with no printer, no root
and no system change:

```bash
bash test/run-all.sh
```

## Contributing

The most useful contribution is a row in `ppd/models.tsv` for a model nobody has
qualified yet. It takes about twenty minutes and four sheets of paper, and needs
no code: [docs/contributing-a-model.md](docs/contributing-a-model.md).

For anything else, start at [CONTRIBUTING.md](CONTRIBUTING.md).

## Documentation

- [docs/protocol.md](docs/protocol.md) — the PJL vocabulary and how it was obtained
- [docs/contributing-a-model.md](docs/contributing-a-model.md) — qualifying a new model
- [CONTRIBUTING.md](CONTRIBUTING.md) — tests, conventions, and the load-bearing rules
- [SECURITY.md](SECURITY.md) — what runs as root, what is trusted, how to report

## Licence

GPL-2.0. See [LICENSE](LICENSE).

Not affiliated with, endorsed by, or supported by Brother Industries, Ltd.
"Brother" is their trademark, used here only to say which printers this drives.
