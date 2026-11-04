import SwiftUI

enum AppBrand {
    static let name = "Tạp Hóa Mỹ Thạnh"
    static let subtitle = "Quản lý giao dịch - hàng hóa"
    static let fullName = "Tạp Hóa Mỹ Thạnh - Quản lý giao dịch - hàng hóa"
}

struct BrandOpeningView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "basket.fill").font(.system(size: 52)).foregroundStyle(.teal)
            Text(AppBrand.name).font(.system(.largeTitle, design: .rounded).bold())
            Text(AppBrand.subtitle).font(.subheadline).foregroundStyle(.secondary)
            ProgressView().padding(.top, 12)
        }.multilineTextAlignment(.center).padding(28).accessibilityElement(children: .combine)
            .accessibilityLabel(AppBrand.fullName)
    }
}
