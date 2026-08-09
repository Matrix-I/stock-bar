# StockBar — notes for working in this repo

## Build and test

```bash
./build_app.sh              # compile + bundle + sign + relaunch StockBar.app
./build_app.sh --no-launch  # same, without relaunching
./run_tests.sh              # unit tests — use this, NOT a bare `swift test`
./Tools/probe.sh            # hit the real upstreams and print what came back
./Tools/uisnap.sh /tmp/p.png  # render the real popover to a PNG
./Tools/makeicon.sh         # regenerate AppIcon.icns from BrandMark
```

There is no Xcode project and no SwiftPM app target. `build_app.sh` runs `swiftc -O` over every `.swift`
file under `Sources/` as a single module and links Sparkle. Only the Command Line Tools are needed; a full
Xcode install is not. `run_tests.sh` exists because SwiftPM cannot locate swift-testing under the CLT by
itself — its header explains the three flags. `Package.swift` is for tests only and `build_app.sh` never
reads it.

Tests use swift-testing (`import Testing`, `@Suite`, `@Test`, `#expect`), not XCTest — the CLT ships the
former and not the latter.

## Where new code goes

`Sources/` is split by layer, and the dependencies only point downwards:

```
View  →  Store  →  Reader  →  Core          (System and Update sit off to the side)
```

- **`Core`** — pure derivation. Foundation only: no network, no `UserDefaults`, no AppKit or SwiftUI, no
  `ObservableObject`, and nothing that reads the wall clock without being handed it. **This is the only
  directory the tests compile**, and `run_tests.sh` greps it for violations and fails the run, so the rule
  is enforced rather than merely documented. A new file here needs no manifest edit — the target is the
  directory.
- **`Reader`** — one type per feed, plus the shared `URLSession` and a router per market that draws on
  several of them (`WorldQuoteSource`, `VNQuoteSource`). Not every type here is a `QuoteSource`:
  `InvestingBarSource` answers only for bars, and the missing conformance is what stops it being asked
  for a price. Nothing here holds published state.
- **`Store`** — the two `ObservableObject`s the UI binds to (`QuoteReader`, `Watchlist`). Cadence,
  caching, persistence.
- **`System`** — OS integration that isn't a data source: login item, polling timer, bundle version.
- **`Update`** — Sparkle. Isolated in its own directory so `Tools/probe.sh` can exclude it by path and
  stay runnable when `Frameworks/` hasn't been fetched.
- **`View/Design`** — the design system (see below). **`View/MenuBar`** — the baked status-bar image.
  **`View/Panel`** — the SwiftUI popover, one file per region.
- **`App`** — the `NSStatusItem`/`NSPopover` shell and `@main`. Wiring only.

The menu-bar label is the worked example of the split:

1. `Core/MenuBarLabel.swift` decides *what to say* — strings and bands, from the watchlist and the quote
   cache. Pure, `Equatable`, tested.
2. `View/MenuBar/MenuBarGlyph.swift` decides *how it looks* — one `NSAttributedString` drawn into a
   non-template `NSImage`.
3. `App/StockBarApp.swift` only compares the new label with the last one and hands it over.

Derivation left inside a view or an app delegate cannot be reached by any test, and this app's shipped
bugs have all been that shape: crypto pairs filed under the wrong market, a cache key missing a field, an
index losing its quote after 23:00. Each printed something believable.

## The design system

Everything in the panel is sized through `Theme` (`Sources/View/Design/Theme.swift`) and coloured through
`BandStyle` — plus `CardStyle` for the detail card, whose fill is the app's own `windowBackgroundColor`,
which means its hairline and shadow are the entire difference between a card and a gap in the list. Its
header records the two palettes that were tried and rejected; read it before changing one value of the
four. **No raw point values and no `.system(size:)` in `Sources/View/Panel`.**

