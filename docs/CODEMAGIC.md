# Build IPA và dùng TestFlight từ Windows

Repository: [K-PN/kp-managerMT](https://github.com/K-PN/kp-managerMT). `origin` local đã trỏ tới repository này; chưa push mã nguồn và chưa chạy build Codemagic trong phiên triển khai.

Có hai workflow trong [codemagic.yaml](../codemagic.yaml):

- `ios-verify`: không cần tài khoản/khóa Apple; kiểm tra source và CI scripts, chạy Swift package tests, sinh Xcode project, chạy app/UI tests trên iPhone Simulator. Nếu đạt, xuất `SoNoAI-simulator.zip` và screenshot attachments của giao diện thật trong Artifacts.
- `ios-testflight`: kiểm tra cấu hình, chạy cùng các test, lấy số build tiếp theo, lấy/tạo chứng chỉ và provisioning profile, archive Release, xuất IPA, kiểm tra metadata rồi upload App Store Connect. Sau Apple xử lý, bạn chọn build vào nhóm TestFlight nội bộ trên trang web.

Hai workflow chạy thủ công, không tự kích hoạt khi push. GitHub Actions cũ cũng chuyển sang chạy thủ công để dùng khi cần. Pipeline mới chưa được chạy trên macOS; các kiểm tra Windows không thay thế build thật.

## Bạn đã có Apple Developer: ID nào cần tạo mới?

**Apple Team ID giữ nguyên**, vì Sổ Nợ AI thuộc cùng tài khoản Developer với app bạn đã phát hành. Tìm ở [Apple Developer → Membership details](https://developer.apple.com/account).

**Bundle ID cần mới cho Sổ Nợ AI**, ví dụ `vn.kpn.sonoai` nếu bạn đăng ký được ID này. Vào [Certificates, Identifiers & Profiles → Identifiers](https://developer.apple.com/account/resources/identifiers/list), tạo explicit App ID cho iOS. Không dùng Bundle ID của app cũ, vì Apple sẽ coi đó là bản cập nhật app cũ.

**App Store Apple ID cũng mới và do Apple tự cấp**: vào [App Store Connect → Apps](https://appstoreconnect.apple.com/apps), tạo app mới, chọn iOS, tên Sổ Nợ AI, Bundle ID vừa đăng ký, ngôn ngữ Vietnamese và SKU riêng như `sono-ai-ios`. Mở App Information để lấy **Apple ID dạng số**. Đây không phải địa chỉ email Apple Account.

**Issuer ID, API Key ID và khóa `.p8`** có thể dùng lại nếu là team API key có đủ quyền, còn hiệu lực và bạn còn giữ private key. Tuy nhiên, dùng một team API key riêng cho Codemagic giúp quản lý/thu hồi độc lập. Tạo ở Users and Access → Integrations → App Store Connect API, quyền App Manager theo hướng dẫn Codemagic. Individual API key không hỗ trợ provisioning endpoints nên không phù hợp với workflow tự lấy/tạo signing assets này. [Apple API keys](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api), [Codemagic signing](https://docs.codemagic.io/partials/alternative-code-signing-methods-ios/).

Không cần tạo tài khoản Developer thứ hai. Việc này không thêm đăng nhập vào ứng dụng Sổ Nợ AI.

## 1. Đưa source lên GitHub

Trong PowerShell, tại `D:\4\App\ManagerMT`, sau khi xem lại các tệp:

```powershell
git add .
git commit -m "Build SoNo AI with Codemagic and TestFlight pipeline"
git branch -M main
git push -u origin main
```

Đăng nhập GitHub khi Git Credential Manager yêu cầu trên máy bạn. Repository được kiểm tra chưa có refs ở thời điểm cấu hình; nếu sau đó bạn đã thêm source khác vào remote, fetch và đối chiếu trước khi push. Không force push. `.gitignore` đã chặn `.p8`, `.p12`, `.pem`, `.key`, provisioning, IPA, tệp dữ liệu và thư mục signing local.

## 2. Kết nối Codemagic và chạy kiểm tra trước

Trong Codemagic, Add application, kết nối GitHub và chọn `K-PN/kp-managerMT`, cấu hình bằng `codemagic.yaml`. Chọn branch vừa push và scan configuration. Chạy **ios-verify** trước. Bước này không cần nhập thông tin Apple và chưa tạo IPA cài lên máy thật.

Khi build đạt, Artifacts có gói Simulator và ảnh chụp dashboard, khách hàng, sổ giao dịch, cài đặt, cùng ảnh sau ghi nợ/thu một phần. Các ảnh được tạo bằng UI test trên app chạy thật, không phải ảnh thiết kế. UI tests dùng database trống riêng với UUID cho mỗi lần chạy; không xóa hoặc seed dữ liệu vào database thông thường. Hook chọn kho test chỉ được biên dịch trong Debug Simulator. Gói `.app` này không cài trực tiếp lên iPhone; bản cài iPhone cần `ios-testflight` với signing.

Pipeline dùng Mac mini M2 với Xcode **26.1**, tự cài XcodeGen nếu chưa có và tạo Python venv. Signing CLI pin **codemagic-cli-tools 0.70.2** trong workflow phát hành. Xem [image Xcode 26.1](https://docs.codemagic.io/specs-macos/xcode-26-1/) và [Codemagic native iOS](https://docs.codemagic.io/yaml-quick-start/building-a-native-ios-app/).

Mọi thao tác tài chính và UI hiện mới là source chưa qua compiler Xcode. Nếu build đầu lỗi, mở step và tải `build/logs/*.log` để xử lý lỗi cụ thể. Pipeline dừng nếu test lỗi, không tiếp tục ký/upload.

## 3. Tạo distribution private key bằng Windows

Workflow dùng automatic signing qua Codemagic CLI. Ngoài `.p8` xác thực API, cần **RSA private key để tạo/tìm Apple Distribution certificate**. Đây là hai khóa khác nhau.

Máy Windows có OpenSSL 3+ có thể chạy:

```powershell
python scripts/create_signing_key.py
```

Script tạo `.local-signing/ios_distribution_private_key.pem`, không in nội dung và từ chối ghi đè tệp đã có. Script chỉ sinh key trên máy khi bạn chủ động chạy; phiên triển khai này chưa sinh key hoặc chứng chỉ Apple. Để sao chép vào trường Secret trên Codemagic:

```powershell
Get-Content -LiteralPath '.local-signing/ios_distribution_private_key.pem' -Raw | Set-Clipboard
```

Giữ khóa này để những lần build sau tái sử dụng certificate. Không thay khóa mỗi build. `--create` cho phép CLI tạo certificate/profile khi cần; không tự thu hồi chứng chỉ của app cũ. Nếu tài khoản đã chạm hạn mức certificate, kiểm tra các chứng chỉ đang sử dụng và cân nhắc dùng lại private key phù hợp thay vì xóa chứng chỉ đang dùng cho ứng dụng khác.

## 4. Tạo group biến trên Codemagic

Trong Environment variables, tạo group **`sono_app_store`**, cấp cho app này, gồm đúng các biến sau. Nhập giá trị trong UI Codemagic; không đưa chúng vào `codemagic.yaml` hoặc gửi private key qua chat.

- `BUNDLE_ID`: Bundle ID mới đã đăng ký cho Sổ Nợ AI, ví dụ `vn.kpn.sonoai`.
- `APPLE_TEAM_ID`: Team ID tài khoản Developer hiện tại, 10 ký tự in hoa/chữ số.
- `APP_STORE_APPLE_ID`: Apple ID dạng số của hồ sơ Sổ Nợ AI mới tạo.
- `APP_STORE_CONNECT_ISSUER_ID`: Issuer ID dạng UUID của team API key.
- `APP_STORE_CONNECT_KEY_IDENTIFIER`: Key ID, 10 ký tự in hoa/chữ số.
- `APP_STORE_CONNECT_PRIVATE_KEY`: **Secret**, toàn bộ nội dung `.p8`, giữ nguyên dòng BEGIN/END và xuống dòng.
- `CERTIFICATE_PRIVATE_KEY`: **Secret**, toàn bộ nội dung RSA key tạo ở bước 3.

Ba biến đầu và các ID không phải private key nhưng vẫn nên để trong group cấu hình thay vì commit thông tin tài khoản. Quyền của team API key quyết định phạm vi truy cập Apple; không dùng lại ID của ứng dụng khác cho `APP_STORE_APPLE_ID`.

Không cần thiết lập Developer Portal integration riêng cho cấu hình hiện tại: các lệnh CLI và bước publishing cùng dùng nhóm biến này. Nếu dùng cách tích hợp bằng tên key trong UI, cần thay đồng bộ YAML; đừng trộn hai cách xác thực.

## 5. Chạy workflow phát hành

Đảm bảo `ios-verify` đã đạt, rồi chạy **ios-testflight** trên branch tin cậy. Pipeline thực hiện:

1. Kiểm tra các ID, PEM và phiên bản; không in private key.
2. Kiểm tra workspace/CI scripts, chạy `swift test`.
3. Đối chiếu Apple ID với Bundle ID trên App Store Connect để chặn nhầm sang app cũ, rồi hỏi số build lớn nhất trên tất cả phiên bản. Lỗi xác thực/mạng làm dừng, không bị hiểu nhầm là app chưa có build.
4. Chọn số build là giá trị lớn hơn giữa số Apple hiện có + 1 và bộ đếm `PROJECT_BUILD_NUMBER` của Codemagic cộng `BUILD_NUMBER_OFFSET` tùy chọn. Tạo `project.ci.json` tại repo root; không sửa `project.yml` trong source.
5. Sinh project và chạy app tests trên một iPhone Simulator iOS 17+ có sẵn.
6. Tạo keychain tạm, fetch/create signing files đúng Bundle ID và kiểu App Store, áp profiles.
7. Archive Release và xuất IPA; đối chiếu Bundle ID, version/build, provisioning và tài nguyên chữ ký trong ZIP.
8. Upload App Store Connect bằng publishing của Codemagic.

**Chỉ chạy một release workflow cùng lúc** cho app để tránh hai lần build cùng đọc một số Apple trước khi upload được xử lý. Bộ đếm và `BUILD_NUMBER_OFFSET` hỗ trợ khi chuyển CI, nhưng không thay thế khóa phân tán giữa nhiều dịch vụ build. Số build hiện giới hạn 1–9999; script sẽ yêu cầu xem lại chính sách nếu vượt mức đó. `MARKETING_VERSION` mặc định `1.0.0` trong YAML, đổi khi phát hành phiên bản mới.

Không bật `--log-api-calls`, shell tracing hoặc lệnh dump environment khi chẩn đoán vì runner chứa private keys. Các artifact được giữ gồm IPA, dSYM, xcresult, log build/test và metadata công khai; không xuất kho certificate/keychain hoặc project spec chứa secrets.

## 6. Cài qua TestFlight trên iPhone

Sau upload thành công, Apple cần xử lý build. Mở App Store Connect → Sổ Nợ AI → TestFlight trên trình duyệt Windows. Hoàn tất thông tin Apple yêu cầu, thêm build vào nhóm internal testers và thêm tài khoản tester phù hợp. Cài ứng dụng TestFlight trên iPhone để nhận build.

YAML hiện có `submit_to_testflight: false`: trong Codemagic, cờ này điều khiển **gửi beta review**, không phải tắt upload IPA. Cấu hình vẫn upload để bạn chọn build cho nhóm nội bộ; chưa tự gửi external beta review hoặc App Store review. [Codemagic publishing](https://docs.codemagic.io/yaml-publishing/app-store-connect/).

App có mã hóa backup bằng CryptoKit. Repo **chưa tự điền câu trả lời export compliance** hoặc đặt `ITSAppUsesNonExemptEncryption`; chủ tài khoản cần khai báo đúng trong App Store Connect nếu Apple yêu cầu trước khi cho tester cài. Chưa có khẳng định việc dùng mã hóa này thuộc trường hợp miễn cụ thể.

App icon gồm các kích thước iPhone và ảnh 1024×1024 RGB không alpha đã có trong asset catalog. Bạn vẫn cần kiểm tra UI, quyền camera/micro, Face ID, dữ liệu offline và backup trên iPhone theo [VERIFICATION.md](VERIFICATION.md).

## Kiểm tra được trên Windows

```powershell
python -m pip install -r scripts/requirements-dev.txt
python scripts/check_workspace.py
python -m unittest discover -s scripts/tests -v
python scripts/ci/pipeline.py prepare
```

Lệnh cuối chỉ tạo spec cho Simulator, không cần khóa Apple. Không chạy `--release` trên Windows để thử giả IPA. Bộ test pipeline dùng metadata, ZIP và khóa fixture không có giá trị, không truy cập Apple và không tạo certificate. Kiểm tra IPA ở Python chỉ kiểm tra cấu trúc/metadata; việc xuất ký mã và chấp nhận upload phải do Xcode/Apple xác nhận.
