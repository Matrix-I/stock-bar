# StockBar — Vietnamese stocks + crypto in the macOS menu bar

A menu-bar ticker that refreshes about once a minute. Vietnamese equities and indices (HOSE/HNX) come
from VPS's public market-data backends; crypto comes from Binance's public REST API. No API key, no
account, no Python — the app talks to both over `URLSession`.

```bash
./build_app.sh            # compiles Sources/ into StockBar.app and relaunches it
open StockBar.app
```

```bash
./run_tests.sh            # unit tests over Sources/Core — use this, not a bare `swift test`
```

Requires macOS 13+ and the Xcode **Command Line Tools** (`xcode-select --install`). Full Xcode is not
needed: `build_app.sh` compiles with `swiftc` and assembles the `.app` bundle by hand, and `run_tests.sh`
exists because SwiftPM cannot locate swift-testing under the Command Line Tools by itself.

## Installing a downloaded release

The `.dmg` attached to a [release](https://github.com/Matrix-I/stock-bar/releases) is **ad-hoc signed and
not notarized**. There is no paid Apple Developer account behind this app, so the bundle carries no
Developer ID signature for Gatekeeper to check against Apple. macOS quarantines anything arriving from a
browser and then refuses to open it — usually with *"StockBar is damaged and can't be opened"*, which is
misleading: nothing is damaged, the signature is simply not one Apple vouches for.

Drag the app to `/Applications`, then clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/StockBar.app
```

Once per download, not once per launch. Two cases need it and one doesn't:

- **Building from source** never does — the flag is written by whatever downloaded the file, not by the
  compiler, so a locally built bundle has none.
- **Updates the app installs itself** never do either — Sparkle unpacks the archive with its own
  machinery rather than through a browser, so the replacement bundle is not flagged. Only the first,
  hand-downloaded copy is.

## What it shows

The menu bar shows the symbols you pin, e.g. `VNI 1,704.68 +1.43%  BTC 64,013.97 +0.19%`. Clicking it
opens a panel with every watched symbol, its intraday sparkline, the daily band, and the controls for
editing the list.

The pencil turns on edit mode, which gives each row pin / move up / move down / remove. The sparkline
hides while editing to make room — four controls plus a chart and a price don't fit on one row without
truncating the change. Pinned symbols are drawn in watchlist order and only the first four get a slot,
so reordering is also how you choose which ones appear.

The symbol list **scrolls** once it grows past what the screen can hold — 90% of the display's usable
height, measured on whichever display the popover actually opened on. Below that the panel is exactly as
tall as its contents, so a four-row watchlist has no empty space. The header and the footer never scroll:
Refresh, the add field, the settings and Quit stay reachable at any list length.

**Adding a symbol checks it with the venue first.** Neither upstream rejects a bad ticker outright — the
Vietnamese board just omits the row and Binance answers `400` — so a typo used to join the list and render
a dash forever, indistinguishable from a feed that was down. The add field now asks for a quote before
committing the row, and says which of the two happened. The market picker is only a hint: a ticker ending
in a stablecoin quote (`BTCUSDT`, `ETHUSDC`) is filed under Binance whatever the picker says, because
sending it to a HOSE backend can only ever fail. An existing watchlist with symbols on the wrong market is
repaired on load.

**Resting the pointer on a row floats a detail card off it**, at once rather than after AppKit's
one-to-two-second tooltip delay:

```
VNINDEX                                      1,704.68
Index     ▁▂▃▂▄▅▄▆                  ▲ +24.06 (+1.43%)
VCB   ┌──────────────────────────────────────────────────┐
HOSE  │ Ceiling    58,400      P/E                12.99  │
      │ Floor      50,800      P/B                 2.04  │
      │ Reference  54,600      Updated         just now  │
      │ Volume       207k                                │
      └──────────────────────────────────────────────────┘
BTCUSDT                                     64,310.01
```

The card is drawn over the panel, not in it — opening it moves nothing. It used to be laid out under its
row, and that made pointing at a price a way of pushing every price below it downwards. It goes under the
row where there is room and above it where there isn't, which is what the bottom row of the list gets; the
placement is `Sources/Core/DetailCardLayout.swift`, and the reason a row cannot place it itself is at the top
of `View/Panel/DetailCardOverlay.swift`.

An index drops the band and the ratios; a crypto pair shows `24h open` instead of `Reference` and gets no
valuation at all. The card is suppressed in edit mode, where it would cover the reorder chevrons the pointer
is on its way to.

**P/E and P/B are computed from the price on screen**, not taken ready-made from the feed. SSI reports a
P/E of 14.23 for VCB on an EPS of 4,210 — which implies a price of 59,900, while the board that same minute
quoted 54,600. Printing 14.23 under 54,600 invites the reader to divide the two, get 12.97, and disbelieve
the panel. So only the per-share figures are kept and the ratios are recomputed; see
`Sources/Core/Fundamentals.swift` for how the book value is recovered from the feed's own numbers. A
loss-making company shows no P/E rather than a negative multiple.

Every size in the panel goes through `Theme` in `View/Design/Theme.swift`, which multiplies by
`Theme.scale` (currently `1.5`). Change that one constant to resize the whole panel: scaling the fonts alone
would clip the columns, so widths, padding and spacing scale with them. The menu-bar label is not
affected — a status item is capped at the menu bar's own height, so its text cannot grow with the panel,
which is why `View/MenuBar/MenuBarStyle.swift` holds its own unscaled tokens.

Prices are shown **in full, never abbreviated or rounded** — the menu bar and the panel call the same
`PriceFormat.price` in `Core/PriceFormat.swift`, so they cannot disagree about what an instrument costs.
That costs width: about 125pt per pinned symbol with the percentage shown. Turn off *Show change % in the
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
| VN fundamentals | `iboard-api.ssi.com.vn/statistics/company/financial-indicator?symbol=VCB` | EPS and the P/E–P/B pair the book value is recovered from. Cached for the ICT day. |

The VPS and SSI endpoints are the JSON services behind those brokers' own public web boards. They need no
key and are community-known rather than formally documented, so treat them as something that can change
without notice — `Tools/probe.sh` exists to tell you quickly when it has.

The fundamentals feed was picked by elimination, all checked live on 2026-07-30: the VPS board this app
already calls carries 57 fields and not one valuation ratio; TCBS's `tcanalysis` paths answer 404; Fireant
returns 401 without a token; VNDIRECT's `finfo` host times out through a TLS-inspecting proxy; and SSI's own
`financial-ratio` and `company-info` paths are 404 while `financial-indicator` is not. An index, an unknown
ticker and a company with no filings all answer `200` with `data: null`, which is why "no ratios" is a
normal result here rather than an error.

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

`Sources/` is split by layer, and the layers only depend downwards:
`View` → `Store` → `Reader` → `Core`, with `System` and `Update` off to the side.

```
build_app.sh                   the VERSION line, compile, bundle, embed Sparkle, sign, relaunch
release.sh                     cut a tagged release with a .dmg on GitHub, then bump
fetch_sparkle.sh               vendor the pinned Sparkle framework + tools (gitignored)
update_appcast.sh              EdDSA-sign a .dmg and add it to appcast.xml
appcast.xml                    the Sparkle feed, served raw from GitHub
Package.swift + run_tests.sh   unit tests over Sources/Core; they do NOT build the app
Sources/
  Core/                        the pure layer — Foundation only, and the only code the tests compile
    Market.swift               the two venues; inferring one from a ticker; Ticker.isIndex
    Quote.swift                the shape every source normalises into; PriceBand and its arrow
    WatchedSymbol.swift        one configured row: its id, its menu-bar alias, its venue line
    MarketHours.swift          HOSE session windows, and the status line that explains them
    PriceFormat.swift          every number → the string on screen
    Fundamentals.swift         EPS and book value → P/E and P/B at the live price
    QuoteDetail.swift          the hover card's label/value rows, per kind of instrument
    DetailCardLayout.swift     where that card floats: under the row, above it, or over the chrome
    WatchlistRepair.swift      refile a symbol stored under a market that cannot serve it
    MenuBarLabel.swift         what the menu bar says, as an Equatable value
  Reader/                      the venues
    QuoteSource.swift          the protocol both implement, and QuoteError
    HTTPClient.swift           shared URLSession + lenient JSON number coercion
    VNQuoteSource.swift        VPS board + TradingView UDF history
    CryptoQuoteSource.swift    Binance ticker + klines
    FundamentalsSource.swift   SSI financial-indicator, cached for the ICT day
  Store/                       the observable state the UI binds to
    QuoteReader.swift          cadence, fan-out, last-good-quote store, add-time validation
    Watchlist.swift            the user's symbols, persisted to UserDefaults
  System/                      AppInfo, LoginItem, PollingTimer
  Update/                      Sparkle wrapper + the compact update window
  View/
    Design/Theme.swift         the design tokens: scale, spacing, sizes, type
    Design/BandStyle.swift     band → colour, in both SwiftUI and AppKit spellings
    Design/CardStyle.swift     the hover card's palette — light on both themes, on purpose
    Design/MeasuredHeight.swift  .measuringHeight(into:) — how the panel sizes its scroll area
    Design/AppKitBridges.swift   which screen the popover is on; thin overlay scrollers
    MenuBar/MenuBarGlyph.swift   bakes the coloured status-bar NSImage
    MenuBar/MenuBarStyle.swift   the glyph's own (unscaled) tokens
    Panel/TickerPopover.swift    the panel's layout and the scroll decision
    Panel/DetailCardOverlay.swift  draws the hovered row's card over the panel, not in it
    Panel/                       PanelHeader, SymbolList, QuoteRow, Sparkline,
                                 QuoteDetailCard, AddSymbolField, SettingsFooter
  App/StockBarApp.swift        NSStatusItem + NSPopover, entry point
Tests/StockBarCoreTests/       76 tests over Sources/Core
Tools/probe.sh                 exercises the data layer from the command line
Tools/uisnap.sh                renders the popover to a PNG (no Screen Recording permission needed)
```

Two structural rules are worth knowing before adding anything:

- **`Sources/Core` is pure** — Foundation only, no network, no `UserDefaults`, no AppKit or SwiftUI, no
  `ObservableObject`. `run_tests.sh` greps for violations and fails the run, so it is enforced rather
  than merely documented. Derivation belongs there, where it can be tested; effects belong outside it.
- **The panel is sized only through `Theme`.** No raw point values or `.system(size:)` in
  `Sources/View/Panel`. Everything is scaled by `Theme.scale`, so a literal at a call site is one element
  that silently stops matching the rest of the panel.

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

The generated notes end with the `xattr -dr com.apple.quarantine` step from *Installing a downloaded
release* above, because the uploaded `.dmg` is ad-hoc signed and every downloader will hit Gatekeeper
without it.

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

The probe compiles the app's own Core/Reader/Store layers and the menu-bar glyph, so what it prints — and
the PNG it renders — is what the app itself would produce. It excludes only `App`, `Update` and
`View/Panel`, the three directories that would pull in `@main` or Sparkle.

There is also a unit suite, which covers the derivation the probe can only show you:

```bash
./run_tests.sh                            # all 53
./run_tests.sh --filter PriceFormat       # one suite
```

It compiles `Sources/Core` only. That directory is kept free of I/O and live objects precisely so the
suite is deterministic — `run_tests.sh` greps for forbidden imports and fails before running a single
test if something impure has moved in. A green run therefore says something about the formatting, the
band classification, the session gate and the menu-bar label, and nothing at all about the fetch paths:
that is what the probe is for.

To look at the panel itself:

```bash
./Tools/uisnap.sh /tmp/panel.png          # dark
./Tools/uisnap.sh /tmp/panel-light.png light
STOCKBAR_UI_EDIT=1 ./Tools/uisnap.sh /tmp/edit.png          # the edit-mode row layout
STOCKBAR_UI_HOVER=VCB ./Tools/uisnap.sh /tmp/hover.png      # the detail card, opened
STOCKBAR_UI_WATCHLIST=VCB,MBB,HPG,FPT ./Tools/uisnap.sh /tmp/long.png   # append real tickers
```

`uisnap` hosts the real `TickerPopover` in a window and caches its display into a PNG. It exists because
`screencapture` of the actual panel fails here without Screen Recording permission, which would leave
every layout change unverifiable from a terminal. The environment variables reach states the tool can't
otherwise click or point its way into: `STOCKBAR_UI_EDIT` turns on edit mode, `STOCKBAR_UI_HOVER=VCB` opens
one row's detail card, and `STOCKBAR_UI_WATCHLIST` appends symbols so a list long enough to scroll can be
rendered — the shipped default is four rows, which never reaches the cap. None is ever set for the app
itself.

Two caveats. `Bundle.main` is the tool, not `StockBar.app`, so the header renders the version as `dev`;
check the real value against `Info.plist`. And `cacheDisplay` does not capture an `NSSwitch`'s on-state
tint, so a switch that is on renders with a grey track — the tool cannot confirm switch colour.

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
