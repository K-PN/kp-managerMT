import SwiftUI
import SoNoCore

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var transaction = false
    @State private var scan = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Một cuốn sổ. Mọi khoản rõ ràng.").font(.subheadline).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    Label("TỔNG PHẢI THU", systemImage: "wallet.bifold").font(.caption.bold())
                    Text(VND.string(model.summary?.receivable ?? 0)).font(.system(.largeTitle, design: .rounded).bold()).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                    Text("Dữ liệu được lưu trên iPhone của bạn").font(.caption)
                }.foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).padding(24)
                    .background(LinearGradient(colors: [.teal, Color(red: 0.02, green: 0.35, blue: 0.34)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    MoneyMetric(title: "Thu hôm nay", amount: model.summary?.collectedToday ?? 0, symbol: "arrow.down.left")
                    MoneyMetric(title: "Thu tháng này", amount: model.summary?.collectedThisMonth ?? 0, symbol: "calendar")
                    MoneyMetric(title: "Nợ quá hạn", amount: model.summary?.overdue ?? 0, symbol: "clock.badge.exclamationmark")
                    MoneyMetric(title: "Tôi phải trả", amount: model.summary?.payable ?? 0, symbol: "arrow.up.right")
                    MoneyMetric(title: "Khách trả trước", amount: model.summary?.prepaid ?? 0, symbol: "tray.and.arrow.down")
                }
                HStack {
                    Button { transaction = true } label: { Label("Ghi giao dịch", systemImage: "plus.circle.fill").frame(maxWidth: .infinity).padding(.vertical, 8) }
                    Button { scan = true } label: { Label("Quét sổ", systemImage: "doc.viewfinder").frame(maxWidth: .infinity).padding(.vertical, 8) }
                }.buttonStyle(.bordered)
                ErrorMessage()
                if model.customers.isEmpty {
                    ContentUnavailableView("Bắt đầu với khách hàng đầu tiên", systemImage: "person.crop.circle.badge.plus", description: Text("Thêm khách trong mục Khách hàng, sau đó ghi nợ hoặc thu nợ. Không có dữ liệu mẫu trong sổ của bạn."))
                } else {
                    Text("Khách còn nợ nhiều nhất").font(.title3.bold())
                    ForEach(model.customers.filter { model.balance(for: $0.id).receivable > 0 }.sorted { model.balance(for: $0.id).receivable > model.balance(for: $1.id).receivable }.prefix(5)) { customer in
                        NavigationLink { CustomerDetailView(customerID: customer.id) } label: {
                            HStack { Text(customer.name); Spacer(); Text(VND.string(model.balance(for: customer.id).receivable)).bold() }.padding().background(.background, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    Text("Sắp đến hạn trong 7 ngày").font(.title3.bold())
                    ForEach(upcoming) { entry in NavigationLink { TransactionDetailView(entry: entry) } label: { TransactionRow(entry: entry) } }
                    Text("Giao dịch gần đây").font(.title3.bold())
                    ForEach(model.state.transactions.sorted { $0.createdAt > $1.createdAt }.prefix(8)) { entry in
                        NavigationLink { TransactionDetailView(entry: entry) } label: { TransactionRow(entry: entry) }.foregroundStyle(.primary)
                    }
                }
            }.padding()
        }.background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Sổ Nợ AI")
            .toolbar { NavigationLink { ReportsView() } label: { Label("Báo cáo", systemImage: "chart.bar.xaxis") } }
            .refreshable { await model.refresh() }
            .sheet(isPresented: $transaction) { NavigationStack { TransactionEditorView() } }
            .sheet(isPresented: $scan) { NavigationStack { NotebookScanView() } }
    }
    private var upcoming: [DebtTransaction] {
        let today = VietnameseDate.calendar.startOfDay(for: Date())
        let end = VietnameseDate.calendar.date(byAdding: .day, value: 7, to: today)!
        let openIDs = Set((model.summary?.balances.values.flatMap(\.outstanding) ?? []).map(\.id))
        return model.state.transactions.filter { entry in
            guard openIDs.contains(entry.id), let due = entry.dueDate else { return false }; return due >= today && due < end
        }.sorted { $0.dueDate! < $1.dueDate! }
    }
}
