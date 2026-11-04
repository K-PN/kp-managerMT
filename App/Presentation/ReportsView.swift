import SwiftUI
import SoNoCore

struct ReportsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var period: ReportPeriod = .month
    @State private var report: [TradingReport] = []
    @State private var totals = ReportTotals()
    @State private var exportURL: URL?
    @State private var loading = false
    var body: some View {
        List {
            Section("Tổng cộng") {
                LabeledContent("Tổng nợ khách", value: VND.string(totals.receivable))
                LabeledContent("Tổng tiền hàng", value: VND.string(totals.purchases))
                LabeledContent("Đã trả tiền hàng", value: VND.string(totals.paid))
                LabeledContent("Tổng nợ tiền hàng", value: VND.string(totals.goodsPayable))
                LabeledContent("Tổng thu nợ", value: VND.string(totals.collected))
            }.accessibilityIdentifier("reports.totals")
            Section {
                Picker("Gom theo", selection: $period) { ForEach(ReportPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                Button("Xuất sổ CSV kèm tổng") { Task { await exportCSV() } }.disabled(loading)
                Button("Xuất báo cáo PDF kèm tổng") { Task { await exportPDF() } }.disabled(loading)
                if let exportURL { ShareLink("Lưu hoặc chia sẻ tệp", item: exportURL) }
            }
            Section("Chi tiết theo \(period.rawValue.lowercased())") {
                if loading { ProgressView() }
                else if report.isEmpty { Text("Chưa có giao dịch.").foregroundStyle(.secondary) }
                ForEach(report) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(VietnameseDate.display(row.id)).font(.headline)
                        LabeledContent("Tiền hàng", value: VND.string(row.purchases))
                        LabeledContent("Đã trả tiền hàng", value: VND.string(row.paid))
                        LabeledContent("Thu nợ", value: VND.string(row.collected))
                    }.padding(.vertical, 6)
                }
            }
            ErrorMessage()
        }.navigationTitle("Báo cáo")
            .task(id: period) { await loadReport() }
            .onChange(of: model.state.transactions) { _, _ in Task { await loadReport() } }
    }
    private func loadReport() async {
        loading = true; defer { loading = false }
        do {
            let snapshot = model.state, grouping = period
            let result = try await Task.detached { (try ReportService.trading(snapshot.transactions, period: grouping), try ReportService.totals(snapshot: snapshot)) }.value
            try Task.checkCancellation(); report = result.0; totals = result.1
        } catch { if !Task.isCancelled { model.error = error.localizedDescription } }
    }
    private func exportCSV() async {
        loading = true; defer { loading = false }
        do {
            let snapshot = model.state
            exportURL = try await Task.detached {
                let csv = try ReportService.csv(snapshot: snapshot)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("my-thanh-\(UUID().uuidString).csv")
                try Data(csv.utf8).write(to: url, options: [.atomic, .completeFileProtection]); return url
            }.value
        } catch { model.error = error.localizedDescription }
    }
    private func exportPDF() async {
        loading = true; defer { loading = false }
        do {
            let snapshot = model.state, grouping = period
            exportURL = try await Task.detached { try PDFReports.trading(snapshot: snapshot, period: grouping) }.value
        } catch { model.error = error.localizedDescription }
    }
}

struct AuditLogView: View {
    @EnvironmentObject private var model: AppModel
    var entityID: UUID?
    @State private var query = ""
    @State private var limit = 100
    private var events: [AuditEvent] {
        model.state.audit.filter { event in
            (entityID == nil || event.entityID == entityID || event.oldValue?.contains(entityID!.uuidString) == true || event.newValue?.contains(entityID!.uuidString) == true) &&
            (query.isEmpty || TextKey.normalize(event.event + " " + event.reason).contains(TextKey.normalize(query)))
        }.sorted { $0.timestamp > $1.timestamp }
    }
    var body: some View {
        List {
            ForEach(events.prefix(limit)) { event in
                DisclosureGroup {
                    Text("Đối tượng: \(event.entityID.uuidString)").font(.caption)
                    if let old = event.oldValue { Text("Trước: \(old)").font(.caption).textSelection(.enabled) }
                    if let new = event.newValue { Text("Sau: \(new)").font(.caption).textSelection(.enabled) }
                    if !event.reason.isEmpty { Text("Lý do: \(event.reason)") }
                } label: {
                    VStack(alignment: .leading) { Text(event.event).font(.headline); Text(VietnameseDate.display(event.timestamp)).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if events.count > limit { Button("Xem thêm 100 mục") { limit += 100 } }
            if events.isEmpty { Text("Chưa có nhật ký phù hợp.").foregroundStyle(.secondary) }
        }.navigationTitle("Nhật ký thay đổi").searchable(text: $query, prompt: "Thao tác hoặc lý do")
    }
}
