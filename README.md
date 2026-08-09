# StockBar — Vietnamese stocks, crypto and world markets in the macOS menu bar

A menu-bar ticker that refreshes about once a minute. Vietnamese equities and indices (HOSE/HNX) come
from VPS's public market-data backends; crypto comes from Binance's public REST API; the Dow, the Nasdaq
Composite, the Nikkei 225 and the US dollar index come from Yahoo Finance's chart endpoint; spot gold comes
from TradingView's scanner, the only one of those that carries it, with its sparkline borrowed from
investing.com because the scanner publishes no bars; the domestic SJC gold bar comes from PNJ's retail
board and the dollar rate from Vietcombank's published sheet. No API key, no account, no Python — the app
talks to all of them over `URLSession`.

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

With **nothing pinned** it shows the app's mark instead — the same rising line as the app icon, drawn as a
template so it tints and inverts like the system's own glyphs. It used to be `— —`, which is the state
StockBar is in but says nothing about which app you would click to change it. A symbol that *is* pinned but
has no quote yet still shows as text with a dash: an icon there would hide a symbol you asked for and make
a broken feed look like an idle app.

**Past midnight a Vietnamese row reads flat until its session opens.** The board goes on serving the
finished session's closing price against that session's reference until it rolls over the next morning, so
without this a stock sat there claiming `+3.48%` at two in the morning and all weekend — yesterday's answer
to today's question. From ICT midnight the change is rebased onto the last close, which is precisely the
reference HOSE will publish for the coming session: the price stays, the percentage reads `0.00%`, and the
row is the board's own tham chiếu yellow until something actually trades. The card's Ceiling and Floor drop
out with it, because a ±7% band belongs to the reference it was cut from. Crypto is untouched — Binance
quotes against a rolling 24 hours, not a session, so it has no midnight to observe.

The pencil turns on edit mode, which gives each row pin / move up / move down / remove. The sparkline
hides while editing to make room — four controls plus a chart and a price don't fit on one row without
truncating the change. Pinned symbols are drawn in watchlist order and only the first four get a slot,
so reordering is also how you choose which ones appear.

The symbol list **scrolls** once it grows past what the screen can hold — 90% of the display's usable
height, measured on whichever display the popover actually opened on. Below that the panel is exactly as
tall as its contents, so a four-row watchlist has no empty space. The header and the footer never scroll:
Refresh, the add field, the settings and Quit stay reachable at any list length.

**Five world instruments are carried alongside the VN and crypto rows**: `DJI` (Dow Jones), `IXIC` (Nasdaq
Composite), `NI225` (Nikkei 225), `GOLD` (spot XAU/USD) and `DXY` (the US dollar index). They are typed like
any other symbol — the picker's `World` setting is only a hint, since none of those names can belong to
another venue — and `N225`, `^N225`, `DJIA`, `NASDAQ`, `XAU`, `XAUUSD`, `GC=F`, `USDX` and `DX-Y.NYB` are
accepted as spellings of the same five. Each row's second line names its venue (`New York`, `Tokyo`, `Spot`,
`ICE`) rather than saying `Index`, because when a price hasn't moved in hours the useful thing to know is
which clock it is on. `DOW` is deliberately *not* a spelling of the Dow — it is a real NYSE ticker (Dow
Inc.) — and neither `GC` nor `DX` is accepted, being short enough that a Vietnamese listing could yet claim
them.

**`GOLD` is the spot price, and it needs a second feed to get.** Yahoo carries no spot gold at any spelling
(`XAUUSD=X`, `XAU=X` and `GCUSD=X` all answer 404), and the COMEX front-month future it *does* carry quotes
some sixty dollars above spot on the cost of carry — right for a futures trader, wrong next to a gold page.
So this one row comes from TradingView's scanner, which returns exactly what TradingView draws as `GOLD`,
to the cent and in real time.

**Its sparkline comes from a third place, and that is a different kind of borrowing.** The scanner publishes
no series at all, so the bars are asked of investing.com's chart API — pair `68`, which is spot XAU/USD and
not the COMEX future their own search hands you for "gold". Same instrument, checked rather than assumed:
pair 68's last minute closed 4,309.87 while the scanner read 4,309.43 and Swissquote bid 4,309.02, all
inside a dollar, where pair 8830 printed 4,369.12 at that moment. Mixing feeds for a *price* would put two
numbers on one row with one of them implicit, which is the thing this codebase has a rule against; a
sparkline is normalised inside its own box and carries no axis, so what it draws is a shape, and two honest
quotes of the same OTC market agree about the shape. The one visible difference from the other rows: that
endpoint returns a fixed 288 one-minute bars, so gold's sparkline is a rolling **last 4h48m** rather than
the session — a gold session is twenty-three hours long, so a session-wide line would be mostly last night.

