# Kết quả kiểm tra và việc còn cần chạy

## Sửa văn bản Apple Speech và tên nhà cung cấp 1.2.1

Source `5feedbe`, ngày 05/11/2026. Người dùng báo Apple Speech trả “nợ 50.000” khi nói “nợ 50 nghìn”; parser cũ chỉ lấy span có đơn vị nên bỏ sót. Thêm nhận số VNĐ không có hậu tố trong ngữ cảnh nợ/trả/tổng/thành tiền, không đổi quy tắc span OCR. Phần tổng và đã trả hỗ trợ cùng kiểu số; loại số lượng hàng, ngày, số âm và số điện thoại không nằm trong ngữ cảnh tiền. Lệnh “Thu nợ” ưu tiên collection trước từ “nợ”.

Tách tên sau xe/nhà xe/nhà cung cấp/công ty, dừng trước thao tác/số tiền/mặt hàng. Đối chiếu tên đầy đủ/biệt danh, ưu tiên khớp cả tiền tố, không chọn theo từ cuối. Chưa có hồ sơ thì điền tên mới vào bản nháp nợ tiền hàng; tra cứu không tạo hồ sơ. Xác nhận vẫn là bước duy nhất ghi dữ liệu.

Windows đạt 7/7 kiểm tra workspace và 18/18 pipeline tests; đã bổ sung sáu core regression tests và đổi UI test sang chính văn bản “Xe An nợ 50.000”, không có “Thêm” hoặc “đồng”. Dự kiến 53 core + 5 app + 5 UI tests; chưa coi là đạt khi chưa có kết quả cloud.

