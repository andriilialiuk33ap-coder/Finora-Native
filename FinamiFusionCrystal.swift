import SwiftUI
import UIKit

/// A single presentation of the existing five TabView destinations.
struct FinamiFusionCrystal: View {
    @Binding var selection: Int
    let homeTitle: String
    let accent: Color
    var lowEffects = false
    var onReselect: (Int) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.scenePhase) private var phase
    private var opaque: Bool { reduceTransparency || lowEffects || ProcessInfo.processInfo.isLowPowerModeEnabled || phase != .active }
    private var tabs: [(String, String)] {
        [(homeTitle, "house"), ("Операції", "arrow.left.arrow.right"), ("Рахунки", "wallet.pass"), ("Звіти", "chart.bar.xaxis"), ("Ще", "ellipsis")]
    }
    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs.indices, id: \.self) { index in tile(index) }
        }
        .padding(6)
        .background {
            let shape = RoundedRectangle(cornerRadius: FinamiDesignPolicy.navigationCorner, style: .continuous)
            if opaque { shape.fill(Color(uiColor: .secondarySystemBackground)) }
            else { shape.fill(.regularMaterial) }
        }
        .overlay { RoundedRectangle(cornerRadius: FinamiDesignPolicy.navigationCorner).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1).allowsHitTesting(false) }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Нижня навігація")
    }
    private func tile(_ index: Int) -> some View {
        let selected = selection == index
        let tint = selected || index == 2 ? accent : Color.secondary
        let label = tabs[index].0
        let shape = RoundedRectangle(cornerRadius: FinamiDesignPolicy.navigationTileCorner, style: .continuous)
        return Button {
            guard selection != index else { onReselect(index); return }
            if reduceMotion || opaque { selection = index }
            else { withAnimation(.easeInOut(duration: 0.16)) { selection = index } }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tabs[index].1)
                    .font(.system(size: index == 2 ? 23 : 20, weight: .medium))
                    .frame(height: 25)
                    .foregroundStyle(tint)
                Text(label)
                    .font(.caption2.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(dynamicType.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
                Capsule().fill(selected ? accent : .clear).frame(width: 13, height: 3)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 1)
            .frame(maxWidth: .infinity, minHeight: dynamicType.isAccessibilitySize ? FinamiDesignPolicy.navigationAccessibleHeight : FinamiDesignPolicy.navigationTileHeight)
            .background(shape.fill(selected ? accent.opacity(scheme == .dark ? 0.20 : 0.12) : Color.primary.opacity(0.045)))
            .overlay { shape.strokeBorder(selected ? accent : Color.primary.opacity(0.13), lineWidth: 1).allowsHitTesting(false) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("qa.tab.\(index)")
    }
}
