# Contributing

Two very different kinds of contribution land here, and they ask different
things of you.

| You have | Start at |
|---|---|
| A Brother inkjet and twenty minutes | [docs/contributing-a-model.md](docs/contributing-a-model.md) — no code required |
| A bug, or a capability to add | this page |

Adding a model is the common case and by far the most useful. You do not need
to read any of the code to do it.

---

## Running the tests

Everything except the hardware checks runs on any Mac, with no printer, no root
and no system change:

```bash
bash test/run-all.sh
python3 test/test_package.py
```

These checks run in CI on every pull request, so a green local run is a good
predictor. The hardware checks are separate and need a printer and `sudo`:

```bash
./test/verify-hardware.sh
```

## What the pieces are

```
PDF → cgpdftoraster → rastertopwg → rastertobrotherpjl → usb:// → printer
      └──────── stock macOS ──────┘   └── this repo ──┘   └ macOS ┘
```

- `filter/rastertobrotherpjl` — the whole driver: wraps PWG Raster in PJL.
- `ppd/template.ppd` — a superset PPD, with `@PLACEHOLDER@` substitution points.
- `ppd/models.tsv` — one row per model, saying which of the superset it gets.
- `ppd/generate-ppd.sh` — cuts the template down to one model's row.
- `install.sh` / `uninstall.sh` — detect, generate, install, create the queue.
- `tools/make-testpage.py` — the calibration page every claim here was measured on.

[docs/protocol.md](docs/protocol.md) explains what the printer actually speaks
and how that was established. Read it before changing the filter.

## Rules that are load-bearing

These are not style preferences. Each one exists because breaking it damages
something outside the current job.

**Emit only `@PJL SET`, never `@PJL DEFAULT`.** `SET` is scoped to the job;
`DEFAULT` writes the printer's non-volatile memory and survives a power cycle. A
bug there does not produce a bad page, it changes somebody's printer. CI fails
the build if the string appears outside a comment, and `sanitize()` in the
filter strips `@` from job and user names so the rule can be audited with one
`grep`.

**Never populate `borderless` for an unverified model.** On a printer that does
not support it, ink lands on the platen roller and marks the back of the pages
that follow. It is the one option whose failure mode reaches outside the sheet.

**`verified` means someone looked at paper.** Not "it should work", not "the
spec says". A row without photographed evidence stays `generic`, which is not an
insult — it is an accurate description of what anyone can claim about hardware
they have not seen.

**Untrusted input stays untrusted.** The job title, the user name and the PPD
options reach the filter from whoever submitted the job; the model name reaches
`generate-ppd.sh` from whatever is plugged into the USB bus. Both are validated
or stripped at the boundary rather than escaped at each use.

## Conventions

- **No dependencies.** Stock macOS only — `/bin/sh`, `/bin/bash` 3.2, and the
  system `python3`. Anything that needs Homebrew is out.
- **`filter/` and `ppd/` are POSIX `sh`.** CUPS runs the filter; it does not owe
  us bash. The installers and the tests are `#!/bin/bash` and may use bashisms,
  but must work on the bash 3.2 that ships with macOS.
- **`set -u` everywhere.** Not `set -e`: these scripts check each step and give
  a specific message instead, which is worth more than an anonymous abort.
- **Shell test suites source `test/lib.sh`** for `ok` / `nope` / `skip` /
  `assert_status` / `summary`, and ends with `summary`. Do not re-declare them.
- **Comments say why, not what.** The repository is full of measurements and
  trade-offs that are invisible from the code; those are the comments worth
  writing. `git log` is where the history goes.
- **British spelling** in prose and identifiers (`colour`, `licence`,
  `behaviour`), except where a standard spells it otherwise — PPD keywords such
  as `ColorModel` and `*ColorDevice` are fixed by the spec.
- **New page sizes need four lines** in `ppd/template.ppd`: `PageSize`,
  `PageRegion`, `ImageableArea`, `PaperDimension`. `test/test_ppd.sh` fails if
  you miss one.

## Pull requests

- One change per pull request.
- `bash test/run-all.sh` passes.
- New behaviour comes with a test. New measurements come with a photo.
- Say which hardware you ran it on, or say that you could not.

Everything here is GPL-2.0. By opening a pull request you agree your
contribution ships under it.
