import SwiftUI
import PhotosUI
import VisionKit
import SoNoCore

private struct NotebookPage: Codable, Identifiable, Sendable {
    var id = UUID()
    var original: Data
    var preview: Data
}
private struct NotebookDraft: Codable, Sendable {
    var pages: [NotebookPage] = []
    var rows: [OCRRow] = []
}

struct NotebookScanView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var notebook = NotebookDraft()
    @State private var pageIndex = 0
    @State private var camera = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var processing = false
    @State private var consent = false
    @State private var replaceLocal = false
    @State private var request: Task<Void, Never>?
    @State private var persistence: Task<Void, Never>?
    @State private var importConfirmation = false
    @State private var loaded = false
    private let draftID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private var page: NotebookPage? { notebook.pages.indices.contains(pageIndex) ? notebook.pages[pageIndex] : nil }
    private var reviewed: [OCRRow] { notebook.rows.filter(\.confirmed) }
    var body: some View {
        List {
            Section("Chụp hoặc chọn trang sổ") {
                Button { camera = true } label: { Label("Quét nhiều trang bằng camera", systemImage: "doc.viewfinder") }.disabled(!VNDocumentCameraViewController.isSupported || processing)
                PhotosPicker(selection: $photos, maxSelectionCount: 10, matching: .images) { Label("Chọn từ Ảnh", systemImage: "photo.on.rectangle") }.disabled(processing)
                Text("Camera có công cụ cắt, xoay và chỉnh phối cảnh. Ảnh nguồn được giữ trên iPhone. Tối đa 10 trang và 60 MB cho mỗi bản nháp.").font(.caption).foregroundStyle(.secondary)
            }
            if let page {
                Section("Ảnh nguồn — trang \(pageIndex + 1)/\(notebook.pages.count)") {
                    if let image = UIImage(data: page.preview) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 320).accessibilityLabel("Trang sổ đang đối chiếu") }
                    HStack {
                        Button("Trước") { pageIndex = max(0, pageIndex - 1) }.disabled(pageIndex == 0)
                        Spacer()
                        Button("Sau") { pageIndex = min(notebook.pages.count - 1, pageIndex + 1) }.disabled(pageIndex + 1 >= notebook.pages.count)
                    }.buttonStyle(.borderless)
                    HStack {
                        Button("Xoay 90°") { transform(rotate: true) }
                        Button("Tăng độ rõ") { transform(rotate: false) }
                    }.buttonStyle(.bordered).disabled(processing)
                    Button("Đọc trang này bằng Apple Vision") {
                        if notebook.rows.contains(where: { $0.attachmentID == page.id }) { replaceLocal = true } else { recognize(online: false) }
                    }.disabled(processing)
                    Button("Đọc trang này bằng AI online…") { consent = true }.disabled(processing)
                    Text("Vision có thể không hỗ trợ tốt chữ viết tay tiếng Việt. Chữ, ngày và số tiền đều phải đối chiếu ảnh gốc. Nhận dạng lại sẽ thay các dòng nháp của trang đang xem.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if processing { Section { ProgressView("Đang xử lý trang…"); Button("Hủy xử lý") { request?.cancel(); processing = false } } }
            Section("Dòng đề xuất — chạm để sửa") {
                if notebook.rows.isEmpty { Text("Chưa có kết quả nhận dạng. Không có giao dịch nào tự động được ghi.").foregroundStyle(.secondary) }
                ForEach($notebook.rows) { $row in
                    NavigationLink { OCRRowEditor(row: $row, image: notebook.pages.first { $0.id == row.attachmentID }?.preview) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Image(systemName: row.confirmed ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(row.confirmed ? .teal : .orange); Text(row.customerID.map(model.customerName) ?? row.customerName).font(.headline) }
                            Text(row.kind.title + " · " + (row.amount.map(VND.string) ?? "Chưa rõ số tiền"))
                            Text(VietnameseDate.display(row.date)).font(.caption)
                            if let warning = row.warning { Text(warning).font(.caption).foregroundStyle(.orange) }
                        }
                    }
                }.onDelete { indices in notebook.rows.remove(atOffsets: indices); persist() }
            }
            Section("Kiểm tra trước khi nhập") {
                Text("Đã xác nhận \(reviewed.count)/\(notebook.rows.count) dòng.")
                if let totals = try? OCRReviewSummary(rows: reviewed) {
                    LabeledContent("Tổng ghi tăng phải thu", value: VND.string(totals.debt))
                    LabeledContent("Tổng thu nợ", value: VND.string(totals.collections))
                    ForEach(totals.customerIDs, id: \.self) { id in
                        LabeledContent("Dư phải thu dự kiến · \(model.customerName(id))", value: projectedBalance(id))
                    }
                }
                Button("Nhập các dòng đã xác nhận") { importConfirmation = true }.disabled(reviewed.isEmpty || processing || model.busy)
                Text("Ghi cả nhóm cùng lúc hoặc không ghi dòng nào nếu có lỗi. Dòng trùng sẽ bị chặn; bạn cần xóa hoặc kiểm tra lại.").font(.caption).foregroundStyle(.secondary)
            }
            ErrorMessage()
        }.navigationTitle("Quét sổ viết tay")
            .toolbar { Button("Đóng") { dismiss() } }
            .sheet(isPresented: $camera) { DocumentScanner { data in camera = false; Task { await appendPages(data) } } onCancel: { camera = false } onError: { error in camera = false; model.error = error.localizedDescription } }
            .task {
                guard !loaded else { return }; loaded = true
                do {
                    if let ledger = model.ledger, let draft = try await ledger.loadDraft(draftID) {
                        notebook = try JSONDecoder().decode(NotebookDraft.self, from: draft.data)
                    }
                } catch { model.error = "Không đọc được bản nháp quét sổ. Bản gốc vẫn được giữ trong dữ liệu sao lưu." }
            }
            .onChange(of: photos) { _, items in Task {
                do {
                    var data: [Data] = []
                    for item in items { if let image = try await item.loadTransferable(type: Data.self) { data.append(image) } }
                    await appendPages(data)
                } catch { model.error = error.localizedDescription }
            } }
            .onChange(of: notebook.rows) { _, _ in persist() }
            .onDisappear { request?.cancel(); persist(immediate: true) }
            .confirmationDialog("Chỉ gửi trang đang xem tới proxy AI đã ghép nối. Có thể phát sinh phí và kết quả cần kiểm tra. Các dòng nháp của trang này sẽ được thay thế.", isPresented: $consent, titleVisibility: .visible) {
                Button("Đồng ý gửi trang này") { recognize(online: true) }
                Button("Hủy", role: .cancel) { }
            }
            .confirmationDialog("Thay các dòng nháp của trang này bằng kết quả Vision mới?", isPresented: $replaceLocal, titleVisibility: .visible) { Button("Nhận dạng lại") { recognize(online: false) } }
            .confirmationDialog("Ghi \(reviewed.count) dòng đã xác nhận vào sổ?", isPresented: $importConfirmation, titleVisibility: .visible) { Button("Xác nhận nhập") { Task { await importRows() } } }
    }
    private func projectedBalance(_ id: UUID) -> String {
        do {
            return VND.string(try OCRReviewSummary.projectedReceivable(existing: model.entries(for: id), rows: reviewed.filter { $0.customerID == id }))
        } catch { return "Cần kiểm tra thứ tự hoặc số tiền" }
    }
    private func appendPages(_ data: [Data]) async {
        guard notebook.pages.count + data.count <= 10, notebook.pages.reduce(0, { $0 + $1.original.count }) + data.reduce(0, { $0 + $1.count }) <= 60_000_000 else { model.error = "Bản nháp vượt 10 trang hoặc 60 MB. Hãy nhập nhóm hiện tại trước."; return }
        processing = true; defer { processing = false }
        do {
            var pages: [NotebookPage] = []
            for image in data { pages.append(NotebookPage(original: image, preview: try await ImagePreparation.prepare(image))) }
            notebook.pages += pages; persist()
        } catch { model.error = error.localizedDescription }
    }
    private func transform(rotate: Bool) {
        guard let page else { return }; processing = true
        request = Task {
            defer { processing = false }
            do {
                let preview = try await ImagePreparation.prepare(page.preview, rotate: rotate, enhance: !rotate)
                try Task.checkCancellation()
                if let index = notebook.pages.firstIndex(where: { $0.id == page.id }) { notebook.pages[index].preview = preview; persist() }
            } catch { if !Task.isCancelled { model.error = error.localizedDescription } }
        }
    }
    private func recognize(online: Bool) {
        guard let page else { return }; processing = true
        request = Task {
            defer { processing = false }
            do {
                var rows: [OCRRow]
                if online { rows = try await OnlineAIClient().handwriting(image: page.preview, attachmentID: page.id, consent: true) }
                else {
                    let text = try await AppleHandwritingOCR().recognize(page.preview)
                    rows = NotebookParser().parse(text, attachmentID: page.id, customers: model.customers)
                    if rows.isEmpty { throw LedgerError.unavailable("Vision chưa tách được dòng giao dịch. Thử ảnh rõ hơn, proxy online hoặc ghi thủ công.") }
                }
                try Task.checkCancellation()
                for index in rows.indices where rows[index].customerID == nil {
                    let matches = CustomerMatcher.match(rows[index].customerName, customers: model.customers)
                    if matches.count == 1 { rows[index].customerID = matches[0].id }
                }
                notebook.rows.removeAll { $0.attachmentID == page.id }; notebook.rows += rows; persist()
            } catch { if !Task.isCancelled { model.error = error.localizedDescription } }
        }
    }
    private func persist(immediate: Bool = false) {
        persistence?.cancel(); let value = notebook
        persistence = Task {
            if !immediate { try? await Task.sleep(for: .milliseconds(400)) }
            guard !Task.isCancelled, let ledger = model.ledger else { return }
            do {
                let data = try await Task.detached { try JSONCoding.encode(value) }.value
                guard !Task.isCancelled else { return }
                try await ledger.saveDraft(SavedDraft(id: draftID, data: data))
            } catch { model.error = error.localizedDescription }
        }
    }
    private func importRows() async {
        guard let ledger = model.ledger else { return }
        do {
            let entries = try reviewed.map { try $0.transaction() }
            let needed = Set(entries.flatMap(\.attachmentIDs)), existing = Set(model.state.attachments.map(\.id))
            let images = notebook.pages.filter { needed.contains($0.id) && !existing.contains($0.id) }.map { Attachment(id: $0.id, data: $0.original) }
            if await model.perform({ try await ledger.post(entries, attachments: images, confirmed: true) }) {
                notebook.rows.removeAll { $0.confirmed }
                let remaining = Set(notebook.rows.map(\.attachmentID))
                notebook.pages.removeAll { needed.contains($0.id) && !remaining.contains($0.id) }
                pageIndex = 0; persist(immediate: true)
            }
        } catch { model.error = error.localizedDescription }
    }
}

