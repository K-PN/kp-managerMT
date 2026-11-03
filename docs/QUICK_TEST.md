# Kiểm thử Sổ Nợ AI

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

Đã tạo app record **Sổ Nợ AI**, Apple ID **6830292186**, Bundle ID **vn.kpn.sonoai** và nhóm **SoNo AI Internal** với tài khoản chủ sở hữu. Chủ tài khoản đã chấp nhận thỏa thuận Developer cập nhật. Codemagic đã có group `sono_app_store`, integration và provisioning profile; release workflow đang được kiểm chứng. Sau upload và Apple processing, thêm build vào nhóm này. Xem [CODEMAGIC.md](CODEMAGIC.md).

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
