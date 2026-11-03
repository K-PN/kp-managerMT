# Tiến độ Sổ Nợ AI

Cập nhật: 03/11/2026, Asia/Bangkok. Nhãn **đã viết mã** không có nghĩa đã chạy thành công trên iOS.

## Phase 1 — Nền tảng: đã viết mã, chờ build Mac

- [x] Kiểm tra workspace: trống; Windows PowerShell 5.1, Git/Python/Node có sẵn; không có Swift/Xcode/iOS SDK, WSL chưa dùng được.
- [x] Khởi tạo Git, commit và push source lên branch main của K-PN/kp-managerMT.
- [x] Swift package độc lập, SwiftUI app iOS 17+, XcodeGen/scheme, CI Mac.
- [x] Phân lớp, protocols, SQLite schema v1 và migration theo transaction.
- [x] Navigation native, tiếng Việt, theme hệ thống/sáng/tối, Dynamic Type và nhãn accessibility.
- [ ] Sinh project và xác minh type checking/linking bằng Xcode.

## Phase 2 — Financial Core: đã viết mã, chờ XCTest/iOS

- [x] Khách: thêm/sửa, tìm không dấu/biệt danh, cảnh báo trùng, gộp đã xác nhận; không xóa lịch sử.
- [x] Int64 checked arithmetic, FIFO, phải thu/phải trả/trả trước riêng, chặn vượt nợ.
- [x] Giao dịch immutable qua API; hoàn tác, thay thế và audit atomic.
- [x] Dashboard thật, lịch sử, tìm/lọc khách/ngày/số tiền/tình trạng, hiển thị từng nhóm 100 dòng.
- [x] XCTest cho các nhánh nghiệp vụ và persistence; SQL contract tests chạy được trên Windows.
- [ ] Chạy XCTest và test UI thực tế; test tải hàng nghìn khách/hàng chục nghìn giao dịch.

## Phase 3 — Voice: đã viết mã, chờ quyền/thiết bị

- [x] Apple Speech vi-VN, kiểm tra runtime offline, đồng ý xử lý Apple online.
- [x] Parser tiền tiếng Việt, cảnh báo cách nói rút gọn, quantity × unit price với câu có số lượng chữ số rõ ràng.
- [x] Intent ghi/thu/tra cứu, matching tên/biệt danh/trùng tên, bản nháp + xác nhận.
- [x] Lưu văn bản nháp local; adapter proxy STT, thu tối đa 60 giây, đồng ý gửi từng bản ghi và không tự retry.
- [ ] Đo chất lượng Speech trên iPhone tiếng Việt, lỗi mạng/thu âm/cuộc gọi chen ngang.
- [ ] Mở rộng số lượng bằng chữ và ngày tự nhiên ngoài hôm nay/hôm qua; hiện yêu cầu sửa thủ công.

## Phase 4 — OCR: đã viết mã, cần đánh giá độ chính xác

- [x] Camera tài liệu nhiều trang, Photos, xoay, tăng tương phản/sharpen, giữ ảnh nguồn local.
- [x] Vision theo ngôn ngữ runtime, parser dòng sổ, cảnh báo thiếu năm/sai ngày/tiền mơ hồ.
- [x] Review ảnh và từng dòng; sửa khách/ngày/tiền/loại/số lượng/đơn giá, xóa dòng, tổng và dư dự kiến.
- [x] Validation quantity × price, import nhóm atomic, khóa import trùng, liên kết ảnh gốc.
- [x] Adapter AI Vision proxy: phiên Keychain, HTTPS, consent từng trang, timeout/cancel/giới hạn.
- [ ] Triển khai proxy bảo mật và ghép nối thiết bị; chưa có credential, không gọi dịch vụ trả phí.
- [ ] Đánh giá trên tập sổ viết tay tiếng Việt thật được người dùng cho phép; hiện không có ảnh mẫu thực tế.
- [ ] Công cụ crop thủ công cho ảnh chọn từ Photos; hiện crop/phối cảnh qua document camera, Photos có xoay/tăng độ rõ.

## Phase 5 — Reliability: đã viết mã, chờ kiểm chứng trên Apple SDK

