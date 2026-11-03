# Build IPA và dùng TestFlight từ Windows

Repository: [K-PN/kp-managerMT](https://github.com/K-PN/kp-managerMT), branch `main`. Codemagic [ios-testflight #4](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aea267da87b4d255fde3a68), source `f342836`, đã đạt 36/36 XCTest, ký IPA **1.0.0 (10)** và được Apple xác nhận **UPLOAD SUCCEEDED with no errors**. App record Sổ Nợ AI có Apple ID **6830292186**. Xem VERIFICATION.md để phân biệt upload với trạng thái sẵn sàng cài TestFlight.

## Cấu hình Apple đã chọn

Sổ Nợ AI dùng Bundle ID riêng **`vn.kpn.sonoai`**, SKU `sono-ai-ios`, ngôn ngữ Vietnamese. Team ID dùng chung với tài khoản Developer hiện có; Apple ID dạng số lấy từ hồ sơ Sổ Nợ AI mới trong App Store Connect. Không dùng ID hoặc Bundle ID của QHS Manager.

Codemagic đã có App Store Connect integration **`qhs_apple`** và chứng chỉ Distribution **`QHS Manager`** còn hạn đến 19/09/2027. Workflow dùng lại các tài sản này, kết hợp provisioning profile App Store riêng **`SoNo AI App Store`** cho Bundle ID mới. Không cần tạo API key hoặc distribution private key mới cho cấu hình này.

Trong Personal Account → Code signing identities → iOS provisioning profiles, dùng **Fetch profiles** để nhập profile mới, reference `SoNoAI_AppStore`. Profile phải chứa đúng chứng chỉ Distribution hiện có. Giữ nguyên chứng chỉ và các profile của ứng dụng cũ.

## Biến môi trường

Trong app Codemagic → Environment variables, group **`sono_app_store`** chứa:

- `APPLE_TEAM_ID`: Team ID 10 ký tự của tài khoản hiện có.
- `APP_STORE_APPLE_ID`: Apple ID dạng số của hồ sơ Sổ Nợ AI mới.

`BUNDLE_ID=vn.kpn.sonoai` và `MARKETING_VERSION=1.0.0` được đặt trong YAML. Bundle ID trong `ios_signing` phải trùng `BUNDLE_ID`.

Integration `qhs_apple` cung cấp `APP_STORE_CONNECT_PRIVATE_KEY`, `APP_STORE_CONNECT_KEY_IDENTIFIER`, `APP_STORE_CONNECT_ISSUER_ID` cho CLI và publishing. Preflight hỗ trợ PEM trực tiếp hoặc secret reference `@file:`/`@env:` của CLI mà không in nội dung/đường dẫn khóa. Không khai báo trùng các biến này trong group, không đưa private key vào repository, log hoặc chat. Managed signing nhập certificate/profile vào runner; không dùng `CERTIFICATE_PRIVATE_KEY`, không gọi `fetch-signing-files --create`.

Tham khảo [Codemagic managed signing](https://docs.codemagic.io/yaml-code-signing/signing-ios/) và [publishing qua integration](https://docs.codemagic.io/partials/yaml-publishing-app-store-connect-team-integration/).

## Hai workflow thủ công

`ios-verify` không cần khóa Apple: kiểm tra workspace/CI, chạy Swift core tests, sinh Xcode project, chạy app/UI tests trên iPhone Simulator và xuất `SoNoAI-simulator.zip`, screenshot attachments. Gói Simulator không cài trực tiếp lên iPhone. Xem [QUICK_TEST.md](QUICK_TEST.md) và [VERIFICATION.md](VERIFICATION.md).

`ios-testflight` chạy trên Mac mini M2, Xcode 26.1, dùng managed signing và integration đã nêu. Pipeline:

1. Kiểm tra ID, phiên bản, API key được integration cung cấp; không in secrets.
2. Kiểm tra workspace/CI scripts và chạy financial core tests.
3. Đối chiếu Apple ID với Bundle ID bằng API để tránh upload nhầm app cũ. Lỗi API làm dừng build.
4. Chọn số build lớn hơn giữa số Apple hiện có + 1 và `PROJECT_BUILD_NUMBER` cộng `BUILD_NUMBER_OFFSET` tùy chọn. Ghi spec tạm `project.ci.json` tại repo root.
5. Sinh project, chạy app/UI tests trên iPhone Simulator iOS 17+.
6. Áp managed provisioning profile, archive Release, xuất IPA.
7. Kiểm tra Bundle ID, version/build, provisioning và tài nguyên chữ ký trong IPA.
8. Upload App Store Connect bằng `auth: integration`.

Chạy **SoNo AI - Signed IPA and TestFlight upload** trên branch `main` đã push. Chỉ chạy một release workflow cùng lúc để tránh trùng số build. Số build hiện giới hạn 1–9999. Không bật shell tracing, dump environment hoặc `--log-api-calls` vì runner có private keys. Artifacts chỉ gồm IPA, dSYM, xcresult, log test/build và metadata công khai; không xuất keychain.

Signing CLI pin `codemagic-cli-tools 0.70.2`. XcodeGen và Python venv được chuẩn bị tự động. Workflow không tự chạy khi push; GitHub Actions cũng chạy thủ công.

## Cài trên iPhone

Sau khi Codemagic upload thành công, đợi Apple xử lý build trong App Store Connect → Sổ Nợ AI → TestFlight. Hoàn tất thông tin Apple yêu cầu, chọn build cho nhóm internal testers rồi mở ứng dụng TestFlight trên iPhone bằng tài khoản tester.

YAML đặt `submit_to_testflight: false`: cờ này điều khiển gửi beta review, còn upload IPA vẫn hoạt động. Chưa tự gửi external beta review hoặc App Store review. [Codemagic publishing](https://docs.codemagic.io/yaml-publishing/app-store-connect/).

Build **1.0.0 (10)** đã xử lý xong, gán vào **SoNo AI Internal** và có trạng thái **Testing**; tài khoản chủ sở hữu có trạng thái **Invited**.

App mã hóa backup bằng CryptoKit và dẫn xuất khóa bằng CommonCrypto của hệ điều hành Apple, không nhúng thư viện cipher bên ngoài. Trong câu hỏi App Encryption Documentation đã chọn **None of the algorithms mentioned above** (không dùng thuật toán riêng hoặc thuật toán chuẩn ngoài phần mã hóa Apple cung cấp), lưu thành công và hết Missing Compliance. Đối chiếu [tài liệu Apple về mã hóa trong hệ điều hành](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption). Chưa tự đặt `ITSAppUsesNonExemptEncryption`; các build sau vẫn có thể cần trả lời lại, và cần xem lại khai báo nếu chức năng mã hóa thay đổi. Camera/micro, Face ID, Keychain, offline và backup cần kiểm tra thêm trên iPhone theo VERIFICATION.md.

## Kiểm tra trên Windows

```powershell
python -m pip install -r scripts/requirements-dev.txt
python scripts/check_workspace.py
python -m unittest discover -s scripts/tests -v
python scripts/ci/pipeline.py prepare
```

Lệnh cuối chỉ tạo spec Simulator. Tests dùng fixture không có giá trị xác thực và không truy cập Apple. Kiểm tra ZIP/metadata không thay thế việc Xcode ký code và Apple chấp nhận upload. `.gitignore` chặn khóa, provisioning, IPA, dữ liệu local và thư mục build.
