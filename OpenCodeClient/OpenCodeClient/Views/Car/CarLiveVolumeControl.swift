import SwiftUI

#if os(iOS)
import MediaPlayer
import UIKit

struct CarLiveVolumeControl: View {
    var body: some View {
        HStack(spacing: DesignSpacing.sm) {
            Image(systemName: "speaker.fill")
                .font(DesignTypography.meta.weight(.semibold))
                .foregroundStyle(DesignColors.Neutral.textSecondary)
                .accessibilityHidden(true)
            CarLiveSystemVolumeSlider()
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .fixedSize(horizontal: false, vertical: true)
                .clipped()
            Image(systemName: "speaker.wave.3.fill")
                .font(DesignTypography.meta.weight(.semibold))
                .foregroundStyle(DesignColors.Neutral.textSecondary)
                .accessibilityHidden(true)
        }
        .frame(height: 44)
        .accessibilityIdentifier("car-live-volume-row")
    }
}

private struct CarLiveSystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> CarLiveVolumeSliderView {
        let view = CarLiveVolumeSliderView(frame: CGRect(x: 0, y: 0, width: 240, height: 32))
        configure(view)
        return view
    }

    func updateUIView(_ uiView: CarLiveVolumeSliderView, context: Context) {
        configure(uiView)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: CarLiveVolumeSliderView,
        context: Context
    ) -> CGSize? {
        CGSize(width: proposal.width ?? 240, height: 32)
    }

    private func configure(_ view: CarLiveVolumeSliderView) {
        view.showsVolumeSlider = true
        view.clipsToBounds = true
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
    }
}

private final class CarLiveVolumeSliderView: MPVolumeView {
    private var tinted = false

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 32)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let target = bounds
        for subview in subviews {
            let nested = subview.subviews.compactMap { $0 as? UISlider }.first
            if let slider = subview as? UISlider ?? nested {
                if subview is UISlider, slider.frame != target {
                    slider.frame = target
                }
                if !tinted {
                    slider.minimumTrackTintColor = UIColor(red: 0.231, green: 0.510, blue: 0.965, alpha: 1)
                    slider.maximumTrackTintColor = UIColor.secondaryLabel.withAlphaComponent(0.35)
                    tinted = true
                }
            } else if !subview.isHidden {
                subview.isHidden = true
                subview.isUserInteractionEnabled = false
                subview.accessibilityElementsHidden = true
            }
        }
    }
}
#endif
