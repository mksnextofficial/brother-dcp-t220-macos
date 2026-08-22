# Qualifying a model

Only the DCP-T220 is `verified`. Everything else runs on the generic profile,
which deliberately claims less than the hardware can probably do.

Moving your model from `generic` to `verified` takes about twenty minutes and
four sheets of paper. You do not need to read any of the code.

---

## 1. Check the driver applies at all

```bash
/usr/sbin/lpinfo -l -v | grep -B2 -A4 -i brother
```

You want the `device-id` line:

```
device-id = SERN:…;MFG:Brother;CMD:HBP,PJL;MDL:DCP-T220;CLS:PRINTER;…
```

**`CMD:` must contain `HBP`.** If it does not, this driver does not apply to your
printer and `install.sh` will refuse to install it. Note the `MDL:` value — that
string is your model name for the table.

## 2. Install on the generic profile

```bash
sudo ./install.sh
```

It will tell you the model is unverified and that borderless is withheld. That is
expected; that is what you are here to fix.

## 3. Margins

```bash
python3 tools/make-testpage.py -o /tmp/m.pdf --label "margins"
lp -d Brother_PWG /tmp/m.pdf
```

Along each edge is a row of bars. **The bar labelled N sits exactly N mm from the
paper edge.** The lowest number whose bar printed *complete* is that edge's
margin, in millimetres. No ruler needed — read it off the sheet.

- All four edges show a low number (1–3) → the raster lands correctly. Good.
- One edge much larger than the opposite one → the image is shifted. Report the
  numbers; the margins are adjustable and we will work out the offset.

Also check the four corner brackets and the labelled **100 mm span**. If that
span does not measure 100 mm against a real ruler, the page is being scaled and
we want to know.

## 4. Quality levels

```bash
python3 tools/make-testpage.py -o /tmp/q1.pdf --focus quality --label "Normal"
lp -d Brother_PWG -o BRQuality=Normal /tmp/q1.pdf

python3 tools/make-testpage.py -o /tmp/q2.pdf --focus quality --label "Best"
lp -d Brother_PWG -o BRQuality=Best /tmp/q2.pdf
```

Compare the two sheets, looking only at the banding block — the flat 40% tone,
the gradient and the solid black bar. Inkjet quality modes differ in pass count,
and pass count shows as banding long before it shows in fine detail.

- **Best is visibly smoother** → keep `Best` in `qualities`.
- **Indistinguishable** → drop `Best`; it would only cost time.

Then look at the resolution block on the `Best` sheet: which is the finest set
still showing separate lines rather than flat grey?

- 1200 dpi resolves → keep `Photo`.
- **1200 dpi is solid** → leave `Photo` out. It quadruples the data for nothing.
  (This is the DCP-T220's result.)

## 5. Borderless — last, and read this first

**Borderless on plain paper sprays a little ink past the sheet onto the platen
roller.** Nothing is damaged, but it can mark the back of the next few pages
until it dries. Use photo paper if you have it, and skip this step entirely if
you would rather not — a model without borderless is still a useful table row.

```bash
python3 tools/make-testpage.py -o /tmp/b.pdf --focus bleed --label "borderless"
lp -d Brother_PWG -o PageSize=A4.Fullbleed /tmp/b.pdf
```

Look at the four solid colour bands at the paper edges:

- ink reaches the paper edge with no white strip → borderless works
- a white strip on every edge → borderless was ignored; use `none`
- nothing printed, or an error on the printer's panel → `none`

`A4.Fullbleed` will only appear if you edit the table first, so for this test
pass the option on the command line as above.

## 6. Write the row

`ppd/models.tsv`, tab-separated, above the `*` row:

```
DCP-T220	verified	Draft,Normal,Best,Photo	Normal	colour	A4,Letter,Legal,A5,A6,Executive,4x6,5x7,5x8,3.5x5,Env10,EnvDL,EnvC5,EnvMonarch	A4,Letter,A6,4x6,5x7,5x8,3.5x5	1
```

| field | what to put |
|---|---|
| `model` | the exact `MDL:` string from step 1 |
| `status` | `verified` |
| `qualities` | what survived step 4, from `Draft,Normal,Best,Photo` |
| `default_quality` | `Normal` unless you have a reason |
| `colour` | `colour` or `mono` |
| `papersizes` | sizes your printer's manual lists. Known keywords: `A4 Letter Legal A5 A6 Executive 4x6 5x7 5x8 3.5x5 Env10 EnvDL EnvC5 EnvMonarch` |
| `borderless` | what worked in step 5, or `none` |
| `trays` | tray count; only tray 1 is driven today |

Anything in `papersizes` or `borderless` must already exist in
`ppd/template.ppd`. Adding a genuinely new size means adding four lines there —
`PageSize`, `PageRegion`, `ImageableArea`, `PaperDimension` — and
`test/test_ppd.sh` will fail if you miss one.

Check your work:

```bash
bash test/run-all.sh
sudo ./install.sh --yes && lp -d Brother_PWG /tmp/m.pdf
```

## 7. Send it

Open a pull request with the row and **photos of your sheets**.

The photos are the point. `verified` means someone looked at paper — a row
without evidence stays `generic`, which is not an insult, just an accurate
description of what anyone can claim about hardware they have not seen.
