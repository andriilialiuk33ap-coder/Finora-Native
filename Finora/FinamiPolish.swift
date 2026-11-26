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
    @EnvironmentObject private var s: Store
    @Environment(\.colorScheme) private var scheme
    var tint: Color
    var radius: CGFloat
    var body: some View {
        let design=FinamiDesign(rawValue:s.db.preferences?.design ?? "Dark Classic") ?? .darkClassic
        let r=s.db.preferences?.designRadius.map { CGFloat(FinamiDesignPolicy.radius($0)) } ?? radius
        RoundedRectangle(cornerRadius:r).fill(finamiDesignSurface(design,scheme:scheme))
            .overlay { if s.db.preferences?.designLowEffects != true { RoundedRectangle(cornerRadius:r).fill(LinearGradient(colors:[tint.opacity(scheme == .dark ? 0.13 : 0.08),tint.opacity(0.015)],startPoint:.topLeading,endPoint:.bottomTrailing)) } }
            .overlay { RoundedRectangle(cornerRadius:r).strokeBorder(tint.opacity(0.16),lineWidth:1) }
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
// A full-width, informative header for every collapsed dashboard section.
struct FinamiCollapsedDashboardCard: View {
    @EnvironmentObject private var s: Store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var typeSize
    var title: String
    var summary: String
    var icon: String
    var tint: Color
    var template: String?
    private var accent: Color {
        finamiDesignAccent(s.db.preferences?.designAccent) ?? tint
    }
    var body: some View {
        HStack(alignment:.center,spacing:12) {
            FinamiIconTile(icon:icon,tint:accent,side:typeSize.isAccessibilitySize ? 44 : 42)
            VStack(alignment:.leading,spacing:4) {
                Text(title).font(.headline).foregroundStyle(.primary).fixedSize(horizontal:false,vertical:true)
                Text(summary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.frame(maxWidth:.infinity,alignment:.leading)
            Image(systemName:"chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).accessibilityHidden(true)
        }
        .padding(.horizontal,14).padding(.vertical,12)
        .frame(maxWidth:.infinity,minHeight:76,alignment:.leading)
        .background {
            if s.db.preferences?.designLowEffects != true && !reduceTransparency {
                LinearGradient(colors:[accent.opacity(scheme == .dark ? 0.03 : 0.01),accent.opacity(scheme == .dark ? 0.14 : 0.06)],startPoint:.bottomLeading,endPoint:.topTrailing)
            }
        }
        .modifier(FinamiCardStyle(tint:accent,template:template))
        .contentShape(Rectangle())
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
    private var collapsed: Bool { (s.db.preferences?.collapsedReports ?? []).contains(icon) }
    private func toggleCollapsed() { s.changeAppearance { p in var ids=Set(p.collapsedReports ?? []);if ids.contains(icon) { ids.remove(icon) } else { ids.insert(icon) };p.collapsedReports=ids.sorted() } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { FinamiIconTile(icon: icon, tint: tint, side: 36); Button { toggleCollapsed() } label: { Text(title).font(.headline).foregroundStyle(.primary).frame(minHeight:44,alignment:.leading) }.buttonStyle(.plain).accessibilityLabel((collapsed ? "Розгорнути " : "Згорнути ") + title); Spacer(minLength: 4)
                Button { hidden.toggle() } label: { Image(systemName: hidden ? "eye.slash" : "eye").frame(minWidth: 44, minHeight: 44) }.buttonStyle(.plain).disabled(s.privateAmounts).accessibilityLabel(hidden ? "Показати суми" : "Приховати суми")
            }
            if collapsed { Button("Розгорнути") { toggleCollapsed() }.font(.caption) }
            else if hidden { Text("••••").font(.title.bold()).accessibilityLabel("Суми приховано") } else { content() }
        }.padding(s.db.preferences?.modernCompactSpacing == true ? 12 : 16).frame(maxWidth: .infinity, alignment: .leading).modifier(FinamiCardStyle(tint: tint))
    }
}
struct FinamiMenuGroup<Content: View>: View {
    @EnvironmentObject private var s: Store
    var title: String
    @ViewBuilder var content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                s.changeAppearance { p in var groups=Set(p.collapsedMenu ?? []);if groups.contains(title) { groups.remove(title) } else { groups.insert(title) };p.collapsedMenu=groups.sorted() }
            } label: {
                HStack { Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(0.7);Spacer();Image(systemName:(s.db.preferences?.collapsedMenu ?? []).contains(title) ? "chevron.down" : "chevron.up") }.foregroundStyle(.secondary).frame(minHeight:44).padding(.horizontal,4).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Згорнути або розгорнути " + title)
            if !(s.db.preferences?.collapsedMenu ?? []).contains(title) {
                VStack(alignment:.leading,spacing:s.db.preferences?.menuCompact == true ? 2 : 6) { content() }
                    .padding(10).modifier(FinamiCardStyle(tint:.teal))
            }
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
