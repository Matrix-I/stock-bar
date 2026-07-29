# StockBar — Vietnamese stocks + crypto in the macOS menu bar

A menu-bar ticker that refreshes about once a minute. Vietnamese equities and indices (HOSE/HNX) come
from VPS's public market-data backends; crypto comes from Binance's public REST API. No API key, no
account, no Python — the app talks to both over `URLSession`.

```bash
./build_app.sh            # compiles Sources/ into StockBar.app and relaunches it
open StockBar.app
```

Requires macOS 13+ and the Xcode **Command Line Tools** (`xcode-select --install`). Full Xcode is not
needed: `build_app.sh` compiles with `swiftc` and assembles the `.app` bundle by hand.

## What it shows

The menu bar shows the symbols you pin, e.g. `VNI 1,704.68 +1.43%  BTC 64,013.97 +0.19%`. Clicking it
opens a panel with every watched symbol, its intraday sparkline, the daily band, and the controls for
editing the list.

The pencil turns on edit mode, which gives each row pin / move up / move down / remove. The sparkline
hides while editing to make room — four controls plus a chart and a price don't fit on one row without
truncating the change. Pinned symbols are drawn in watchlist order and only the first four get a slot,
so reordering is also how you choose which ones appear.

Every size in the panel goes through `pt()`/`uiFont()` in `View/TickerPopover.swift`, which multiply by
`uiScale` (currently `1.5`). Change that one constant to resize the whole panel: scaling the fonts alone
would clip the columns, so widths, padding and spacing scale with them. The menu-bar label is not
affected — a status item is capped at the menu bar's own height, so its text cannot grow with the panel.

Prices are shown **in full, never abbreviated or rounded** — the menu bar and the panel call the same
`fmtPrice` in `Support/Formatting.swift`, so they cannot disagree about what an instrument costs. That
costs width: about 125pt per pinned symbol with the percentage shown. Turn off *Show change % in the
menu bar* in the panel to get roughly 45pt of that back per symbol.

Colours follow the **Vietnamese board convention**, which is not the Western one:

| Colour | Meaning |
|---|---|
| 🟢 green | tăng (up) |
| 🔴 red | giảm (down) |
| 🟣 purple | trần (ceiling — locked at the daily upper limit) |
| 🩵 cyan | sàn (floor — locked at the daily lower limit) |
| 🟡 yellow | tham chiếu (unchanged from the reference price) |

Crypto uses green/red only; it has no daily band.

## Data sources

| What | Endpoint | Notes |
|---|---|---|
| VN equities | `bgapidatafeed.vps.com.vn/getliststockdata/VCB,FPT,…` | One request covers every ticker. Returns last price, reference, ceiling, floor, volume. |
| VN indices | `histdatafeed.vps.com.vn/tradingview/history?resolution=1` | TradingView UDF feed. 1-minute bars, so one request gives both the live value and the sparkline. |
| VN reference | same, `resolution=1D` | Previous session's close. Cached for the day — it only changes overnight. |
| Crypto | `api.binance.com/api/v3/ticker/24hr?symbols=[…]` | One request covers every pair. Reference is `openPrice` (24h rolling), matching Binance's own UI. |
| Crypto sparkline | `api.binance.com/api/v3/klines?interval=1m&limit=60` | Last hour of 1-minute candles. |

The VPS endpoints are the JSON services behind VPS's own public web board. They need no key and are
community-known rather than formally documented, so treat them as something that can change without
notice — `Tools/probe.sh` exists to tell you quickly when it has.

### Price scaling

VPS quotes **equities in thousands of VND**: VCB reads `54.6`, meaning 54,600 VND. Ceiling, floor and
reference use the same unit. The app multiplies by 1000 on the way in so `Quote.price` is always real
VND, and formats back down for display. Index values (VN-Index 1704.68) are already points and are not
scaled. Getting this wrong is a 1000× error on screen.

## Refresh behaviour

- **60s** while any watched market is trading; **600s** when they are all closed.
- HOSE session gating: weekdays 09:00–15:00 ICT, minus the 11:30–13:00 lunch break. That removes about
  85% of requests and stops the machine waking every minute for a number that cannot move. Crypto is
  always polled.
- Public holidays are deliberately not modelled — a stale hardcoded calendar would wrongly suppress
  polling on a real trading day, which is a worse failure than wasting a few requests on Tết.
