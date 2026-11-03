# Kết quả kiểm tra và việc còn cần chạy

Ngày 03/11/2026. Môi trường: Windows PowerShell 5.1, workspace mới, không có Swift/Xcode/iOS SDK. Không cài toolchain toàn hệ thống, không có build iOS, không chạy dịch vụ AI hay gửi dữ liệu ra provider.

## Đã thực hiện trên Windows

`python scripts/check_workspace.py` chạy thành công **7 kiểm tra**:

1. Parse tất cả tệp Swift bằng tree-sitter, không có nút lỗi cú pháp.
2. Đọc XcodeGen YAML, kiểm tra deployment target, target test và resource migration.
3. SQLite thực thi migration v1 và chặn foreign key/số tiền không hợp lệ.
4. SQLite chặn import key trùng và hoàn tác trùng.
5. Trigger audit chặn UPDATE và DELETE.
6. Lỗi insert audit rollback giao dịch cùng transaction.
7. Restore xóa các dòng tự tham chiếu rồi gặp lỗi FK rollback lại dữ liệu; integrity check là `ok`.

Các kiểm tra SQLite dùng Python SQLite thực thi chính tệp SQL migration của app; **chúng không chạy `SQLiteStore.swift` hoặc `LedgerService.swift`**. Tree-sitter chỉ kiểm tra cú pháp, không kiểm tra kiểu, API, concurrency hoặc linking.

Sau khi thêm Codemagic, `python -m unittest discover -s scripts/tests -v` chạy đạt **17 kiểm thử pipeline**: preflight ID/PEM và không ghi keys vào metadata, xử lý số build đầu/đang có/lỗi, chọn Simulator, sinh spec không sửa source, chặn nhầm Apple ID sang Bundle ID app cũ, dừng khi API lỗi, kích thước PNG không alpha, kiểm tra metadata và tài nguyên signing của IPA fixture, thứ tự test trước signing, cú pháp Bash, mô phỏng Swift trả mã lỗi 47 qua `tee`, tạo key fixture không ghi đè và dọn file khi OpenSSL lỗi. Không có test nào gọi Apple, tạo chứng chỉ hoặc kiểm tra chữ ký IPA thật.

## Đã viết nhưng chưa chạy

Tổng cộng **34 phương thức XCTest** trong core và app. Core gồm: tạo/sửa/trùng/gộp khách; ghi/thu một phần/toàn bộ/vượt nợ; phải trả/trả trước; overflow; FIFO; hoàn tác và thay thế; rebuild số dư; báo cáo; CSV injection; parser tiền tiếng Việt; số lượng × đơn giá; intent/query/mơ hồ/trùng tên; OCR example/review/validation/duplicate; atomic audit; lưu/reopen ngoại tuyến và draft; restore validation/nhật ký; migration v1 và schema mới hơn; mã hóa backup/mật khẩu sai/tamper.

Bổ sung **2 UI tests** trong `AppUITests`: chụp các màn hình chính; tạo khách rồi ghi nợ 500.000, thu 200.000 và kiểm tra dư 300.000. Chỉ dùng database riêng của Debug Simulator, không trộn dữ liệu thử vào sổ thông thường. Hai test này chưa chạy trên môi trường Windows.

`AppTests` có smoke test định dạng VND, ảnh hỏng và đọc cấu hình Keychain mà không gọi mạng. Codemagic đã cấu hình chạy Swift package tests rồi sinh project và chạy native app tests trước khi ký mã; GitHub Actions giữ làm dự phòng thủ công. CI chưa chạy, không có trạng thái pass cho XCTest hoặc build.

## Trình tự kiểm chứng trên Mac

1. `swift test`; sửa mọi lỗi compiler và assertion trước.
2. `xcodegen generate`; mở `SoNoAI.xcodeproj`, chọn scheme SoNoAI và iPhone Simulator.
3. Product → Test; Product → Run. Build không ký mã trên Simulator; kiểm tra ký mã riêng trên iPhone.
4. Thử bộ dữ liệu thử local: 500.000 ghi nợ, 250.000 ghi nợ, 300.000 thu → dư 450.000. Thử thu vượt nợ, hoàn tác thu, hoàn tác nợ đang có khoản thu, điều chỉnh có lý do.
5. Tạo hai khách cùng tên khác điện thoại, tra cứu giọng nói phải yêu cầu chọn người. Thử “hai triệu ba” phải sửa số tiền; “5 bao mỗi bao 90 nghìn” phải đề xuất 450.000 và vẫn yêu cầu xác nhận.
6. Tắt Wi-Fi/mobile data: tạo/sửa/ghi/thu/tra cứu/báo cáo phải hoạt động. Speech phải thông báo nếu `supportsOnDeviceRecognition` không có. Đóng/mở lại app và màn hình để kiểm tra draft giữ nguyên.
7. Camera nhiều trang và Photos: so ảnh gốc với kết quả, sửa ngày/năm/tiền/khách, bỏ dòng lỗi, xác nhận riêng. Dòng không xác nhận không được nhập. Cố nhập trùng ảnh/dòng và batch có một dòng lỗi: không được ghi một phần.
8. Backup với ảnh/draft, dùng mật khẩu đúng/sai, sửa một byte, schema mới, ảnh/link/UUID lỗi; so dữ liệu trước/sau và kiểm tra restore audit. Thử hết dung lượng và force quit khi ghi/restore bằng thiết bị thử.
9. Bật/tắt thông báo, đổi hạn trả, thu hết nợ, kiểm tra lịch được hủy/cập nhật. Khoản đã quá mốc +1 ngày hiện chỉ có trong dashboard, chưa có nhắc bù.
10. Face ID/mật mã/lock khi app vào background, ảnh chụp màn hình app switcher, Dynamic Type lớn, VoiceOver, light/dark và bàn phím tiếng Việt.
11. Kiểm tra layout PDF nhiều trang, Unicode, dòng dài; CSV mở Excel/Numbers đúng VND, encoding và không thực thi công thức từ tên/ghi chú.
12. Profiling với hàng nghìn khách và hàng chục nghìn giao dịch, cả trường hợp nhiều ảnh. Snapshot hiện giữ ảnh trong bộ nhớ; cần đo trước khi dùng đến giới hạn.

## Trước khi bật proxy hoặc dùng dữ liệu thật

Triển khai server theo `AI_PROXY.md`; kiểm thử token sai/hết hạn, không log PII, rate limit, ngân sách, body quá lớn, redirect bị chặn, hủy request, mất mạng và server lỗi. Cần ảnh sổ viết tay tiếng Việt được phép sử dụng để đo độ chính xác. Không có điểm số OCR hoặc cam kết offline Speech khi chưa đo.

App icon đã được tạo và kiểm tra kích thước/RGB trên Windows. Kiểm tra privacy report/App Store, export compliance, UI automation và test thiết bị vật lý chưa hoàn tất. Source là cơ sở triển khai và kiểm chứng, chưa phải bản phát hành được chứng nhận. Lộ trình build khi không sở hữu Mac ở [CODEMAGIC.md](CODEMAGIC.md).
