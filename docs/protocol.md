# The Brother PWG Raster protocol

What these printers actually speak, how that was established, and the one rule
you must not break when changing the filter.

---

## The envelope

A job is a PJL header, a PWG Raster stream, and a PJL footer.

```
<ESC>%-12345X
@PJL JOB NAME="<job>"
@PJL SET JOBNAME="<job>"
@PJL SET USERNAME="<user>"
@PJL SET FIDELITY=TRUE
@PJL SET PAPER=<A4|LETTER|LEGAL|EXECUTIVE|A5|A6|…>
@PJL SET MEDIATYPE=<PLAIN|GLOSSY|INKJET>
@PJL SET PRINTQUALITY=<DRAFT|NORMAL|HIGH>
@PJL SET RENDERMODE=<COLOR|GRAYSCALE>
@PJL SET DUPLEX=<ON|OFF>
@PJL SET BORDERLESS=<ON|OFF>
@PJL SET JTTOPMARGIN=<n>        ; 1/100 mm
@PJL SET JTBOTMARGIN=<n>
@PJL SET JTLEFTMARGIN=<n>
@PJL SET JTRIGHTMARGIN=<n>
@PJL ENTER LANGUAGE=PWGRASTER
<PWG Raster stream — "RaS2" magic, 1796-byte page headers>
<ESC>%-12345X
@PJL EOJ NAME="<job>"
<ESC>%-12345X
```

`<ESC>%-12345X` is the PJL Universal Exit Language, `\x1b%-12345X`. PJL lines end
`\r\n`.

`@PJL SET SOURCETRAY=<AUTO|TRAY1|TRAY2|MPTRAY|MANUAL>` also exists. The DCP-T220
has one tray, so this driver does not emit it.

**PWG Raster is an open standard** (PWG 5102.4) and macOS produces it natively
through `/usr/libexec/cups/filter/rastertopwg`. That is the whole reason this
driver is a shell script instead of a rasteriser.

---

## THE RULE: never emit `@PJL DEFAULT`

`@PJL SET` is scoped to the job. **`@PJL DEFAULT` writes the printer's
non-volatile memory** and persists after the job, after the cable is unplugged,
after a power cycle. A driver bug there does not produce a bad page — it changes
somebody's printer.

`filter/rastertobrotherpjl` never emits it, and `test/test_filter.sh` asserts the
byte sequence appears nowhere in the output stream.

The assertion is deliberately blunt: not "no `DEFAULT` command is issued" but
"the string `@PJL DEFAULT` does not occur anywhere". That is why `sanitize()`
strips `@` from job and user names as well as quotes. A document titled

    x" @PJL DEFAULT POWERSAVE=1

cannot reach the printer as anything but inert characters, and the rule can be
audited with one `grep` rather than an argument about how a particular firmware
parses text inside a PJL quoted string. The cost is an `@` missing from a job
name in the printer's log. That is a good trade.

**If you add PJL to this driver, keep it to `@PJL SET`.**

---

## How this was established

Brother ships **no** macOS driver for the DCP-T220 — their download page lists
macOS 13 through 26 and offers nothing under any of them. They do ship a Linux
one, and it is the key to everything here.

`dcpt220pdrv` 3.5.0-1 is **80 KB**. That size is the first clue: it is far too
small to contain a raster engine, so the printer must accept something the host
can produce cheaply.

Inside:

| file | what it is |
|---|---|
| `cupswrapper/brother_lpdwrapper_dcpt220` | Perl, GPL-2.0 — readable |
| `lpd/filter_dcpt220` | Perl, GPL-2.0 — readable |
| `lpd/x86_64/brdcpt220filter` | proprietary ELF binary, Linux x86-64 |
| `inf/paperinfij2`, `inf/ImagingArea`, `inf/PaperDimension` | plain-text geometry tables |
| `cupswrapper/brother_dcpt220_printer_en.ppd` | the real PPD |

`strings` on the binary yields the entire PJL vocabulary above, plus:

```
@PJL ENTER LANGUAGE=PWGRASTER
RaS2
PaperType={A4_B,Letter_B,A6_B,Photo_B,…}*RResolution={300,600,750,1200,1200x2400}
rastertobrother.c   brRasterConv.c   SendRasterDoc   raster_write
```

`RaS2` is the PWG Raster sync word. No proprietary format, no traffic capture, no
disassembly — the protocol is legible in a package Brother publishes.

Nothing from that package is redistributed here. The PJL keywords are interface
facts; the page geometry in `ppd/template.ppd` is Brother's measurement of their
own hardware, taken from `inf/ImagingArea` and `inf/PaperDimension`.

---

## Why borderless uses `PAPER=A4`, not `PAPER=A4_B`

