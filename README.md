# Tạp Hóa Mỹ Thạnh

Ứng dụng iPhone cá nhân bằng **Swift + SwiftUI**, iOS 17 trở lên. Sổ khách hàng, giao dịch, ảnh và nhật ký nằm trong SQLite trên iPhone. Không có tài khoản ứng dụng, quảng cáo, Firebase hay Supabase. Tiền dùng `Int64` nguyên đồng; lịch và hiển thị dùng `Asia/Ho_Chi_Minh`.

**Bản cập nhật 1.1.0:** đã bổ sung quản lý nhập hàng, số tiền còn nợ nhà cung cấp, xác nhận giọng nói, bộ lọc ngày và tổng báo cáo. [Build mới](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aea9e93a87b4d255fde5cd2) biên dịch core thành công, đạt 37/38 XCTest và dừng ở lỗi phân tích “Thêm khách mới … ghi nợ 300 nghìn”. Đã sửa việc nhầm “mới” với “mỗi” và bổ sung hai regression tests; bản sửa đạt 7 kiểm tra workspace và 18 kiểm thử pipeline trên Windows, **chờ chạy lại native tests, chưa upload 1.1.0**. Phiên điều khiển Chrome vẫn lỗi. Xem [kịch bản kiểm thử bản mới](docs/QUICK_TEST.md) và [báo cáo kiểm tra](docs/VERIFICATION.md).

Bản TestFlight đã kiểm chứng trước đó là **1.0.0 (10)**, source `f342836`, [release #4](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aea267da87b4d255fde3a68), 36/36 XCTest đạt, đang Testing trong nhóm SoNo AI Internal. Các [ảnh hiện có](docs/screenshots/README.md) thuộc bản cũ. Bundle ID vẫn `vn.kpn.sonoai` để giữ dữ liệu khi nâng cấp. Chưa kiểm chứng trên iPhone thật.

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

- **Khách hàng:** tạo/sửa tên, biệt danh, điện thoại, địa chỉ; tìm không dấu; xác nhận khi trùng tên; gộp hồ sơ có lưu dấu vết. Có thể đề xuất thêm khách qua giọng nói và chỉ lưu khi xác nhận.
- **Giao dịch:** ghi nợ, thu nợ, nhập hàng và trả tiền hàng. Nhập hàng có mặt hàng, tổng tiền, đã trả và phần còn nợ nhà cung cấp. Không yêu cầu hạn trả. Lịch sử và loại giao dịch cũ được giữ lại; sổ có bộ lọc từ ngày–đến ngày, bao gồm cả ngày cuối.
- **Điều chỉnh:** ghi hoàn tác và bản thay thế trong cùng transaction. Hoàn tác có thể bị từ chối nếu làm các khoản thu còn lại vượt nợ.
- **Tổng quan:** bốn thẻ đồng cấp: Tổng nợ, Tiền hàng tháng này, Tiền hàng tuần này, Tổng nợ tiền hàng. Tháng/tuần tính tổng giá trị hàng nhập gồm đã trả và còn nợ; tổng nợ tiền hàng chỉ tính phần chưa trả nhà cung cấp. Tuần bắt đầu thứ Hai, múi giờ Việt Nam.
- **Giọng nói:** mở là bắt đầu Apple Speech `vi-VN`, cho phép Apple xử lý trực tuyến. iOS vẫn yêu cầu quyền micro và Speech lần đầu. Chạm micro để dừng và tự phân tích; văn bản sửa được. Kết quả tạm đối chiếu khách, nợ cũ và số dư sau giao dịch. Chỉ nút **Xác nhận** mới lưu khách mới và giao dịch trong cùng một transaction; đóng màn hình bỏ kết quả chưa xác nhận.
- **Quét sổ:** camera nhiều trang có công cụ cắt/xoay/chỉnh phối cảnh của iOS; hoặc chọn từ Photos. Giữ dữ liệu nguồn, xử lý ảnh ngoài main thread, xoay/tăng độ rõ, thử Vision hoặc gửi riêng trang đang xem tới proxy sau đồng ý. Đối chiếu ảnh, sửa từng dòng, chọn khách, xác nhận rồi nhập nhóm atomically. Không giả định Vision đọc tốt chữ viết tay tiếng Việt.
- **Báo cáo:** nhập hàng/đã trả/thu nợ theo kỳ; CSV và PDF có tổng tiền hàng, tổng trả tiền hàng, tổng thu nợ, nợ khách và nợ tiền hàng. CSV chống công thức từ nội dung người dùng. Share Sheet do bạn mở và chọn nơi gửi.
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