[Build #14](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aec1e28004ce28f20ee0b48) ghi kết quả dưới đây. Lượt #13 được hủy lúc chuẩn bị để dùng commit mới nhất, chưa ký/upload.

Build #14 biên dịch core thành công, 49/53 tests đạt; bốn assertion cùng thuộc câu có tổng nợ và “đã trả”: parser ưu tiên nhầm supplierPayment. Đã ưu tiên câu ghi nợ tiền hàng kèm đã trả, vẫn phân biệt rõ “Trả nợ tiền hàng”, và giữ “đã trả 0” hợp lệ. Commit `5feedbe` gồm các regression assertions này. Lượt #15 hủy trước native build để dùng bản sửa số tiền đã trả bằng 0.

[Build #16](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aec1f30004ce28f20ee0b83), source `5feedbe`: **63/63 XCTest đạt** (53 core + 5 app + 5 UI). UI test nhập chính văn bản “Xe An nợ 50.000”, không có “đồng” hoặc “Thêm”: ô số tiền tự có 50000, tự đề xuất tên mới, xác nhận lưu vào Xe hàng, tra cứu lại đúng 50.000đ và không có dòng nợ khách. Chưa thử thu âm trên iPhone thay người dùng.

Build #16 thành công sau 9m01s; đã ký/xuất IPA **1.2.1 (22)** 1,27 MB, kiểm tra metadata/provisioning/signature resources đạt. Apple trả **UPLOAD SUCCEEDED with no errors**, delivery UUID `8acdfdff-fa67-4b2f-bd63-3f0efddeaeff`.

**Đã xác minh TestFlight 1.2.1 (22) ngày 05/11/2026:** Apple processing và khai báo mã hóa hệ điều hành hoàn tất; đã gán vào **SoNo AI Internal**. Trang nhóm xác nhận **1 Tester ∙ 4 Builds**, bản **1.2.1 (22)** đang **Testing**. Tester hiện đã cài 1.2.0 (18), có thể cập nhật. Ảnh bằng chứng `build/evidence/my-thanh-testflight-22-testing.png` lưu cục bộ (ignored).

## Tách sổ khách / xe hàng 1.2.0

Ngày 05/11/2026, source `8b0fa3d`: bỏ khối icon/khẩu hiệu trên Tổng quan; phân cấp hai thẻ tổng nợ lớn và hai thẻ tiền hàng nhỏ. Sổ giao dịch bỏ nhóm Tất cả, chỉ có Nợ khách/Tiền hàng với danh sách người và loại giao dịch riêng. Hồ sơ có nhóm tùy chọn, JSON cũ thiếu trường vẫn đọc được; dữ liệu cũ suy ra nhóm theo tên/lịch sử. Trường hợp có lịch sử cả hai nhóm vẫn truy cập được ở mỗi sổ, không xóa dữ liệu. Chi tiết, preview, tra cứu và phiếu PDF chỉ hiện các số dư thuộc nhóm đang xem.

Parser nhận câu bắt đầu bằng “Nợ”, không cần nói “đồng” sau “nghìn/ngàn”; từ xe/nhà cung cấp/công ty định tuyến nợ, trả và tra cứu tiền hàng. Sáu thao tác chính trong menu giọng nói; thêm xe mới qua lời nói vẫn chờ xác nhận. Cùng tên ở hai nhóm được tạo riêng; trùng trong cùng nhóm vẫn bị chặn.

Windows đạt 7/7 kiểm tra workspace, 18/18 kiểm thử pipeline; `git diff --check` sạch. Bộ XCTest gồm 47 core + 5 app smoke + 5 UI; không xác minh micro thật bằng kiểm thử văn bản hoặc Simulator.

Build #10 dừng ở compiler core: hàm `newName(in:)` cần `return` tường minh sau khi thêm nhánh nhận tên xe. Đã sửa ở `ab45eca` và khởi chạy [build #11](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aec1444004ce28f20ee0901). Chưa ký/upload 1.2.0 ở lượt #10.

Build #11: 47/47 core, 5/5 app smoke và 4/5 UI đạt. PDF theo từng nhóm không hiện số dư không liên quan; các luồng công nợ, nhập hàng, dashboard/bộ lọc/báo cáo và tạo khách bằng giọng nói đạt. UI test mới dừng vì `voice.amount` chưa có trong cây accessibility khi còn ở ngoài vùng hiển thị của Form. Commit `f4bcc5f` cho cuộn tối đa 5 lần để tìm ô số tiền/kết quả tra cứu rồi vẫn kiểm tra đầy đủ 20.000đ, lưu và phân nhóm.

[Build #12](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aec163a004ce28f20ee096e), `f4bcc5f`: **57/57 XCTest đạt** (47 core + 5 app smoke + 5 UI). Test mới nhận “Thêm xe An nợ 20 nghìn” thành 20.000đ, xác nhận lưu, xe không có trong danh sách khách nợ, chi tiết xe chỉ hiện nợ tiền hàng; tra cứu “Tra cứu nợ xe An” trả đúng 20.000đ và không có dòng nợ khách. Archive/export và kiểm tra metadata đạt.

Build #12 thành công sau 8m36s; IPA **1.2.0 (18)** 1,26 MB, dSYM 2,28 MB, artifact log/xcresult 94,46 MB. Apple trả **UPLOAD SUCCEEDED with no errors**, delivery UUID `7c9dcd17-5054-4837-8d7c-fd10ded20049`.

**Đã xác minh TestFlight 1.2.0 (18) ngày 05/11/2026:** Apple processing hoàn tất, khai báo mã hóa hệ điều hành đã lưu; gán bản 18 vào nhóm **SoNo AI Internal** hiện có. Trang Builds xác nhận **1 Tester ∙ 3 Builds**, bản **1.2.0 (18)** đang **Testing**. Tester hiện đã cài 1.1.0 (15), có thể cập nhật. Ảnh bằng chứng `build/evidence/my-thanh-testflight-18-testing.png` lưu cục bộ (ignored). Chưa cài bản mới hoặc thử âm thanh micro trên thiết bị thay người dùng.

## Cập nhật Tạp Hóa Mỹ Thạnh 1.1.0

Ngày 04/11/2026, source `3955153`: đã triển khai tên mới, quản lý nhập hàng/đã trả/nợ nhà cung cấp, bốn thẻ tổng quan, Apple Speech tự mở với kết quả tạm và xác nhận, thêm khách bằng giọng nói, bộ lọc ngày và tổng CSV/PDF. Người dùng đã xác nhận tiền hàng tháng/tuần là tổng hàng nhập gồm đã trả và còn nợ.

Trên Windows: **7/7 workspace checks**, **18/18 kiểm thử pipeline** đạt; `git diff --check` sạch và LaunchScreen XML đọc được. Ngày 05/11/2026, kết nối Chrome đã hoạt động trở lại. App Store Connect đã lưu tên **Tạp Hóa Mỹ Thạnh** và subtitle **Quản lý giao dịch - hàng hóa** cho Apple ID 6830292186; Bundle ID vẫn `vn.kpn.sonoai`. Các ảnh bản 1.0.0 phía dưới không xác minh giao diện mới. Kịch bản mới ở [QUICK_TEST.md](QUICK_TEST.md).

Người dùng đã chạy [build 6aea9e93a87b4d255fde5cd2](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aea9e93a87b4d255fde5cd2) và cung cấp log: core biên dịch thành công sau 13,02 giây, **37/38 XCTest đạt**. `TradingTests.swift:91` thất bại vì lệnh “Thêm khách mới Chị Mai ghi nợ 300 nghìn” trả `amount == nil`. Nguyên nhân: chuẩn hóa bỏ dấu biến cả “mới” và “mỗi” thành `moi`, làm nhánh tính số lượng × đơn giá xóa số tiền. Pipeline dừng ở **Test financial core**; chưa chạy ibtool, app/UI tests, ký hoặc upload.

Bản sửa loại cụm khai báo “thêm/tạo khách mới” khỏi phần nhận diện đơn giá, kiểm tra từ `moi` theo ranh giới từ và vẫn tính/chặn trường hợp có “mỗi bao” theo quy tắc cũ. Bổ sung hai core tests cho lệnh có/không dấu và thêm khách kèm đơn giá đủ/thiếu số lượng. Sau sửa, 7 workspace checks + 18 pipeline tests đạt trên Windows. Bộ native hiện có **40 core + 4 app smoke + 4 UI tests**; kết quả từng lượt chạy ghi dưới đây.

Build [ios-testflight #6](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aeabc3ea87b4d255fde62ff), `45f7aa3`: core và app đã biên dịch, 4 app smoke tests đạt, gồm PDF có thương hiệu/tổng tiền; 3/4 UI tests đạt. Kiểm thử nhập hàng dừng tại SoNoUITests.swift:104: công tắc xác nhận vẫn tắt sau cú bấm tọa độ trên hàng. Không ký/upload.

Build [ios-testflight #7](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aeb704d004ce28f20eddb66), `06666cf`: **40/40 core + 4/4 app smoke đạt**. Hai UI tests giao dịch thất bại ở điều kiện toàn bộ hàng nằm trong vùng nhìn thấy; hai UI tests màn hình chính và giọng nói đạt. Log cây giao diện xác nhận cửa sổ 402×874, hàng xác nhận ở y724.3–778.3 hoặc y766–820, còn UISwitch con ở y737.3–765.3 hoặc y779–807. Giới hạn inset 100 quá chặt; không coi việc thử cuộn này là bản sửa đã đạt.

Commit `3f100ac` chỉnh giới hạn vùng nhìn thấy và bấm trực tiếp UISwitch con thay vì tọa độ tương đối trên hàng. Giữ assertion trạng thái ban đầu tắt, trạng thái sau bấm bật và chỉ sau đó mới lưu. Ảnh trước/sau được giữ trong xcresult; bản sửa đã đạt ở build #9. Chrome chặn tải ZIP qua storage.googleapis.com với ERR_BLOCKED_BY_CLIENT, chưa tải/kiểm tra ảnh giao diện mới và không bỏ qua chặn tải này.

Build [ios-testflight #8](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aeb7229004ce28f20eddc31), `3f100ac`: biên dịch native thành công, 4/4 app smoke đạt. XCTest Runner lỗi khởi động `XCTDaemonErrorDomain Code=18`, `Timed out waiting for AX loaded notification`; không có UI test nào bắt đầu nên chưa kiểm chứng được bản sửa công tắc. Pipeline trả lỗi 65 và không ký/upload. Ngày 05/11/2026 đã chạy lại cùng mã trên máy cloud mới ở [build #9](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aebd854004ce28f20edfb86), không bỏ qua kiểm thử.

**Build [ios-testflight #9](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aebd854004ce28f20edfb86), `3f100ac`, thành công ngày 05/11/2026 sau 9m50s:** 40 core + 4 app smoke + 4 UI tests đạt, tổng **48/48 XCTest**. Luồng nợ 500.000đ → thu 200.000đ → dư 300.000đ, nhập hàng 1.000.000đ/đã trả 400.000đ, mở bộ lọc ngày/báo cáo tổng và thêm khách qua văn bản giọng nói với preview không ghi dữ liệu đều đạt. Đã xuất 17 screenshot attachments trong xcresult. Không kiểm chứng nhận dạng âm thanh trên iPhone thật. Lỗi AX khởi động của #8 không lặp lại khi chạy lại cùng mã.

Archive/export **Tạp Hóa Mỹ Thạnh 1.1.0 (15)** thành công, IPA 1,24 MB; kiểm tra metadata, provisioning và signature resources đạt. Apple trả **UPLOAD SUCCEEDED with no errors**, delivery UUID `ff48dbb7-7864-40c7-9c6e-774a1857376c`. Phiên App Store Connect hết đăng nhập; người dùng đã đăng nhập lại trên tab mới.

**TestFlight 1.1.0 (15) đã sẵn sàng ngày 05/11/2026:** Apple processing hoàn tất, khai báo chỉ sử dụng mã hóa hệ điều hành đã lưu và hết Missing Compliance. Gán bản 15 vào nhóm **SoNo AI Internal** hiện có; trang Builds của nhóm xác nhận **1 Tester ∙ 2 Builds**, bản **1.1.0 (15)** đang **Testing**. Tester đã cài bản cũ 1.0.0 (10), có thể cập nhật qua TestFlight. Ảnh bằng chứng `build/evidence/my-thanh-testflight-15-testing.png` lưu cục bộ (ignored). Chưa cài hoặc thử micro bản mới trên iPhone thay người dùng.

## Cập nhật build cloud

**Release [ios-testflight #4](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aea267da87b4d255fde3a68), `f342836`, thành công sau 7m14s.** 7 workspace checks + 18 CI tests, 31 core XCTest, 3 app smoke và 2 UI XCTest đạt. Test xác nhận đúng tên khách trước lưu; luồng ghi nợ 500.000đ → thu 200.000đ → dư 300.000đ đạt. Archive/export IPA **1.0.0 (10)** thành công; metadata, chữ ký/provisioning resources và `UIDeviceFamily == [1]` đạt. Apple trả **UPLOAD SUCCEEDED with no errors**, delivery UUID `46052f33-75b6-4a77-9b48-3a4e75f6b9b0`. Artifacts có IPA 1,13 MB, dSYM 2,13 MB, logs/xcresult 75,31 MB. Chưa đồng nhất upload thành công với Apple processing hoặc việc đã cài trên iPhone thật.

**TestFlight đã sẵn sàng ngày 04/11/2026:** Apple processing hoàn tất, khai báo mã hóa chỉ dùng framework hệ điều hành đã lưu và hết Missing Compliance. Build **1.0.0 (10)** được gán vào nhóm **SoNo AI Internal**; trang nhóm hiển thị **1 Tester ∙ 1 Build**, build **Testing**, tài khoản chủ sở hữu **Invited**. Chưa cài hoặc kiểm chứng trên iPhone thật thay người dùng. Bằng chứng chụp trang lưu trong `build/evidence/` (ignored); kịch bản test thiết bị ở QUICK_TEST.md.

Ngày 04/11/2026: đã tạo Bundle ID `vn.kpn.sonoai`, hồ sơ Sổ Nợ AI (Apple ID 6830292186), provisioning App Store và nhóm internal TestFlight cho chủ tài khoản. Dùng lại integration `qhs_apple` và Distribution certificate đã lưu trên Codemagic.

Release [ios-testflight #1](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aea2120a87b4d255fde3891), `e605653`: managed signing assets nhập thành công, preflight dừng vì chỉ nhận PEM trực tiếp. Đã bổ sung hỗ trợ secret reference `@file:`/`@env:` theo CLI, kiểm tra nội dung mà không in khóa hoặc đường dẫn.

Release [ios-testflight #2](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aea21bfa87b4d255fde38d1), `31d4f42`: API xác thực đúng app, 31 core + 3 app smoke + 2 UI XCTest đạt; archive và export `SoNoAI.ipa` (1,13 MB) có chữ ký Distribution thành công. Upload bị Apple từ chối với hai lỗi iPad: thiếu icon 152×152 và thiếu các hướng xoay cho multitasking. Nguyên nhân là preset iOS của XcodeGen tại target ghi đè setting iPhone ở project. Đã đặt `TARGETED_DEVICE_FAMILY: "1"` trực tiếp ở target app, bổ sung kiểm tra `UIDeviceFamily == [1]` trên IPA trước upload. Chưa có build TestFlight được Apple nhận tại checkpoint này.

Release [ios-testflight #3](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aea2419a87b4d255fde3997), `9d012b5`: core và app smoke đạt; test chụp màn hình đạt, test giao dịch dừng ở bước tìm tên khách sau khi lưu (SoNoUITests.swift:34). Chưa chạy archive/upload trong lần này. Đã tắt autocorrection cho tên/biệt danh và thêm assertion giá trị ô tên trước khi lưu để tránh đổi tên riêng và có chẩn đoán rõ hơn; chưa coi nguyên nhân đã được xác nhận cho đến khi chạy lại.

Build [ios-verify #1](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aea101fa87b4d255fde3204), commit `55cbe31`, đã biên dịch thành công SoNoCore trên Mac và chạy 31 XCTest: 30 đạt, 1 lỗi cập nhật khách trùng tên sau khi đã xác nhận tạo riêng. Đã sửa validation cho phép giữ nguyên tên khi cập nhật thông tin khác và bổ sung kiểm tra đổi tên sang tên trùng vẫn bị chặn. Bản sửa chờ build kế tiếp. Các bước sinh project và app/UI test chưa chạy trong build đầu vì pipeline dừng khi core test lỗi. Những phần bên dưới ghi checkpoint kiểm tra Windows trước build này.

Build [ios-verify #2](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aea10f7a87b4d255fde325f), commit `d9c6d2e`: **31/31 core XCTest đạt**, XcodeGen tạo project thành công, iPhone 17 Pro Simulator khởi động. Compiler iOS phát hiện `greatestFiniteMagnitude` mơ hồ giữa CGFloat/Double trong `PDFReports.swift`; đã chỉ rõ kiểu CGFloat và Data ở commit `c5a07aa`. Chưa có app/UI test chạy thành công trong build này; tệp `.app` tự thu thập khi build lỗi không được coi là bản dùng thử hoàn chỉnh.

Build [ios-verify #3](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aea1300a87b4d255fde332c), `c5a07aa`: core 31/31 đạt, lỗi PDF đã qua; compiler báo body SwiftUI của NotebookScanView quá phức tạp để type-check. Đã tách thành các view riêng và giữ nguyên chuỗi tiếng Việt, xử lý nghiệp vụ ở `085ed0c`.

Build [ios-verify #4](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aea159fa87b4d255fde342d), `085ed0c`: core 31/31 đạt, app và test target biên dịch thành công cho Simulator arm64/x86_64, ứng dụng đã chạy trên iPhone 17 Pro. App smoke 2/3 đạt; test đọc Keychain thật lỗi vì app Simulator không ký mã. UI tests 0/2 đạt: ảnh thật xác nhận nút micro che thanh tab. Đã đổi bố cục sang VStack để tách vùng bấm; thay smoke test phụ thuộc Keychain thật bằng kiểm tra URL/token/hạn phiên không hợp lệ phải bị từ chối trước khi ghi Keychain. Không bỏ qua lỗi đọc Keychain trong ứng dụng.

Build [ios-verify #5](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aea1731a87b4d255fde34c3), `6d1f823`: core 31/31, app smoke 3/3 và UI chụp bốn màn hình chính đều đạt. Luồng tạo khách chạy được, dừng ở nút Ghi sổ vì UI test chưa bật công tắc xác nhận khi bàn phím số còn mở. Video và ảnh được giữ để chẩn đoán.

**Build [ios-verify #6](https://codemagic.io/app/6aea10057cef5b806068b14c/build/6aea18dba87b4d255fde356e), `a65fd40`, thành công sau 5m52s:** core 31/31, app smoke 3/3, UI 2/2, tổng 36/36 XCTest đạt. App được biên dịch cho Simulator arm64/x86_64 và chạy trên iPhone 17 Pro. UI test mở bốn màn hình, tạo khách, ghi nợ 500.000đ, thu 200.000đ và kiểm tra phải thu còn 300.000đ. Có gói SoNoAI-simulator.zip, raw .app, xcresult, log và ảnh attachments. Đã tải artifact về Windows, đối chiếu log 31 + 5 test đạt, không có test thất bại; kiểm tra ZIP có executable, Info.plist và platform iPhoneSimulator. Sáu [ảnh chạy thật](screenshots/README.md) đã lưu trong repo. Chưa ký/upload App Store Connect; chưa có IPA hoặc TestFlight.

Script CI giới hạn chờ boot 420 giây, chạy UI tests tuần tự và lưu screenshot attachments cả khi test lỗi. Đã mô phỏng trên Bash: build lỗi 23, export ảnh cũng lỗi 13, pipeline vẫn trả đúng lỗi build 23.

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

## Bộ kiểm thử XCTest

Tổng cộng **34 phương thức XCTest** trong core và app. Core gồm: tạo/sửa/trùng/gộp khách; ghi/thu một phần/toàn bộ/vượt nợ; phải trả/trả trước; overflow; FIFO; hoàn tác và thay thế; rebuild số dư; báo cáo; CSV injection; parser tiền tiếng Việt; số lượng × đơn giá; intent/query/mơ hồ/trùng tên; OCR example/review/validation/duplicate; atomic audit; lưu/reopen ngoại tuyến và draft; restore validation/nhật ký; migration v1 và schema mới hơn; mã hóa backup/mật khẩu sai/tamper.

Bổ sung **2 UI tests** trong `AppUITests`: chụp các màn hình chính; tạo khách rồi ghi nợ 500.000, thu 200.000 và kiểm tra dư 300.000. Chỉ dùng database riêng của Debug Simulator, không trộn dữ liệu thử vào sổ thông thường. Hai test này chưa chạy trên môi trường Windows.

`AppTests` kiểm tra định dạng VND, từ chối ảnh hỏng, và từ chối URL/token/hạn phiên AI không hợp lệ trước khi ghi Keychain. Không gọi mạng. Toàn bộ core/app/UI XCTest đã chạy đạt ở build #6; GitHub Actions giữ làm dự phòng thủ công. Keychain với cấu hình hợp lệ cần thử trên thiết bị/bản được ký mã; bản Simulator không chứng minh được việc lưu/đọc khóa trên iPhone.

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
