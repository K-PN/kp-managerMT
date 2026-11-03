import SwiftUI
import SoNoCore

struct ReportsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var period: ReportPeriod = .month
    @State private var report: [CollectionReport] = []
    @State private var exportURL: URL?
    @State private var loading = false
    var body: some View {
        List {
            Section {
                Picker("Gom theo", selection: $period) { ForEach(ReportPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                Button("Xuất toàn bộ sổ CSV") { Task { await exportCSV() } }.disabled(loading)
                Button("Xuất báo cáo thu nợ PDF") {
                    let rows = report, grouping = period; loading = true
                    Task {
                        defer { loading = false }
                        do { exportURL = try await Task.detached { try PDFReports.collections(rows, period: grouping) }.value }
                        catch { model.error = error.localizedDescription }
                    }
                }.disabled(loading)
                if let exportURL { ShareLink("Lưu hoặc chia sẻ tệp", item: exportURL) }
            }
            Section("Thu nợ theo \(period.rawValue.lowercased())") {
                if loading { ProgressView("Đang tính báo cáo…") }
                else if report.isEmpty { Text("Chưa có khoản thu nợ.").foregroundStyle(.secondary) }
                ForEach(report) { row in
                    VStack(alignment: .leading) {
                        Text(VietnameseDate.display(row.id)).font(.headline)
                        LabeledContent("\(row.count) giao dịch", value: VND.string(row.total))
                    }
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
            let entries = model.state.transactions, grouping = period
            let rows = try await Task.detached { try ReportService.collections(entries, period: grouping) }.value
            try Task.checkCancellation(); report = rows
        } catch { if !Task.isCancelled { model.error = error.localizedDescription } }
    }
    private func exportCSV() async {
        loading = true; defer { loading = false }
        do {
            let snapshot = model.state
            let url = try await Task.detached {
                let csv = try ReportService.csv(snapshot: snapshot)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("so-no-\(UUID().uuidString).csv")
                try Data(csv.utf8).write(to: url, options: [.atomic, .completeFileProtection]); return url
            }.value
            exportURL = url
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