Look closely at that capability string:

```
PaperType={A4_B,Letter_B,…}*RResolution={300,600,750,1200,1200x2400}
```

Two keys run together with no separator. `PaperType` is an internal capability
vocabulary, not demonstrably a set of `PAPER` values.

Both spellings were tried on a DCP-T220 and **both printed**. That is precisely
why the plain one is used: `PAPER=A4` + `BORDERLESS=ON` is demonstrably
sufficient, whereas `PAPER=A4_B` requires assuming `_B` is a valid `PAPER` token.
If that assumption were wrong, a printer might silently fall back to a default
rather than fail visibly — the worst kind of bug to chase later.

---

## Measured behaviour

Established on a DCP-T220 with `tools/make-testpage.py`. Anything here is
hardware fact, not inference.

**Margins.** With all four `JT*MARGIN` at 0 and a full-sheet raster, every
calibration ladder bar from 1 mm inward printed complete on all four edges and
all four corner brackets survived: under 1 mm lost, no offset. Setting them to
300 (3 mm) *shifted* the image and clipped the far edges. `JT*MARGIN` moves the
raster; it does not reserve a margin. **0 is correct.**

**Full-sheet raster.** `ImagingBBox null` in the PPD's `setpagedevice` is what
makes CUPS rasterise the whole sheet, which is what the printer expects.
`*ImageableArea` only tells applications where to lay out content — it does not
size the raster. A4 at 300 dpi comes out 2479 × 3508 px, the full sheet.

**Resolution reaches the raster.** Requested 300 / 600 / 1200 dpi produce PWG
page headers reading 300×300, 600×600, 1200×1200. The pipeline is not the
bottleneck.

**Quality and resolution are coupled.** At `PRINTQUALITY=NORMAL` the 600 dpi
line-pair target collapses into about five coarse aliased bands. At `HIGH` the
same target resolves into many separate fine lines, and flat mid-tones and solid
blacks are visibly smoother. Sending high-resolution raster at `NORMAL` spends
bandwidth for nothing.

This is why the PPD exposes **one** control. `BRQuality` sets `HWResolution` in
the PPD and `PRINTQUALITY` in the filter, so the pair cannot disagree:

| `BRQuality` | raster | `PRINTQUALITY` |
|---|---|---|
| Draft | 300 dpi | `DRAFT` |
| Normal | 600 dpi | `NORMAL` |
| Best | 600 dpi | `HIGH` |
| Photo | 1200 dpi | `HIGH` |

**1200 dpi does not resolve.** The 1200 dpi line-pair block is solid in both
axes, and an A4 page at 1200 dpi is roughly 417 MB before compression over
USB 2.0. `Photo` is offered, not recommended.

**Resolution is asymmetric.** Down-page detail resolves at 600 dpi; across-page
detail is already flat by 300. That matches the hardware's `1200x2400` claim:
paper advance is precise, the head sweep plus ink spread is not.

**Colour fringing on fine detail is a scanner artefact, not ink.** The greyscale
sheet converted correctly — nozzle check showed C as light grey, M as mid grey,
Y as near white, K as black — yet its line-pair blocks showed the same rainbow
banding as the colour sheet. With no colour left in the file, the fringing cannot
be coming from the printer. It is moiré from scanning a fine line pattern.
Composite black is *not* a problem here, and greyscale is an option rather than a
recommended default.

---

## The printer is not an AirPrint device

```
Interface 0: class 7 / subclass 1 / protocol 2   (legacy bidirectional)
Interface 1: class 255 (vendor)
Interface 2: class 255 (vendor)
```

IPP-over-USB requires **protocol 4**. This printer does not have it.

So any `ippusb://` queue on these models is not talking to the printer — it is
talking to `com.brother.HttpToUsbBridge`, a userspace daemon Brother installs
that bridges HTTP to the USB interface and advertises a synthetic `_ipp._tcp`
service on localhost. macOS then builds a PPD by asking *the bridge* what the
printer can do, and the bridge's answers are incomplete:

```
*% WARNING Printer reported as unsupported: requested-attributes
*% WARNING no URF supported resolutions found.
*DefaultResolution: 300x300dpi
```

That is the origin of the 300 dpi ceiling, and of jobs that hang at
`Looking for printer` whenever the LaunchAgent is not running.

This driver bypasses all of it and talks to interface 0 through the stock CUPS
`usb://` backend.

---

## References

- PWG 5102.4, PWG Raster Format — <https://ftp.pwg.org/pub/pwg/candidates/cs-ippraster10-20120420-5102.4.pdf>
- PJL is documented in HP's *Printer Job Language Technical Reference Manual*
- `models.tsv` records which models have been confirmed on real hardware
