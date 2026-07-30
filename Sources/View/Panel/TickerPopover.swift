// TickerPopover.swift — the panel that drops down from the menu-bar item.
//
// This file is the layout only: a pinned header, a symbol list that scrolls once it outgrows the screen,
// and a pinned footer. The pieces are in their own files beside it (PanelHeader, SymbolList,
// AddSymbolField, SettingsFooter), each owning the state only it needs.
//
// The one piece of real logic here is the scroll decision, and it is here because it is a question about
// the whole panel: the list may take whatever the screen can spare once the pinned header and footer have
// had their share. See MeasuredHeight for why the heights have to be measured rather than asked for.

import SwiftUI
import AppKit

struct TickerPopover: View {
    @ObservedObject var reader: QuoteReader
    @ObservedObject var watchlist: Watchlist
    @ObservedObject var updater: Updater
    let checkForUpdates: () -> Void
    let quitAction: () -> Void

    /// Edit mode. The environment check exists so Tools/uisnap.sh can render this state: an edit row
    /// carries four controls beside a price, which is exactly the layout worth checking, and it is
    /// unreachable from a snapshot tool otherwise. The variable is never set for the app itself, so this
    /// is always false in a real launch.
    @State private var editing = ProcessInfo.processInfo.environment["STOCKBAR_UI_EDIT"] != nil

    /// visibleFrame height of the display the popover is actually shown on, reported by
    /// PanelScreenReporter. Seeded with the menu-bar screen so the first layout pass already has a
    /// sensible number to cap against.
    @State private var screenHeight: CGFloat = TickerPopover.initialScreenHeight
    @State private var listHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            // Render un-scrolled by default — identical to the plain auto-sizing stack this panel used to
            // be — so the very first layout pass always has a well-defined height and the popover opens at
            // its natural size. Only once the list has measured taller than the room the screen can spare
            // does it switch to a ScrollView, and then with a concrete height.
            if listHeight > maxListHeight {
                ScrollView(.vertical) {
                    list.background(OverlayScrollerConfigurator())
                }
                .frame(height: maxListHeight)
            } else {
                list
            }

            footer
        }
        // Only the vertical padding belongs to the panel. The horizontal padding is applied per region —
        // including inside the scroll area — so the ScrollView spans the panel's full width and the
        // overlay scroller has a gutter of its own to sit in. With the padding out here the scroll view
        // ended exactly where the content did, and the scroller was drawn on top of the change figures.
        .padding(.vertical, Theme.Space.panelV)
        .frame(width: Theme.Size.panelWidth)
        // The detail card is drawn here, over the finished panel, rather than by the row it belongs to: it
        // has to be able to overlap the header, the footer and the rows either side of its own, and a row
        // inside the ScrollView can draw none of that. Attached after the frame and the padding so the
        // height it is placed against is the panel's real one. See DetailCardOverlay.
        .overlayPreferenceValue(DetailAnchorKey.self) { anchor in
            DetailCardOverlay(reader: reader,
                              anchor: anchor,
                              listTop: Theme.Space.panelV + headerHeight,
                              listBottomInset: Theme.Space.panelV + footerHeight)
        }
        .background(PanelScreenReporter { screenHeight = $0 })
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(isFetching: reader.isFetching,
                        editing: $editing,
                        onRefresh: reader.refresh)
            Divider().padding(.vertical, Theme.Space.divider)
        }
        .padding(.horizontal, Theme.Space.panelH)
        .measuringHeight(into: $headerHeight)
    }

    private var list: some View {
        SymbolList(reader: reader, watchlist: watchlist, editing: editing)
            .padding(.horizontal, Theme.Space.panelH)
            .measuringHeight(into: $listHeight)
    }

    /// The add field, the divider and the settings. Outside the scroll area on purpose: on a list long
    /// enough to scroll, adding a symbol would otherwise mean scrolling to the bottom to reach the field,
    /// and Quit would be just as far away.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            if editing {
                AddSymbolField(reader: reader, watchlist: watchlist)
                    .padding(.top, Theme.Space.addTop)
            }
            Divider().padding(.vertical, Theme.Space.divider)
            SettingsFooter(reader: reader,
                           updater: updater,
                           checkForUpdates: checkForUpdates,
                           quitAction: quitAction)
        }
        .padding(.horizontal, Theme.Space.panelH)
        .measuringHeight(into: $footerHeight)
    }

    /// The tallest the symbol list may get: whatever the screen can spare once the pinned header, the
    /// pinned footer and the panel's own outer padding have taken their share.
    private var maxListHeight: CGFloat {
        let chrome = headerHeight + footerHeight + Theme.Space.panelV * 2
        return max(Theme.Size.minListHeight, screenHeight * Theme.panelHeightFraction - chrome)
    }

    /// Best guess before the popover's window exists: the display that owns the menu bar, identified by
    /// its frame origin sitting at (0,0) in AppKit's global space. That is stable, unlike the order of
    /// `NSScreen.screens` or `NSScreen.main`, which follows keyboard focus.
    private static var initialScreenHeight: CGFloat {
        let menuBarScreen = NSScreen.screens.first { $0.frame.origin == .zero }
            ?? NSScreen.screens.first
            ?? NSScreen.main
        return menuBarScreen?.visibleFrame.height ?? 800
    }
}