`Design/BrandMark.swift` is the app's mark as a path, and it has two consumers at wildly different sizes:
`Tools/makeicon.sh` compiles it to render `AppIcon.icns`, and `MenuBarGlyph` strokes it at 14pt when
nothing is pinned. It must therefore stay free of `Theme`, of SwiftUI and of the panel's types — the icon
tool links it as a two-file build. Exporting a PNG of the mark and drawing that instead is the regression
to watch for: it costs the small size its crispness and gives the two consumers separate artwork to drift.

The panel renders at `Theme.scale` (1.5×) and the settings block at a further `Theme.settingsScale` (0.8×).
Because widths, padding and type all scale together, a literal at a call site is one element that quietly
stops matching the rest — which is how a 66pt symbol column ended up unable to hold `BTCUSDT`. Add a named
token instead; a value that appears twice is a value that will eventually be changed in one place only.

`Theme.Space.panelH` in particular is read both by the padding and by the scroll-height arithmetic in
`TickerPopover`. That is the pair that drifted before: with the padding applied outside the `ScrollView`
the overlay scroller was drawn on top of the change figures.

`MenuBarStyle` is deliberately NOT scaled by `Theme.scale` — the menu bar's height is fixed at 22pt by the
system.

The detail card is drawn by the **panel**, over the finished layout, and not by the row it describes — see
`View/Panel/DetailCardOverlay.swift` for the anchor-preference seam and `Core/DetailCardLayout.swift` for
where it lands. Moving it back into the row's own stack is the regression to watch for: it compiles, it looks
right in a screenshot, and it turns asking about a price into a way of pushing every price below it down the
panel. `uisnap` reports the panel height, and the card states must report the same one as `plain`.

**A row is a click target, and the card it opens is the only thing a click on a row does.** It was hover
once; clicking means the card can be read without holding the pointer still, and it means the card has to be
closable from the same place it was opened (click the row again) and has to be cleared when the panel closes
— the popover's view tree is built once and outlives every showing of it, so a stale selection reopens as a
card nobody asked for. Two things follow that are easy to undo by accident. The overlay keeps
`allowsHitTesting(false)`: with it on, the GeometryReader covering the panel swallows every click meant for a
row, which is a total and silent failure. And nothing inside a row may be selectable text — selectable text
claims the mouse-down for a drag-selection of its own, so `.textSelection(.enabled)` on the price (which is
where it used to be) makes the gesture fail on the biggest target in the row.

## Conventions

- **Comments explain why, not what**, and at length where the reason isn't recoverable from the code —
  most files open with a header arguing for their own existence, and tests state the failure they guard
  against. Match that density; don't strip it.
- **Commit subjects** are `type(scope): imperative summary`; bodies are prose paragraphs wrapped at 94
  columns. No bullet lists or ASCII tables in commit bodies.
- **The app version lives only in `build_app.sh`.** Between releases the short version carries a
  `-SNAPSHOT` suffix; `CFBundleVersion` stays a plain numeric triple, because Sparkle compares that key
  against the appcast. `release.sh` is the only thing that rewrites the line.
- **Releases go out through `gh` as the `Matrix-I` account** — there are two GitHub accounts on this
  machine.
- **`Frameworks/` holds a signed Sparkle bundle.** It is gitignored and fetched by `fetch_sparkle.sh`.
  Don't `cd` into it (that breaks codesign paths) and don't commit it.
- **VN prices are real VND in the model.** The VPS board reports equities in thousands and indices in
  points; the scaling happens once, in `VNQuoteSource`. Getting it wrong is a 1000× error on screen.
- **An alert is the app's only output that interrupts somebody, so its rules are pure and tested.**
  `Core/PriceAlert.swift` owns both: fire once then disarm, and rearm only past a half-percent margin.
  Neither is checkable by looking — telling "fires once" from "fires every minute" takes an hour of
  watching a real price sit on a real threshold — and the cost of getting it wrong is a permission the
  user revokes permanently. `AlertEngine.evaluate` returns the updated watchlist alongside the firings
  because a rearm changes state while announcing nothing; dropping that write is what silently turns
  "once" into "every minute".
