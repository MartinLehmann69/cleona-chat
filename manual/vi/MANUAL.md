# Cleona Chat -- Hướng dẫn sử dụng

Version 3.1.125 | Tháng 7 năm 2026

---

## Mục lục

1. [Cleona Chat là gì?](#1-was-ist-cleona-chat)
2. [Bắt đầu](#2-erste-schritte)
3. [Danh bạ](#3-kontakte)
4. [Tin nhắn](#4-nachrichten)
5. [Nhóm](#5-gruppen)
6. [Kênh công khai](#6-oeffentliche-kanaele)
7. [Cuộc gọi](#7-anrufe)
8. [Lịch](#8-kalender)
9. [Khảo sát](#9-umfragen)
10. [Nhiều danh tính](#10-mehrere-identitaeten)
11. [Đa thiết bị](#11-multi-device)
12. [Khôi phục](#12-wiederherstellung)
13. [Cài đặt](#13-einstellungen)
14. [Bảo mật](#14-sicherheit)
15. [Cập nhật phần mềm](#15-software-updates)
16. [Câu hỏi thường gặp](#16-haeufige-fragen)

---

## 1. Cleona Chat là gì?

### Ứng dụng nhắn tin của bạn, dữ liệu của bạn

Cleona Chat là một ứng dụng nhắn tin hoạt động hoàn toàn không cần máy chủ
trung tâm. Tin nhắn của bạn đi thẳng từ thiết bị của bạn đến thiết bị của
người nhận -- không qua trụ sở công ty nào, không qua đám mây, không qua
trung tâm dữ liệu nào. Không một công ty nào có thể đọc, lưu trữ hay chia sẻ
tin nhắn của bạn, đơn giản vì không có công ty nào đứng ở giữa cả.

### Không cần tài khoản, không cần số điện thoại

Với Cleona, bạn không cần số điện thoại lẫn địa chỉ email để đăng nhập. Danh
tính của bạn là một cặp khóa mật mã, được tạo tự động trên thiết bị ngay lần
khởi động đầu tiên. Điều đó có nghĩa là: không ai có thể tìm ra bạn qua số
điện thoại hay địa chỉ email, trừ khi chính bạn chia sẻ thông tin liên hệ
của mình.

### Mã hóa bền vững trước tương lai

Cleona sử dụng cái gọi là mã hóa hậu lượng tử (Post-Quantum). Điều này có
nghĩa là: ngay cả máy tính lượng tử trong tương lai cũng không thể phá được
tin nhắn của bạn. Bạn không cần hiểu chi tiết kỹ thuật -- điều quan trọng là
việc liên lạc của bạn được bảo vệ tốt nhất có thể theo trình độ công nghệ
hiện tại.

### Hoạt động thế nào nếu không có máy chủ?

Hãy hình dung bạn và danh bạ của bạn cùng nhau tạo thành một mạng lưới. Mỗi
thiết bị đều góp phần chuyển tiếp tin nhắn. Nếu người nhận đang trực tuyến,
tin nhắn sẽ đi thẳng đến họ. Nếu người nhận đang ngoại tuyến, các danh bạ
chung sẽ tạm giữ tin nhắn và chuyển nó đi ngay khi người nhận quay lại trực
tuyến. Vậy nên danh bạ của bạn đồng thời cũng chính là mạng lưới của bạn.

### Nền tảng

Cleona hiện có sẵn cho Android, iOS, macOS, Linux và Windows.

---

## 2. Bắt đầu

### Cài đặt ứng dụng

**Android:**
1. Tải file APK từ trang web Cleona hoặc từ GitHub Releases.
2. Mở file trên điện thoại của bạn. Nếu cần, cho phép cài đặt từ nguồn không
   xác định (Android sẽ tự động hỏi bạn).
3. Chạm "Cài đặt" và chờ cho đến khi quá trình cài đặt hoàn tất.

**iOS:**
1. Mở liên kết mời TestFlight trên iPhone của bạn.
2. Chạm "Cài đặt". TestFlight là kênh phân phối ứng dụng bản beta chính thức
   của Apple.
3. Sau khi cài đặt xong, bạn sẽ thấy Cleona trên màn hình chính.

**macOS:**
1. Tải file DMG từ trang web Cleona hoặc từ GitHub Releases.
2. Mở file DMG và kéo Cleona vào thư mục Ứng dụng (Applications).
3. Khi khởi động lần đầu, macOS có thể hỏi liệu bạn có muốn mở ứng dụng của
   một nhà phát triển đã xác định danh tính hay không -- hãy xác nhận đồng ý.

**Linux (Ubuntu/Debian):**
1. Tải file .deb từ trang web Cleona hoặc từ GitHub Releases.
2. Cài đặt bằng cách nhấp đúp hoặc trong terminal: `sudo dpkg -i cleona-chat_VERSION_amd64.deb`
3. Khởi động Cleona qua menu ứng dụng hoặc trong terminal bằng lệnh `cleona-chat`.

**Linux (Fedora/openSUSE):**
1. Tải file .rpm từ trang web Cleona hoặc từ GitHub Releases.
2. Cài đặt bằng: `sudo dnf install cleona-chat-VERSION.x86_64.rpm`
3. Khởi động Cleona qua menu ứng dụng hoặc trong terminal bằng lệnh `cleona-chat`.

**Linux (mọi bản phân phối -- AppImage):**
1. Tải file .AppImage từ trang web Cleona hoặc từ GitHub Releases.
2. Cấp quyền thực thi cho file: nhấp chuột phải, Thuộc tính (Properties), chọn
   Có thể thực thi (Executable), hoặc trong terminal: `chmod +x cleona-chat-VERSION-x86_64.AppImage`
3. Khởi động bằng cách nhấp đúp hoặc trong terminal: `./cleona-chat-VERSION-x86_64.AppImage`

**Windows:**
1. Tải trình cài đặt từ trang web Cleona hoặc từ GitHub Releases.
2. Chạy file cài đặt và làm theo hướng dẫn.
3. Khởi động Cleona qua menu Start hoặc biểu tượng trên màn hình nền.

### Tạo danh tính

Khi khởi động lần đầu, Cleona sẽ tự động tạo một danh tính mới cho bạn. Bạn
có thể đặt cho mình một tên hiển thị -- đây là tên mà danh bạ của bạn sẽ
nhìn thấy. Tên này có thể thay đổi bất cứ lúc nào.

### Ghi lại Seed-Phrase -- điều quan trọng nhất

Sau khi tạo danh tính, Cleona sẽ hiển thị cho bạn 24 từ. Đây chính là
**Seed-Phrase** của bạn -- khóa khôi phục cá nhân của bạn.

**Hãy ghi 24 từ này ra giấy và cất giữ ở nơi an toàn.**

Tại sao điều này lại quan trọng đến vậy?

- Nếu điện thoại của bạn hỏng, bị mất hoặc bị đánh cắp, bạn có thể dùng 24
  từ này để khôi phục toàn bộ danh tính của mình trên một thiết bị mới.
- Nếu không có Seed-Phrase, sẽ không có cách nào quay lại được. Không có nút
  "quên mật khẩu" và cũng không có bộ phận hỗ trợ nào có thể trả lại tài
  khoản cho bạn -- vì đơn giản là không hề có tài khoản nào trên máy chủ cả.
- Không bao giờ chia sẻ Seed-Phrase cho người khác. Ai biết những từ này có
  thể mạo danh bạn.

Bạn có thể xem lại Seed-Phrase sau này trong phần Cài đặt, mục "Bảo mật",
nếu muốn đọc lại.

### Thêm danh bạ đầu tiên

Để trò chuyện với ai đó, trước tiên bạn cần thêm người đó vào danh bạ. Có
nhiều cách để làm điều này -- tất cả sẽ được giải thích trong phần tiếp theo.

---

## 3. Danh bạ

### Quét mã QR-Code (khuyến nghị)

Cách đơn giản nhất để thêm một danh bạ:

1. Người kia mở trang chi tiết danh tính của họ (chạm vào tên của chính họ
   trên thanh trên cùng) và cho bạn xem mã QR-Code của họ.
2. Bạn chạm vào nút dấu cộng và chọn "Quét mã QR-Code".
3. Đưa điện thoại của bạn hướng vào mã QR-Code của người kia.
4. Yêu cầu kết bạn sẽ được gửi tự động. Ngay khi người kia chấp nhận, hai
   bạn có thể nhắn tin cho nhau.

Nếu hai bạn gặp nhau trực tiếp, mã QR-Code là phương thức an toàn nhất, vì
bạn biết chính xác mình đang trao đổi danh bạ với ai.

### NFC (chạm hai điện thoại vào nhau)

Nếu cả hai thiết bị đều hỗ trợ NFC:

1. Cả hai mở chức năng thêm danh bạ.
2. Áp mặt sau hai điện thoại vào nhau.
3. Thông tin danh bạ sẽ được trao đổi tự động.

Cũng giống như mã QR-Code, NFC mang lại độ an toàn cao vì việc trao đổi chỉ
hoạt động khi hai bạn đứng cạnh nhau về mặt vật lý.

### Chia sẻ liên kết (cleona://-URI)

Bạn cũng có thể gửi liên kết danh bạ của mình qua email, SMS hoặc qua một
ứng dụng nhắn tin khác:

1. Mở trang chi tiết danh tính của bạn.
2. Sao chép liên kết cleona:// của bạn.
3. Gửi liên kết cho người muốn thêm bạn.
4. Người kia mở liên kết, hoặc dán liên kết vào hộp thoại thêm danh bạ.

Lưu ý: với cách này, bạn đang tin tưởng rằng liên kết không bị thay đổi trên
đường truyền. Đối với những danh bạ đặc biệt nhạy cảm, chúng tôi khuyên bạn
nên dùng mã QR-Code hoặc NFC.

### Chấp nhận yêu cầu kết bạn

Khi ai đó gửi cho bạn yêu cầu kết bạn, yêu cầu đó sẽ xuất hiện trong hộp thư
đến của bạn (tab cuối cùng trên thanh dưới cùng). Tại đó bạn có thể:

- **Chấp nhận** -- người đó sẽ được thêm vào danh bạ của bạn.
- **Từ chối** -- yêu cầu sẽ bị hủy bỏ.
- **Chặn** -- người đó sẽ không thể gửi thêm yêu cầu nào cho bạn nữa.

### Các cấp độ xác minh

Cleona cho bạn biết danh tính của một danh bạ đã được xác nhận chắc chắn đến
mức nào:

| Cấp độ | Ý nghĩa |
|-------|-----------|
| Chưa xác định | Bạn chỉ mới nhận được Node-ID hoặc một liên kết. |
| Đã thấy | Quá trình trao đổi khóa đã thành công, hai bạn có thể liên lạc mã hóa với nhau. |
| Đã xác minh | Hai bạn đã gặp nhau trực tiếp và xác minh qua mã QR-Code hoặc NFC. |
| Đáng tin cậy | Bạn đã đánh dấu rõ ràng danh bạ này là đáng tin cậy. |

Cấp độ càng cao, bạn càng có thể chắc chắn rằng mình thực sự đang nói chuyện
với đúng người.

---

## 4. Tin nhắn

### Gửi và nhận tin nhắn văn bản

Chỉ cần gõ tin nhắn của bạn vào ô nhập liệu bên dưới rồi nhấn Enter hoặc nút
Gửi. Tin nhắn của bạn sẽ được mã hóa tự động trước khi rời khỏi thiết bị.

Tin nhắn đến sẽ hiện trong lịch sử trò chuyện. Một dấu tích cho bạn biết liệu
tin nhắn của bạn đã được gửi đến hay chưa.

### Gửi hình ảnh, video và tệp tin

Bạn có nhiều cách để làm điều này:

- **Biểu tượng kẹp giấy** trong ô nhập liệu: chạm vào đó để chọn một tệp tin,
  hình ảnh hoặc video từ thư viện hoặc hệ thống tệp của bạn.
- **Kéo và thả** (trên máy tính để bàn): chỉ cần kéo một tệp tin vào cửa sổ
  trò chuyện.
- **Dán từ clipboard** (trên máy tính để bàn): sao chép một hình ảnh và dán
  vào cuộc trò chuyện.

Các tệp nhỏ (dưới 256 KB) sẽ được gửi kèm trực tiếp. Các tệp lớn hơn được
truyền theo quy trình hai bước: trước tiên tệp được thông báo trước, sau đó
được truyền theo từng phần.

### Tin nhắn thoại

1. Giữ nút micro trong ô nhập liệu.
2. Nói tin nhắn của bạn.
3. Thả nút ra để gửi tin nhắn.

Nếu tính năng nhận dạng giọng nói được bật trên thiết bị của bạn (xem phần
Cài đặt), tin nhắn thoại của bạn sẽ tự động được chuyển thành văn bản. Người
nhận sẽ thấy cả bản ghi âm lẫn văn bản đã được chuyển đổi.

### Trả lời tin nhắn (Trích dẫn)

Để trả lời một tin nhắn cụ thể:

1. Mở menu ba chấm cạnh tin nhắn.
2. Chọn "Trả lời".
3. Một banner với tin nhắn được trích dẫn sẽ xuất hiện phía trên ô nhập liệu.
4. Viết câu trả lời của bạn và gửi đi.

Tin nhắn được trích dẫn sẽ hiển thị trong câu trả lời của bạn, để mối liên
hệ được rõ ràng.

### Chỉnh sửa và xóa tin nhắn

- **Chỉnh sửa:** Menu ba chấm của tin nhắn, sau đó chọn "Chỉnh sửa". Thay đổi
  nội dung và gửi lại. Người nhận sẽ thấy rằng tin nhắn đã được chỉnh sửa.
  Việc chỉnh sửa chỉ khả thi trong vòng 15 phút sau khi gửi.
- **Xóa:** Menu ba chấm của tin nhắn, sau đó chọn "Xóa". Tin nhắn sẽ bị xóa
  cả ở phía bạn lẫn phía người nhận. Bạn có thể xóa tin nhắn của chính mình
  bất cứ lúc nào -- không có giới hạn thời gian nào cho việc xóa.

### Biểu tượng cảm xúc phản hồi

Thay vì viết một câu trả lời, bạn có thể phản hồi một tin nhắn bằng biểu
tượng cảm xúc (emoji):

1. Mở menu ba chấm hoặc nhấn giữ tin nhắn.
2. Chọn một emoji từ danh sách nhanh hoặc mở bảng chọn emoji đầy đủ.
3. Phản hồi của bạn sẽ xuất hiện bên dưới tin nhắn.

### Sao chép văn bản

Qua menu ba chấm của một tin nhắn, bạn có thể sao chép nội dung tin nhắn vào
clipboard.

### Tìm kiếm tin nhắn

Ở phía trên cửa sổ trò chuyện có chức năng tìm kiếm. Nhập từ khóa cần tìm,
Cleona sẽ hiển thị tất cả kết quả trong cuộc trò chuyện hiện tại. Bạn có thể
dùng các phím mũi tên để chuyển qua lại giữa các kết quả.

Trên màn hình chính còn có thêm bộ lọc tìm kiếm xuyên suốt các tab, cho phép
bạn tìm kiếm một từ khóa trong tất cả các cuộc trò chuyện.

### Xem trước liên kết

Khi bạn gửi một liên kết, Cleona sẽ tự động tạo bản xem trước (tiêu đề, mô
tả, hình ảnh xem trước). Bản xem trước này được tạo trên thiết bị của bạn và
gửi kèm theo -- người nhận không cần phải kết nối đến trang web được liên
kết.

Khi bạn chạm vào một liên kết nhận được, bạn sẽ được hỏi liệu muốn mở nó
bằng trình duyệt thông thường, chế độ ẩn danh, hay không mở gì cả.

---

## 5. Nhóm

### Tạo nhóm

1. Chuyển sang tab "Nhóm".
2. Chạm vào nút dấu cộng.
3. Đặt tên cho nhóm.
4. Chọn các danh bạ bạn muốn mời.
5. Chạm "Tạo".

Các danh bạ được mời sẽ nhận được thông báo và có thể tham gia nhóm.

### Mời thành viên

Ngay cả sau khi tạo nhóm, bạn vẫn có thể mời thêm danh bạ khác:

1. Mở thông tin nhóm (menu ba chấm trong danh sách nhóm hoặc thanh trên
   cùng trong cuộc trò chuyện nhóm).
2. Chạm "Mời".
3. Chọn các danh bạ bạn muốn thêm vào.

### Vai trò

Mỗi nhóm có ba vai trò:

- **Chủ sở hữu (Owner):** Có toàn quyền kiểm soát. Có thể thêm và xóa thành
  viên, bổ nhiệm quản trị viên và quản lý nhóm. Chủ sở hữu cũng có thể chuyển
  giao vai trò của mình cho một thành viên khác.
- **Quản trị viên (Admin):** Có thể xóa thành viên và hỗ trợ quản lý.
- **Thành viên:** Có thể đọc và viết tin nhắn.

### Rời nhóm

1. Mở menu ba chấm trong danh sách nhóm.
2. Chọn "Rời nhóm".
3. Xác nhận quyết định của bạn.

Khi bạn rời một nhóm, những tin nhắn trước đây của bạn vẫn sẽ hiển thị cho
các thành viên khác.

---

## 6. Kênh công khai

### Kênh là gì?

Kênh là các diễn đàn thảo luận công khai bên trong mạng lưới Cleona. Khác
với nhóm, ở đây bất kỳ ai cũng có thể theo dõi mà không cần được mời. Chỉ
chủ sở hữu và quản trị viên mới có thể đăng bài -- người theo dõi chỉ đọc.

### Tìm và tham gia kênh

1. Chuyển sang tab "Kênh".
2. Mở tab "Tìm kiếm".
3. Duyệt qua các kênh có sẵn theo tên hoặc chủ đề.
4. Chạm vào một kênh rồi chọn "Theo dõi".

Các kênh có thể được lọc theo ngôn ngữ. Một số kênh được đánh dấu là "Không
dành cho trẻ em" -- những kênh này chỉ hiển thị khi bạn đã xác nhận trong hồ
sơ của mình rằng bạn trên 18 tuổi.

### Tạo kênh riêng

1. Chuyển sang tab "Kênh".
2. Chạm vào nút dấu cộng.
3. Nhập tên kênh (phải là duy nhất trong toàn mạng lưới).
4. Chọn ngôn ngữ và kênh sẽ là công khai hay riêng tư.
5. Tùy chọn: thêm mô tả và hình ảnh.
6. Chạm "Tạo".

Đối với các kênh công khai, bạn có thể quy định nội dung có được xếp loại
"Không dành cho trẻ em" hay không.

### Báo cáo nội dung

Nếu bạn nhận thấy nội dung không phù hợp trong một kênh công khai, bạn có
thể báo cáo. Cleona sử dụng một hệ thống kiểm duyệt phi tập trung: các báo
cáo sẽ được đánh giá bởi các thành viên được chọn ngẫu nhiên trong mạng lưới
(giống như một "bồi thẩm đoàn"). Nếu phát hiện vi phạm, kênh sẽ nhận một
cảnh báo. Nếu tái phạm nhiều lần, kênh sẽ bị hạ thứ hạng trong chỉ mục tìm
kiếm hoặc bị khóa.

### Kênh hệ thống

Cleona có sẵn hai kênh hệ thống tích hợp:

- **Bug Log:** Khi Cleona phát hiện lỗi, nó sẽ hỏi bạn có muốn gửi báo cáo
  lỗi ẩn danh hay không. Những báo cáo này sẽ được đăng lên kênh Bug Log, nơi
  cộng đồng có thể xem. Không có dữ liệu cá nhân nào được truyền đi -- chỉ có
  mô tả lỗi kỹ thuật. Bạn cũng có thể tự gửi báo cáo log theo cách thủ công
  (kèm hộp thoại xem trước và sự đồng ý rõ ràng).
- **Feature Requests:** Tại đây người dùng có thể gửi các đề xuất tính năng
  và bình chọn cho các đề xuất hiện có. Các đề xuất được sắp xếp theo số
  lượt bình chọn.

Cả hai kênh hệ thống đều có giới hạn dung lượng 25 MB và được giám sát bởi
hệ thống kiểm duyệt bồi thẩm đoàn.

---

## 7. Cuộc gọi

### Bắt đầu cuộc gọi thoại

1. Mở cuộc trò chuyện với danh bạ bạn muốn gọi.
2. Chạm vào biểu tượng điện thoại trên thanh trên cùng.
3. Chờ cho đến khi người kia trả lời cuộc gọi.

Trong lúc trò chuyện, bạn sẽ thấy thời lượng cuộc gọi và có quyền truy cập
vào chức năng tắt tiếng và loa ngoài.

Để kết thúc cuộc gọi, chạm vào nút kết thúc cuộc gọi màu đỏ.

### Bắt đầu cuộc gọi video

1. Mở cuộc trò chuyện với danh bạ.
2. Chạm vào biểu tượng camera trên thanh trên cùng.
3. Hình ảnh của bạn sẽ xuất hiện trong một cửa sổ nhỏ, hình ảnh của người
   kia hiển thị ở khu vực lớn.

Bạn có thể chuyển đổi giữa camera trước và camera sau trong lúc gọi.

### Cuộc gọi đến

Khi có ai đó gọi cho bạn, một cửa sổ thông báo sẽ hiện ra kèm tên người gọi.
Bạn có thể:

- **Trả lời** -- cuộc gọi bắt đầu.
- **Từ chối** -- người gọi sẽ được thông báo.

Nếu bạn đang trong một cuộc gọi khác, cuộc gọi mới sẽ tự động bị từ chối.

### Cuộc gọi nhóm

Bạn cũng có thể thực hiện cuộc gọi nhóm với nhiều người tham gia cùng lúc.
Cuộc gọi được tổ chức qua một cây chuyển tiếp thông minh, nhờ đó không phải
mỗi người tham gia đều cần kết nối trực tiếp với tất cả những người khác.
Tất cả các cuộc gọi đều được mã hóa toàn trình.

### Mã hóa trong cuộc gọi

Tất cả các cuộc gọi đều được mã hóa bằng những khóa dùng một lần, chỉ tồn
tại trong suốt thời gian cuộc gọi. Sau khi kết thúc cuộc gọi, các khóa này
sẽ bị xóa ngay lập tức. Không ai có thể giải mã một cuộc gọi đã diễn ra
trong quá khứ.

---

## 8. Lịch

Cleona có một ứng dụng lịch tích hợp, hoạt động mã hóa và hoàn toàn phi tập
trung -- không cần dịch vụ đám mây.

### Các chế độ xem

Lịch cung cấp năm chế độ xem: Ngày, Tuần, Tháng, Năm và một chế độ xem Công
việc (Tasks). Chuyển đổi giữa các chế độ này qua các tab ở phía trên màn
hình lịch.

### Tạo sự kiện

Chạm vào một khung giờ hoặc dùng nút thêm mới để tạo một sự kiện. Bạn có thể
nhập tiêu đề, ngày, giờ, địa điểm và ghi chú. Sự kiện được lưu trữ mã hóa
trên thiết bị của bạn.

### Sự kiện lặp lại

Sự kiện có thể lặp lại hằng ngày, hằng tuần, hằng tháng hoặc hằng năm. Bạn
có thể tùy chỉnh chu kỳ (ví dụ: thứ Ba cách tuần, hoặc ngày đầu tiên mỗi
tháng) và đặt ngày kết thúc hoặc số lần lặp lại.

### Mời danh bạ

Khi tạo hoặc chỉnh sửa một sự kiện, bạn có thể mời các danh bạ Cleona của
mình. Họ sẽ nhận được lời mời lịch được mã hóa và có thể trả lời Đồng ý, Từ
chối hoặc Có thể. Mọi thay đổi đối với sự kiện sẽ tự động được gửi đến tất cả
người được mời.

### Hiển thị Rảnh/Bận

Bạn có thể chia sẻ tình trạng rảnh/bận của mình với danh bạ mà không cần
tiết lộ chi tiết sự kiện. Có ba mức độ bảo mật: chi tiết đầy đủ, chỉ khung
giờ, hoặc ẩn hoàn toàn. Bạn có thể đặt một mức mặc định và ghi đè riêng cho
từng danh bạ.

### Nhắc nhở

Sự kiện có thể có lời nhắc, kích hoạt một thông báo hệ thống trước khi sự
kiện bắt đầu. Bạn có thể hoãn (báo lại) lời nhắc khi cần.

### Đồng bộ với lịch bên ngoài

Cleona có thể đồng bộ với các dịch vụ lịch bên ngoài:

- **CalDAV** -- Kết nối với bất kỳ máy chủ tương thích CalDAV nào (Nextcloud,
  Radicale, v.v.).
- **Google Lịch** -- Đồng bộ qua Google Calendar API với xác thực OAuth2 an
  toàn.
- **Máy chủ CalDAV cục bộ** -- Cleona có thể khởi chạy một máy chủ CalDAV cục
  bộ ngay trên thiết bị của bạn, để các ứng dụng lịch trên máy tính để bàn
  (Thunderbird, Outlook, Apple Calendar, Evolution) có thể đồng bộ với lịch
  Cleona của bạn.
- **Lịch hệ thống Android** -- Sự kiện từ Cleona có thể được chuyển sang ứng
  dụng lịch tích hợp sẵn trên thiết bị Android của bạn.
- **Tệp ICS** -- Nhập và xuất sự kiện theo định dạng iCalendar tiêu chuẩn.

### Xuất PDF

Bạn có thể in hoặc xuất bất kỳ chế độ xem lịch nào (Ngày, Tuần, Tháng, Năm)
dưới dạng tài liệu PDF.

---

## 9. Khảo sát

Bạn có thể tạo khảo sát trong bất kỳ cuộc trò chuyện hoặc nhóm nào để thu
thập ý kiến hoặc lên kế hoạch hẹn gặp.

### Các loại khảo sát

Cleona hỗ trợ năm loại khảo sát:

- **Chọn một** -- Người tham gia chọn một phương án.
- **Chọn nhiều** -- Người tham gia có thể chọn nhiều phương án.
- **Khảo sát lịch hẹn** -- Tìm một thời điểm phù hợp cho tất cả mọi người.
  Mỗi người tham gia đánh dấu các thời điểm là rảnh, có thể, hoặc không
  rảnh.
- **Thang điểm** -- Đánh giá điều gì đó trên một thang số (ví dụ từ 1 đến
  5).
- **Văn bản tự do** -- Người tham gia tự viết câu trả lời của riêng mình.

### Tạo khảo sát

Mở một cuộc trò chuyện và chạm vào biểu tượng khảo sát (hoặc dùng menu đính
kèm). Chọn loại khảo sát, đặt câu hỏi và các phương án, rồi gửi khảo sát đi.
Nó sẽ xuất hiện dưới dạng một tin nhắn trong cuộc trò chuyện.

### Bình chọn

Chạm vào một khảo sát để bỏ phiếu. Bạn có thể thay đổi hoặc rút lại phiếu
bầu của mình bất cứ lúc nào.

### Bình chọn ẩn danh

Khảo sát có thể được cấu hình cho bình chọn ẩn danh. Khi được bật, các phiếu
bầu sẽ ẩn danh về mặt mật mã học -- không ai, kể cả người tạo khảo sát, có
thể biết ai đã bầu cho phương án nào. Tổng số phiếu bầu vẫn hiển thị bình
thường.

### Chuyển khảo sát lịch hẹn sang lịch

Khi một khảo sát lịch hẹn đã hoàn tất, thời điểm chiến thắng có thể được
chuyển trực tiếp thành một mục trong lịch chỉ bằng một cú chạm.

---

## 10. Nhiều danh tính

### Tại sao cần nhiều danh tính?

Hãy hình dung bạn muốn tách biệt cuộc sống công việc và cuộc sống riêng tư
của mình -- giống như có hai số điện thoại khác nhau, nhưng không cần đến
điện thoại thứ hai. Trong Cleona, bạn có thể sử dụng nhiều danh tính trên
cùng một thiết bị. Mỗi danh tính có tên riêng, ảnh đại diện riêng, danh bạ
riêng và các cuộc trò chuyện riêng.

### Tạo danh tính mới

1. Trên thanh trên cùng, bạn sẽ thấy danh tính hiện tại của mình dưới dạng
   một tab.
2. Chạm vào dấu cộng (+) bên phải các tab danh tính của bạn.
3. Nhập tên cho danh tính mới.
4. Xong -- danh tính mới sẽ hoạt động ngay lập tức.

### Chuyển đổi giữa các danh tính

Chỉ cần chạm vào tab danh tính trên thanh trên cùng. Việc chuyển đổi diễn ra
ngay lập tức -- không cần chờ đợi, không cần tải lại.

### Tất cả đều hoạt động cùng lúc

Một điểm quan trọng: tất cả các danh tính của bạn đều hoạt động đồng thời.
Ngay cả khi bạn đang hiển thị là danh tính "Công việc", danh tính "Riêng tư"
của bạn vẫn tiếp tục nhận tin nhắn. Bạn sẽ không bỏ lỡ điều gì, bất kể danh
tính nào bạn đang chọn.

### Trang chi tiết danh tính

Khi bạn chạm vào tab của danh tính đang hoạt động, trang chi tiết sẽ mở ra.
Tại đây bạn có thể:

- Hiển thị mã QR-Code của mình cho danh bạ.
- Thay đổi hoặc xóa ảnh đại diện.
- Thêm phần mô tả hồ sơ.
- Thay đổi tên hiển thị.
- Chọn một giao diện (Skin) cho danh tính này.
- Xóa danh tính nếu bạn không cần đến nữa.

### Xóa danh tính

Khi bạn xóa một danh tính, danh bạ của bạn sẽ được thông báo về việc này.
Danh tính và toàn bộ dữ liệu liên quan sẽ bị xóa khỏi thiết bị của bạn. Quá
trình này không thể hoàn tác.

---

## 11. Đa thiết bị

### Sử dụng Cleona trên nhiều thiết bị

Bạn có thể dùng cùng một danh tính trên tối đa 5 thiết bị cùng lúc. Một
thiết bị là thiết bị chính (nó lưu giữ Seed-Phrase), và các thiết bị khác sẽ
được liên kết với nó.

### Liên kết thiết bị mới

1. Mở phần Cài đặt trên thiết bị chính của bạn.
2. Vào mục "Thiết bị đã liên kết".
3. Chọn "Liên kết thiết bị mới".
4. Cài đặt Cleona trên thiết bị mới và khi khởi động, chọn "Liên kết với
   thiết bị đã có".
5. Quét mã QR-Code ghép nối được hiển thị trên thiết bị chính của bạn, hoặc
   dùng liên kết ghép nối.

Thiết bị được liên kết sẽ nhận một chứng chỉ ủy quyền từ thiết bị chính. Các
tin nhắn được gửi từ một thiết bị đã liên kết sẽ được ký bằng mật mã với một
khóa được ủy quyền, để danh bạ có thể xác minh rằng tin nhắn thực sự đến từ
danh tính của bạn.

### Cách thức hoạt động

- Thiết bị chính lưu giữ Seed-Phrase và các khóa chủ (master keys) của bạn.
- Các thiết bị được liên kết nhận các khóa chữ ký được suy ra và một chứng
  chỉ ủy quyền -- chúng không bao giờ nhận được Seed-Phrase gốc.
- Tất cả các thiết bị đều dùng chung một danh tính và danh bạ. Tin nhắn sẽ
  đến trên tất cả các thiết bị.
- Chứng chỉ ủy quyền được tự động gia hạn trước khi hết hạn.

### Quản lý thiết bị

Mở phần Cài đặt và vào mục "Thiết bị đã liên kết" để xem tất cả các thiết bị
đã liên kết, trạng thái và hoạt động gần nhất của chúng. Bạn có thể thu hồi
một thiết bị đã liên kết bất cứ lúc nào, nếu nó bị mất hoặc bị đánh cắp.

### Xoay vòng khóa khẩn cấp

Nếu bạn nghi ngờ rằng một thiết bị đã bị xâm nhập, bạn có thể kích hoạt việc
xoay vòng khóa khẩn cấp. Khi đó các khóa mới sẽ được tạo ra, và việc xoay
vòng này cần được đa số các thiết bị khác của bạn xác nhận. Điều này ngăn
chặn việc một thiết bị duy nhất bị đánh cắp có thể tự ý xoay vòng khóa.

---

## 12. Khôi phục

### Sử dụng Seed-Phrase

Nếu bạn mất thiết bị hoặc thiết lập một thiết bị mới:

1. Cài đặt Cleona trên thiết bị mới.
2. Khi khởi động, chọn "Khôi phục".
3. Nhập 24 từ của bạn.
4. Cleona sẽ khôi phục danh tính của bạn và tự động liên hệ với các danh bạ
   trước đây của bạn.
5. Danh bạ của bạn sẽ phản hồi với thông tin liên hệ, các nhóm bạn tham gia
   và lịch sử tin nhắn.

Quá trình khôi phục diễn ra theo ba bước:
- Đầu tiên là danh bạ và nhóm của bạn quay trở lại.
- Tiếp theo là 50 tin nhắn gần nhất trong mỗi cuộc trò chuyện.
- Cuối cùng là toàn bộ lịch sử tin nhắn.

Chỉ cần một danh bạ duy nhất của bạn đang trực tuyến là quá trình khôi phục
đã có thể hoạt động.

### Guardian Recovery (Người bảo hộ tin cậy)

Bạn có thể chỉ định tối đa năm người bạn tin tưởng làm "Guardian" (người bảo
hộ). Khi đó khóa khôi phục của bạn sẽ được chia thành năm phần, mỗi Guardian
nhận một phần. Để khôi phục danh tính của bạn, chỉ cần ba trong số năm phần
là đủ.

Điều đó có nghĩa là: ngay cả khi bạn đã mất Seed-Phrase, ba trong số các
Guardian của bạn có thể cùng nhau khôi phục tài khoản cho bạn. Không một
Guardian nào có thể một mình truy cập vào dữ liệu của bạn -- luôn cần ít
nhất ba người.

Thiết lập Guardian như sau:
1. Mở phần Cài đặt.
2. Vào mục "Bảo mật".
3. Chọn "Guardian Recovery".
4. Chọn năm danh bạ đáng tin cậy.

### Vì sao danh bạ chính là bản sao lưu của bạn

Ở các ứng dụng nhắn tin thông thường, dữ liệu của bạn nằm trên máy chủ của
nhà cung cấp dịch vụ. Với Cleona thì không có máy chủ nào cả -- nhưng danh
bạ của bạn đảm nhận vai trò đó. Khi bạn gửi một tin nhắn, các danh bạ chung
sẽ lưu một bản sao mã hóa phòng trường hợp người nhận đang ngoại tuyến. Khi
khôi phục, danh bạ của bạn sẽ trả lại dữ liệu cho bạn.

Điều này có nghĩa là: bạn càng có nhiều danh bạ hoạt động tích cực, bản sao
lưu của bạn càng đáng tin cậy. Chỉ cần một danh bạ thường xuyên trực tuyến là
đủ để khôi phục thành công.

---

## 13. Cài đặt

Bạn có thể vào phần Cài đặt qua biểu tượng bánh răng ở góc trên bên phải.

### Thông báo và nhạc chuông

- Chọn một trong sáu nhạc chuông khác nhau cho cuộc gọi đến.
- Đặt âm thanh thông báo tin nhắn.
- Trên thiết bị Android, bạn còn có thể bật hoặc tắt rung.

### Giao diện (Skins)

Cleona cung cấp mười giao diện khác nhau: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold và Contrast. Giao diện Contrast đạt mức độ
truy cập cao nhất (WCAG AAA) và đặc biệt dễ đọc đối với người có thị lực hạn
chế.

Mỗi danh tính có thể có giao diện riêng của mình. Bạn thay đổi giao diện
trong trang chi tiết danh tính (chạm vào tab danh tính đang hoạt động).

Ngoài ra, trong phần Cài đặt mục "Giao diện", bạn có thể chuyển đổi giữa chế
độ sáng, tối và theo hệ thống.

### Thay đổi ngôn ngữ

Cleona có sẵn với 33 ngôn ngữ, trong đó có cả các ngôn ngữ viết từ phải sang
trái (ví dụ tiếng Ả Rập, tiếng Hebrew). Thay đổi ngôn ngữ trong phần Cài đặt
mục "Ngôn ngữ".

### Giới hạn dung lượng lưu trữ

Bạn có thể quy định lượng dung lượng lưu trữ mà Cleona được phép sử dụng
trên thiết bị của mình (từ 100 MB đến 2 GB). Khi đạt đến giới hạn, các
phương tiện cũ hơn sẽ tự động được chuyển ra ngoài hoặc xóa đi -- tin nhắn
văn bản luôn được giữ lại.

### Lưu trữ phương tiện tự động

Nếu bạn có một thiết bị lưu trữ mạng (NAS) hoặc một thư mục chia sẻ tại nhà,
Cleona có thể tự động chuyển phương tiện của bạn sang đó. Các giao thức được
hỗ trợ: SMB, SFTP, FTPS và WebDAV.

Việc lưu trữ theo tầng hoạt động như sau:
- 30 ngày đầu tiên: mọi thứ vẫn nằm trên thiết bị của bạn.
- Sau 30 ngày: một ảnh xem trước vẫn ở lại trên thiết bị, bản gốc được lưu
  trữ đi.
- Sau 90 ngày: chỉ còn một ảnh xem trước nhỏ ở lại trên thiết bị.
- Sau một năm: chỉ còn một phần tử giữ chỗ, bản gốc nằm an toàn trong kho
  lưu trữ.

Bạn có thể chạm vào bất kỳ phương tiện đã lưu trữ nào bất cứ lúc nào để lấy
lại -- với điều kiện bạn đang kết nối với mạng gia đình của mình. Những
phương tiện đặc biệt quan trọng có thể được ghim lại để không bao giờ bị
chuyển ra ngoài.

### Chuyển văn bản cho tin nhắn thoại

Nếu được bật, tin nhắn thoại của bạn sẽ được chuyển thành văn bản ngay trên
thiết bị (bằng mô hình mã nguồn mở Whisper). Văn bản đã chuyển đổi sẽ được
gửi cùng với bản ghi âm đến người nhận. Việc chuyển đổi diễn ra hoàn toàn
trên thiết bị của bạn -- không có dữ liệu nào được gửi đến các dịch vụ bên
ngoài.

### Tự động tải xuống

Bạn có thể quy định từ dung lượng nào thì phương tiện sẽ được tự động tải
xuống. Ví dụ, bạn có thể để hình ảnh tự động tải, nhưng tự quyết định thủ
công đối với các video dung lượng lớn.

### Thiết bị đã liên kết

Quản lý các thiết bị đã liên kết của bạn trong mục này của phần Cài đặt. Xem
chương Đa thiết bị để biết thêm chi tiết.

---

## 14. Bảo mật

### Mã hóa hậu lượng tử (Post-Quantum) là gì?

Mã hóa ngày nay dựa trên các bài toán mà máy tính thông thường cực kỳ khó
giải. Máy tính lượng tử trong tương lai có thể giải nhanh một số bài toán
này. Mã hóa hậu lượng tử sử dụng thêm các phương pháp có thể chống chịu được
cả máy tính lượng tử.

Cleona kết hợp cả hai phương pháp: mã hóa cổ điển để đảm bảo độ tin cậy và
phương pháp hậu lượng tử để bền vững trước tương lai. Nhờ đó bạn được bảo vệ
đồng thời trước các mối đe dọa hiện tại lẫn tương lai.

Với mỗi tin nhắn, một khóa riêng sẽ được tạo ra. Ngay cả khi kẻ tấn công phá
được khóa của một tin nhắn, chúng cũng không thể dùng nó để đọc bất kỳ tin
nhắn nào khác.

### Vì sao không có máy chủ lại an toàn hơn

Ở các ứng dụng nhắn tin thông thường, tin nhắn của bạn đi qua máy chủ của
nhà cung cấp dịch vụ. Cho dù chúng có được mã hóa ở đó đi nữa: nhà cung cấp
vẫn có quyền truy cập vào siêu dữ liệu (ai liên lạc với ai, khi nào, bao
nhiêu lần, từ đâu) và trong một số trường hợp có thể phải giao nộp dữ liệu
này theo lệnh của tòa án.

Với Cleona không hề có điểm trung tâm nào như vậy. Tin nhắn của bạn đi trực
tiếp từ thiết bị đến thiết bị. Không có nơi nào tất cả siêu dữ liệu hội tụ
lại. Không ai có thể dựa vào một điểm dữ liệu duy nhất để dựng lại hành vi
liên lạc của bạn.

### Điều gì xảy ra khi bạn ngoại tuyến?

Khi bạn gửi một tin nhắn và người nhận đang ngoại tuyến:

1. Trước tiên Cleona sẽ cố gắng gửi tin nhắn trực tiếp.
2. Nếu không thành công, tin nhắn sẽ được chuyển tiếp qua các danh bạ chung.
3. Đồng thời, tin nhắn sẽ được chia thành các mảnh mã hóa và phân tán trên
   nhiều nút trong mạng lưới (giống như một trò chơi ghép hình gồm 10 mảnh,
   trong đó chỉ cần 7 mảnh là đủ để ghép lại bức tranh hoàn chỉnh).
4. Tin nhắn được lưu giữ tối đa 7 ngày.

Ngay khi người nhận trực tuyến trở lại, tin nhắn sẽ được gửi đến. Bạn sẽ
nhận được xác nhận khi tin nhắn của bạn đã đến nơi.

### Chống kiểm duyệt

Nếu mạng của bạn chặn phương thức kết nối tiêu chuẩn (UDP), Cleona sẽ tự
động chuyển sang một phương thức truyền tải thay thế (TLS), khó bị phát
hiện và chặn hơn. Điều này diễn ra hoàn toàn tự động -- bạn không cần cấu
hình gì cả.

### Lưu trữ khóa an toàn

Trên các nền tảng được hỗ trợ, Cleona lưu trữ khóa mã hóa của bạn trong kho
khóa an toàn của hệ điều hành (Android Keystore, iOS Keychain, macOS
Keychain). Ở những nơi khả dụng, điều này mang lại sự bảo vệ dựa trên phần
cứng cho khóa của bạn.

### Mã hóa cơ sở dữ liệu

Tất cả tin nhắn, danh bạ và cài đặt của bạn đều được lưu trữ mã hóa trên
thiết bị của bạn. Ngay cả khi ai đó có quyền truy cập vào hệ thống tệp của
bạn, họ cũng không thể đọc được gì nếu không có khóa mật mã của bạn. Khóa
này được suy ra từ danh tính của bạn và chỉ tồn tại trên thiết bị của bạn.

### Mạng lưới khép kín

Cleona hoạt động như một mạng lưới khép kín. Mỗi gói tin mạng đều được xác
thực, để chỉ những thiết bị Cleona chính thức mới có thể tham gia. Điều này
ngăn chặn người ngoài chèn tin nhắn giả mạo hoặc nghe lén lưu lượng mạng.

---

## 15. Cập nhật phần mềm

### Làm sao để nhận cập nhật?

Cleona có thể được cập nhật qua nhiều kênh khác nhau. Mục tiêu là để bạn vẫn
có thể nhận được cập nhật ngay cả khi từng kênh phân phối riêng lẻ bị gián
đoạn hoặc bị chặn:

1. **App Store / Play Store:** Nếu bạn cài đặt Cleona qua một App Store, bạn
   sẽ nhận cập nhật như bình thường qua cửa hàng đó.
2. **GitHub Releases:** Trên trang GitHub của dự án, bạn sẽ tìm thấy các gói
   cài đặt đã được ký cho tất cả các nền tảng.
3. **Cập nhật trong mạng lưới (In-Network):** Nếu một người dùng Cleona khác
   trong mạng lưới của bạn đã có phiên bản mới nhất, Cleona có thể lấy bản
   cập nhật trực tiếp qua mạng P2P -- mà không cần máy chủ bên ngoài. Khi đó
   phiên bản mới sẽ được chia thành các mảnh có khả năng sửa lỗi và phân tán
   qua nhiều nút. Thiết bị của bạn sẽ thu thập đủ số mảnh và ghép lại thành
   bản cập nhật. Tính xác thực được kiểm tra bằng chữ ký Ed25519 của nhà
   phát triển.
4. **Liên kết mời:** Bạn có thể tạo các liên kết mời chứa mọi thứ mà một
   người dùng mới cần để cài đặt Cleona và kết nối với mạng lưới.
5. **Chuyển giao vật lý:** Trong môi trường không có Internet, bạn có thể
   chuyển Cleona cho người khác qua USB hoặc trong mạng cục bộ.

### Thông báo cập nhật

Khi có bản cập nhật mới, Cleona sẽ hiển thị thông báo trên màn hình chính.
Nếu bản cập nhật cũng khả dụng qua mạng lưới (In-Network-Update), bạn có
thể lựa chọn tải trực tiếp từ mạng lưới.

### Phân phối nhị phân

Theo mặc định, thiết bị của bạn sẽ giúp chuyển tiếp bản cập nhật cho những
người dùng khác trong mạng lưới. Nếu bạn không muốn điều này, bạn có thể tắt
chức năng này trong phần Cài đặt mục "Mạng lưới". Dung lượng lưu trữ dành
cho các mảnh cập nhật bị giới hạn (5 MB trên thiết bị di động, 20 MB trên
thiết bị để bàn) và được dọn dẹp định kỳ.

### Kiểm tra chữ ký

Mỗi bản cập nhật đều được ký bằng mật mã. Cleona sẽ tự động kiểm tra chữ ký
trước khi cài đặt bản cập nhật. Điều này đảm bảo rằng chỉ những bản cập nhật
từ nhà phát triển chính thức mới được chấp nhận -- ngay cả khi bản cập nhật
được lấy qua mạng P2P.

---

## 16. Câu hỏi thường gặp

### "Tôi có thể dùng Cleona mà không cần Internet không?"

Không, Cleona cần có kết nối mạng để gửi và nhận tin nhắn. Tuy nhiên bạn
không cần phải trực tuyến cùng lúc với người kia: những tin nhắn được gửi
trong lúc người nhận đang ngoại tuyến sẽ được lưu tạm và tự động gửi đến
ngay khi cả hai bên kết nối trở lại. Trong mạng cục bộ (ví dụ cùng một
WLAN), hai bạn cũng có thể liên lạc với nhau mà hoàn toàn không cần truy
cập Internet.

### "Nếu tôi mất Seed-Phrase thì sao?"

Nếu bạn đã thiết lập Guardian, ba trong số năm người bảo hộ của bạn có thể
cùng nhau khôi phục quyền truy cập cho bạn. Nếu không có Guardian và cũng
không có Seed-Phrase, rất tiếc là không có cách nào để lấy lại danh tính
của bạn. Vì vậy việc cất giữ 24 từ này ở nơi an toàn là vô cùng quan trọng.

### "Có ai có thể đọc lén tin nhắn của tôi không?"

Không. Mỗi tin nhắn được mã hóa bằng một khóa dùng một lần, chỉ áp dụng cho
đúng tin nhắn đó. Chỉ bạn và người nhận mới có thể giải mã tin nhắn. Không có
máy chủ trung tâm nào, không có khóa vạn năng, và cũng không có quyền truy
cập nào dành cho nhà phát triển. Ngay cả khi một thiết bị chuyển tiếp tin
nhắn trên đường truyền, nó cũng chỉ thấy một mớ dữ liệu đã mã hóa.

### "Tại sao tôi không cần số điện thoại?"

Vì danh tính của bạn hoàn toàn dựa trên mật mã học. Thay vì một số điện
thoại hay địa chỉ email gắn liền với tên thật của bạn, bạn được nhận diện
bằng một cặp khóa được tạo ra ngay trên thiết bị của bạn. Bạn thêm danh bạ
qua mã QR-Code, NFC hoặc liên kết -- không phải qua danh bạ điện thoại. Điều
này mang lại nhiều quyền riêng tư hơn, vì tài khoản ứng dụng nhắn tin của
bạn không gắn liền với danh tính thực của bạn.

### "Làm sao để tìm người trên Cleona?"

Cleona chủ động không có chức năng tìm kiếm danh bạ theo số điện thoại hay
tên -- điều đó sẽ là một vấn đề về quyền riêng tư. Thay vào đó, bạn trao đổi
thông tin liên hệ trực tiếp: qua mã QR-Code, NFC, liên kết cleona:// hoặc
trong các kênh công khai. Nó giống như trao danh thiếp cho nhau, thay vì
tra cứu trong danh bạ điện thoại.

### "Cleona có hoạt động ở nước ngoài không?"

Có. Miễn là bạn có kết nối Internet, Cleona hoạt động ở bất cứ đâu trên thế
giới. Vì không có máy chủ trung tâm nào, dịch vụ cũng không thể bị chặn theo
từng quốc gia cụ thể. Cleona còn có cơ chế dự phòng chống kiểm duyệt: nếu
kết nối thông thường (UDP) bị chặn, Cleona sẽ tự động chuyển sang một
phương thức truyền tải thay thế (TLS), khó bị phát hiện và chặn hơn.

### "Cleona có miễn phí không?"

Có. Cleona hoàn toàn miễn phí và không có quảng cáo. Vì không có máy chủ
trung tâm nào, cũng không phát sinh chi phí vận hành máy chủ. Trong ứng
dụng, ở mục "Ủng hộ" bạn sẽ tìm thấy tùy chọn để tự nguyện hỗ trợ quá trình
phát triển.

### "Tin nhắn của tôi có biểu tượng đồng hồ -- điều đó có nghĩa là gì?"

Điều đó có nghĩa là tin nhắn chưa được gửi đến. Người nhận có lẽ đang ngoại
tuyến. Ngay khi tin nhắn được gửi đến, biểu tượng sẽ thay đổi. Tin nhắn được
lưu giữ tối đa 7 ngày để chờ gửi đi.

### "Tôi có thể chuyển từ WhatsApp sang Cleona không?"

Có, nhưng bạn không thể chuyển các cuộc trò chuyện WhatsApp của mình sang.
Cleona và WhatsApp là hai hệ thống hoàn toàn khác nhau. Bạn sẽ phải thêm
từng danh bạ vào Cleona một cách thủ công. Cách đơn giản nhất là đăng liên
kết cleona:// của bạn vào một nhóm WhatsApp và nhờ mọi người thêm bạn ở đó.

### "Tôi có thể dùng Cleona trên nhiều thiết bị cùng lúc không?"

Có. Bạn có thể liên kết tối đa 5 thiết bị với cùng một danh tính. Một thiết
bị là thiết bị chính (nó lưu giữ Seed-Phrase), và các thiết bị khác được
liên kết qua một quy trình ghép nối an toàn. Tất cả các thiết bị đều dùng
chung một danh tính, danh bạ và các cuộc trò chuyện. Xem chương Đa thiết bị
để biết thêm chi tiết.

### "Làm sao để nhận cập nhật khi App Store bị chặn?"

Cleona có thể lấy bản cập nhật trực tiếp qua mạng P2P, mà không cần phụ
thuộc vào App Store, trang web hay máy chủ tải xuống nào cả. Nếu một người
dùng khác trong mạng lưới đã có phiên bản mới nhất, thiết bị của bạn có thể
tải bản cập nhật từ đó. Tính xác thực được kiểm tra bằng chữ ký số của nhà
phát triển. Ngoài ra, một danh bạ cũng có thể chuyển ứng dụng cho bạn qua
liên kết mời hoặc USB. Xem thêm trong chương "Cập nhật phần mềm".

---

## Hỗ trợ và liên hệ

Nếu bạn có câu hỏi hoặc gặp vấn đề, bạn có thể tìm thông tin mới nhất trên
trang web Cleona và trên GitHub. Vì Cleona là một dự án phi tập trung, không
có bộ phận hỗ trợ khách hàng theo kiểu truyền thống -- nhưng có một cộng
đồng năng động luôn sẵn lòng giúp đỡ.

---

*Hướng dẫn sử dụng này mô tả Cleona Chat phiên bản 3.1.125. Một số tính năng
có thể thay đổi hoặc được mở rộng trong các phiên bản mới hơn.*
