# Kiểm thử Sổ Nợ AI

Đã có giao diện SwiftUI và source chức năng: tổng quan, khách hàng, ghi/thu nợ, lịch sử, audit, voice/OCR có review, báo cáo, backup và cài đặt. Tình trạng chạy thực tế xem build Codemagic, không suy ra từ việc có source.

## Xem kết quả build thật

Repository đã được push lên [K-PN/kp-managerMT](https://github.com/K-PN/kp-managerMT). Ứng dụng Codemagic: [kp-managerMT](https://codemagic.io/app/6aea10057cef5b806068b14c/settings). Build kiểm tra đầu: [ios-verify #1](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aea101fa87b4d255fde3204).

`ios-verify` chạy trên Mac mini M2, gồm XCTest core và UI test trên iPhone Simulator. Nếu đạt, Artifacts có:

- `SoNoAI-simulator.zip`: ứng dụng native cho Simulator, không phải IPA để cài iPhone.
- Screenshot attachments: tổng quan, khách hàng, sổ giao dịch, cài đặt và số dư sau ghi nợ/thu một phần.
- Log và `xcresult`: kết quả chạy thật để chẩn đoán nếu build hoặc UI test lỗi.

Ảnh chỉ được tạo khi UI test chạy app; không có ảnh giao diện giả thay cho kết quả build. Simulator không kiểm chứng đầy đủ camera, micro, Face ID hay chất lượng nhận dạng.

## Test trên iPhone qua TestFlight

Cần hoàn tất app record Sổ Nợ AI mới, Bundle ID riêng, group `sono_app_store`, chạy `ios-testflight` và thêm build vào nhóm tester sau Apple processing. Xem [CODEMAGIC.md](CODEMAGIC.md). App Store Connect tại thời điểm kiểm tra chỉ có QHS Manager và đang hiển thị yêu cầu Account Holder xem/chấp nhận thỏa thuận Developer cập nhật; chủ tài khoản cần tự thực hiện nếu Apple chặn upload.

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
