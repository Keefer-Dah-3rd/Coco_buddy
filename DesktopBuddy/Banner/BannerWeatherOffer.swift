import SwiftUI

/// Under the banner, once: an offer to match the scene to the real weather, saying why and what
/// it uses before anything is asked. “Allow” brings up the system's location prompt; “Not now”
/// hides this for good (Settings › Weather still has it). If location then turns out to be off,
/// it says so and points at the other way in: a city. Figma: Banner/Weather Offer.
struct BannerWeatherOffer: View {
    let model: AppModel

    enum Kind { case offer, locationOff }

    /// What to show right now, if anything.
    static func kind(for model: AppModel) -> Kind? {
        if !model.weather.isOn { return model.preferences.weatherOfferDismissed ? nil : .offer }
        return model.weather.status == .locationDenied ? .locationOff : nil
    }

    var body: some View {
        if let kind = Self.kind(for: model) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: kind == .offer ? "cloud.sun" : "location.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(Sky.accentText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind == .offer ? "Match the scene to your weather?" : "Location is off for \(Buddy.name).")
                        .skyType(.bannerOfferTitle)
                        .foregroundStyle(Sky.ink)
                    Text(kind == .offer ? "Approximate location, just for the forecast."
                                        : "Add a town or city in Settings instead.")
                        .skyType(.bannerOfferDetail)
                        .foregroundStyle(Sky.muted)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(kind == .offer ? "Allow" : "Settings") {
                    if kind == .offer { Task { await model.weather.turnOnWithMacLocation() } }
                    else { model.openSettings() }
                }
                .buttonStyle(SkyButtonStyle(kind: .accent, compact: true))
                Button {
                    if kind == .locationOff { model.weather.turnOff() }
                    model.preferences.weatherOfferDismissed = true
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(SkyRoundStyle(size: 22, fill: .clear, tint: Sky.faint))
                .help("Not now — Settings › Weather has this any time")
                .accessibilityLabel("Not now")
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Sky.Radius.field, style: .continuous).fill(Sky.accentPale))
            .transition(.opacity)
        }
    }
}