private struct OCRRowEditor: View {
    @EnvironmentObject private var model: AppModel
    @Binding var row: OCRRow
    var image: Data?
    @State private var amount = ""
    @State private var quantity = ""
    @State private var unitPrice = ""
    var body: some View {
        Form {
            if let image, let uiImage = UIImage(data: image) { Image(uiImage: uiImage).resizable().scaledToFit().frame(maxHeight: 280) }
            Section("Đối chiếu từng trường") {
                Text(row.rawText).textSelection(.enabled)
                if let warning = row.warning { Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                TextField("Tên nhận diện", text: $row.customerName)
                Picker("Khách hàng", selection: $row.customerID) {
                    Text("Chọn khách").tag(nil as UUID?)
                    ForEach(model.customers) { Text($0.name + " · " + $0.phone).tag(Optional($0.id)) }
                }
                Picker("Loại", selection: $row.kind) { ForEach(TransactionKind.editable, id: \.self) { Text($0.title).tag($0) } }
                DatePicker("Ngày giao dịch", selection: $row.date, in: ...Date(), displayedComponents: .date)
                TextField("Thành tiền (đồng)", text: $amount).keyboardType(.numberPad)
                TextField("Số lượng (tùy chọn)", text: $quantity).keyboardType(.numberPad)
                TextField("Đơn giá (tùy chọn)", text: $unitPrice).keyboardType(.numberPad)
                TextField("Ghi chú / hàng hóa", text: $row.note, axis: .vertical)
                Toggle("Tôi đã đối chiếu ảnh và xác nhận dòng này", isOn: $row.confirmed).disabled(row.amount == nil || row.customerID == nil)
            }
        }.navigationTitle("Kiểm tra dòng")
            .onAppear { amount = row.amount.map(String.init) ?? ""; quantity = row.quantity.map(String.init) ?? ""; unitPrice = row.unitPrice.map(String.init) ?? "" }
            .onChange(of: amount) { _, value in let parsed = VietnameseMoneyParser().parse(value).amount; if parsed != row.amount { row.amount = parsed; row.confirmed = false } }
            .onChange(of: quantity) { _, value in let parsed = Int64(value); if parsed != row.quantity { row.quantity = parsed; row.confirmed = false } }
            .onChange(of: unitPrice) { _, value in let parsed = VietnameseMoneyParser().parse(value).amount; if parsed != row.unitPrice { row.unitPrice = parsed; row.confirmed = false } }
            .onChange(of: row.date) { _, _ in row.confirmed = false }
            .onChange(of: row.kind) { _, _ in row.confirmed = false }
            .onChange(of: row.customerID) { _, _ in row.confirmed = false }
    }
}

struct DocumentScanner: UIViewControllerRepresentable {
    var onScan: ([Data]) -> Void
    var onCancel: () -> Void
    var onError: (Error) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController(); controller.delegate = context.coordinator; return controller
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(parent: DocumentScanner) { self.parent = parent }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount <= 10 else { parent.onError(LedgerError.invalid("Chỉ quét tối đa 10 trang mỗi lần.")); return }
            parent.onScan((0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).jpegData(compressionQuality: 0.95) })
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.onCancel() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { parent.onError(error) }
    }
}
