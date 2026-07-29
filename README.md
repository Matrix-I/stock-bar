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
Sources/
  App/StockBarApp.swift        NSStatusItem + NSPopover, glyph cache, entry point
  Model/Quote.swift            the shape every source normalises into; PriceBand
  Reader/QuoteSource.swift     shared URLSession + lenient JSON number coercion
  Reader/VNQuoteSource.swift   VPS board + TradingView UDF history
  Reader/CryptoQuoteSource.swift  Binance ticker + klines
  Reader/QuoteReader.swift     cadence, fan-out, last-good-quote store
  Support/                     Formatting, MarketHours, Watchlist, PollingTimer, LoginItem
  View/MenuBarGlyph.swift      bakes the coloured status-bar NSImage
  View/TickerPopover.swift     the panel: rows, sparklines, settings
Tools/probe.sh                 exercises the data layer from the command line
```

`NSStatusItem` rather than SwiftUI's `MenuBarExtra`, for two reasons: the label must be
multi-coloured and `MenuBarExtra` renders its label as a monochrome template, and `MenuBarExtra`'s
presentation state desynchronises when its window is closed from outside, producing the familiar
"first click does nothing" bug.

## Debugging

```bash
./Tools/probe.sh                          # the shipped watchlist
./Tools/probe.sh VCB FPT BTCUSDT          # specific symbols
GLYPH_OUT=/tmp/g.png ./Tools/probe.sh     # also render the real menu-bar label to a PNG
GLYPH_DEMO=1 GLYPH_OUT=/tmp/b.png ./Tools/probe.sh   # render all five band colours
```

The probe compiles the app's own Model/Support/Reader layers, so what it prints is what the app sees.

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