`WorldQuoteSource` routes per listing on both axes: `WorldIndex.feed` says who has the price, `WorldIndex.bars`
says who has the shape and normally answers "the same one". `DXY` is an index proper, computed by ICE against
a basket of six currencies, and stays wholly on Yahoo.

Their sessions are gated per venue, in the venue's own time zone: 09:30–16:00 New York, 09:00–15:30 Tokyo
with its lunch break, and — for gold and the dollar index — an overnight week that opens on Sunday evening
in New York and runs to Friday afternoon, pausing once a day (17:00–18:00 ET for gold, 18:00–19:30 at ICE).
That means Wall Street is polled from 20:30 ICT in summer and 21:30 in winter, which is why every one of
these windows comes from the system time-zone database rather than from a fixed offset the way Vietnam's
does. The overnight edges come from the feeds themselves rather than from a venue's website, since what
matters is when a new print can be expected.

**The dollar index arrives ten minutes late, and the app expects that.** ICE holds free data back, so a
healthy `DXY` quote is always ~600 seconds old (measured: 602s, against 0.9s for the Dow). Judged against
the ordinary staleness allowance the row rendered permanently dimmed — a working feed reporting itself
broken — so the venue's delay is added to the allowance, and the detail card says `Updated 10m ago` instead
of pretending otherwise. Gold does not need it: the scanner streams.

