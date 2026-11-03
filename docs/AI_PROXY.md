# Hợp đồng proxy AI tùy chọn

**Có trong repo:** iOS client adapter HTTPS + Keychain, UI ghép nối phiên, đồng ý gửi từng trang/âm thanh và hủy request. **Chưa có:** server, cấp phiên, App Attest, kết nối nhà cung cấp, hạn mức server hay triển khai hosting. Không trỏ app vào public endpoint chưa được bảo vệ. Không có request AI thực tế nào được thực hiện khi tạo mã nguồn này.

## Cấp phiên cho app cá nhân không có tài khoản

Triển khai quản trị proxy riêng ngoài app. Quản trị viên tạo ngẫu nhiên một bearer token tối thiểu 256 bit cho một phiên sử dụng trên thiết bị, có hạn thật ở server tối đa 60 phút, chỉ có scope `handwriting` và `transcribe`. Nhập URL HTTPS, token và thời hạn còn lại vào Cài đặt app. Không dùng API key nhà cung cấp làm token. Không nhúng token chung vào binary.

Server chỉ cần giữ hash token, ngày hết hạn, scope, bộ đếm hạn mức/request ID; không giữ sổ nợ, nội dung ảnh, âm thanh hay kết quả sau khi trả response. Không mở endpoint cấp phiên công khai không xác thực. Khóa quản trị và provider key chỉ ở secret manager/server environment. Cơ chế session này dùng cho proxy cá nhân do bạn quản trị; chưa cung cấp xác thực thiết bị bằng App Attest. Nếu phát hành rộng hơn cần bổ sung enrollment/attestation và client tương ứng, không chỉ nhúng URL.

App chặn token hết hạn và URL không HTTPS, không có user/password/query/fragment. Server phải tự kiểm tra expiry: thời hạn do người dùng nhập trong app không phải quyền xác thực. App dùng ephemeral URLSession, không cache/cookie, không theo redirect để tránh chuyển Authorization sang host khác.

## Bắt buộc ở server trước khi bật online

- TLS và xác thực token trước khi đọc/giải mã payload lớn.
- Hạn mức theo phiên/thiết bị/IP và hạn mức toàn cục; ví dụ 10 request/phút, tối đa 50 request/phiên. Đây là gợi ý cấu hình khởi đầu, không phải giới hạn đã triển khai.
- Trần chi phí ngày/tháng bằng tiền thật. Giữ trước ngân sách cho request trước khi gọi provider, từ chối khi không đủ và giải phóng phần dư sau response. Không coi giới hạn phía client là bảo vệ chi phí.
- `requestID` duy nhất theo phiên để chống xử lý trùng; không tự chuyển sang model/provider khác có phí.
- Giới hạn body tổng khoảng 12 MB; chỉ decode một ảnh/audio tối đa 8 MB, ảnh tối đa 2400 px cạnh dài từ client và giới hạn pixel ở server để tránh ảnh nén gây tốn bộ nhớ. Kiểm tra MIME thực tế và không tải URL tùy ý từ người dùng.
- Timeout tổng dưới 60 giây; cắt tác vụ provider khi client ngắt nếu API hỗ trợ. Không hứa hủy sẽ xóa phí đã phát sinh.
- Không log request/response, Authorization, tên người, ảnh, transcript hoặc số tiền. Log vận hành chỉ request ID ngẫu nhiên, status, độ trễ và số tiền chi phí tổng hợp cần thiết.
- Chọn chính sách không lưu/không huấn luyện và thời gian lưu phù hợp tại provider; hiển thị chính sách thực tế cho người dùng. Không hứa dữ liệu không bị lưu nếu provider không cam kết điều đó.
- Đầu ra chỉ là đề xuất. JSON đúng schema, tiền nguyên đồng hoặc null, cảnh báo phần khó đọc. Không suy đoán số tiền/ngày mất nét và không làm số học tài chính bằng LLM.

## Request

URL gốc người dùng nhập, ví dụ `https://proxy.example/v1`. Client thêm `/handwriting` hoặc `/transcribe`. Cả hai dùng `POST`, `Content-Type: application/json`, `Authorization: Bearer <short-lived-session>`.

Mẫu hợp đồng sau là fixture tài liệu, không phải dữ liệu đã được AI nhận dạng.

```json
{
  "requestID": "11111111-1111-1111-1111-111111111111",
  "imageBase64": "<jpeg-base64>",
  "mediaType": "image/jpeg",
  "locale": "vi-VN"
}
```

STT thay `imageBase64` bằng `audioBase64`, `mediaType` là `audio/mp4` (AAC trong m4a, một kênh, 16 kHz, tối đa 60 giây). Không có dữ liệu khách hoặc database trong body.

## Response OCR

`200 application/json`, tối đa 2 MB và 500 dòng:

```json
{
  "rows": [
    {
      "rawText": "12/10: 500.000",
      "customerName": "Anh Nam",
      "date": null,
      "amountVND": 500000,
      "kind": "debt",
      "note": "",
      "quantity": null,
      "unitPriceVND": null,
      "warning": "Thiếu năm; người dùng cần chọn ngày đầy đủ."
    }
  ]
}
```

Ngày đầy đủ dùng `yyyy-MM-dd`. Không tự điền năm còn thiếu tại server. `kind` thuộc enum core: `debt`, `loan`, `collection`, `borrowing`, `repayment`, `advanceReceived`, `advanceUsed`, `adjustmentIncrease`, `adjustmentDecrease`; **không được trả reversal để ghi trực tiếp**. Không đưa customer ID từ server: app đối chiếu local và người dùng chọn. Số lượng × đơn giá được core kiểm tra lại, không tin thành tiền từ provider.

Client đặt tất cả dòng về chưa xác nhận, gắn ảnh nguồn, hiển thị cảnh báo và không ghi sổ. Thiếu ngày/loại có giá trị đề xuất trong UI kèm cảnh báo, người dùng phải đối chiếu và chọn trước khi xác nhận.

## Response STT và lỗi

```json
{"text":"Anh Nam lấy thêm hàng 350 nghìn."}
```

Transcript tối đa 20.000 ký tự, sau đó đi qua parser local và màn hình xác nhận. Server trả `401/403` khi phiên không hợp lệ, `413` khi quá lớn, `429` khi hết hạn mức/ngân sách, `502/503` khi provider lỗi. Không trả nội dung nhạy cảm trong error body. Client hiển thị lỗi chung, giữ bản nháp và chỉ gửi lại khi người dùng thao tác mới.
