# Security

## Reporting a vulnerability

Please report privately, not as a public issue:
[open a security advisory](https://github.com/mksnextofficial/brother-dcp-t220-macos/security/advisories/new).

If that link does not work, private reporting has not been enabled on the
repository yet — open a normal issue saying only that you have a security
report and asking for a private channel, with no details in it.

There is no bounty and no service-level agreement. This is a small driver
maintained by whoever has the hardware.

## What this software does that matters

`install.sh` needs `sudo`, and what it does with it is worth knowing:

- writes `/Library/Printers/BrotherPWG/`, owned `root:wheel`, mode `755` for
  the filter and `644` for the PPD;
- registers a CUPS print queue pointing at that PPD;
- the graphical package additionally installs a selectable PPD, README, license and package receipt. It does not install a daemon, a LaunchAgent, or a kernel
  extension, does not modify Brother's software, and does not touch queues it
  did not create. `uninstall.sh` removes this distribution's queues, driver files, selectable PPD and receipt.

The consequence is that `filter/rastertobrotherpjl` is **executed by `cupsd`
for every job sent to the queue**, with whatever privileges CUPS gives a
filter. It is about 160 lines of POSIX shell, deliberately, so that it can be
read in full by anyone deciding whether to install it.

## Trust boundaries

Three inputs come from outside and are treated as hostile:

| Input | Reaches | Handling |
|---|---|---|
| Job title, user name | PJL header | `sanitize()` strips `"`, `@`, CR, LF and ESC, then truncates to 64 bytes |
| PPD options (`BRQuality`, margins, …) | PJL header | mapped through fixed `case` tables; margins reduced to digits |
| Model name from the USB device-id | Generated PPD | rejected unless it is letters, digits, space and `. _ + -` |

The rule those exist to protect is the one in
[docs/protocol.md](docs/protocol.md): the byte sequence `@PJL DEFAULT` must
never reach the printer, because it writes non-volatile memory and persists
beyond the job. `test/test_filter.sh` asserts its absence from the output
stream and CI fails the build if it appears in the source outside a comment.

## What is not defended against

- A user who can already run commands as root. Everything here is reachable
  more directly at that point.
- A malicious USB device that claims to be a Brother printer. It gets a print
  queue pointed at itself and receives whatever is printed to that queue. This
  is true of every printer driver, and is not something a driver can fix.
- Firmware bugs in the printer. The `@PJL SET`-only rule is the mitigation for
  the one such bug whose blast radius outlives the job.

## Supported versions

The latest published release and the `main` branch. Version 1.0.0 is unsigned and not notarized. Report packaging issues here; upstream protocol issues may also be reported to the credited upstream project.

## No warranty

GPL-2.0, sections 11 and 12: this software comes with **no warranty**. It
drives hardware, and hardware can be wasteful of ink and paper when a driver is
wrong. See [LICENSE](LICENSE).
