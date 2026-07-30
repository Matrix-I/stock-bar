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
- **`Reader`** — one type per venue, plus the shared `URLSession`. Nothing here holds published state.
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
`BandStyle` — plus `CardStyle` for the hover card, whose fill is the app's own `windowBackgroundColor`,
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

The hover card is drawn by the **panel**, over the finished layout, and not by the row it describes — see
`View/Panel/DetailCardOverlay.swift` for the anchor-preference seam and `Core/DetailCardLayout.swift` for
where it lands. Moving it back into the row's own stack is the regression to watch for: it compiles, it looks
right in a screenshot, and it turns pointing at a price into a way of pushing every price below it down the
panel. `uisnap` reports the panel height, and the hover states must report the same one as `plain`.

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
- **A change figure belongs to a session, and the day turns at ICT midnight.** Both feeds keep serving the
  finished session's numbers until the next one starts, so `QuoteReader.quotes` runs every quote through
  `Quote.rebasedForPendingSession(at:)`, which rebases a VN quote onto its own last close once the day has
  rolled past it — flat, no band, price intact. Two regressions to watch for. Doing it at fetch time instead:
  nothing is fetched between the close and the next open, so there would be no event at midnight to trigger
  it, and the correction has to be a function of the read. And testing the clock instead of the reading's
  `asOf`: at 09:05 the board is mid-auction with no matched price, so the previous day's change would come
  back for the ten minutes until a real quote lands.
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
  STOCKBAR_UI_HOVER=VCB ./Tools/uisnap.sh /tmp/hover.png dark
  STOCKBAR_UI_WATCHLIST=VCB,MBB,FPT,HPG,SSI,VIC,VHM,MSN,GAS,CTG,BID,TCB,ACB,STB ./Tools/uisnap.sh /tmp/long.png dark
  ```
  The long one matters: with 18 rows the list exceeds the cap and the *scrolling* branch is what gets
  rendered. A refactor that claims to preserve the layout should produce identical hashes across all of
  them. The hover one needs the network to show its P/E and P/B, so it is the one state that is not
  byte-deterministic — check it by eye, and check that the height it prints matches `plain`, because the
  card floats and must cost the panel nothing. Force it onto the last symbol as well as the first: those
  are the two placements (below the row, and flipped above it).

When a change is *meant* to preserve behaviour, prove it rather than asserting it. Four matching PNG
hashes is a proof; "it still compiles" is not.

Two guards deserve a mutant before you trust a test of them: break the code so the guard no longer fires
and confirm the suite goes red. The band epsilon in `Quote.band` and the lunch-break hole in `MarketHours`
have both been checked that way. Revert a mutant with `git checkout` only if the file is committed —
otherwise it takes the uncommitted work with it.
