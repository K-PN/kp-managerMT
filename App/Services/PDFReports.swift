import UIKit
import SoNoCore

enum PDFReports {
    static func statement(customer: Customer, entries: [DebtTransaction], balance: Balance, book: AccountBook? = nil) throws -> URL {
        let active = try LedgerCalculator.active(entries)
        let activeIDs = Set(active.map(\.id))
        let rows = entries.sorted { $0.effectiveDate < $1.effectiveDate }.map { entry in
            "\(VietnameseDate.display(entry.effectiveDate))  |  \(entry.kind.title)  |  \(VND.string(entry.amount))\n\(entry.goodsDescription ?? "")" + (!activeIDs.contains(entry.id) && entry.kind != .reversal ? " · Đã hoàn tác" : "")
        }
        let purchased = try CheckedMoney.sum(active.filter { $0.kind == .purchase }.map(\.amount))
        let paid = try CheckedMoney.sum(active.filter { $0.kind == .supplierPayment }.map(\.amount))
        let collected = try CheckedMoney.sum(active.filter { $0.kind == .collection }.map(\.amount))
        let header = "\(AppBrand.name.uppercased())\nPHIẾU ĐỐI CHIẾU\n\nKhách / nhà cung cấp: \(customer.name)\nĐiện thoại: \(customer.phone)\nLập lúc: \(VietnameseDate.display(Date()))\n\nLỊCH SỬ GIAO DỊCH"
        let totals: String
        if book == .goods {
            totals = "TỔNG CỘNG\nTổng tiền hàng: \(VND.string(purchased))\nĐã trả tiền hàng: \(VND.string(paid))\nTổng nợ tiền hàng: \(VND.string(balance.goodsPayable))"
        } else if book == .debt {
            totals = "TỔNG CỘNG\nĐã thu nợ: \(VND.string(collected))\nTổng nợ khách: \(VND.string(balance.receivable))"
        } else {
            totals = "TỔNG CỘNG\nTổng tiền hàng: \(VND.string(purchased))\nĐã trả tiền hàng: \(VND.string(paid))\nĐã thu nợ: \(VND.string(collected))\nTổng nợ khách: \(VND.string(balance.receivable))\nTổng nợ tiền hàng: \(VND.string(balance.goodsPayable))"
        }
        return try render(title: "doi-chieu-my-thanh", paragraphs: [header] + rows + [totals, "Người lập phiếu: __________________\n\nKhách hàng xác nhận: __________________"])
    }
    static func collections(_ reports: [CollectionReport], period: ReportPeriod) throws -> URL {
        let total = try CheckedMoney.sum(reports.map(\.total))
        return try render(title: "bao-cao-thu-no", paragraphs: ["\(AppBrand.name.uppercased())\nBÁO CÁO THU NỢ THEO \(period.rawValue.uppercased())\nLập lúc: \(VietnameseDate.display(Date()))\n"] + reports.map { "\(VietnameseDate.display($0.id))\n\($0.count) giao dịch  ·  \(VND.string($0.total))" } + ["TỔNG CỘNG: \(VND.string(total))"])
    }
    static func trading(snapshot: LedgerSnapshot, period: ReportPeriod) throws -> URL {
        let rows = try ReportService.trading(snapshot.transactions, period: period)
        let totals = try ReportService.totals(snapshot: snapshot)
        let header = "\(AppBrand.name.uppercased())\nBÁO CÁO GIAO DỊCH - HÀNG HÓA\nTheo \(period.rawValue.lowercased()) · \(VietnameseDate.display(Date()))"
        let lines = rows.map { "\(VietnameseDate.display($0.id))\nTiền hàng: \(VND.string($0.purchases))\nĐã trả tiền hàng: \(VND.string($0.paid))\nThu nợ: \(VND.string($0.collected))" }
        let footer = "TỔNG CỘNG\nTổng tiền hàng: \(VND.string(totals.purchases))\nTổng đã trả tiền hàng: \(VND.string(totals.paid))\nTổng thu nợ: \(VND.string(totals.collected))\nTổng nợ khách: \(VND.string(totals.receivable))\nTổng nợ tiền hàng: \(VND.string(totals.goodsPayable))"
        return try render(title: "bao-cao-my-thanh", paragraphs: [header] + lines + [footer])
    }
    private static func render(title: String, paragraphs: [String]) throws -> URL {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let data: Data = renderer.pdfData { context in
            var page = 0, y: CGFloat = 0
            func newPage() {
                context.beginPage(); page += 1; y = 44
                ("\(AppBrand.name) · Trang \(page)" as NSString).draw(at: CGPoint(x: 40, y: 810), withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray])
            }
            newPage()
            let style = NSMutableParagraphStyle(); style.lineSpacing = 4
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.black, .paragraphStyle: style]
            // Bound each line so even a very long note flows across pages.
            for paragraph in paragraphs {
                for line in wrap(paragraph, width: 515, attributes: attributes) {
                    let height = max(20, (line as NSString).boundingRect(with: CGSize(width: 515, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).height + 4)
                    if y + height > 790 { newPage() }
                    (line as NSString).draw(in: CGRect(x: 40, y: y, width: 515, height: height), withAttributes: attributes)
                    y += height
                }
                y += 12
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(title)-\(UUID().uuidString).pdf")
        try data.write(to: url, options: [.atomic, .completeFileProtection]); return url
    }
    private static func wrap(_ text: String, width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> [String] {
        var result: [String] = []
        for source in text.components(separatedBy: .newlines) {
            var line = ""
            for character in source {
                let candidate = line + String(character)
                if !line.isEmpty && (candidate as NSString).size(withAttributes: attributes).width > width { result.append(line); line = String(character) }
                else { line = candidate }
            }
            result.append(line)
        }
        return result
    }
}