- **`QuoteReader.history` merges two sources and a feed always wins.** Fetched bars where a feed has
  them, `PriceLog`'s recorded series where none exists (SJC, USDVND, GOLDGAP). Merged in the one computed
  property rather than at the three call sites, so a row cannot draw a fetched chart in one place and a
  recorded one in another. The recorder keeps a point only when the price CHANGES — a rate sheet polled
  all day is hundreds of readings of four values, and storing observations instead of changes fills the
  buffer with a flat line. **And never more than one point per half hour**, because that change filter is
  no filter at all for `GOLDGAP`: it is arithmetic over a world spot price that moves every minute, so it
  differs at every poll, filled the whole buffer in about two hours and rewrote the stored blob sixty times
  an hour doing it. The floor is measured on `PriceLog.lastObserved` — **when the app looked** — and not on
  the point's own stamp, because `GOLDGAP.asOf` is the oldest of its three inputs and therefore PNJ's
  publication time, which stands still all afternoon while the gap moves; spacing by that records one point
  a day and calls it a chart. Two clocks in one function is the thing to preserve here.
- **`VPSQuoteSource` has two board paths and they differ on purpose.** `fetchQuotes` drops a stock whose
  `lastPrice` is 0 (a watched row must never render as `0` and −100%); `fetchBoardRows` keeps it, because
  breadth must count an untraded stock or the denominator every ratio is measured against silently shrinks.
  Counting HOSE through the price path gave 365 constituents and zero untraded where the floor had 404 and
  39 — both render perfectly and only one is true. Reach for `fetchBoardRows` whenever you are COUNTING
  rather than DRAWING.
- **The portfolio total is the only thing here that adds two rows together, so it is built out of
  refusals.** `Currency.of(symbol:market:)` names every row's unit — the Nikkei is yen, and folding it in
  as dollars is a 150× error that still renders plausibly — and `Portfolio.total` excludes what it cannot
  convert AND counts the exclusions, because a total quietly missing a position reads as a complete
  answer. It converts through the `USDVND` row the panel draws, never a private rate, and inherits the age
  of its stalest input including that rate.
- **`Currency.of` returns nil, and the feed outranks it.** It first shipped defaulting the unknown case to
  `.usd`, which reopened the exact hole the type was cut to close: `.world` is not a table of five indices
  but a bucket served by Yahoo, which forwards any ticker it knows and prices each listing in that
  listing's own currency, so `7203.T` arrives at 2,980 **yen** through the very code path whose comment
  promises the yen mistake cannot happen. Hence `Quote.currency`, read from `meta.currency` — the one
  statement of a row's unit that cannot disagree with the price it came in — with the table as fallback
  and nil meaning *leave this row out and say so*. The same rule downgrades crypto: only a stablecoin-quoted
  pair is dollars, because ETHBTC prints in bitcoin. Adding a market or a feed without answering "what is
  this priced in, and who says so" is the regression to watch for.
- **Three separate ways a held row misses the total, and all three are drawn.** Unconvertible currency
  (`excluded`), quote not arrived (`unpriced`), and no average cost typed (`withoutBasis`). The third is
  the subtle one: its value is known and belongs in `value`, its return is not and must stay out of
  `measured`/`cost`. `Portfolio` therefore carries **two** value figures, and `profit` is `measured - cost`
  and never `value - cost` — the latter reported a basis-less position's entire market value as profit, and
  the `cost > 0` guard did not catch it because that guard only fires when NO position has a basis. One
  unfilled row mixed with one real one drew ▲ +308.00% in green. Note the shape of the test that missed it:
  it only ever checked the all-zero case, and the mixed case is where the guard stops covering.
