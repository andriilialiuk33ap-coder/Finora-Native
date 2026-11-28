import SwiftUI

// Pure decoration: no amounts, no chart, no animation loop.
struct FinamiAuroraSurface: ViewModifier {
    @EnvironmentObject private var s: Store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let tint: Color
    func body(content: Content) -> some View {
        let p = s.db.preferences ?? .init()
        let tint = finamiDesignAccent(p.designAccent) ?? self.tint
        let radius = CGFloat(p.designRadius.map { FinamiDesignPolicy.radius($0) } ?? 23)
        let shape = RoundedRectangle(cornerRadius: radius)
        content.background {
            shape.fill(finamiDesignSurface(FinamiDesign(rawValue: p.design ?? "Signature") ?? .signature, scheme: scheme))
                .overlay {
                    if p.designLowEffects != true && !reduceTransparency {
                        ZStack(alignment: .topTrailing) {
                            LinearGradient(colors: [tint.opacity(0.025), tint.opacity(scheme == .dark ? 0.25 : 0.12)], startPoint: .bottomLeading, endPoint: .topTrailing)
                            RadialGradient(colors: [tint.opacity(0.17), .clear], center: .topTrailing, startRadius: 0, endRadius: 150)
                            ForEach(0..<5) { index in
                                Circle().strokeBorder(tint.opacity(0.10), lineWidth: 1).frame(width: CGFloat(90 + 26 * index), height: CGFloat(90 + 26 * index)).offset(x: 46, y: -65)
                            }
                        }.clipShape(shape).accessibilityHidden(true).allowsHitTesting(false)
                    }
                }.overlay { shape.strokeBorder(tint.opacity(0.22), lineWidth: 1) }
        }
    }
}
