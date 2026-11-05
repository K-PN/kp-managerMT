import SwiftUI
import SoNoCore

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var voice = false
    var body: some View {
        Group {
            if model.isLoading { BrandOpeningView() }
            else if model.ledger == nil {
                ContentUnavailableView {
                    Label("Chưa mở được sổ", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(model.error ?? "Hãy thử mở lại ứng dụng.")
                } actions: {
                    Button("Thử lại") { Task { await model.open() } }
                }
            } else if model.locked {
                VStack(spacing: 24) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 64)).foregroundStyle(.teal)
                    Text(AppBrand.name).font(.largeTitle.bold())
                    Text(AppBrand.subtitle).foregroundStyle(.secondary)
                    Button("Mở khóa") { Task { await model.unlock() } }.buttonStyle(.borderedProminent).controlSize(.large)
                    ErrorMessage()
                }.padding()
            } else {
                VStack(spacing: 0) {
                    TabView {
                        NavigationStack { DashboardView() }.tabItem { Label("Tổng quan", systemImage: "square.grid.2x2.fill") }
                        NavigationStack { CustomersView() }.tabItem { Label("Khách hàng", systemImage: "person.2.fill") }
                        NavigationStack { LedgerView() }.tabItem { Label("Sổ giao dịch", systemImage: "book.closed.fill") }
                        NavigationStack { SettingsView() }.tabItem { Label("Cài đặt", systemImage: "gearshape.fill") }
                    }
                    Button { voice = true } label: { Label("Nói để ghi sổ hoặc tra cứu", systemImage: "mic.fill").font(.headline).frame(maxWidth: .infinity).padding(13) }
                        .buttonStyle(.borderedProminent).padding(.horizontal).padding(.vertical, 6).background(.regularMaterial).accessibilityIdentifier("voice.open")
                }
                .sheet(isPresented: $voice) { NavigationStack { VoiceInputView() } }
            }
        }
    }
}

struct ErrorMessage: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        if let error = model.error {
            VStack(alignment: .leading, spacing: 8) {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                Button("Đóng thông báo") { model.error = nil }.font(.caption)
            }.accessibilityElement(children: .combine)
        }
    }
}
struct MoneyMetric: View {
    var title: String
    var amount: Int64
    var symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
            Text(VND.string(amount)).font(.title2.bold()).monospacedDigit().minimumScaleFactor(0.65).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}
struct TransactionRow: View {
    @EnvironmentObject private var model: AppModel
    var entry: DebtTransaction
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.kind == .collection ? "arrow.down.left.circle.fill" : entry.kind == .reversal ? "arrow.uturn.backward.circle" : "arrow.up.right.circle.fill")
                .font(.title2).foregroundStyle(entry.kind == .collection ? .teal : .orange).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.customerName(entry.customerID)).font(.headline)
                Text(entry.kind.title).font(.caption).foregroundStyle(.secondary)
                if let goods = entry.goodsDescription, !goods.isEmpty { Text("Hàng: \(goods)").font(.caption).lineLimit(2).foregroundStyle(.secondary) }
                Text(VietnameseDate.display(entry.effectiveDate)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(VND.string(entry.amount)).font(.subheadline.bold()).monospacedDigit()
        }.padding(.vertical, 5).accessibilityElement(children: .combine)
    }
}