- **A holding refuses to answer more often than it answers.** `Core/Holding.swift` returns nil for both
  profit figures unless quantity AND average cost are positive: with a basis of zero the profit equals the
  whole market value, which renders as an enormous gain on a position whose cost has simply not been typed
  in yet. Units are the instrument's own everywhere — shares, coins, lượng, each against its own currency
  — and nothing in that file converts. If a portfolio total is ever added, it is the place that converts,
  and it needs its own answer for a stale `USDVND`.
- **A new field on `WatchedSymbol` must be decoded with `decodeIfPresent`.** A property default does NOT
  make a Codable key optional — the synthesised `init(from:)` still requires it — so adding `alerts`
  briefly made every previously stored row undecodable, and `WatchlistCoding` correctly carried them all
  as foreign and showed the shipped defaults. Nothing was lost and nothing was visible. That is why the
  type now has a hand-written `init(from:)`.
- **`.vietnam` is a bucket of venues too, and one of its rows is not fetched at all.** `VNQuoteSource` is a
  router over `DomesticIndex.listing(for:)`: the VPS board serves the exchange rows, PNJ quotes the SJC gold
  bar and Vietcombank the dollar. Anything unlisted goes to the board, never the other way — PNJ answers with
  its own product list whatever it is asked, so a stray symbol sent there comes back with somebody else's
  gold price rather than an honest miss. `GOLDGAP` is **derived**: `QuoteReader` computes it in `apply`, from
  `lastGood` rather than from the batch just fetched, because its three inputs are on two different clocks and
  most ticks refetch only some of them. A derived row pulls its inputs into the plan (`DerivedQuote.tracked`),
  which is also what `apply`'s prune and `applyCadence` read — reading the visible list in either place drops
  the inputs the moment they arrive, or idles the poll while they are still moving.
- **Three constants stand between the gold gap and a plausible wrong number.** A lượng is 37.5 g, a troy
  ounce 31.1034768 g, and PNJ quotes in thousands of dong per chỉ (ten to the lượng). Get any one wrong and
  the gap is still a seven-figure VND number that renders without complaint — there is no appearance to check
  it against, which is why `GoldUnit` is pinned by test and by mutant. Verify a new domestic feed's unit the
  way this one was verified: convert the world price into it and check the plain 999.9 ring lands a few
  percent above, not a hundredfold away.
- **`.vietnam` no longer implies HOSE's clock.** The domestic boards keep shop hours (08:30–17:00, Mon–Sat,
  no lunch break) and carry an eight-hour staleness allowance, and `Quote.isFromCurrentSession` exempts them
  from the midnight rebase — applied to a row with no reference, that rebase manufactures the very flat
  reading the missing reference exists to avoid. `WatchedSymbol.hasPerShareFundamentals` is the matching
  guard on the other side: SSI answers for "SJC" with some other company's figures.
- **Foreign flow is shares, never value.** The board's `fBValue`/`fSValue` pair has a unit that does not
  reconcile — measured against a real session it is neither dong nor thousands of dong — so
  `Quote.foreignNet` is built from `fBVol`/`fSVolume` only. A number whose unit cannot be verified is not
  shown; this is the gold-gap rule applied to a smaller number.