- [x] Backup toàn snapshot, ảnh và drafts; version/hash/quan hệ; AES-GCM + PBKDF2 tùy chọn.
- [x] Restore SQL atomic, giữ audit trước restore, không đổi sổ nếu lỗi.
- [x] Files/Share Sheet, CSV, PDF báo cáo/phiếu đối chiếu, nhắc hạn local, khóa thiết bị.
- [x] Kiểm tra SQL thật trên Windows: constraints/FK/unique/append-only audit/rollback.
- [ ] XCTest mã hóa/khôi phục/migration; thử ngắt ứng dụng khi ghi và khi restore trên thiết bị.
- [ ] Thử quyền thông báo, DST/timezone, Face ID/mật mã, background/privacy và hạn mức iOS.

## Phase 6 — Release: chưa hoàn tất

- [x] Hướng dẫn build, ký mã/cài iPhone, backup và hợp đồng proxy.
- [x] Chốt Codemagic; thêm hai workflow verify/TestFlight, automatic signing bằng CLI, versioning và artifact checks.
- [x] Nối origin, push source và thêm ứng dụng Codemagic kp-managerMT.
- [x] Thêm 2 UI tests với database Debug Simulator riêng, gói Simulator và ảnh chụp UI thật.
- [x] Khởi chạy build ios-verify đầu tiên trên Codemagic; kết quả cuối chưa ghi nhận ở checkpoint này.
- [x] App icon iPhone và 1024px RGB, script tái tạo icon.
- [x] 17 kiểm thử pipeline trên Windows, gồm lỗi Swift giả lập qua Bash và chặn nhầm Apple ID sang app cũ; không gọi Apple.
- [ ] Compile/build/test bằng Xcode và xử lý lỗi SDK/type checking nếu có.
- [ ] Visual QA light/dark, Dynamic Type lớn, VoiceOver và chữ tiếng Việt.
- [ ] Kiểm tra privacy manifest và export compliance theo cấu hình phát hành/proxy thực tế.
- [ ] Tạo Bundle ID/hồ sơ Sổ Nợ AI trong App Store Connect; nhập ID và hai private key trong group Codemagic.
- [ ] Chạy ios-verify rồi ios-testflight, xử lý Apple processing và thêm nhóm tester nội bộ.
- [ ] Profiling bộ nhớ/tốc độ, UI tests và kiểm thử trên iPhone vật lý.
- [ ] Kiểm tra restore bản sao lưu trên thiết bị khác trước khi dùng lâu dài.

## Vấn đề và giới hạn còn lại

- Chưa có binary iOS; tree-sitter không phát hiện được lỗi kiểu, actor isolation hoặc lỗi API/linker.
- Proxy chỉ có adapter và hợp đồng; chưa có server hoặc attestation/pairing triển khai. Không coi URL hay mã app cố định là xác thực.
- Parser local cố ý hạn chế: không giải mọi cách nói, không tự gán tiền/ngày thiếu căn cứ. Vision không được bảo đảm đọc đúng chữ viết tay.
- Một snapshot vẫn nạp ảnh/drafts vào bộ nhớ; chỉ danh sách UI được phân trang. Cần tách truy vấn metadata/ảnh lazy và streaming backup để hỗ trợ kho ảnh lớn hơn giới hạn hiện tại.
- Nhắc local chỉ được lên lịch cho tối đa 28 khoản và các mốc tương lai. Khoản đã quá cả mốc +1 ngày vẫn hiện trên dashboard nhưng chưa có thông báo bù.
- SQLite có schema v1 và chặn schema mới hơn; chưa có v2 để kiểm thử migration nâng cấp dữ liệu thực tế.
- Chưa có undo cho thao tác gộp khách; giao dịch gốc và nhật ký vẫn còn.

## Bước tiếp theo cụ thể

1. Push source lên repository, kết nối Codemagic và chạy `ios-verify` theo `docs/CODEMAGIC.md`; không cần sở hữu Mac.
2. Tạo app mới trong tài khoản Apple hiện có, cấu hình group Secret và chạy `ios-testflight`. Sửa lỗi compiler/SDK nếu có; kiểm tra checklist trong `docs/VERIFICATION.md`.
3. Đo tải và đánh giá Speech/OCR trên iPhone, hoàn thiện các giới hạn phía trên.
4. Chỉ bật proxy sau khi triển khai xác thực thiết bị, giới hạn ngân sách và chính sách không lưu nội dung.
