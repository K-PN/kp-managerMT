import UIKit
import SoNoCore

enum PDFReports {
    static func statement(customer: Customer, entries: [DebtTransaction], balance: Balance) throws -> URL {
        let rows = entries.sorted { $0.effectiveDate < $1.effectiveDate }.map { "\(VietnameseDate.display($0.effectiveDate))  |  \($0.kind.title)  |  \(VND.string($0.amount))\n\($0.note)" }
        let header = "PHIẾU ĐỐI CHIẾU CÔNG NỢ\n\nKhách hàng: \(customer.name)\nĐiện thoại: \(customer.phone)\nLập lúc: \(VietnameseDate.display(Date()))\n\nPhải thu: \(VND.string(balance.receivable))\nTôi phải trả: \(VND.string(balance.payable))\nKhách trả trước: \(VND.string(balance.prepaid))\n\nLỊCH SỬ GIAO DỊCH\nSổ có giữ các giao dịch hoàn tác để đối chiếu.\n"
        return try render(title: "doi-chieu-cong-no", paragraphs: [header] + rows + ["\nNgười lập phiếu: __________________\n\nKhách hàng xác nhận: __________________\n\nPhiếu được tạo từ dữ liệu do người sử dụng nhập và xác nhận."])
    }
    static func collections(_ reports: [CollectionReport], period: ReportPeriod) throws -> URL {
        try render(title: "bao-cao-thu-no", paragraphs: ["BÁO CÁO THU NỢ THEO \(period.rawValue.uppercased())\nLập lúc: \(VietnameseDate.display(Date()))\n"] + reports.map { "\(VietnameseDate.display($0.id))\n\($0.count) giao dịch  ·  \(VND.string($0.total))" })
    }
    private static func render(title: String, paragraphs: [String]) throws -> URL {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let data: Data = renderer.pdfData { context in
            var page = 0, y: CGFloat = 0
            func newPage() {
                context.beginPage(); page += 1; y = 44
                ("Sổ Nợ AI · Trang \(page)" as NSString).draw(at: CGPoint(x: 40, y: 810), withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray])
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
