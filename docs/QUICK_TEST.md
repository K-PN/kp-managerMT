# Kiểm thử Tạp Hóa Mỹ Thạnh

## Bản cập nhật 1.1.0 (15) — sẵn sàng trên TestFlight

[Build #9](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aebd854004ce28f20edfb86), commit `3f100ac`, thành công sau 9m50s: **48/48 XCTest đạt** (40 core + 4 app smoke + 4 UI), đã ký IPA **1.1.0 (15)** và Apple xác nhận upload thành công. Lỗi khởi động XCTest Runner của build #8 không lặp lại. Ngày 05/11/2026, Apple processing và khai báo mã hóa hoàn tất; nhóm **SoNo AI Internal** hiển thị bản **1.1.0 (15)** đang **Testing**, cùng tester hiện có. Kết quả 36 XCTest và các ảnh bên dưới thuộc bản 1.0.0.

Mở TestFlight trên iPhone → **Tạp Hóa Mỹ Thạnh → Update**, kiểm tra phiên bản **1.1.0 (15)**. Giữ ứng dụng hiện tại để kiểm tra dữ liệu cũ còn nguyên. Dùng khách và chứng từ thử riêng:

1. Kiểm tra tên dưới icon, màn hình mở và trong app: **Tạp Hóa Mỹ Thạnh**, mô tả **Quản lý giao dịch - hàng hóa**.
2. Tạo khách thử, ghi nợ 500.000đ rồi thu 200.000đ: tổng nợ còn **300.000đ**, không cần hạn trả.
3. Tạo nhà cung cấp thử, nhập “2 thùng mì”, tổng **1.000.000đ**, đã trả **400.000đ**: nợ tiền hàng **600.000đ**. Tiền hàng tháng/tuần tăng đủ **1.000.000đ** nếu ngày nhập thuộc kỳ. Trả tiếp 100.000đ: nợ tiền hàng còn **500.000đ**, giá trị hàng nhập không đổi.
4. Bấm nút nói, cấp quyền iOS lần đầu. Nói “Thêm khách mới Chi Mai ghi nợ ba trăm nghìn”, chạm micro để phân tích. Kiểm tra tên, nợ cũ và số dư dự kiến; đóng mà không xác nhận phải không tạo khách/giao dịch. Lặp lại và bấm **Xác nhận** chỉ ghi một lần.
5. Với nhà cung cấp đã tạo, nói “Nhập hàng của [tên nhà cung cấp], gồm hai thùng mì, tổng một triệu, đã trả bốn trăm nghìn, còn nợ sáu trăm nghìn”. Đối chiếu mặt hàng, tổng tiền, đã trả, nợ cũ và nợ sau. Sửa văn bản hoặc các ô kết quả nếu nhận dạng sai, rồi mới xác nhận.
6. Ở Sổ giao dịch, bật lọc từ ngày–đến ngày; giao dịch cuối ngày kết thúc phải vẫn hiện. Kiểm tra riêng Nợ/Tiền hàng và từng khách.
7. Xuất CSV/PDF: kiểm tra hàng **TỔNG CỘNG** và các tổng so với giao dịch thử; khoản đã hoàn tác không được cộng vào tổng.
8. Đóng/mở app, thử nhập thủ công khi mất mạng và đối chiếu số dư. Kiểm tra micro trên iPhone thật; Simulator không chứng minh chất lượng Apple Speech hoặc thời điểm kết thúc câu.

## Lịch sử bản 1.0.0

Đã có giao diện SwiftUI và source chức năng: tổng quan, khách hàng, ghi/thu nợ, lịch sử, audit, voice/OCR có review, báo cáo, backup và cài đặt. Tình trạng chạy thực tế xem build Codemagic, không suy ra từ việc có source.

## Xem kết quả build thật

Repository: [K-PN/kp-managerMT](https://github.com/K-PN/kp-managerMT). Bản test đã đạt: [ios-verify #6](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aea18dba87b4d255fde356e), source `a65fd40`, **36/36 XCTest đạt** (31 core + 3 app smoke + 2 UI). Thời gian 5m52s trên Mac mini M2. UI đã tạo khách, ghi nợ 500.000đ, thu 200.000đ và kiểm tra dư 300.000đ.

`ios-verify` chạy trên Mac mini M2, gồm XCTest core và UI test trên iPhone Simulator. Nếu đạt, Artifacts có:

- `SoNoAI-simulator.zip`: ứng dụng native cho Simulator, không phải IPA để cài iPhone.
- Screenshot attachments: tổng quan, khách hàng, sổ giao dịch, cài đặt và số dư sau ghi nợ/thu một phần.
- Log và `xcresult`: kết quả chạy thật để chẩn đoán nếu build hoặc UI test lỗi.

Ảnh chỉ được tạo khi UI test chạy app; không có ảnh giao diện giả thay cho kết quả build. Simulator không kiểm chứng đầy đủ camera, micro, Face ID hay chất lượng nhận dạng.

## Ảnh chạy thật và tùy chọn App Preview

Người dùng đã chọn **TestFlight trên iPhone**. Chưa bật trial App Preview. Codemagic có **Quick launch** cho artifact Simulator, nhưng đây là lựa chọn riêng có thể yêu cầu gói trả phí; tải `.app` về Windows không thay thế Simulator. Xem [tài liệu App Preview](https://docs.codemagic.io/yaml-distributing/app-preview/) nếu sau này cần cách này.

Các ảnh từ build #6: [Tổng quan](screenshots/01-dashboard.png), [Khách hàng](screenshots/02-customers.png), [Sổ giao dịch](screenshots/03-ledger.png), [Cài đặt](screenshots/04-settings.png), [sau ghi nợ](screenshots/05-customer-after-debt.png), [sau thu một phần](screenshots/06-customer-after-partial-payment.png). App record/khóa ký Apple không cần cho cách chạy thử Simulator này.

## Test trên iPhone qua TestFlight

**Đã sẵn sàng:** build **1.0.0 (10)** đang **Testing** trong **SoNo AI Internal**; tài khoản chủ sở hữu đã có trạng thái **Invited**. [Release #4](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aea267da87b4d255fde3a68), source `f342836`, đã đạt 36/36 XCTest, ký IPA và upload Apple thành công. Apple processing và khai báo mã hóa đã hoàn tất. App Store Apple ID **6830292186**, Bundle ID **vn.kpn.sonoai**.

Trên iPhone iOS 17 trở lên:

1. Cài **TestFlight** từ App Store.
2. Mở email mời của Apple tại địa chỉ tài khoản chủ sở hữu đã được thêm vào nhóm.
3. Bấm **View in TestFlight → Accept → Install** cho **Sổ Nợ AI 1.0.0 (10)**. Nếu đã nhận lời mời, mở TestFlight để tìm ứng dụng.

[Mở nhóm kiểm thử trong App Store Connect](https://appstoreconnect.apple.com/teams/089cecc4-21e3-4285-bd8a-d5707654ad78/apps/6830292186/testflight/groups/06051f02-259a-4305-ac14-c0bbdc1b22f6/builds). Đây là trang quản lý yêu cầu đăng nhập, không phải link beta công khai. Xem [CODEMAGIC.md](CODEMAGIC.md) để build lại từ Windows.

Khi cài được bản TestFlight, dùng dữ liệu thử riêng:

1. **Khách hàng:** tạo `Khách thử nghiệm`, thêm biệt danh và điện thoại. Tìm bằng tên không dấu.
2. **Ghi nợ:** mở khách → thêm giao dịch → Ghi nợ `500000` → bật xác nhận → Ghi sổ. Phải thu là **500.000đ**.
3. **Thu một phần:** thêm Thu nợ `200000`. Phải thu còn **300.000đ**.
4. **Chặn vượt nợ:** thử thu `400000`. Ứng dụng phải báo lỗi, số dư vẫn **300.000đ**, không tạo giao dịch mới.
5. **Hoàn tác:** mở khoản thu `200000`, nhập lý do rồi hoàn tác. Phải thu trở về **500.000đ**; lịch sử giữ cả bản gốc và hoàn tác.
6. **Voice:** nói “Khách thử nghiệm trả hai trăm nghìn”; kiểm tra đúng người, loại và tiền trước khi lưu. Nếu Speech không khả dụng, sửa văn bản hoặc dùng nhập thủ công.
7. **OCR:** chọn/chụp một trang thử, đọc bằng Vision, đối chiếu từng dòng, sửa khách/ngày/tiền, bật xác nhận rồi nhập. Không nhập sổ thật trước khi kiểm chứng độ chính xác.
8. **Offline:** tắt mạng và tạo giao dịch thủ công; đóng/mở ứng dụng, dữ liệu phải còn.
9. **Backup:** xuất bản sao có mật khẩu, lưu ra ngoài ứng dụng. Chỉ thử restore với dữ liệu thử vì restore thay sổ hiện tại bằng bản sao.

Nếu có lỗi, ghi lại màn hình/thao tác, số tiền kỳ vọng và kết quả thực tế; tránh đưa dữ liệu khách thật vào ảnh lỗi khi chưa cần thiết.
