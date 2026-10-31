import SwiftUI
import UIKit

/// Leading space reserved by the system window controls in iPadOS windowed
/// apps. The traffic lights do not contribute to the safe area, so custom
/// header bars must inset themselves to keep their controls clear.
private struct WindowControlsLeadingInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var windowControlsLeadingInset: CGFloat {
        get { self[WindowControlsLeadingInsetKey.self] }
        set { self[WindowControlsLeadingInsetKey.self] = newValue }
    }
}

/// Measures the margin region that clears the window controls. The probe must
/// cover the whole window for the layout guide to be resolved in window space.
struct WindowControlsLayoutProbe: UIViewRepresentable {
    @Binding var leadingInset: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(leadingInset: $leadingInset)
    }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onLeadingInsetChange = { [weak coordinator = context.coordinator] inset in
            coordinator?.report(inset)
        }
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        context.coordinator.leadingInset = $leadingInset
    }

    @MainActor
    final class Coordinator {
        var leadingInset: Binding<CGFloat>
        private var pendingInset: CGFloat?

        init(leadingInset: Binding<CGFloat>) {
            self.leadingInset = leadingInset
        }

        func report(_ inset: CGFloat) {
            guard inset != leadingInset.wrappedValue, pendingInset != inset else { return }
            pendingInset = inset
            // `layoutSubviews` can run while SwiftUI is committing an update.
            Task { @MainActor [weak self] in
                guard let self, let inset = self.pendingInset else { return }
                self.pendingInset = nil
                guard inset != self.leadingInset.wrappedValue else { return }
                self.leadingInset.wrappedValue = inset
            }
        }
    }

    final class ProbeView: UIView {
        var onLeadingInsetChange: ((CGFloat) -> Void)?
        private var lastReportedInset: CGFloat?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isOpaque = false
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard #available(iOS 26.0, *), window != nil else { return }

            let guideFrame = layoutGuide(for: .margins(cornerAdaptation: .horizontal)).layoutFrame
            guard !guideFrame.isNull, !guideFrame.isInfinite else { return }

            let inset = max(0, guideFrame.minX - safeAreaInsets.left)
            guard inset != lastReportedInset else { return }
            lastReportedInset = inset
            onLeadingInsetChange?(inset)
        }
    }
}
