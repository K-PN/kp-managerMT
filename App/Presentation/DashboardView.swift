import SwiftUI
import SoNoCore

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var transaction = false
    @State private var scan = false
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LazyVGrid(columns: columns, spacing: 12) {
                    NavigationLink { LedgerView(account: "debt", openOnly: true) } label: {
                        SummaryCard(title: "Tổng khách nợ", amount: model.summary?.receivable ?? 0, symbol: "person.2.fill", color: .teal)
                    }.accessibilityIdentifier("dashboard.debt")
                    NavigationLink { LedgerView(account: "goods", openOnly: true) } label: {
                        SummaryCard(title: "Tổng nợ tiền hàng", amount: model.summary?.goodsPayable ?? 0, symbol: "creditcard.fill", color: .orange)
                    }.accessibilityIdentifier("dashboard.goodsDebt")
                    NavigationLink { LedgerView(kind: .purchase, from: monthStart, to: Date(), account: "goods") } label: {
                        SummaryCard(title: "Tiền hàng tháng này", amount: model.summary?.goodsThisMonth ?? 0, symbol: "shippingbox.fill", color: .indigo, compact: true)
                    }.accessibilityIdentifier("dashboard.goodsMonth")
                    NavigationLink { LedgerView(kind: .purchase, from: weekStart, to: Date(), account: "goods") } label: {
                        SummaryCard(title: "Tiền hàng tuần này", amount: model.summary?.goodsThisWeek ?? 0, symbol: "calendar", color: .blue, compact: true)
                    }.accessibilityIdentifier("dashboard.goodsWeek")
                }.buttonStyle(.plain)
                HStack(spacing: 12) {
                    Button { transaction = true } label: { Label("Ghi giao dịch", systemImage: "plus.circle.fill").frame(maxWidth: .infinity).padding(.vertical, 10) }
                        .buttonStyle(.borderedProminent)
                    Button { scan = true } label: { Label("Quét sổ", systemImage: "doc.viewfinder").frame(maxWidth: .infinity).padding(.vertical, 10) }
                        .buttonStyle(.bordered)
                }
                ErrorMessage()
                if model.customers.isEmpty {
                    ContentUnavailableView("Chưa có khách hàng", systemImage: "person.crop.circle.badge.plus")
                } else {
                    recent
                }
            }.padding()
        }.background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(AppBrand.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { NavigationLink { ReportsView() } label: { Label("Báo cáo", systemImage: "chart.bar.xaxis") } }
            .refreshable { await model.refresh() }
            .sheet(isPresented: $transaction) { NavigationStack { TransactionEditorView() } }
            .sheet(isPresented: $scan) { NavigationStack { NotebookScanView() } }
    }
    private var recent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Giao dịch gần đây").font(.title3.bold())
            ForEach(model.state.transactions.sorted { $0.createdAt > $1.createdAt }.prefix(8)) { entry in
                NavigationLink { TransactionDetailView(entry: entry) } label: {
                    TransactionRow(entry: entry).padding(.horizontal).padding(.vertical, 6)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }.foregroundStyle(.primary)
            }
        }
    }
    private var monthStart: Date { VietnameseDate.calendar.dateInterval(of: .month, for: Date())!.start }
    private var weekStart: Date { VietnameseDate.calendar.dateInterval(of: .weekOfYear, for: Date())!.start }
}

private struct SummaryCard: View {
    let title: String
    let amount: Int64
    let symbol: String
    let color: Color
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 14) {
            HStack {
                Image(systemName: symbol).font(.title3).foregroundStyle(color)
                    .frame(width: 36, height: 36).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary).lineLimit(2).frame(minHeight: compact ? 20 : 40, alignment: .top)
            Text(VND.string(amount)).font(.system(compact ? .headline : .title2, design: .rounded).bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
                .foregroundStyle(color)
        }.padding(16).frame(maxWidth: .infinity, minHeight: compact ? 124 : 180, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
            .overlay(alignment: .top) { RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.7)).frame(height: 3).padding(.horizontal, 24) }
            .accessibilityElement(children: .combine)
    }
}
