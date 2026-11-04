import AppKit
import SwiftUI
import BuddyCore

/// What the banner's corner says about the weather, worked out by `DailyBannerManager`.
struct BannerCaption: Equatable {
    /// “RAINY · 12°”, or nil when there's no weather to show.
    var weather: String?
    /// The reading's age and source, for the tooltip.
    var detail: String?
    /// The reading is old and being refreshed: shown, but quieter.
    var isStale = false
    /// Looking up the weather for the first time.
    var isLoading = false
}

/// Today's illustrated banner — Figma: Banner/Card (Coco-2 › Banners). The art (one of six
/// little places, in today's light and weather) fills a 22 pt rounded card with a 1 pt ink rim;
/// over it, the Make file's text: the done count, Coco's note, the light and weather, and what's
/// left. The card is always 320 : 152, so its height never changes with the task count.
struct IllustratedBannerView: View {
    let state: BannerState
    var caption = BannerCaption()
    /// Animate changes (off for snapshots and the first appearance).
    var animated = true

    static let aspect: CGFloat = 320 / 152

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / 320
            ZStack(alignment: .topLeading) {
                BannerSceneRepresentable(state: state, animated: animated)
                BannerTextLayer(state: state, caption: caption, s: s)
            }
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Sky.Radius.card, style: .continuous))
        // The rim is painted above the clipped art so its corners stay whole (as in the Make file).
        .overlay(RoundedRectangle(cornerRadius: Sky.Radius.card, style: .continuous).strokeBorder(Sky.ink, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isImage)
    }

    private var accessibilityText: String {
        let p = state.progress
        let count = p.isEmpty ? "No tasks yet." : "\(p.done) of \(p.total) tasks done."
        let weather = caption.weather.map { ", \($0.lowercased())" } ?? ""
        return "\(count) \(p.note) \(state.time.label)\(weather). \(state.banner.title): \(state.banner.accessibilityDescription)"
    }
}

/// The Make file's text, placed in the art's own units (320 wide) so it scales with the card.
/// The count grows to the right and pushes Coco's note along with it, and the note gives way
/// to the right-hand column, so nothing overlaps whatever the numbers are.
private struct BannerTextLayer: View {
    let state: BannerState
    let caption: BannerCaption
    let s: CGFloat

    /// The text colour on the night art (Figma: the Banner collection's `text` in Night mode).
    static let nightInk = Color(hex: 0xFFF5DC)
    private var ink: Color { state.time == .night ? Self.nightInk : Sky.ink }
    /// The Sky/Banner text styles are set at the 350-pt card; scale them with the card.
    private var k: CGFloat { s * 320 / 350 }

    var body: some View {
        let p = state.progress
        BannerTextLayout(s: s) {
            // 1. The count: “3/5” (or just “0” before there's a list).
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(p.done)")
                    .skyType(SkyType.bannerCount.scaled(k))
                    .contentTransition(.numericText())
                if !p.isEmpty {
                    Text("/\(p.total)")
                        .skyType(SkyType.bannerTotal.scaled(k))
                        .contentTransition(.numericText())
                }
            }
            .monospacedDigit()
            .fixedSize()
            // 2. Coco's note.
            Text(p.note)
                .skyType(SkyType.bannerNote.scaled(k))
                .opacity(0.78)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            // 3. Light · weather (· temperature).
            Text(cornerLabel)
                .skyType(SkyType.bannerCorner.scaled(k))
                .lineLimit(1)
                .fixedSize()
                .opacity(caption.isStale ? 0.6 : 1)
                .help(caption.detail ?? "")
            // 4. What's left.
            Text(p.remainingLabel)
                .skyType(SkyType.bannerRemaining.scaled(k))
                .opacity(0.72)
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(ink)
        .animation(.easeInOut(duration: 0.35), value: p)
        .animation(.easeInOut(duration: 0.6), value: state.time)
    }

    private var cornerLabel: String {
        var parts = [state.time.label]
        if let weather = caption.weather { parts.append(weather) }
        else if caption.isLoading { parts.append("LOOKING OUTSIDE…") }
        return parts.joined(separator: " · ")
    }
}

/// Lays out the banner text where the Make file puts it. Units are the art's (×`s` for points).
private struct BannerTextLayout: Layout {
    let s: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 4 else { return }
        func y(_ sceneY: CGFloat) -> CGFloat { bounds.minY + (sceneY + 44) * s }
        let right = bounds.minX + 301 * s
        let count = subviews[0], note = subviews[1], corner = subviews[2], remaining = subviews[3]

        // The count sits on its baseline at y −10.
        let countSize = count.sizeThatFits(.unspecified)
        let countBaseline = count.dimensions(in: .unspecified)[.firstTextBaseline]
        count.place(at: CGPoint(x: bounds.minX + 18 * s, y: y(-10) - countBaseline), proposal: .unspecified)

        // Light · weather hangs from y −32; what's left sits on its baseline at y −12. Both end at x 301.
        let cornerSize = corner.sizeThatFits(.unspecified)
        corner.place(at: CGPoint(x: right - cornerSize.width, y: y(-32)), proposal: .unspecified)
        let remainingSize = remaining.sizeThatFits(.unspecified)
        let remainingBaseline = remaining.dimensions(in: .unspecified)[.firstTextBaseline]
        remaining.place(at: CGPoint(x: right - remainingSize.width, y: y(-12) - remainingBaseline), proposal: .unspecified)

        // Coco's note from x 78 (or just past a long count), giving way to the right-hand column.
        let columnX = right - max(cornerSize.width, remainingSize.width)
        let noteX = max(bounds.minX + 78 * s, bounds.minX + 18 * s + countSize.width + 10 * s)
        let noteWidth = max(20 * s, columnX - 10 * s - noteX)
        note.place(at: CGPoint(x: noteX, y: y(-32)), proposal: ProposedViewSize(width: noteWidth, height: nil))
    }
}

/// Hosts the Core Animation scene in SwiftUI.
private struct BannerSceneRepresentable: NSViewRepresentable {
    let state: BannerState
    let animated: Bool

    func makeNSView(context: Context) -> BannerSceneView {
        let view = BannerSceneView()
        view.show(state, animated: false)
        return view
    }

    func updateNSView(_ view: BannerSceneView, context: Context) {
        view.show(state, animated: animated)
    }
}

extension SkyType {
    /// The same style at `k` times its size and tracking (the banner scales with its card).
    func scaled(_ k: CGFloat) -> SkyType {
        SkyType(family: family, face: face, weight: weight, size: size * k, tracking: tracking * k, uppercase: uppercase)
    }
}