- A failed fetch never clears a quote. The last good value stays on screen and fades as it ages, because
  an empty menu bar reads as a crash while a dimmed one reads as old data.
- The app refreshes immediately on wake — a `Timer` does not fire during sleep and does not catch up.

## Layout

```
build_app.sh                   the VERSION line, compile, bundle, embed Sparkle, sign, relaunch
release.sh                     cut a tagged release with a .dmg on GitHub, then bump
fetch_sparkle.sh               vendor the pinned Sparkle framework + tools (gitignored)
update_appcast.sh              EdDSA-sign a .dmg and add it to appcast.xml
appcast.xml                    the Sparkle feed, served raw from GitHub
Sources/
  App/StockBarApp.swift        NSStatusItem + NSPopover, glyph cache, entry point
  Model/Quote.swift            the shape every source normalises into; PriceBand
  Reader/QuoteSource.swift     shared URLSession + lenient JSON number coercion
  Reader/VNQuoteSource.swift   VPS board + TradingView UDF history
  Reader/CryptoQuoteSource.swift  Binance ticker + klines
  Reader/QuoteReader.swift     cadence, fan-out, last-good-quote store
  Support/                     Formatting, MarketHours, Watchlist, PollingTimer, LoginItem, AppInfo
  Support/Updater.swift        Sparkle wrapper; UpdateUserDriver.swift is the compact update window
  View/MenuBarGlyph.swift      bakes the coloured status-bar NSImage
  View/TickerPopover.swift     the panel: rows, sparklines, settings
Tools/probe.sh                 exercises the data layer from the command line
Tools/uisnap.sh                renders the popover to a PNG (no Screen Recording permission needed)
```

`NSStatusItem` rather than SwiftUI's `MenuBarExtra`, for two reasons: the label must be
multi-coloured and `MenuBarExtra` renders its label as a monochrome template, and `MenuBarExtra`'s
presentation state desynchronises when its window is closed from outside, producing the familiar
"first click does nothing" bug.

## Versioning and releases

The version is written in exactly one line of `build_app.sh` (`VERSION="1.0.0-SNAPSHOT"`), which stamps
it into `Info.plist`; the panel header shows it back, in orange while it still carries `-SNAPSHOT`.
During development it always does — a snapshot version is what says "this is not the build someone
downloaded".

`release.sh` cuts a release, and is the only thing that rewrites that line:

```bash
./release.sh --dry-run     # build the .dmg and print the notes; touches nothing remote
./release.sh               # drop -SNAPSHOT → build → tag → publish → bump to the next -SNAPSHOT
./release.sh --next patch  # bump the patch component afterwards instead of the minor one
```

So `1.0.0-SNAPSHOT` releases as tag `v1.0.0` and the branch continues on `1.1.0-SNAPSHOT`. The default
bump is **minor**, because the reason to keep developing after a release is normally a new feature.

Release notes are generated from the conventional-commit subjects since the previous tag, grouped into
Added / Fixed / Other. `chore:` commits are dropped; anything that doesn't parse lands under Other
rather than being silently lost.

The uploaded `.dmg` is **ad-hoc signed and not notarized**, so Gatekeeper refuses to open it on any
other machine until the quarantine flag is cleared — the generated notes tell the downloader to run
`xattr -dr com.apple.quarantine /Applications/StockBar.app`. Notarizing instead would need a paid
Apple Developer account.

`release.sh` refuses to start unless the tree is clean, the branch is `main`, the checkout is not
behind `origin/main`, the tag is free both locally and on the remote, and `gh` is active as the
account that owns the repo — it checks that rather than switching, since `gh auth switch` is global
state that would affect the user's other shells.

## Auto-update

Sparkle 2.9.4, same setup as `stats-bar`. `fetch_sparkle.sh` vendors the framework into `Frameworks/`
and the release tools into `.sparkle-tools/` — both gitignored and re-fetched on demand, so a fresh
checkout builds with no manual step. `build_app.sh` links it, embeds it in `Contents/Frameworks`, and
signs inside-out (framework first, then the app around it — signing the app first would invalidate its
seal the moment the nested framework was re-signed).

The panel's footer carries the two controls: an **Automatically check for updates** checkbox (bound
straight onto Sparkle, which persists it itself) and **Check for updates…**. A background check runs
every 6 hours (`SUScheduledCheckInterval`) and stays silent unless there is something new; only a check
the user started ever shows an "up to date" window.

