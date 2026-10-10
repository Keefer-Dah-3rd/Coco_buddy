import SwiftUI

enum CharacterLayout {
    static let artSize: CGFloat = 96
    /// Space above the art box for ear tips, hops and thought bubbles.
    static let headroom: CGFloat = 18
    static let compactScale: CGFloat = 0.7
    static let chipHeight: CGFloat = 18
    static let windowSize = CGSize(width: 124, height: artSize + headroom + 4 + chipHeight + 4)
    /// The character's square art box inside the window at full size (window coords, origin bottom-left).
    static let artFrame = CGRect(x: (windowSize.width - artSize) / 2, y: chipHeight + 8, width: artSize, height: artSize)
    /// The view the character is drawn into: the art box plus headroom.
    static let artViewFrame = CGRect(x: artFrame.minX, y: artFrame.minY, width: artSize, height: artSize + headroom)
    static let chipFrame = CGRect(x: 0, y: 2, width: windowSize.width, height: chipHeight + 2)
}

/// The tiny LCD countdown under the character while a session runs.
/// SwiftUI is fine here: it only changes once a second.
struct CountdownChipView: View {
    let model: CharacterModel

    var body: some View {
        ZStack {
            if let countdown = model.countdown {
                HStack(spacing: 4) {
                    if countdown.isPaused {
                        Image(systemName: "pause.fill").font(.system(size: 7, weight: .black))
                    } else if countdown.isBreak {
                        Text("BRK").font(Theme.mono(9, .bold))
                    }
                    Text(countdown.text)
                        .font(Theme.mono(11, .semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(Theme.phosphor.opacity(countdown.isPaused ? 0.6 : 1))
                .padding(.horizontal, 6)
                .frame(height: 17)
                .background(Theme.lcd, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.black.opacity(0.35)))
                .opacity(model.isDimmed ? 0.6 : 1)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.2), value: model.countdown == nil)
    }
}