- **`.world` is a bucket of venues AND of feeds, not one of either.** `Market` picks a source, but that
  source is now `WorldQuoteSource`, a router: Yahoo's chart endpoint serves the Dow, the Nasdaq, the Nikkei
  and the dollar index, while TradingView's scanner serves spot gold, because Yahoo carries no spot gold at
  any spelling and its COMEX front-month future quotes ~60 dollars above it. Routing is one field on the
  listing (`WorldIndex.feed`), so a new upstream stays one row in the table plus the source. Unlisted symbols
  go to Yahoo — it will take an arbitrary ticker, the scanner wants an `EXCHANGE:SYMBOL` it already knows.
  **Price and bars route separately** (`WorldIndex.bars`), because the scanner with the best gold price
  publishes no series at all: gold's sparkline comes from investing.com pair 68, spot XAU/USD, while its
  price stays on TradingView. That is allowed where mixing feeds for a price is not — a sparkline is
  normalised inside its own box and draws a shape, so two honest quotes of one OTC market agree; two prices
  on one row would not, and one of them would be invisible. Verify a new bars pair against the price feed
  before wiring it: investing.com's own search returns 8830 for "gold", which is the COMEX future.
  The trading day likewise differs per symbol, via `WorldIndex.listing`. So `isOpen(.world)` is the union —
  and since spot gold and ICE trade overnight, that union is now true at every hour of a weekday. It is therefore useless as a gate:
  **both** `QuoteReader.shouldFetch` and `isStale` ask `isOpen(_:symbol:)` per row instead. Reading it per
  market is a regression in each direction — every Dow row greyed out for the length of a Tokyo session, and
  once a gold row existed the Dow, the Nasdaq and the Nikkei were refetched every minute all night. Every
  window comes from the system time-zone database, unlike Vietnam's fixed +07:00: ET moves an hour twice a
  year, so 09:30 there is 20:30 ICT in summer and 21:30 in winter and no fixed offset is right all year.
  Adding an instrument is a row in `WorldIndex.all`; adding a *venue* is also a window here.