**Three Vietnamese rows are not on any exchange**: `SJC` (the gold bar, in VND per lượng), `USDVND`
(Vietcombank's selling rate) and `GOLDGAP` — *chênh lệch*, how much more a lượng of SJC costs than the same
weight of world spot gold. The gap is the reason the other two are here, and it is the first row in this app
whose value is **computed rather than fetched**: SJC's price minus `GOLD × 1.2057 × USDVND`, where 1.2057 is
a lượng (37.5 g) in troy ounces (31.1034768 g). Watching `GOLDGAP` alone works — a derived row pulls its
three inputs into the fetch plan, and they are cached without being drawn.

Their venue lines say `PNJ`, `VCB` and `SJC − spot`, and the first of those is a deliberate admission:
sjc.com.vn is unreachable from behind a Cloudflare Gateway, so the bar is quoted through a retailer and the
row says whose price it is. PNJ's board is in **thousands of dong per chỉ**, which the response never states
— the check that settled it was the plain 999.9 ring, which carries almost no premium and read 4.9% over the
converted world price, exactly where a ring should sit.

**The gap's detail card shows its working.** Clicking `GOLDGAP` lists the three numbers it was born from —
SJC, the spot price converted to VND per lượng, and the dollar rate — plus the premium as a percentage of
the converted price, all through the same conversion helper the gap itself uses, so the card and the value
cannot disagree. A number nobody publishes is only trustworthy while the subtraction behind it stays
checkable.

`SJC` and `GOLDGAP` show a **bare price with no change figure**, because PNJ publishes no previous close and
ignores a date parameter; inventing a baseline for them would be worse than omitting one. `USDVND` does have
one — VCB's endpoint takes a date and carries its sheet forward across weekends and holidays, so yesterday's
rate is always one request away. None of the three has a sparkline: they are step functions published a
handful of times a day, with no series behind them.

They keep **shop hours, not HOSE's** — 08:30–17:00 ICT, Monday to Saturday, with no lunch break, since a
jeweller does not close its board to eat. Their staleness allowance is eight hours rather than ninety
seconds, for the same reason the dollar index needs ten minutes: against the ordinary allowance a board that
publishes once at 11:00 would render permanently dimmed by 11:02. `USD` and `VND` are deliberately *not*
accepted spellings — `USD` is a live UPCOM ticker and `VND` is VNDirect on HOSE — so the aliases are
`VANGSJC`, `GOLDSJC`, `TYGIA` and `GAP`.

**Any row can carry price alerts.** Edit mode gives each row a bell; opening it reveals two fields, `≥`
and `≤`, and crossing either posts a macOS notification. A bell on the venue line marks a row that has one
set, and its tooltip says what the threshold is and whether it has already gone off.

Two rules make them usable rather than maddening, and both are the difference between an alert and a
nuisance. An alert **fires once and then goes quiet**, rearming only when the price has come back through
the line by half a percent — a price resting on its threshold crosses it back and forth all session, and
firing each time would spend the app's notification permission in an afternoon. And an alert **set on a
price that has already crossed starts disarmed**: asking to be told when gold passes 4,300 while it reads
4,341 means the next time, not the number on screen while you type.

What no rule can fix, and what the editor says out loud instead: **an alert is only checked while StockBar
is running and the row's own venue is open.** There is no server behind this app. A threshold on spot gold
can fire overnight because spot gold trades overnight; the same threshold on a HOSE ticker cannot fire
before nine in the morning. Permission is requested when the first alert is created, not at launch — a
menu-bar ticker that demands notification access before it has anything to notify about gets refused, and
the refusal is remembered.

**A row can also carry a position.** The same editor strip takes a quantity and an average cost, and the
detail card then adds Qty, Avg cost, Value and P/L — the profit signed and grouped, with the percentage
beside it. Units are the instrument's own throughout: shares for a HOSE ticker, coins for a Binance pair,
lượng for the gold bar, with the cost in whatever currency that row is already quoted in. Nothing here
converts anything, which is what keeps the arithmetic honest.

Half a position shows half the rows. A quantity typed before the cost has been dug out gives Qty and
Value; **P/L stays absent until there is a basis to measure against**, because with a cost of zero the
"profit" is the entire market value and would render as a spectacular gain on a position nobody has
finished entering.

**There is deliberately no portfolio total.** Summing these means adding dong to dollars, and while the app
could now convert — `USDVND` is a row it carries — a total is a different feature with a different failure
mode: one stale rate quietly re-pricing everything you own. A per-row profit is useful on its own in a way
half a total is not.

**Adding a symbol checks it with the venue first.** Neither upstream rejects a bad ticker outright — the
Vietnamese board just omits the row and Binance answers `400` — so a typo used to join the list and render
a dash forever, indistinguishable from a feed that was down. The add field now asks for a quote before
committing the row, and says which of the two happened. The market picker is only a hint: a ticker ending
in a stablecoin quote (`BTCUSDT`, `ETHUSDC`) is filed under Binance whatever the picker says, because
sending it to a HOSE backend can only ever fail. An existing watchlist with symbols on the wrong market is
repaired on load. The row it adds is fetched immediately rather than at the next tick — and the list the
fetch is planned from comes from the change notification itself, because `@Published` publishes from
`willSet` and reading the property back at that moment still returns the list from before the edit.

**An older copy of the app cannot delete a newer one's watchlist.** The list is one JSON blob in
`UserDefaults`, and it used to be decoded in one go: a single row carrying a market the running build had
never heard of made the whole decode throw, which was silently read as "no watchlist" and answered with the
four shipped defaults — over the top of a dozen real symbols. It is a live risk rather than a theoretical
one, because an installed copy in `~/Applications` is what the login item launches while development
continues in `~/stock-bar`, so the build that runs at every restart is routinely the older of the two. Rows
are decoded one at a time now, and anything this build cannot account for — a whole row from a later
version, or a field on a row it can otherwise read — is carried through untouched to the next save. An older
build shows less than a newer one wrote; it no longer deletes the difference. See
`Sources/Core/WatchlistCoding.swift`.

**Clicking a row floats a detail card off it**, and the card stays until it is dismissed — click the same
row again to close it, or another row to move it there:

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
row, and that made asking about a price a way of pushing every price below it downwards. It goes under the
row where there is room and above it where there isn't, which is what the bottom row of the list gets; the
placement is `Sources/Core/DetailCardLayout.swift`, and the reason a row cannot place it itself is at the top
of `View/Panel/DetailCardOverlay.swift`. Because it is an annotation drawn on top and takes no clicks of its
own, a click on the card itself reaches the row underneath and moves the card there.

An index drops the band and the ratios; a crypto pair shows `24h open` instead of `Reference` and gets no
valuation at all. The card closes with the panel, so reopening the panel never restores a card nobody asked
for, and it is suppressed in edit mode, where it would cover the reorder chevrons being clicked towards.

The price is deliberately not selectable text. The row is a click target now, and selectable text inside one
claims the mouse-down for a drag-selection of its own — on the largest and most obvious thing to aim at.

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
| VN equities | `bgapidatafeed.vps.com.vn/getliststockdata/VCB,FPT,…` | One request covers every ticker. Returns last price, reference, ceiling, floor, volume — plus the day's high/low, the volume-weighted average (`avePrice`) and foreign buy/sell volume (`fBVol`/`fSVolume`), the remaining foreign room (`fRoom`) and the best bid/ask (`g1`/`g4`, spelled `"59.7|2860|i"`), all shown on the detail card. Foreign flow is read in **shares**, never from `fBValue`/`fSValue`: measured against a real session, that pair's unit reconciles with neither dong nor thousands of dong. |
| VN indices | `histdatafeed.vps.com.vn/tradingview/history?resolution=1` | TradingView UDF feed. 1-minute bars, so one request gives both the live value and the sparkline. |
| VN reference | same, `resolution=1D` | Previous session's close. Cached for the day — it only changes overnight. |
| Domestic gold | `edge-api.pnj.io/ecom-frontend/v1/get-gold-price` | PNJ's whole retail board in one request; `masp: "SJC"` is the bar, `giaban` the selling price and `giamua` the buy-back shown as the card's dealer spread. Prices are **thousands of dong per chỉ**, which nothing in the response says — see below. No previous close, and `?date=` is ignored. `updateDate` is a real publication time. |
| USD/VND | `vietcombank.com.vn/api/exchangerates?date=2026-08-09` | The `sell` column. The sheet is carried forward on weekends and holidays, so the previous-day request for the reference never falls in a hole. `UpdatedDate` reads 23:00 on the requested date — in the future during a session — so it is not usable as `asOf`. |
| Crypto | `api.binance.com/api/v3/ticker/24hr?symbols=[…]` | One request covers every pair. Reference is `openPrice` (24h rolling), matching Binance's own UI; `highPrice`/`lowPrice` are the same window's extremes, and `bidPrice`/`askPrice` (+`Qty`) the top of book. |
| Crypto sparkline | `api.binance.com/api/v3/klines?interval=1m&limit=60` | Last hour of 1-minute candles. |
| VN fundamentals | `iboard-api.ssi.com.vn/statistics/company/financial-indicator?symbol=VCB` | EPS and the P/E–P/B pair the book value is recovered from. Cached for the ICT day. |
| World indices | `query1.finance.yahoo.com/v8/finance/chart/%5EDJI?range=1d&interval=1m` | One request per symbol, carrying the live value, the previous close and the minute bars for the sparkline. `range=1d` is load-bearing: at a longer range the previous close is the one before the *range*, not before today. `DX%2DY%2ENYB` works the same way — Yahoo decodes the path segment — and ICE delays it ten minutes. |
| Spot gold | `scanner.tradingview.com/symbol?symbol=TVC%3AGOLD&fields=close,change_abs,volume,high,low,high,low` | Real-time (`update_mode: streaming`). No previous-close field, so the reference is `close - change_abs`. An unknown symbol is a clean 404. `time` is the start of the trading day, not the last print. |
| Spot gold sparkline | `api.investing.com/api/financialdata/68/historical/chart/?period=P1D&interval=PT1M&pointscount=120` | Pair `68` is spot XAU/USD (`8830` is the COMEX future). Requires a `domain-id: www` header — without it, a 500 that reads like an outage. `pointscount` is validated against `{60,70,90,110,120,140,160}` but not honoured: the answer is always the last 288 one-minute bars, rolling. An unknown pair is a 500, not a 404. |

The VPS and SSI endpoints are the JSON services behind those brokers' own public web boards. They need no
key and are community-known rather than formally documented, so treat them as something that can change
without notice — `Tools/probe.sh` exists to tell you quickly when it has.

Two things about the Yahoo endpoint, both established by probing it live on 2026-07-30. **`range=1d` is
load-bearing**: `meta.chartPreviousClose` is the close before the first bar *of the requested range*, so the
same call at `range=5d` returns the close from six sessions ago and produces a plausible, wrong change all
day. And it is **one request per symbol** — the multi-symbol endpoint (`v7/finance/quote`) answers `401`
without a crumb and cookie lifted from the web app. A `User-Agent` is required; with none at all the answer
is `429`.

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
- Every world row is polled — and aged — against **its own** exchange's clock, not against the market as a
  whole. Both directions of that matter: judged by the market, every Dow row greyed out for the length of a
  Tokyo session, and once gold joined the list the market counted as open around the clock, which would have
  refetched the Dow, the Nasdaq and the Nikkei every minute all night for numbers that cannot move.
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
    Market.swift               the three markets; inferring one from a ticker; Ticker.isIndex/canonical
    WorldIndex.swift           the world table: typed name → feed, feed symbol, venue, aliases, delay
    Quote.swift                the shape every source normalises into; PriceBand, its arrow, the reset
    WatchedSymbol.swift        one configured row: its id, its menu-bar alias, its venue line
    MarketHours.swift          session windows for HOSE, New York, Tokyo, spot gold and ICE; the ICT day
    PriceFormat.swift          every number → the string on screen
    Fundamentals.swift         EPS and book value → P/E and P/B at the live price
    QuoteDetail.swift          the detail card's label/value rows, per kind of instrument
    DetailCardLayout.swift     where that card floats: under the row, above it, or over the chrome
    WatchlistCoding.swift      read/write the stored blob, keeping rows a build can't decode
    WatchlistRepair.swift      refile a symbol stored under a market that cannot serve it
    MenuBarLabel.swift         what the menu bar says, as an Equatable value
  Reader/                      the venues
    QuoteSource.swift          the protocol they all implement, and QuoteError
    HTTPClient.swift           shared URLSession + lenient JSON number coercion
    VNQuoteSource.swift        routes a Vietnamese symbol to its venue — one bucket, three upstreams
    VPSQuoteSource.swift       VPS board + TradingView UDF history: the exchange rows
    PNJQuoteSource.swift       PNJ's retail board: the SJC bar, quoted in dong per lượng
    VietcombankQuoteSource.swift  VCB's rate sheet: USD/VND, against the previous day
    CryptoQuoteSource.swift    Binance ticker + klines
    WorldQuoteSource.swift     routes a world symbol to its feed, and its bars to theirs — one bucket, three upstreams
    YahooQuoteSource.swift     Yahoo chart endpoint: quote and sparkline from one response
    TradingViewQuoteSource.swift  TradingView scanner: spot gold, real-time, no bars
    InvestingBarSource.swift   investing.com chart API: gold's bars only, never a price
    FundamentalsSource.swift   SSI financial-indicator, cached for the ICT day
  Store/                       the observable state the UI binds to
    QuoteReader.swift          cadence, fan-out, last-good-quote store, add-time validation
    Watchlist.swift            the user's symbols, persisted to UserDefaults
  System/                      AppInfo, LoginItem, PollingTimer
  Update/                      Sparkle wrapper + the compact update window
  View/
    Design/Theme.swift         the design tokens: scale, spacing, sizes, type
    Design/BandStyle.swift     band → colour, in both SwiftUI and AppKit spellings
    Design/CardStyle.swift     the detail card's palette — the app's own background colour
    Design/BrandMark.swift     the mark, as geometry: the app icon and the empty menu bar draw it
    Design/MeasuredHeight.swift  .measuringHeight(into:) — how the panel sizes its scroll area
    Design/AppKitBridges.swift   which screen the popover is on; thin overlay scrollers
    MenuBar/MenuBarGlyph.swift   bakes the coloured status-bar NSImage
    MenuBar/MenuBarStyle.swift   the glyph's own (unscaled) tokens
    Panel/TickerPopover.swift    the panel's layout and the scroll decision
    Panel/DetailCardOverlay.swift  draws the clicked row's card over the panel, not in it
    Panel/                       PanelHeader, SymbolList, QuoteRow, Sparkline,
                                 QuoteDetailCard, AddSymbolField, SettingsFooter
  App/StockBarApp.swift        NSStatusItem + NSPopover, entry point
Tests/StockBarCoreTests/       150 tests over Sources/Core
Tools/probe.sh                 exercises the data layer from the command line
Tools/uisnap.sh                renders the popover to a PNG (no Screen Recording permission needed)
Tools/makeicon.sh              regenerates AppIcon.icns from BrandMark (the .icns is committed)
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
STOCKBAR_UI_CARD=VCB ./Tools/uisnap.sh /tmp/card.png        # the detail card, opened
STOCKBAR_UI_WATCHLIST=VCB,MBB,HPG,FPT ./Tools/uisnap.sh /tmp/long.png   # append real tickers
```

`uisnap` hosts the real `TickerPopover` in a window and caches its display into a PNG. It exists because
`screencapture` of the actual panel fails here without Screen Recording permission, which would leave
every layout change unverifiable from a terminal. The environment variables reach states the tool can't
otherwise click its way into: `STOCKBAR_UI_EDIT` turns on edit mode, `STOCKBAR_UI_CARD=VCB` opens
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