Two behaviours worth knowing before you conclude something is broken:

- **The checkbox reads off on the very first run.** Sparkle deliberately waits until the *second* launch
  before asking whether it may check automatically; our driver answers yes without showing a dialog, so
  `SUEnableAutomaticChecks` flips to 1 then. Verified by clearing the `SU*` defaults and launching twice.
- **`Check for updates…` fails until `appcast.xml` is on `main`.** `SUFeedURL` points at
  raw.githubusercontent.com, which 404s until the file is pushed — the app is fine, the feed just doesn't
  exist yet. It goes live with the first `release.sh` run (or any push of `appcast.xml`).

The UI is one compact window rather than Sparkle's default multi-window flow — `UpdateUserDriver.swift`
implements `SPUUserDriver` to replace only the *presentation*. Feed fetch, EdDSA verification, download,
in-place install and relaunch are all stock Sparkle.

```
StockBar.app  ──SUFeedURL──▶  raw.githubusercontent.com/Matrix-I/stock-bar/main/appcast.xml
                                        │ enclosure url + sparkle:edSignature
                                        ▼
                              github.com/…/releases/download/vX.Y.Z/StockBar-X.Y.Z.dmg
```

`release.sh` adds each release to the feed via `update_appcast.sh`, which EdDSA-signs the `.dmg` with
the private key in this machine's keychain and prepends an `<item>` to `appcast.xml`. That happens
*after* the GitHub release exists, because the enclosure URL has to resolve — a feed entry that 404s
would reach every installed copy. The first signing run shows a one-time keychain prompt; click **Always
Allow**. For a non-interactive run, export the key with `.sparkle-tools/generate_keys -x keyfile` (keep
it out of the repo) and point `SPARKLE_ED_KEY_FILE` at it.

**That EdDSA signature is what makes updating an unnotarized app safe.** Sparkle refuses any download
that doesn't verify against `SUPublicEDKey` in `Info.plist`. And because Sparkle downloads through its
own machinery rather than a browser, the update never gets a `com.apple.quarantine` flag — so Gatekeeper
doesn't block the in-place install even though the app isn't notarized. Only the *first* install, from
the `.dmg` a human downloaded, needs the `xattr` step.

## Debugging

```bash
./Tools/probe.sh                          # the shipped watchlist
./Tools/probe.sh VCB FPT BTCUSDT          # specific symbols
GLYPH_OUT=/tmp/g.png ./Tools/probe.sh     # also render the real menu-bar label to a PNG
GLYPH_DEMO=1 GLYPH_OUT=/tmp/b.png ./Tools/probe.sh   # render all five band colours
```

The probe compiles the app's own Model/Support/Reader layers, so what it prints is what the app sees.

To look at the panel itself:

```bash
./Tools/uisnap.sh /tmp/panel.png          # dark
./Tools/uisnap.sh /tmp/panel-light.png light
```

`uisnap` hosts the real `TickerPopover` in a window and caches its display into a PNG. It exists because
`screencapture` of the actual panel fails here without Screen Recording permission, which would leave
every layout change unverifiable from a terminal. Caveat: `Bundle.main` is the tool, not `StockBar.app`,
so the header renders the version as `dev` — check the real value against `Info.plist`.

### Behind a TLS-inspecting proxy

On a machine where Cloudflare WARP/Gateway re-signs HTTPS, **Swift needs no special handling**: the
Gateway CA is in the System keychain and `URLSession` consults the system trust store. Never add a
`serverTrust` override to work around a TLS error here — it would be unnecessary and a real regression.

Command-line tools are the ones that break, because they carry their own CA bundles:

```bash
curl --cacert ~/warp-ca.crt https://bgapidatafeed.vps.com.vn/getliststockdata/VCB
```

## Notes

- The app is ad-hoc signed by default. To keep "Launch at login" from being re-asked after each
  rebuild, create a self-signed code-signing certificate named `StockBar Local` in Keychain Access
  (Certificate Assistant ▸ Create a Certificate… ▸ Self Signed Root ▸ Code Signing); `build_app.sh`
  picks it up automatically.
- At most 4 symbols can be pinned to the menu bar. Beyond that macOS silently truncates the item,
  which reads as the app being broken rather than as a limit being hit.
