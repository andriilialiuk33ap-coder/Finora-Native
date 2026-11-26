import SwiftUI

// Local, semantic colours keep the components legible in all ten presets.
struct FinamiIconTile: View {
    @Environment(\.colorScheme) private var scheme
    var icon: String
    var tint: Color
    var side: CGFloat = 44
    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.26)
            .fill(scheme == .dark ? Color(red:0.045,green:0.045,blue:0.055) : tint.opacity(0.10))
            .overlay { RoundedRectangle(cornerRadius:side*0.26).strokeBorder(tint.opacity(scheme == .dark ? 0.24 : 0.10),lineWidth:1) }
            .overlay { Image(systemName:icon).font(.system(size:side*0.40,weight:.semibold)).foregroundStyle(tint) }
            .frame(width:side,height:side).accessibilityHidden(true)
    }
}
struct FinamiAccountSurface: View {
    @Environment(\.colorScheme) private var scheme
    var tint: Color
    var radius: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius:radius).fill(Color(uiColor:.secondarySystemGroupedBackground))
            .overlay { RoundedRectangle(cornerRadius:radius).fill(LinearGradient(colors:[tint.opacity(scheme == .dark ? 0.13 : 0.08),tint.opacity(0.015)],startPoint:.topLeading,endPoint:.bottomTrailing)) }
            .overlay { RoundedRectangle(cornerRadius:radius).strokeBorder(tint.opacity(0.16),lineWidth:1) }
    }
}
struct FinamiDashboardSurface: ViewModifier {
    var isAccounts: Bool
    var tint: Color
    var template: String?
    @ViewBuilder func body(content: Content) -> some View {
        if isAccounts { content } else { content.modifier(FinamiCardStyle(tint: tint, template: template)) }
    }
}
struct FinamiSectionTitle: View {
    var title: String
    var subtitle: String
    var icon: String
    var tint: Color
    var body: some View {
        HStack(spacing: 12) {
            FinamiIconTile(icon: icon, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
struct FinamiEmptyCard: View {
    var title: String
    var detail: String
    var icon: String
    var body: some View {
        VStack(spacing: 12) {
            FinamiIconTile(icon: icon, tint: .teal, side: 60)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(24).frame(maxWidth: .infinity).modifier(FinamiCardStyle(tint: .teal))
    }
}
struct FinamiReportPanel<Content: View>: View {
    @EnvironmentObject private var s: Store
    var title: String
    var icon: String
    var tint: Color
    @Binding var hidden: Bool
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { FinamiIconTile(icon: icon, tint: tint, side: 36); Text(title).font(.headline); Spacer(minLength: 4)
                Button { hidden.toggle() } label: { Image(systemName: hidden ? "eye.slash" : "eye").frame(minWidth: 44, minHeight: 44) }.buttonStyle(.plain).disabled(s.privateAmounts).accessibilityLabel(hidden ? "Показати суми" : "Приховати суми")
            }
            if hidden { Text("••••").font(.title.bold()).accessibilityLabel("Суми приховано") } else { content() }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).modifier(FinamiCardStyle(tint: tint))
    }
}
struct FinamiMenuGroup<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(0.7).foregroundStyle(.secondary).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 6) { content() }
                .padding(12).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                .overlay{RoundedRectangle(cornerRadius:18).strokeBorder(Color.primary.opacity(0.07),lineWidth:1)}
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FinamiMenuLabel: View {
    var title: String
    var icon: String
    var color: Color
    var body: some View {
        HStack(spacing: 10) {
            IzanamiLabel(title: title, icon: icon, color: color)
            Spacer(minLength: 2)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}

// Category artwork is decorative. Transaction direction remains visible in the signed amount.
func finamiOperationIcon(_ operation: Operation) -> String {
    if operation.kind == .transfer { return "arrow.left.arrow.right" }
    if operation.kind == .income { return "arrow.down.left" }
    if operation.kind != .expense { return operation.kind.incoming ? "arrow.down.left" : "arrow.up.right" }
    let name = operation.category.lowercased()
    let icons: [(String, String)] = [("продукт", "cart"), ("кава", "cup.and.saucer"), ("харч", "fork.knife"), ("транспорт", "bus"), ("таксі", "car"), ("пальн", "fuelpump"), ("авто", "car"), ("здоров", "cross.case"), ("житл", "house"), ("комунал", "house"), ("підпис", "repeat"), ("покуп", "bag"), ("зв’яз", "iphone"), ("подорож", "airplane"), ("подар", "gift"), ("освіт", "book"), ("розваг", "gamecontroller")]
    return icons.first(where: { name.contains($0.0) })?.1 ?? "arrow.up.right"
}
