import SwiftUI
import PhotosUI
import UIKit

// User-supplied images stay local; built-in graphic icons are original illustrations, not official logos.
struct FinamiBrandTile: View {
    var name: String
    var icon: String
    var tint: Color
    var side: CGFloat
    var banksOnly = false
    var merchantsOnly = false
    var paymentStyle = false
    @AppStorage("finami.brand.enabled") private var enabled = true
    var body: some View {
        if enabled, let brand = FinamiBrand.match(name, banksOnly: banksOnly, merchantsOnly: merchantsOnly) {
            FinamiBrandImage(brand: brand, side: side)
        } else if paymentStyle {
            FinamiPaymentGlyph(icon: icon, tint: tint, side: side)
        } else {
            FinamiIconTile(icon: icon, tint: tint, side: side)
        }
    }
}
private struct FinamiBrandImage: View {
    let brand: FinamiBrand
    let side: CGFloat
    @AppStorage private var imageData: Data
    init(brand: FinamiBrand, side: CGFloat) {
        self.brand = brand; self.side = side
        _imageData = AppStorage(wrappedValue: Data(), "finami.brand.image." + brand.rawValue)
    }
    var body: some View {
        Group {
            if !imageData.isEmpty, let image = FinamiImageCache.shared.image(imageData) {
                Image(uiImage: image).resizable().scaledToFit().padding(3).background(Color(uiColor: .secondarySystemBackground))
            } else {
                Image("Brand-" + brand.rawValue).resizable().scaledToFit()
            }
        }.frame(width: side, height: side).clipShape(RoundedRectangle(cornerRadius: side * 0.24)).accessibilityHidden(true)
    }
}
struct FinamiBrandSettings: View {
    @AppStorage("finami.brand.enabled") private var enabled = true
    var body: some View {
        List {
            Section { Toggle("Автоматичні бренд-іконки", isOn: $enabled) }
            Section("Банки та сервіси") {
                ForEach(FinamiBrand.allCases) { brand in FinamiBrandSettingRow(brand: brand) }
            }
            Section { Text("Вбудовані графічні іконки працюють без інтернету. Можна додати власне зображення кожного бренду. Зберігається лише на цьому пристрої; фінансовий облік не змінюється.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Brand Icons")
    }
}
private struct FinamiBrandSettingRow: View {
    let brand: FinamiBrand
    @AppStorage private var imageData: Data
    @State private var selection: PhotosPickerItem?
    @State private var failure = false
    init(brand: FinamiBrand) {
        self.brand = brand
        _imageData = AppStorage(wrappedValue: Data(), "finami.brand.image." + brand.rawValue)
    }
    var body: some View {
        HStack {
            FinamiBrandImage(brand: brand, side: 44)
            Text(brand.name)
            Spacer()
            PhotosPicker(selection: $selection, matching: .images) { Image(systemName: "photo").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Обрати логотип " + brand.name)
            if !imageData.isEmpty { Button(role: .destructive) { imageData = Data() } label: { Image(systemName: "trash").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Прибрати власний логотип") }
        }.buttonStyle(.borderless).onChange(of: selection) { item in
            guard let item else { return }
            Task { @MainActor in
                do {
                    guard let data = try await item.loadTransferable(type: Data.self), let jpg = finamiThumbnailJPEG(data, maxPixels: 256) else { failure = true; selection = nil; return }
                    imageData = jpg
                } catch { failure = true }
                selection = nil
            }
        }.alert("Не вдалося відкрити зображення", isPresented: $failure) { Button("OK", role: .cancel) {} }
    }
}
