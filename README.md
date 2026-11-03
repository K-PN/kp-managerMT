# Sổ Nợ AI · SoNo AI

Ứng dụng iPhone cá nhân bằng **Swift + SwiftUI**, iOS 17 trở lên. Sổ khách hàng, giao dịch, ảnh và nhật ký nằm trong SQLite trên iPhone. Không có tài khoản ứng dụng, quảng cáo, Firebase hay Supabase. Tiền dùng `Int64` nguyên đồng; lịch và hiển thị dùng `Asia/Ho_Chi_Minh`.

**Trạng thái:** [build ios-testflight #4](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aea267da87b4d255fde3a68), source `f342836`, thành công sau 7m14s: **36/36 XCTest** (31 core, 3 app smoke, 2 UI), archive/export IPA ký Distribution và **Apple xác nhận upload thành công**. Phiên bản **1.0.0 (10)** đang **Testing** trong nhóm **SoNo AI Internal**, tài khoản chủ sở hữu đã được mời. Bundle ID `vn.kpn.sonoai`, iPhone iOS 17+. Luồng tạo khách → ghi nợ 500.000đ → thu 200.000đ → dư 300.000đ đã đạt. Có [ảnh chạy thật](docs/screenshots/README.md). Chưa kiểm chứng trên iPhone thật. Xem [cách cài và test](docs/QUICK_TEST.md), [báo cáo kiểm tra](docs/VERIFICATION.md).

Source đã push lên GitHub. [Mở build và kịch bản test](docs/QUICK_TEST.md); kết quả cập nhật trên trang Codemagic.

## Build và cài qua TestFlight khi không có Mac

Phương án chính đã chọn là **Codemagic**. [Hướng dẫn đầy đủ từ Windows](docs/CODEMAGIC.md) giải thích cách tạo Bundle ID/app mới trong tài khoản Apple Developer hiện tại, nối GitHub `K-PN/kp-managerMT`, chạy kiểm tra, cấu hình signing và upload TestFlight.

`codemagic.yaml` có `ios-verify` không cần khóa Apple và `ios-testflight` ký IPA rồi upload App Store Connect. Các bước test phải đạt trước khi ký/upload. Hai workflow chạy thủ công. Bản ký dùng integration `qhs_apple` và managed signing assets trong Codemagic; group `sono_app_store` giữ Team ID và Apple ID của app mới. Không đưa private keys vào repo.

## Mở và kiểm tra trên Mac

Cài Xcode có SDK hỗ trợ iOS 17+, mở Xcode để hoàn tất thiết lập và cài iPhone Simulator. Sau đó, tại thư mục dự án:

```sh
brew install xcodegen
swift test
xcodegen generate
open SoNoAI.xcodeproj
```

Chọn scheme **SoNoAI**, chọn một iPhone Simulator có sẵn, rồi **Product → Test** và **Run**. Scheme chạy `SoNoAppTests` và `SoNoUITests`; bộ kiểm thử nghiệp vụ, SQLite và sao lưu chạy bằng `swift test`. Không cần API key để build hoặc sử dụng phần lõi.

Ví dụ chạy từ terminal, thay tên Simulator bằng thiết bị cài trên máy:

```sh
xcrun simctl list devices available
xcodebuild -project SoNoAI.xcodeproj -scheme SoNoAI \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test
```

GitHub Actions trong `.github/workflows/ios.yml` giữ làm phương án chạy thủ công dự phòng và chưa chạy; Codemagic là pipeline chính và đã chạy kiểm tra cloud.

## Cài trên iPhone cá nhân

1. Kết nối iPhone với Mac và bật Developer Mode nếu iPhone yêu cầu.
2. Trong Xcode → target SoNoAI → Signing & Capabilities, chọn Development Team của bạn. Đổi bundle identifier nếu cần.
3. Chọn iPhone làm run destination và bấm Run. Làm theo yêu cầu Trust/Developer Mode trên thiết bị.
4. Kiểm tra toàn bộ luồng trong `docs/VERIFICATION.md` bằng dữ liệu thử trước. Thời hạn chữ ký và quyền phân phối phụ thuộc loại tài khoản Apple của bạn.

Tệp `.xcodeproj` được sinh từ `project.yml` và không đưa vào Git. Không có chứng chỉ, provisioning profile hay thông tin nhóm ký mã trong repo.

## Sử dụng

- **Khách hàng:** tạo/sửa tên, biệt danh, điện thoại, địa chỉ, ghi chú; tìm không dấu; xác nhận khi trùng tên; gộp hồ sơ có lưu dấu vết. Không cung cấp chức năng xóa lịch sử tài chính.
- **Giao dịch:** ghi nợ/cho vay, thu một phần/toàn bộ, tôi vay/tôi trả, nhận trả trước/cấn trừ và điều chỉnh phải thu. Khoản thu vượt nợ bị chặn; phần trả trước phải ghi riêng. Có ngày hiệu lực, hạn trả, ghi chú và ảnh chứng từ.
- **Điều chỉnh:** ghi hoàn tác và bản thay thế trong cùng transaction. Hoàn tác có thể bị từ chối nếu làm các khoản thu còn lại vượt nợ.
- **Tổng quan:** tính từ sổ thật, gồm phải thu/phải trả/trả trước, thu hôm nay/tháng này, nợ quá hạn sau phân bổ FIFO, khách nợ nhiều và hạn trả trong 7 ngày.
- **Giọng nói:** nút micro luôn có trên màn hình chính. Apple Speech `vi-VN` kiểm tra khả năng xử lý tại chỗ; chỉ cho phép máy chủ Apple khi bạn bật tùy chọn cho lần đó. Có đường thu âm qua proxy riêng sau xác nhận. Văn bản vẫn sửa được khi mất mạng và được lưu bản nháp local. Không tự tạo khách hoặc ghi sổ.
- **Quét sổ:** camera nhiều trang có công cụ cắt/xoay/chỉnh phối cảnh của iOS; hoặc chọn từ Photos. Giữ dữ liệu nguồn, xử lý ảnh ngoài main thread, xoay/tăng độ rõ, thử Vision hoặc gửi riêng trang đang xem tới proxy sau đồng ý. Đối chiếu ảnh, sửa từng dòng, chọn khách, xác nhận rồi nhập nhóm atomically. Không giả định Vision đọc tốt chữ viết tay tiếng Việt.
- **Báo cáo:** thu nợ theo ngày/tuần/tháng, CSV toàn sổ, PDF báo cáo và phiếu đối chiếu theo khách. CSV có chống công thức từ nội dung người dùng. Share Sheet chỉ do bạn mở và chọn nơi gửi.
- **Nhắc hạn:** bật quyền trong Cài đặt, tạo thông báo local trước hạn một ngày và sau hạn một ngày; không gửi SMS/Zalo. Lịch được cập nhật khi mở sổ hoặc ghi dữ liệu, giới hạn 28 khoản với tối đa 56 thông báo.
- **Bảo vệ:** khóa bằng xác thực thiết bị, file protection của iOS, phiên proxy trong Keychain. Không có secret trong UserDefaults hay mã nguồn.

## Sao lưu và khôi phục

Mở **Cài đặt → Sao lưu và khôi phục**. Đặt mật khẩu ít nhất 10 ký tự nếu muốn mã hóa, hoặc để trống để xuất tệp có thể đọc được. Bản sao gồm khách, giao dịch, audit, ảnh và bản nháp. Dùng **Tạo bản sao lưu**, sau đó **Lưu vào Tệp** hoặc **Chia sẻ**; tạo tệp tạm chưa có nghĩa là đã lưu một bản bên ngoài ứng dụng.

Mã hóa dùng AES-GCM, khóa dẫn xuất PBKDF2-HMAC-SHA256 với salt ngẫu nhiên 16 byte và 310.000 vòng. Mật khẩu không được giữ lại. Backup có version và SHA-256 để phát hiện lỗi dữ liệu; backup không mã hóa không chống người chủ động sửa nội dung rồi tính lại hash.

Để khôi phục, nhập mật khẩu tương ứng, chọn `.sono`, đọc cảnh báo và xác nhận. Kiểm tra phiên bản, UUID, liên kết khách/ảnh/hoàn tác, audit và cân đối sổ trước khi thay dữ liệu trong **một SQLite transaction**. Giữ lại audit hiện tại và thêm sự kiện khôi phục; lỗi validation/ghi dữ liệu rollback về sổ trước đó. **Khôi phục không gộp các giao dịch mới hơn với bản cũ.** Hãy xuất sổ hiện tại trước.

Giới hạn hiện tại: snapshot backup tối đa 256 MB trước đóng gói; bản nháp quét tối đa 10 trang/60 MB ảnh nguồn; mỗi ảnh tối đa 20 MB. Cần lưu bản sao ở thiết bị hoặc nơi lưu khác: bản sao chỉ ở cùng iPhone vẫn có thể mất cùng máy. Không phụ thuộc iCloud để sử dụng.

## AI online tùy chọn

Để trống cấu hình nếu chưa có proxy. Adapter có sẵn cho `/handwriting` và `/transcribe`, dùng HTTPS, phiên ngắn hạn trong Keychain, không redirect, timeout, giới hạn dữ liệu và hủy request. Không gọi trực tiếp OpenAI, không dùng model giả, không tự fallback sang nhà cung cấp có phí và không retry âm thầm.

Xem [docs/AI_PROXY.md](docs/AI_PROXY.md) để triển khai hợp đồng API và cơ chế ghép nối. **Repo chưa triển khai proxy, chưa cấp mã phiên và chưa kết nối nhà cung cấp AI trả phí.** Phần lõi không cần chúng.

## Cấu trúc và dữ liệu

- `App/Presentation`: SwiftUI + AppModel; tiền được tính qua domain/service.
- `App/Services`, `App/Security`: Speech, camera/Vision, xử lý ảnh, thông báo, PDF, Keychain và proxy.
- `Sources/SoNoCore/Domain`: mô hình và thuật toán xác định.
- `Sources/SoNoCore/Data`: actor nghiệp vụ, validation, ghi dữ liệu và audit.
- `Sources/SoNoCore/Persistence`: SQLite, migrations có phiên bản; WAL, foreign keys, synchronous FULL.
- `Sources/SoNoCore/Services`, `Security`: protocols, parser, báo cáo và sao lưu.
- `Tests/SoNoCoreTests`, `AppTests`: XCTest, chỉ dùng dữ liệu thử riêng.

Chi tiết schema và quy tắc trong [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Mỗi thay đổi schema phải thêm migration mới, không sửa dữ liệu cũ bằng cách tạo lại database. Khi mở lỗi, ứng dụng dừng mở sổ và hiển thị lỗi, không thay sổ bằng database trống.

## Kiểm tra trên Windows

```powershell
python -m pip install -r scripts/requirements-dev.txt
python scripts/check_workspace.py
python -m unittest discover -s scripts/tests -v
git diff --check
```

Script workspace phân tích cú pháp Swift bằng tree-sitter, kiểm tra cấu hình và chạy SQL migration/ràng buộc/rollback bằng SQLite của Python. Bộ test CI kiểm tra ID, versioning, chọn Simulator, spec sinh ra, icon, metadata IPA và việc lỗi test dừng pipeline. **Không thay thế Swift compiler, XCTest hoặc kiểm tra giao diện iOS.** Không có PWA hay ứng dụng web thay thế.

Nguồn API đã đối chiếu: [Apple Speech](https://developer.apple.com/documentation/speech/sfspeechrecognizer), [Apple Vision](https://developer.apple.com/documentation/vision/vnrecognizetextrequest), [privacy manifest](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest). Khả năng offline và ngôn ngữ OCR vẫn được kiểm tra tại runtime.