- **A venue can be slow on purpose, and staleness has to know.** ICE holds free data back by ten minutes,
  so a dollar-index quote is ALWAYS ~600 seconds old while its venue trades (measured 602s, against 0.9s for
  ^DJI; Yahoo's `exchangeDataDelayedBy` is null and no help). Against the bare `activeInterval * 1.5` the row
  rendered permanently dimmed — a working feed reporting itself broken — so `WorldExchange.feedDelay` is
  added to the allowance. It is set to fifteen minutes, not the measured
  ten: the feed publishes minute bars and the app polls once a minute, so the true lag sweeps to ~660s and a
  tighter bound lets a healthy row flicker. Adding a venue whose data is delayed and leaving `feedDelay` at
  zero is the regression to watch for — it looks like nothing at all in a screenshot taken while the market
  is shut, because a closed venue is never stale.
- **A change figure belongs to a session, and the day turns at ICT midnight.** Both feeds keep serving the
  finished session's numbers until the next one starts, so `QuoteReader.quotes` runs every quote through
  `Quote.rebasedForPendingSession(at:)`, which rebases a VN quote onto its own last close once the day has
  rolled past it — flat, no band, price intact. Two regressions to watch for. Doing it at fetch time instead:
  nothing is fetched between the close and the next open, so there would be no event at midnight to trigger
  it, and the correction has to be a function of the read. And testing the clock instead of the reading's
  `asOf`: at 09:05 the board is mid-auction with no matched price, so the previous day's change would come
  back for the ten minutes until a real quote lands.
- **A build must never delete what it cannot read.** The watchlist is one JSON blob in `UserDefaults`, and
  two copies of this app share it: the installed one in `~/Applications`, which is what the login item
  launches, and the development build in `~/stock-bar`. The installed one is routinely the OLDER of the two,
  so it will meet rows from a market it has never heard of. It used to decode the array in one go, so one
  such row threw, `try?` read the throw as "no watchlist", and a dozen symbols were replaced by the four
  shipped defaults and then saved over. `Core/WatchlistCoding.swift` decodes row by row and carries anything
  it cannot account for — a foreign row, an unknown field on a readable row — straight back into the next
  write. Re-encoding straight from `[WatchedSymbol]` is the regression to watch for: it compiles, it round
  trips, and it silently drops everything a later version added. Note the limit of the fix, too: it protects
  against the *next* downgrade, never against a build already installed, so an old copy still has to be
  replaced rather than reasoned with.
- **`@Published` publishes from `willSet`.** Inside a `sink` on `watchlist.$symbols`, reading
  `watchlist.symbols` gives the list from BEFORE the edit — which is why `QuoteReader` takes the edited list
  from the publisher and passes it into `refresh(using:)`. Reading the property instead planned the fetch
  without the symbol just added, so a new row sat on a dash until the next tick; it looked intermittent only
  because an add during an in-flight fetch is deferred by `refreshQueued` and runs once the property has
  caught up. `Tools`-style harnesses that seed the watchlist before constructing the reader (uisnap does)
  cannot reproduce it — the order has to be reader first, add second.
- **Anything derived from a price is derived from OUR price.** The fundamentals feed hands over a
  ready-made P/E and P/B computed against a snapshot of its own — for VCB that snapshot was 59,900 against
  a board price of 54,600. Only its per-share figures are kept; the ratios are recomputed in
  `Core/Fundamentals.swift`. Reaching for the vendor's `pe`/`pb` because they are right there is the
  regression to watch for: the panel would then show two prices for one instrument again, one of them
  implicit.

## Verifying a change

`./run_tests.sh` covers `Sources/Core` and says nothing about the fetch paths or the views. So:

- **Anything outside Core** — compile the whole tree the way `build_app.sh` does:
  ```bash
  swiftc -parse-as-library -target "$(uname -m)-apple-macos13.0" -typecheck $(find Sources -name '*.swift') -F Frameworks -module-cache-path .build/modulecache
  ```
  The `-module-cache-path` is needed under a sandbox that denies the default clang cache location.
- **A data-layer change** — `./Tools/probe.sh`, which prints the price, reference, change, band and the
  exact menu-bar string for each symbol.
- **A layout change** — `./Tools/uisnap.sh`. **Run it with the network blocked and the PNG is
  byte-identical between runs**, because every row renders a dash: that turns it into a real regression
  check. Capture the four states before touching anything, then compare `md5` after:
  ```bash
  ./Tools/uisnap.sh /tmp/plain.png dark
  ./Tools/uisnap.sh /tmp/light.png light
  STOCKBAR_UI_EDIT=1 ./Tools/uisnap.sh /tmp/edit.png dark
  STOCKBAR_UI_CARD=VCB ./Tools/uisnap.sh /tmp/card.png dark
  STOCKBAR_UI_WATCHLIST=VCB,MBB,FPT,HPG,SSI,VIC,VHM,MSN,GAS,CTG,BID,TCB,ACB,STB ./Tools/uisnap.sh /tmp/long.png dark
  ```
  The long one matters: with 18 rows the list exceeds the cap and the *scrolling* branch is what gets
  rendered. A refactor that claims to preserve the layout should produce identical hashes across all of
  them. The card one needs the network to show its P/E and P/B, so it is the one state that is not
  byte-deterministic — check it by eye, and check that the height it prints matches `plain`, because the
  card floats and must cost the panel nothing. Force it onto the last symbol as well as the first: those
  are the two placements (below the row, and flipped above it).

  A row's DIMMING is only visible with the network up and its venue trading, which is why a delayed feed can
  ship looking fine: `STOCKBAR_UI_WATCHLIST=GOLD,DXY,DJI ./Tools/uisnap.sh /tmp/w.png dark` is what caught
  the ICE delay, and only because it was run at 00:23 ICT with New York open. The same command is the check
  for a row that has quietly lost its data source, since a feed swap shows up here as a missing sparkline or
  a price that jumped by a basis.

When a change is *meant* to preserve behaviour, prove it rather than asserting it. Four matching PNG
hashes is a proof; "it still compiles" is not.

Two guards deserve a mutant before you trust a test of them: break the code so the guard no longer fires
and confirm the suite goes red. The band epsilon in `Quote.band` and the lunch-break hole in `MarketHours`
have both been checked that way. Revert a mutant with `git checkout` only if the file is committed —
otherwise it takes the uncommitted work with it.
