# Kiến trúc triển khai

## Ranh giới

`SwiftUI → AppModel → LedgerService actor → SQLiteStore → SQLite`

Parser, `LedgerCalculator`, `ReportService` và validation nằm trong Swift package, không phụ thuộc SwiftUI, Speech, Vision hoặc mạng. Views nhận số dư đã tính và gọi lệnh nghiệp vụ; không có câu SQL trong View. Camera/Speech/AI chỉ đưa ra dữ liệu đề xuất. `OCRRow.transaction()` và `LedgerService.post()` kiểm tra lại trước khi ghi.

`CustomerRepository`, `DebtRepository`, `TransactionRepository`, `AuditLogRepository`, `VoiceCommandParser`, `HandwritingOCRService`, `BackupService`, `ReminderService` nằm trong core. `VoiceRecognitionService` nằm ở lớp iOS vì giao diện thu âm chạy trên main actor. Các adapter online không được truy cập database.

## Schema v1

- `customers`: UUID, khóa tên/biệt danh/điện thoại đã chuẩn hóa, payload Codable; `mergedInto` nằm trong payload và được domain kiểm tra cycle/đích tồn tại.
- `transactions`: UUID, customer FK, số tiền INTEGER dương, ngày hiệu lực, loại, FK reversal duy nhất, import key duy nhất và toàn bộ payload. Index theo khách/ngày và ngày/loại.
- `audit`: UUID, entity UUID, thời điểm, payload trước/sau/nguồn/lý do. Trigger chặn UPDATE và DELETE, kể cả khi khôi phục.
- `attachments`: UUID và payload ảnh local; liên kết từ transaction được domain kiểm tra. Đặt ảnh trong cùng database giúp ghi ảnh + giao dịch + audit và restore atomic; đánh đổi là snapshot lớn, cần streaming/lazy loading ở bản tối ưu tiếp theo.
- `drafts`: UUID ổn định và payload bản nháp voice/OCR. Bản nháp không tham gia số dư.

Không lưu số dư cache làm nguồn chân lý. `LedgerIndex` gom ledger theo khách gốc một lần; `LedgerCalculator` tái tính từ các giao dịch đang có hiệu lực. Payload là nguồn chi tiết, các cột SQL là ràng buộc/index. Chỉ persistence mới tạo câu SQL.

## Quy tắc tiền

Tất cả số tiền là `Int64 > 0`. Checked addition/multiplication chặn overflow. Thu nợ và điều chỉnh giảm phải thu không được vượt phải thu tại thời điểm có hiệu lực; trả khoản vay không vượt phải trả; cấn trừ không vượt cả phải thu và trả trước.

Ghi nợ, cho vay và điều chỉnh tăng tạo khoản phải thu. Thu nợ/điều chỉnh giảm/cấn trừ phân bổ FIFO theo `effectiveDate`, rồi `createdAt`, rồi UUID. Dùng phần còn lại sau phân bổ để tính quá hạn. Nhận trả trước và tôi vay khách đi vào hai số dư riêng, không tự bù trừ. Không dùng LLM để cộng tiền, phân bổ hay tính số dư.

Hoàn tác là một dòng mới trỏ đến dòng gốc, có cùng khách và số tiền. Không hoàn tác một dòng hoàn tác hoặc hoàn tác cùng dòng hai lần. Khi tái tính, loại cả dòng gốc đã hoàn tác và dòng reversal khỏi ledger có hiệu lực. Nếu bỏ khoản nợ làm khoản thu phía sau không hợp lệ, từ chối toàn bộ thao tác. Điều chỉnh tạo reversal + replacement + hai audit trong cùng transaction.

Gộp khách chỉ đổi liên kết khách gốc và ghi audit; không viết lại customer ID trên các giao dịch cũ. Khi truy vấn số dư/lịch sử của khách đích, gom cả các hồ sơ nguồn. Gộp không có thao tác xóa và chưa có undo tự động.

## Tính nguyên tử và migration

`LedgerService` serialize thao tác trong một actor. Mỗi lệnh thay đổi khách, giao dịch, ảnh hoặc restore dùng `BEGIN IMMEDIATE ... COMMIT`; bất kỳ lỗi nào thực hiện `ROLLBACK`. SQLite bật foreign keys, WAL, busy timeout 5 giây và `synchronous=FULL`. Audit ghi cùng connection/transaction với thay đổi tài chính.

`PRAGMA user_version` là phiên bản schema. Database v0 chạy `001_initial.sql` trong transaction và đổi version thành 1. Version mới hơn 1 bị từ chối; không xóa/tạo lại dữ liệu khi lỗi mở. Các lần nâng cấp tiếp theo cần migration số tăng dần và fixture kiểm thử phiên bản cũ; hiện chỉ có schema v1.

Restore giải mã/kiểm tra version/hash/UUID/FK domain/số dư trước. Trong một transaction: xóa tập giao dịch/khách/ảnh/draft hiện tại, thêm dữ liệu backup theo thứ tự FK, hợp nhất audit không trùng ID, thêm restore audit. Giữ nguyên audit đã có; ID audit trùng nhưng nội dung khác bị từ chối. Giao dịch/khách mới hơn backup không được giữ lại, vì đây là restore thay thế có xác nhận.

## Dữ liệu cá nhân

SQLite ở Application Support, dùng file protection của iOS; không có CloudKit/iCloud dependency. Khóa giao diện dùng LocalAuthentication với Face ID hoặc mật mã thiết bị. Phiên AI ngắn hạn lưu bằng Keychain `WhenUnlockedThisDeviceOnly`. API key nhà cung cấp không được app nhận/lưu.

Apple Speech online cần tùy chọn rõ ràng; yêu cầu on-device được bật nếu người dùng không đồng ý xử lý máy chủ Apple. Proxy chỉ nhận ảnh/audio được chọn, sau consent tương ứng. Request không gửi danh sách khách, số dư hoặc snapshot. Không có automatic paid fallback/retry.

## Giới hạn cần kiểm chứng

Mọi Swift source mới chỉ qua parser cú pháp trên Windows. Actor isolation, SDK availability, linking và mọi XCTest phải được xác minh bằng Apple toolchain. Snapshot hiện đọc cả ảnh/drafts; index cải thiện projection tài chính nhưng không thay thế việc cần tách truy vấn metadata/ảnh lazy, phân trang SQL và backup streaming khi tăng kho dữ liệu. PDF/notification/camera/Speech cần QA trên thiết bị.
