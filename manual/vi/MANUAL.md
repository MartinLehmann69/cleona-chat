# Cleona Chat -- Sổ tay người dùng

Phiên bản 4.2 | Tính đến tháng 11 năm 2026

---

## Mục lục

1. [Cleona Chat là gì?](#1-cleona-chat-là-gì)
2. [Những bước đầu tiên](#2-những-bước-đầu-tiên)
3. [Danh bạ](#3-danh-bạ)
4. [Tin nhắn](#4-tin-nhắn)
5. [Nhóm](#5-nhóm)
6. [Kênh công khai](#6-kênh-công-khai)
7. [Cuộc gọi](#7-cuộc-gọi)
8. [Lịch](#8-lịch)
9. [Bình chọn](#9-bình-chọn)
10. [Nhiều định danh](#10-nhiều-định-danh)
11. [Nhiều thiết bị](#11-nhiều-thiết-bị)
12. [Khôi phục](#12-khôi-phục)
13. [Cài đặt](#13-cài-đặt)
14. [Bảo mật](#14-bảo-mật)
15. [Cập nhật phần mềm](#15-cập-nhật-phần-mềm)
16. [Câu hỏi thường gặp](#16-câu-hỏi-thường-gặp)

---
## 1. Cleona Chat là gì?

### Ứng dụng nhắn tin của bạn, dữ liệu của bạn

Cleona Chat là một ứng dụng nhắn tin hoạt động hoàn toàn không cần máy chủ trung tâm. Tin nhắn của bạn đi thẳng từ thiết bị của bạn sang thiết bị của người đối diện -- không qua trụ sở công ty nào, không có đám mây, không trung tâm dữ liệu. Khi một thiết bị khác có mặt trên đường đi giúp đỡ, nó chỉ chuyển tiếp các gói tin đã mã hóa. Không có công ty nào có thể đọc, lưu trữ hay tiết lộ tin nhắn của bạn, đơn giản vì không có công ty nào đứng giữa.

### Không tài khoản, không số điện thoại

Với Cleona, bạn không cần số điện thoại hay địa chỉ email để đăng ký. Định danh của bạn gồm một cặp khóa mật mã, được tạo tự động trên thiết bị của bạn khi khởi động lần đầu. Điều đó có nghĩa: không ai có thể tìm ra bạn qua số điện thoại hay địa chỉ email, trừ khi bạn tự tiết lộ thông tin liên lạc của mình.

### Mã hóa an toàn cho tương lai

Cleona sử dụng cái gọi là mã hóa hậu lượng tử. Nghĩa là: ngay cả những máy tính lượng tử trong tương lai cũng không thể phá vỡ tin nhắn của bạn. Bạn không cần phải hiểu chi tiết -- điều quan trọng duy nhất là giao tiếp của bạn được bảo vệ tốt nhất có thể theo tiêu chuẩn kỹ thuật hiện tại.

### Nó hoạt động thế nào khi không có máy chủ?

Mạng của Cleona chỉ gồm các thiết bị của người dùng. Mỗi thiết bị là một nút, không nút nào quan trọng hơn nút nào, và mỗi nút chỉ biết những nút láng giềng của mình. Bốn điều làm mạng này đặc biệt:

- **Không có điểm cố định.** Trong ứng dụng không có địa chỉ máy chủ nào, và mạng không phụ thuộc vào một nút đơn lẻ nào. Không có thứ gì có thể tắt được để vô hiệu hóa Cleona.
- **Tức thì.** Tin nhắn của bạn khởi hành ngay khoảnh khắc bạn gửi nó. Nó không chờ nhịp điệu hay bất cứ thứ gì khác.
- **Ngụy trang song song.** Thiết bị của bạn liên tục gửi các gói ngụy trang nhỏ, để nhìn từ bên ngoài không thể biết khi nào bạn thực sự đang viết. Không tin nhắn nào phụ thuộc vào nó -- ngụy trang chỉ chạy bên cạnh mà thôi.
- **Mã thay cho tên.** Ai chuyển tiếp một tin nhắn chỉ thấy một mã thay đổi mỗi ngày. Bình thường thì không ai trong số họ biết cả người gửi lẫn người nhận cùng lúc; các ngoại lệ nằm ở chương 14.

**Ba con đường, tất cả cùng lúc.** Khi bạn gửi một tin nhắn, Cleona không thử từng đường một mà thử tất cả các đường phù hợp cùng một lúc. Ngay khi người đối diện xác nhận đã nhận, các đường còn lại bị hủy.

1. **Trong cùng mạng:** Nếu hai bạn ở cùng một WLAN, tin nhắn đi thẳng sang.
2. **Qua các nút láng giềng cố định:** Trên Internet, thiết bị của bạn giao tin nhắn cho nút láng giềng cố định của nó. Nút đó chuyển tiếp đến các nút láng giềng cố định của người đối diện (tối đa ba cùng lúc), và một trong số đó giao nó đi.
3. **Hộp thư:** Nếu người đối diện đang ngoại tuyến, Cleona để lại tin nhắn đã mã hóa tại ba nút láng giềng. Nó nằm đó tối đa 7 ngày. Khi người đối diện trực tuyến trở lại, họ lấy nó ra.

**Làm sao bạn vào mạng?** Trong ứng dụng không có địa chỉ máy chủ. Lối vào của bạn do liên hệ đầu tiên của bạn cung cấp: lời mời của họ chứa các địa chỉ mà thiết bị của bạn dùng để tìm những nút láng giềng đầu tiên. Trong cùng một WLAN, các thiết bị Cleona cũng tự tìm thấy nhau. Từ đó, thiết bị của bạn học thêm nút mới qua mỗi nút láng giềng.

### Nền tảng

Cleona có sẵn cho Android, iOS, macOS, Linux và Windows. Trên máy tính và trên Android, tin nhắn và cuộc gọi đến trong vòng vài giây. Trên iPhone, điều này đúng khi ứng dụng đang mở. Khi ứng dụng không mở, iOS chỉ đánh thức nó thỉnh thoảng trong chốc lát; iOS quyết định lúc nào. Cleona khi đó lấy mọi thứ được giữ cho bạn và hiển thị một thông báo kèm con số trên biểu tượng ứng dụng. Cuộc gọi không đến được iPhone có ứng dụng không mở. Đó là quy định của Apple, không phải lỗi của Cleona.

---

## 2. Những bước đầu tiên

### Cài đặt ứng dụng

**Android:**
1. Tải tệp APK từ trang web Cleona hoặc từ GitHub Releases.
2. Mở tệp trên điện thoại của bạn. Nếu cần, cho phép cài đặt từ nguồn không xác định (Android sẽ tự động hỏi bạn).
3. Nhấn "Cài đặt" và đợi đến khi quá trình cài đặt hoàn tất.

**iOS:**
1. Mở liên kết mời TestFlight trên iPhone của bạn.
2. Nhấn "Cài đặt". TestFlight là cách chính thức của Apple để phân phối ứng dụng beta.
3. Sau khi cài đặt, bạn sẽ thấy Cleona trên màn hình chính.

**macOS:**
1. Tải tệp DMG từ trang web Cleona hoặc từ GitHub Releases.
2. Mở DMG và kéo Cleona vào thư mục Ứng dụng của bạn.
3. Khi khởi động lần đầu, macOS có thể hỏi bạn có muốn mở ứng dụng của một nhà phát triển đã xác định hay không -- hãy xác nhận.

**Linux (Ubuntu/Debian):**
1. Tải tệp .deb từ trang web Cleona hoặc từ GitHub Releases.
2. Cài đặt bằng cách nhấp đúp hoặc trong terminal: `sudo dpkg -i cleona-chat-beta_VERSION_amd64.deb`
3. Khởi động Cleona từ menu ứng dụng hoặc trong terminal bằng `cleona-chat-beta`.

**Linux (Fedora/openSUSE):**
1. Tải tệp .rpm từ trang web Cleona hoặc từ GitHub Releases.
2. Cài đặt bằng: `sudo dnf install cleona-chat-beta-VERSION-1.x86_64.rpm`
3. Khởi động Cleona từ menu ứng dụng hoặc trong terminal bằng `cleona-chat-beta`.

**Linux (mọi bản phân phối -- AppImage):**
1. Tải tệp .AppImage từ trang web Cleona hoặc từ GitHub Releases.
2. Đặt tệp có thể thực thi: nhấp chuột phải, Thuộc tính, Cho phép thực thi, hoặc trong terminal: `chmod +x cleona-chat-beta-VERSION-x86_64.AppImage`
3. Khởi động bằng nhấp đúp hoặc trong terminal: `./cleona-chat-beta-VERSION-x86_64.AppImage`

Các tên gói dành cho bản beta, hiện là bản duy nhất được công bố; chúng có tên `cleona-chat-beta`.

**Windows:**
1. Tải trình cài đặt từ trang web Cleona hoặc từ GitHub Releases.
2. Chạy tệp cài đặt và làm theo hướng dẫn.
3. Khởi động Cleona từ menu Start hoặc lối tắt trên màn hình.

### Tạo định danh

Khi khởi động lần đầu, Cleona tự động tạo một định danh mới cho bạn. Bạn có thể đặt cho mình một tên hiển thị -- đó là tên mà danh bạ của bạn nhìn thấy. Tên này có thể thay đổi bất cứ lúc nào.

### Ghi chép cụm từ hạt -- điều quan trọng nhất

Sau khi tạo định danh, Cleona hiện cho bạn 24 từ. Đó là **cụm từ hạt** của bạn -- khóa khôi phục cá nhân của bạn.

**Hãy viết 24 từ này ra giấy và cất giữ cẩn thận.**

Tại sao điều này lại quan trọng đến vậy?

- Nếu điện thoại của bạn hỏng, mất hoặc bị đánh cắp, bạn có thể dùng 24 từ này để khôi phục toàn bộ định danh của mình trên một thiết bị mới.
- Không có cụm từ hạt thì không có đường quay lại. Không có nút "quên mật khẩu" và cũng không có bộ phận hỗ trợ nào có thể trả lại tài khoản cho bạn -- vì chẳng hề có tài khoản nào trên máy chủ. Ngay cả danh bạ của bạn cũng không thể khôi phục định danh của bạn, dù có nhiều đến đâu. Một thiết bị thứ hai với cùng định danh sẽ có trong một phiên bản sau (xem chương 11).
- Không bao giờ tiết lộ cụm từ hạt cho người khác. Ai biết những từ này có thể mạo danh bạn.

Bạn cũng tìm thấy 24 từ sau này trong phần Cài đặt dưới "Sao lưu" ->
"Hiển thị cụm từ khôi phục", nếu muốn đọc lại. Trên Android, bạn xác nhận
việc này bằng khóa màn hình của mình.

### Thêm liên hệ đầu tiên

Để trò chuyện với ai đó, trước tiên bạn phải thêm người đó làm liên hệ. Có nhiều cách để làm việc này -- tất cả đều được giải thích trong phần tiếp theo.

---

## 3. Danh bạ

### Lời mời của bạn

Liên hệ trong Cleona chỉ hình thành qua một lời mời. Lời mời của bạn đã có ngay từ lần khởi động đầu tiên -- kể cả khi không có Internet và trước khi thiết bị của bạn tìm được nút láng giềng nào. Bạn tìm thấy nó trên trang chi tiết định danh của mình (nhấn vào tên của chính bạn trên thanh trên).

Lời mời có hai dạng, chứa chính xác cùng một nội dung:

- dạng **mã QR**, khi người đối diện đứng cạnh bạn, và
- dạng **dòng văn bản**, để bạn gửi qua email, SMS hoặc một ứng dụng nhắn tin khác.

Lời mời không chứa số điện thoại và cũng không chứa tên từ bất kỳ danh bạ nào. Nó chứa các khóa công khai của bạn và các địa chỉ mà người đối diện dùng để liên lạc với bạn và các nút láng giềng của bạn. Với một người mới cài Cleona, lời mời của bạn vì thế cũng chính là lối vào mạng.

### Quét mã QR (khuyến nghị)

Nếu hai bạn gặp nhau trực tiếp:

1. Bạn cho người đối diện xem mã QR của lời mời.
2. Người đối diện nhấn nút cộng, chọn "Quét mã QR" và hướng camera vào màn hình của bạn. Việc này cũng chạy được với webcam của máy tính.
3. Yêu cầu gửi đến bạn và được **tự động chấp nhận** -- vì chính bạn vừa cho xem mã.

Một mã QR chỉ có giá trị một lần: yêu cầu hợp lệ đầu tiên được chấp nhận, sau đó lời mời đã dùng. Mã QR là phương pháp an toàn nhất, vì hai bạn biết chính xác mình đang trao đổi liên hệ với ai.

### NFC (đặt hai điện thoại sát nhau)

Nếu cả hai thiết bị hỗ trợ NFC:

1. Cả hai mở chức năng thêm liên hệ.
2. Đặt hai điện thoại lưng chạm lưng nhau.
3. Lời mời được chuyển giao và tự động chấp nhận.

NFC cũng cho mức độ an toàn cao như mã QR, vì việc trao đổi chỉ hoạt động khi hai bạn đứng cạnh nhau về mặt vật lý.

### Gửi dòng văn bản

Nếu hai bạn không thể gặp nhau:

1. Mở lời mời của bạn và sao chép dòng văn bản.
2. Gửi nó cho người sẽ thêm bạn -- qua thư, SMS hoặc một ứng dụng nhắn tin khác.
3. Người kia dán dòng đó vào Cleona trong hộp thoại thêm liên hệ.
4. Yêu cầu hiện ở phía bạn dưới **"Yêu cầu"**. Ở đây **không** tự động chấp nhận: bạn tự quyết định, vì bạn không thể biết ai đã đọc dòng đó trên đường đi.

### Chấp nhận yêu cầu liên hệ

Một yêu cầu đến chưa tạo ra liên hệ. Nó đặt cho bạn một câu hỏi và hiện trong thẻ **"Yêu cầu"**. Ở đó bạn thấy tên và cấp xác minh, và có thể chọn:

- **Chấp nhận** -- chỉ lúc này người đó mới trở thành liên hệ của bạn.
- **Từ chối** -- yêu cầu bị hủy.
- **Chặn** -- người đó không thể gửi thêm yêu cầu cho bạn.

### Không bao giờ dùng làm nút láng giềng cố định

Trong menu của một liên hệ, bạn tìm thấy công tắc **"Không bao giờ dùng làm nút láng giềng cố định"** (mặc định: tắt). Khi bật, liên hệ này không chuyển tiếp tin nhắn cho bạn và vì thế cũng không biết khi nào bạn gửi hay nhận tin nhắn. Việc này dành cho trường hợp nguy hiểm đến từ chính môi trường xung quanh bạn.

Từ người lạ (không phải liên hệ và cũng không phải thành viên của một nhóm chung), Cleona không cho qua gì ngoài một yêu cầu như vậy -- không tin nhắn, không cuộc gọi, không tệp. Và ngay cả yêu cầu đó cũng chỉ đến được nếu người gửi đã giải một bài toán tính toán nhỏ trước đó. Điều đó làm cho thư rác hàng loạt trở nên đắt đỏ.

### Các cấp xác minh

Cleona cho bạn biết định danh của một liên hệ được xác nhận chắc chắn đến mức nào:

| Cấp | Ý nghĩa |
|-------|-----------|
| Chưa xác minh | Hai bạn đã kết nối, nhưng không gì xác nhận rằng đằng sau đúng là người đúng. |
| Đã thấy | Trao đổi khóa thành công, hai bạn có thể giao tiếp được mã hóa. |
| Đã xác minh | Hai bạn đã gặp nhau trực tiếp và kết nối qua quét camera hoặc NFC. |
| Tin cậy | Bạn đã đánh dấu liên hệ này một cách rõ ràng là đáng tin cậy. |

"Đã xác minh" chỉ có trong trao đổi trực tiếp. Một lời mời đến qua chat hay thư không bao giờ đạt cấp này -- ngay cả khi nó chứa cùng những dữ liệu đó.

Nếu khóa của một liên hệ thay đổi mà không báo trước, Cleona đặt lại liên hệ đó về "Chưa xác minh". Việc này bảo vệ bạn khỏi việc ai đó mạo danh liên hệ của bạn mà bạn không hay biết.

---
## 4. Tin nhắn

### Gửi và nhận văn bản

Đơn giản gõ tin nhắn của bạn vào ô nhập bên dưới và nhấn Enter hoặc nút Gửi. Tin nhắn của bạn được tự động mã hóa trước khi rời khỏi thiết bị của bạn.

Tin nhắn đến hiện trong lịch sử trò chuyện.

### Các ký hiệu trên tin nhắn của bạn có ý nghĩa gì

| Ký hiệu | Ý nghĩa |
|---------|-----------|
| Đồng hồ | Tin nhắn đã được tạo, nhưng chưa đường nào mang nó đi. |
| Một dấu tích | Tin nhắn đang trên đường. Điều này cũng đúng khi nó đang đợi người đối diện trong hộp thư. |
| Hai dấu tích | Đã giao: Thiết bị của người đối diện đã xác nhận đã nhận. |
| Dấu cảnh báo | Suốt 14 ngày không đường nào mang tin nhắn đi. Nhấn vào đó để gửi lại. |

**Ngoại tuyến không phải lỗi.** Nếu người đối diện không thể liên lạc được, tin nhắn giữ một dấu tích cho đến khi được lấy ra -- nó không bị mất. Nếu chính thiết bị của bạn không có kết nối, tin nhắn giữ ở đồng hồ và tự khởi hành ngay khi lại có một đường. Dấu cảnh báo chỉ xuất hiện sau khi 14 ngày trời nó không tìm được đường nào; khi đó bạn có thể gửi lại.

Điều này cũng đúng cho một iPhone có ứng dụng không mở: tin nhắn chờ trong hộp thư cho đến khi iOS đánh thức ứng dụng trong chốc lát hoặc cho đến khi người đối diện mở nó. Việc đó có thể lâu hơn trên các thiết bị khác.

Hai dấu tích chỉ có khi bản thân người nhận xác nhận đã nhận. Biên lai này được mã hóa và ký -- không ai trên đường đi có thể làm giả để giả vờ đã giao.

### Gửi hình ảnh, video và tệp

Bạn có nhiều cách:

- **Biểu tượng kẹp ghim** trong ô nhập: Nhấn vào đó để chọn một tệp, hình hoặc video từ thư viện hay hệ thống tệp của bạn.
- **Kéo và thả** (máy tính để bàn): Kéo một tệp thẳng vào cửa sổ trò chuyện.
- **Dán từ bảng tạm** (máy tính để bàn): Sao chép một hình và dán vào trong trò chuyện.

Các tệp nhỏ (dưới 256 KB) đi kèm trực tiếp trong tin nhắn. Các tệp lớn hơn được cắt thành nhiều mảnh và gắn thêm sửa lỗi, sao cho một vài mảnh bị mất cũng không sao. Nếu cả hai đều trực tuyến, chúng được truyền qua một nút láng giềng; nếu không, chúng được đặt tại các thiết bị luôn có thể liên lạc, cho đến khi người đối diện lấy ra.

Từ 256 KB, Cleona hỏi bạn cho từng tệp trước khi tệp được gửi: Một tệp lớn không thể đi con đường của tin nhắn được. Nội dung của nó vẫn được mã hóa, và người đối diện không biết địa chỉ Internet của bạn. Nhưng việc truyền đi nhìn từ bên ngoài thấy được như một sự kiện, và một thiết bị lạ chuyển tiếp hoặc giữ nó thấy ai đang tải lên và ai đang lấy ra. Sự đồng ý của bạn chỉ áp dụng cho riêng tệp đó.

### Tin nhắn thoại

1. Giữ nút micro trong ô nhập.
2. Nói tin nhắn của bạn.
3. Thả nút để gửi tin nhắn.

Nếu trên thiết bị của bạn nhận dạng giọng nói được bật (xem Cài đặt), tin nhắn thoại của bạn sẽ tự động được chuyển thành văn bản. Người đối diện khi đó sẽ thấy cả bản ghi lẫn văn bản đã chuyển.

### Trả lời tin nhắn (trích dẫn)

Để trả lời một tin nhắn cụ thể:

1. Mở menu ba chấm bên cạnh tin nhắn.
2. Chọn "Trả lời".
3. Bên trên ô nhập xuất hiện một băng chứa tin nhắn được trích dẫn.
4. Viết câu trả lời của bạn và gửi.

Tin nhắn được trích dẫn hiện trong câu trả lời của bạn, để người đọc thấy rõ mối liên hệ.

### Sửa và xóa tin nhắn

- **Sửa:** Menu ba chấm của tin nhắn, rồi "Sửa". Thay đổi văn bản và gửi lại. Người đối diện thấy rằng tin nhắn đã được sửa. Việc sửa có thể thực hiện trong vòng 15 phút sau khi gửi.
- **Xóa:** Menu ba chấm của tin nhắn, rồi "Xóa". Tin nhắn được gỡ bỏ ở cả bạn và người đối diện. Bạn có thể xóa tin nhắn của chính mình bất cứ lúc nào -- không có khung giờ nào cho việc xóa.

### Phản ứng bằng biểu tượng

Thay vì viết một câu trả lời, bạn có thể phản ứng một tin nhắn bằng biểu tượng:

1. Mở menu ba chấm hoặc giữ lâu tin nhắn.
2. Chọn một biểu tượng từ lựa chọn nhanh hoặc mở bộ chọn biểu tượng để có đầy đủ lựa chọn.
3. Phản ứng của bạn hiện bên dưới tin nhắn.

### Sao chép văn bản

Qua menu ba chấm của một tin nhắn, bạn có thể sao chép văn bản tin nhắn vào bảng tạm.

### Tìm tin nhắn

Ở cạnh trên của cửa sổ trò chuyện, bạn tìm thấy chức năng tìm kiếm. Nhập một từ khóa, và Cleona hiện cho bạn mọi kết quả trong trò chuyện hiện tại. Bằng các phím mũi tên, bạn có thể nhảy qua lại giữa các kết quả.

Trên trang chính còn có một bộ lọc tìm kiếm xuyên thẻ, dùng để tìm mọi cuộc trò chuyện theo một từ khóa.

### Xem trước liên kết

Khi bạn gửi một liên kết, Cleona tự động tạo xem trước (tiêu đề, mô tả, hình xem trước). Xem trước này được tạo bởi thiết bị của bạn và gửi kèm -- người đối diện không cần kết nối đến trang web được liên kết.

Việc một nhấn vào liên kết nhận được làm gì, bạn đặt trong Cài đặt dưới "Mở liên kết": "Bình thường", "Ưu tiên cửa sổ ẩn danh" (nơi thiết bị không mở được cửa sổ ẩn danh, liên kết mở bình thường) hoặc "Hỏi mỗi lần".

---

## 5. Nhóm

### Tạo nhóm

1. Chuyển sang thẻ "Nhóm".
2. Nhấn nút cộng.
3. Đặt tên cho nhóm.
4. Chọn các liên hệ bạn muốn mời.
5. Nhấn "Tạo".

Các liên hệ được mời nhận một thông báo và có thể tham gia nhóm.

### Tin nhắn nhóm được bảo vệ thế nào

Trong một nhóm tối đa 16 thành viên, Cleona gửi mỗi tin nhắn đến từng thành viên riêng biệt -- mỗi lần chỉ mã hóa cho thành viên đó, như thể bạn đã viết cho mỗi người một tin nhắn riêng. Các dấu tích trên một tin nhắn nhóm thể hiện trạng thái của thành viên mà tin nhắn tiến triển chậm nhất.

Khi nhóm vượt quá 16 thành viên, nhóm dùng một khóa chung. Nó thay đổi mỗi ngày và được tạo mới khi một thành viên rời đi hoặc bị gỡ; một thành viên mới chỉ đọc được từ lúc tham gia. Ở đó, các dấu tích không còn thể hiện trạng thái của từng thành viên, mà là việc tin nhắn đã được đặt trong mạng. Khi nhóm giảm xuống 12 thành viên hoặc ít hơn, nhóm quay lại gửi riêng từng thành viên.

### Ảnh trong nhóm và kênh

Trong cài đặt của một nhóm hoặc một kênh, bạn quy định bằng "Luôn tải ảnh" xem ảnh được tải ngay hay chỉ khi bạn nhấn vào một ảnh.

### Mời thành viên

Ngay cả sau khi tạo, bạn có thể mời thêm liên hệ:

1. Mở thông tin nhóm (menu ba chấm trong danh sách nhóm hoặc thanh trên trong nhóm-chat).
2. Nhấn "Mời".
3. Chọn các liên hệ bạn muốn thêm.

### Vai trò

Mỗi nhóm có ba vai trò:

- **Chủ sở hữu (Owner):** Có toàn quyền. Có thể thêm và gỡ thành viên, bổ nhiệm quản trị viên và quản lý nhóm. Chủ sở hữu cũng có thể chuyển trạng thái của mình sang một thành viên khác.
- **Quản trị viên:** Có thể gỡ thành viên và hỗ trợ quản lý.
- **Thành viên:** Có thể đọc và viết tin nhắn.

### Rời nhóm

1. Mở menu ba chấm trong danh sách nhóm.
2. Chọn "Rời".
3. Xác nhận quyết định của bạn.

Khi bạn rời một nhóm, các tin nhắn trước đây của bạn vẫn hiện với các thành viên khác.

---

## 6. Kênh công khai

### Kênh là gì?

Kênh là các diễn đàn thảo luận công khai bên trong mạng Cleona. Khác với nhóm, ở đây ai cũng có thể theo dõi mà không cần được mời. Chỉ chủ sở hữu và quản trị viên mới có thể đăng bài -- người theo dõi chỉ đọc.

### Tìm và tham gia kênh

1. Chuyển sang thẻ "Kênh".
2. Mở thẻ "Tìm".
3. Tìm các kênh sẵn có theo tên hoặc chủ đề.
4. Nhấn một kênh rồi nhấn "Theo dõi".

Các kênh có thể được lọc theo ngôn ngữ. Một số kênh được đánh dấu "Không phù hợp người vị thành niên" -- chúng chỉ hiện khi bạn đã xác nhận trong hồ sơ rằng mình trên 18 tuổi.

### Tạo kênh riêng

1. Chuyển sang thẻ "Kênh".
2. Nhấn nút cộng.
3. Nhập tên kênh (phải duy nhất trong toàn bộ mạng).
4. Chọn ngôn ngữ và kênh công khai hay riêng tư.
5. Tùy chọn: Thêm mô tả và hình.
6. Nhấn "Tạo".

Với các kênh công khai, bạn có thể quy định nội dung có được xếp loại "Không phù hợp người vị thành niên" hay không.

### Báo cáo nội dung

Nếu bạn nhận thấy nội dung không phù hợp trong một kênh công khai, bạn có thể báo cáo. Cleona dùng một hệ thống kiểm duyệt phi tập trung: các báo cáo được đánh giá bởi các thành viên được chọn ngẫu nhiên trong mạng (một kiểu "bồi thẩm đoàn"). Khi xác định vi phạm, kênh nhận một cảnh báo. Khi vi phạm lặp lại, kênh bị hạ hạng trong chỉ mục tìm kiếm hoặc bị khóa.

### Kênh hệ thống

Cleona có hai kênh hệ thống tích hợp sẵn:

- **Nhật ký lỗi:** Khi Cleona nhận ra một lỗi, nó hỏi bạn có muốn gửi một báo cáo lỗi hay không; trước đó bạn thấy chính xác những gì sẽ được công bố. Các báo cáo này nằm trong kênh nhật ký lỗi, nơi cộng đồng có thể xem. Một báo cáo không mang tên và không mang nội dung các cuộc trò chuyện của bạn, mà một biệt danh. Trong bản beta, nó nêu thêm định danh (User-ID) của bạn, để các nhà phát triển có thể hỏi thêm. Bạn cũng có thể gửi một báo cáo nhật ký thủ công (với hộp xem trước và sự đồng ý rõ ràng).
- **Yêu cầu tính năng:** Ở đây người dùng có thể nộp mong muốn tính năng và bỏ phiếu cho các đề xuất sẵn có. Các đề xuất được sắp xếp theo phiếu.

Mỗi máy tính giữ tối đa 25 MB cho mỗi kênh hệ thống, mỗi điện thoại tối đa 5 MB; khi đầy, cái cũ nhất đi trước -- không bao giờ là những gì chính bạn đã xem.

---
## 7. Cuộc gọi

### Bắt đầu cuộc gọi thoại

1. Mở trò chuyện với liên hệ bạn muốn gọi.
2. Nhấn biểu tượng điện thoại trên thanh trên.
3. Đợi cho đến khi người đối diện nghe máy.

Trong cuộc gọi, bạn thấy một dòng thời gian, thời lượng cuộc gọi và có quyền truy cập tắt tiếng và loa.

Để cúp máy, nhấn nút cúp máy màu đỏ.

Nếu bạn thấy "Không liên lạc được", thiết bị của người đối diện hiện không thể tiếp cận, ví dụ một iPhone có ứng dụng không mở. Hãy gửi tin nhắn thay thế.

### Bắt đầu cuộc gọi video

1. Mở trò chuyện với liên hệ.
2. Nhấn biểu tượng camera trên thanh trên.
3. Hình video của bạn hiện trong một cửa sổ nhỏ, hình của người đối diện trong vùng lớn.

Bạn có thể chuyển giữa camera trước và sau trong cuộc gọi.

### Cuộc gọi đến

Khi ai đó gọi bạn, một cửa sổ thông báo hiện với tên người gọi. Bạn có thể:

- **Nghe máy** -- cuộc gọi bắt đầu.
- **Từ chối** -- người gọi được thông báo.

Nếu bạn đang trong một cuộc gọi, một cuộc gọi mới không đổ chuông; thay vào đó bạn nhận một tin nhắn "Cuộc gọi nhỡ". Điều tương tự áp dụng cho một cuộc gọi nhóm mà bạn không nghe máy -- tin nhắn khi đó nằm trong nhóm-chat.

Nếu ai đó gọi một trong các định danh của bạn đang không hiển thị, điện thoại vẫn đổ chuông; màn hình cuộc gọi nêu định danh nào trong số các định danh của bạn đang được gọi.

Trên iPhone, nó chỉ đổ chuông khi ứng dụng đang mở. Ai gọi bạn khi ứng dụng không mở sẽ thấy "Không liên lạc được" sau 10 giây. Ngay khi bạn mở ứng dụng, bạn tìm thấy một tin nhắn về cuộc gọi nhỡ.

### Cuộc gọi nhóm

Bạn cũng có thể thực hiện các cuộc gọi nhóm với nhiều người tham gia cùng lúc. Cuộc gọi được tổ chức qua một cây chuyển tiếp thông minh, sao cho không phải mỗi người tham gia đều kết nối trực tiếp với mọi người khác. Tất cả cuộc gọi đều được mã hóa xuyên suốt.

Mỗi thành viên nhóm đều có thể bắt đầu một cuộc gọi nhóm. Hai người tham gia không phải là liên hệ của nhau không bao giờ thấy địa chỉ Internet của nhau: Tiếng và hình của họ chạy qua một người tham gia có liên hệ với cả hai. Nếu không có người như vậy, hai người không được kết nối với nhau, và ô hiển thị nói "Không có liên hệ chung trong cuộc gọi". Nếu một đường chuyển tiếp quá tải, tiếng vẫn còn, và video biến mất cho cặp đó.

### Mã hóa trong cuộc gọi

Tất cả cuộc gọi được mã hóa bằng các khóa dùng một lần, chỉ tồn tại trong thời lượng cuộc gọi. Sau khi cúp máy, các khóa này bị xóa ngay. Không ai có thể giải mã một cuộc gọi đã qua về sau.

Thành thật mà nói: Cuộc gọi, khi nào có thể, chạy trực tiếp giữa hai thiết bị, vì ngay cả một độ trễ nhỏ cũng gây khó chịu khi nói. Khác với tin nhắn, nhà cung cấp Internet của bạn vì thế trong một cuộc gọi có thể thấy bạn kết nối với địa chỉ Internet nào. Những gì hai bạn nói thì họ không thấy.

Trong một cuộc gọi, liên hệ của bạn cũng thấy địa chỉ Internet của bạn. Nếu bạn không muốn vậy với một liên hệ, tắt "Cho phép gọi" trong menu của họ (mặc định: bật). Nếu bạn tắt sau này, một địa chỉ họ đã từng thấy vẫn còn được họ biết.

---

## 8. Lịch

Cleona chứa một lịch tích hợp, hoạt động được mã hóa và hoàn toàn phi tập trung -- không cần dịch vụ đám mây.

### Các góc nhìn

Lịch cung cấp năm góc nhìn: Ngày, Tuần, Tháng, Năm và một góc nhìn Nhiệm vụ. Chuyển giữa chúng qua các thẻ ở cạnh trên của màn hình lịch.

### Tạo sự kiện

Nhấn vào một khung giờ hoặc dùng nút thêm để tạo một sự kiện mới. Bạn có thể nhập tiêu đề, ngày, giờ, địa điểm và ghi chú. Các sự kiện được lưu mã hóa trên thiết bị của bạn.

### Sự kiện lặp lại

Sự kiện có thể lặp theo ngày, tuần, tháng hoặc năm. Bạn có thể điều chỉnh mẫu (ví dụ mỗi thứ Ba thứ hai, mỗi ngày mùng một tháng) và đặt một ngày kết thúc hoặc một số lần lặp.

### Mời liên hệ

Khi tạo hoặc sửa một sự kiện, bạn có thể mời các liên hệ Cleona của mình. Họ nhận một lời mời lịch đã mã hóa và có thể trả lời bằng Chấp nhận, Từ chối hoặc Có thể. Các thay đổi đối với sự kiện được gửi tự động đến mọi người được mời.

### Hiển thị rảnh/bận

Bạn có thể chia sẻ tình trạng sẵn sàng của mình với liên hệ mà không tiết lộ chi tiết sự kiện. Có ba cấp quyền riêng tư: đầy đủ chi tiết, chỉ khung thời gian hoặc ẩn. Bạn có thể đặt một mặc định và ghi đè nó cho từng liên hệ.

### Lời nhắc

Sự kiện có thể có lời nhắc, kích hoạt một thông báo hệ thống trước khi sự kiện bắt đầu. Bạn có thể cho lời nhắc ngủ khi cần.

### Đồng bộ lịch bên ngoài

Cleona có thể đồng bộ với các dịch vụ lịch bên ngoài:

- **CalDAV** -- Kết nối với bất kỳ máy chủ tương thích CalDAV nào (Nextcloud, Radicale v.v.).
- **Google Lịch** -- Đồng bộ qua Google Calendar API với xác thực OAuth2 an toàn.
- **Máy chủ CalDAV cục bộ** -- Cleona có thể khởi động một máy chủ CalDAV cục bộ trên thiết bị của bạn, sao cho các ứng dụng lịch máy tính (Thunderbird, Outlook, Apple Lịch, Evolution) có thể đồng bộ với lịch Cleona của bạn.
- **Lịch hệ thống Android** -- Sự kiện từ Cleona có thể được chuyển vào ứng dụng lịch tích hợp của thiết bị Android.
- **Tệp ICS** -- Nhập và xuất sự kiện trong định dạng iCalendar chuẩn.

### Xuất PDF

Bạn có thể in hoặc xuất mỗi góc nhìn lịch (Ngày, Tuần, Tháng, Năm) dưới dạng tài liệu PDF.

---

## 9. Bình chọn

Bạn có thể tạo bình chọn trong bất kỳ trò chuyện hay nhóm nào, để thu thập ý kiến hoặc lên lịch sự kiện.

### Các loại bình chọn

Cleona hỗ trợ năm loại bình chọn:

- **Chọn một** -- Người tham gia chọn một lựa chọn.
- **Chọn nhiều** -- Người tham gia có thể chọn nhiều lựa chọn.
- **Bình chọn thời gian** -- Tìm một thời gian phù hợp với mọi người. Mỗi người tham gia đánh dấu thời gian là sẵn sàng, có thể hoặc không sẵn sàng.
- **Thang điểm** -- Đánh giá một thứ trên một thang số (ví dụ 1 đến 5).
- **Văn bản tự do** -- Người tham gia viết câu trả lời của riêng mình.

### Tạo bình chọn

Mở một trò chuyện và nhấn biểu tượng bình chọn (hoặc dùng menu đính kèm). Chọn loại bình chọn, đặt câu hỏi và các lựa chọn, rồi gửi bình chọn. Nó hiện như một tin nhắn trong trò chuyện.

### Bỏ phiếu

Nhấn một bình chọn để bỏ phiếu. Bạn có thể thay đổi hoặc rút phiếu của mình bất cứ lúc nào.

### Bỏ phiếu ẩn danh

Bình chọn có thể được cấu hình cho bỏ phiếu ẩn danh. Khi bật, các phiếu là ẩn danh về mặt mật mã -- không ai, kể cả người tạo bình chọn, có thể thấy ai đã bỏ phiếu cho cái gì. Số phiếu vẫn hiện.

### Bình chọn thời gian sang lịch

Khi một bình chọn thời gian kết thúc, thời gian thắng có thể được chuyển thành một mục lịch chỉ bằng một nhấn.

---
## 10. Nhiều định danh

### Tại sao nhiều định danh?

Hãy tưởng tượng bạn muốn tách công việc và đời tư -- giống như hai số điện thoại khác nhau, nhưng không cần điện thoại thứ hai. Trong Cleona, bạn có thể dùng nhiều định danh trên một thiết bị. Mỗi định danh có tên riêng, ảnh hồ sơ riêng, danh bạ riêng và cuộc trò chuyện riêng.

### Tạo định danh mới

1. Trên thanh trên, bạn thấy định danh hiện tại của mình như một thẻ.
2. Nhấn dấu cộng (+) bên phải các thẻ định danh.
3. Nhập tên cho định danh mới.
4. Xong -- định danh mới hoạt động ngay.

### Chuyển giữa các định danh

Đơn giản nhấn vào thẻ định danh trên thanh trên. Việc chuyển là tức thì -- không chờ, không nạp lại.

### Tất cả chạy cùng lúc

Một điều quan trọng: Tất cả định danh của bạn đều hoạt động cùng lúc. Ngay cả khi bạn đang hiện là "Công việc", định danh "Riêng tư" vẫn tiếp tục nhận tin nhắn. Bạn không bỏ lỡ gì, dù đang chọn định danh nào.

### Trang chi tiết định danh

Khi bạn nhấn vào thẻ định danh đang hoạt động, trang chi tiết mở ra. Ở đây bạn có thể:

- Hiển thị mã QR của mình cho liên hệ.
- Thay đổi hoặc gỡ ảnh hồ sơ.
- Thêm mô tả hồ sơ.
- Thay đổi tên hiển thị.
- Chọn một thiết kế (giao diện) cho định danh này.
- Xóa định danh, nếu bạn không còn cần.

### Xóa định danh

Khi bạn xóa một định danh, danh bạ của bạn được thông báo. Định danh và tất cả dữ liệu liên quan được gỡ khỏi thiết bị của bạn. Quá trình này không thể đảo ngược.

---

## 11. Nhiều thiết bị

### Một định danh, một thiết bị -- trước mắt là vậy

Hôm nay một định danh chạy trên một thiết bị. Một thiết bị thứ hai cho cùng định danh sẽ có trong một phiên bản sau; trong Cài đặt dưới "Thiết bị" -> "Quản lý thiết bị", "Ghép thêm thiết bị" vì thế còn ghi "Chưa khả dụng".

Khi nó đến, sẽ như sau: Mọi thiết bị đều ngang quyền, không có thiết bị chính. Bạn thiết lập một thiết bị thêm bằng 24 từ của mình, và một trong các thiết bị hiện có của bạn đồng ý. Tối đa 5 thiết bị.

Nếu hôm nay bạn nhập 24 từ của mình trên một thiết bị mới, bạn chuyển nhà: Định danh được khôi phục lên thiết bị mới, và thiết bị cũ của bạn sau đó gỡ định danh khỏi chính nó (xem chương 12).

Trên nhiều thiết bị, hôm nay bạn có thể dùng các định danh khác nhau (chương 10).

### Xoay khóa định danh

Nếu bạn nghi ngờ ai đó đã lấy được khóa của bạn, bạn có thể tạo khóa mới dưới "Quản lý thiết bị" -> "Xoay khóa". Danh bạ của bạn được thông báo, các lời mời còn mở của bạn bị thu hồi. Quan trọng: Sau đó, riêng 24 từ chỉ còn tạo lại được các khóa cũ. Vì thế hãy tạo ngay sau đó một gói khôi phục mới; bạn chỉ còn có thể khôi phục cùng với gói đó.

---

## 12. Khôi phục

### Dùng cụm từ hạt

Nếu bạn mất thiết bị hoặc thiết lập một thiết bị mới:

1. Cài đặt Cleona trên thiết bị mới.
2. Chọn "Khôi phục" khi khởi động.
3. Nhập 24 từ của bạn.
4. Cleona tạo lại tất cả định danh của bạn từ đó -- với cùng các khóa như trước. Đối với danh bạ, bạn vẫn là cùng một người.

### Cái gì quay lại -- và cái gì không

Định danh của bạn nằm trong 24 từ, danh bạ và lịch sử trò chuyện của bạn thì không. Quay lại là lối vào mạng của bạn qua **Gói khôi phục**: Thiết bị của bạn để lại một gói nhỏ, đã mã hóa trong mạng. Chỉ 24 từ của bạn mới có thể tìm và mở nó. Bên trong ghi những gì thiết bị mới của bạn cần để liên lạc lại với danh bạ, và những gì trong thời gian qua đã nằm chờ bạn trong mạng. Không liên hệ nào cần phải trực tuyến cho việc này.

Lịch sử trò chuyện trước đây không được mang lại bằng một lần khôi phục.

Gói khôi phục sống 7 ngày và được thiết bị của bạn làm mới, miễn là nó còn chạy; trong Cài đặt bạn thấy nó có hiệu lực đến khi nào. Nếu không thiết bị nào của bạn chạy trong hơn 7 ngày, nó đã hết hạn. Khi đó 24 từ vẫn khôi phục định danh của bạn, nhưng danh bạ bạn phải mời lại; những gì trong thời gian qua đã nằm chờ bạn trong mạng thì mất.

### Khôi phục nghĩa là chuyển nhà

Nếu thiết bị cũ của bạn về sau phát hiện định danh đã được khôi phục ở nơi khác, nó gỡ định danh khỏi chính nó -- cùng lịch sử của định danh. Vì thế: Ai có 24 từ của bạn có thể lấy định danh khỏi thiết bị của bạn theo cách này. Cho đến khi mọi liên hệ trở lại, ứng dụng nhắc bạn; bằng "Hoàn tất và làm mới khóa" bạn tự kết thúc việc khôi phục.

### Những gì không ai có thể khôi phục

Điều này quan trọng, và chúng tôi nói rõ vì thế:

- **Không ai ngoài bạn có thể khôi phục định danh của bạn.** Không phải nhà phát triển, không phải bộ phận hỗ trợ, và cũng không phải danh bạ của bạn -- dù có nhiều đến đâu. Không có khóa chung và cũng không có phần khóa của bạn được cất ở người khác.
- **Nếu bạn đã mất 24 từ và không còn thiết bị nào, định danh của bạn đã mất.** Khi đó chỉ còn cách tạo một định danh mới và mời lại danh bạ.

Biện pháp bảo vệ tốt nhất: Hãy viết 24 từ ra giấy và cất giữ chúng an toàn.

---
## 13. Cài đặt

Bạn vào Cài đặt qua biểu tượng bánh răng ở góc trên bên phải.

### Thông báo và nhạc chuông

- Chọn từ sáu nhạc chuông khác nhau cho cuộc gọi đến.
- Đặt một âm tin nhắn.
- Trên thiết bị Android, bạn có thể bật hoặc tắt thêm rung.
- **"Tắt tiếng tất cả"** khiến trên thiết bị này không còn tin nhắn nào đổ chuông, rung hay báo mình -- cho mọi định danh. Cuộc gọi vẫn đổ chuông.
- **"Giờ yên lặng"** bạn đặt cho từng định danh với Từ/Đến. Trong khoảng thời gian đó, không tin nhắn nào của định danh này đổ chuông, rung hay báo mình; tin nhắn vẫn đến.
- **"Thông báo không có nội dung"** (mặc định: tắt) chỉ cho biết một tin nhắn, lời mời hay lời nhắc đã đến -- không người gửi, không tên và không văn bản. Cuộc gọi vẫn hiện tên.
- Những gì đến một lúc sau khi khởi động, Cleona báo trong một thông báo gộp ("5 tin nhắn mới trong 2 cuộc trò chuyện"); mọi thứ sau đó báo riêng từng cái. Một nhấn vào một thông báo tin nhắn mở cuộc trò chuyện, kể cả trong một định danh khác.

### Thiết kế (giao diện)

Cleona cung cấp mười thiết kế khác nhau: Teal, Ocean, Sunset, Forest, Amethyst, Fire, Storm, Slate, Gold và Contrast. Thiết kế Contrast đáp ứng cấp trợ năng cao nhất (WCAG AAA) và dễ đọc đặc biệt khi thị lực hạn chế.

Mỗi định danh có thể có thiết kế riêng. Bạn thay thiết kế trong trang chi tiết định danh (nhấn vào thẻ định danh đang hoạt động).

Ngoài ra, bạn có thể chuyển giữa giao diện sáng, tối và giao diện hệ thống trong Cài đặt dưới "Hiển thị".

### Đổi ngôn ngữ

Cleona có sẵn 34 ngôn ngữ, trong đó có cả các ngôn ngữ viết từ phải sang trái (ví dụ Ả Rập, Hebrew). Đổi ngôn ngữ trong Cài đặt dưới "Ngôn ngữ".

### Lưu trữ phương tiện

Nếu ở nhà bạn có một ổ lưu trữ mạng (NAS) hoặc một thư mục dùng chung, Cleona có thể tự động chuyển phương tiện của bạn ra đó. Hỗ trợ SMB, SFTP, FTPS và WebDAV.

Việc lưu trữ phân cấp hoạt động thế này:
- 30 ngày đầu: Mọi thứ đều nằm trên thiết bị của bạn.
- Sau 30 ngày: Một hình xem trước nằm trên thiết bị, bản gốc được lưu trữ.
- Sau 90 ngày: Chỉ còn một hình xem trước nhỏ nằm trên thiết bị.
- Sau một năm: Chỉ còn một ô giữ chỗ, bản gốc nằm an toàn trong kho lưu trữ.

Bạn có thể nhấn vào một phương tiện đã lưu trữ bất cứ lúc nào để lấy lại -- với điều kiện bạn đang kết nối với mạng gia đình. Các phương tiện đặc biệt quan trọng có thể được ghim để không bao giờ bị chuyển ra ngoài.

Dưới "Ngân sách lưu trữ", bạn quy định bao nhiêu MB phương tiện ở lại trên thiết bị (mặc định: 100 MB trên điện thoại, 2 GB trên máy tính). Khi đầy, phương tiện không được ghim cũ nhất được lưu trữ trước. Một bản gốc chỉ bị xóa khi nó đã nằm an toàn trong kho -- tin nhắn văn bản luôn được giữ.

### Chuyển văn bản cho tin nhắn thoại

Khi bật, tin nhắn thoại của bạn được chuyển thành văn bản cục bộ trên thiết bị (với mô hình mã nguồn mở Whisper). Văn bản đã chuyển được gửi cùng bản ghi đến người đối diện. Việc chuyển hoàn toàn trên thiết bị của bạn -- không dữ liệu nào đi ra dịch vụ bên ngoài.

Model nào (tiny, base, small) được tải về, bạn đặt một lần cho thiết bị; ngôn ngữ (tự động hay cố định) cho từng định danh.

### Tự động tải

Bạn có thể đặt, từ kích thước nào phương tiện được tự động tải. Như vậy bạn có thể, ví dụ, để hình tự động tải, nhưng quyết định thủ công với video lớn.

### Thiết bị

Dưới "Thiết bị" -> "Quản lý thiết bị", bạn thấy thiết bị này. Việc ghép thêm một thiết bị sẽ có trong một phiên bản sau (chương 11).

### Mạng

Cleona không cần cài đặt mạng để hoạt động. Có ba công tắc mạng:

- **Mở cổng trên bộ định tuyến** (mặc định: bật). Cleona yêu cầu bộ định tuyến của chính bạn mở một cánh cửa cho Cleona. Nếu thành công, thiết bị của bạn dễ liên lạc hơn với người khác và giúp ích cho mạng. Cleona khi đó chỉ nói chuyện với bộ định tuyến của bạn, không với Internet.
- **Mục địa chỉ công khai** (mặc định: bật). Nếu thiết bị của bạn còn quá ít nút láng giềng, nó tra cứu thêm các lối vào trong một danh bạ công khai (Nostr), và nếu bản thân nó có thể liên lạc từ bên ngoài tốt, nó tự ghi mình vào đó. Mục đó chứa một địa chỉ, không tên và không liên hệ. Nếu bạn tắt nó, thiết bị của bạn chỉ còn tìm nút láng giềng qua lời mời, mạng cục bộ và các nút mà nó đã biết.
- **Ít gói ngụy trang hơn trong WLAN** (mặc định: tắt). Trong WLAN hoặc qua cáp, bạn có thể tắt các gói ngụy trang rỗng. Khi đó lại có thể thấy khi nào bạn viết. Trong mạng di động không có công tắc này -- ở đó Cleona dù sao cũng chỉ gửi một gói ngụy trang mỗi phút.

Không thể tắt dòng ngụy trang nói chung. Đó là cố ý: Chỉ khi nó luôn chạy, hoạt động của thiết bị mới không nói gì về việc bạn có đang viết hay không.

Trên ba công tắc là **Chế độ tiết kiệm dữ liệu**: Trong mạng di động, Cleona đề nghị nó, nhưng không bao giờ tự bật. Nó tiết kiệm dữ liệu, đổi lại thiết bị của bạn dễ bị nhận ra hơn từ bên ngoài.

Dưới đó, bạn đặt **"Bộ nhớ đệm cho media của người khác"**: Thiết bị của bạn giữ các phần đã mã hóa của phương tiện của người khác tối đa 7 ngày, để chúng đến được người nhận (mặc định: 100 MB trên điện thoại, 1 GB trên máy tính). Một kích thước nhỏ hơn giải phóng chỗ ngay lập tức -- các phần cũ nhất trước.

---

## 14. Bảo mật

### Mã hóa hậu lượng tử nghĩa là gì?

Mã hóa ngày nay dựa trên các bài toán toán học cực khó giải với máy tính thường. Máy tính lượng tử có thể giải một số bài toán đó nhanh trong tương lai. Mã hóa hậu lượng tử dùng thêm các phương pháp cũng đứng vững trước máy tính lượng tử.

Cleona kết hợp cả hai hướng: mã hóa cổ điển cho độ tin cậy và phương pháp hậu lượng tử cho an toàn tương lai. Như vậy bạn được bảo vệ đồng thời trước cả mối đe dọa hôm nay lẫn tương lai.

Cho mỗi tin nhắn riêng biệt, một khóa riêng được tạo. Ngay cả nếu kẻ tấn công phá được khóa của một tin nhắn, nó cũng không thể dùng để đọc bất kỳ tin nhắn nào khác.

### Tại sao không có máy chủ lại an toàn hơn

Với các ứng dụng nhắn tin thông thường, tin nhắn của bạn đi qua máy chủ của nhà cung cấp. Ngay cả khi chúng được mã hóa ở đó: nhà cung cấp có quyền truy cập vào siêu dữ liệu (ai giao tiếp với ai, khi nào, bao nhiêu lần, từ đâu) và có thể phải bàn giao chúng theo lệnh tòa án.

Với Cleona, không có điểm trung tâm như vậy. Không có nơi nào mọi siêu dữ liệu hội tụ, và không có danh bạ nào có thể tra xem bạn là ai hay bạn quen ai.

### Ai thấy rằng bạn đang viết với ai đó?

Mã hóa bảo vệ **cái gì** bạn viết. Cũng quan trọng không kém là không một quan sát viên đơn lẻ nào biết **với ai** và **khi nào** bạn viết. Cleona lo việc đó thế này:

- **Trên Internet không bao giờ trực tiếp.** Nếu thiết bị của bạn gửi thẳng một tin nhắn đến địa chỉ Internet của người đối diện, nhà cung cấp của bạn có thể thấy bạn đang viết với ai. Vì thế một tin nhắn trên Internet luôn đi qua các nút láng giềng cố định: của bạn và của người đối diện.
- **Nút láng giềng bạn tin.** Các nút láng giềng cố định của bạn, khi nào có thể, là thiết bị của chính liên hệ bạn -- tối đa ba cái đang có thể liên lạc từ bên ngoài. Nếu một cái mất, một liên hệ khác thay vào. Một liên hệ không thể bị mua bằng máy chủ; một nút bất kỳ trong mạng thì có thể. Nếu bạn chưa có liên hệ có thể liên lạc nào, Cleona lấy một nút láng giềng khác. Lời mời của bạn không bao giờ nêu bất kỳ liên hệ nào của bạn, để không ai qua chúng mà biết địa chỉ của một bạn bè.
- **Mã thay cho tên.** Các nút láng giềng không thấy tên và không thấy định danh, mà chỉ thấy một mã. Nó chỉ dành cho đúng hai bạn, theo một hướng, trong một ngày -- ngày hôm sau là một mã khác. Nút láng giềng của bạn biết gói đến từ đâu, nhưng không biết nó đi đến đâu cuối cùng. Nút láng giềng của người đối diện biết nó đi đến đâu, nhưng không biết nó đến từ đâu. Bình thường thì không ai trên đường đi thấy cả hai đầu.
- **Dòng ngụy trang.** Thiết bị của bạn liên tục, theo các khoảng không đều, gửi các gói ngụy trang đến các nút láng giềng của nó. Chúng to bằng các gói thật, đi qua cùng một cổng và từ bên ngoài không phân biệt được với chúng. Liệu một con người đang viết hay thiết bị chỉ đang chạy, nhờ vậy không thể biết. Tin nhắn của bạn không bao giờ chờ dòng ngụy trang -- chúng khởi hành ngay, dòng ngụy trang chỉ chạy bên cạnh.

**Dòng ngụy trang tốn gì:** Trong WLAN khoảng 13 MB một ngày. Trong mạng di động, Cleona chỉ gửi một gói ngụy trang mỗi phút, khoảng 1,7 MB một ngày. Lý do cho việc hạn chế trong mạng di động không phải dung lượng, mà là pin: mỗi gói đánh thức modem vô tuyến.

**Những gì Cleona không thể giấu** -- thành thật mà nói:

- Không **một** quan sát viên đơn lẻ nào thấy ai đang viết với ai -- không nhà cung cấp của bạn, không các nút trên đường. Ai đó nếu theo dõi **cả hai đầu cùng lúc**, ví dụ một quốc gia theo dõi kết nối của bạn và của người đối diện, hoặc phục kích cả hai nút láng giềng, có thể theo thời gian đối chiếu: gói ra ở bạn, ngay sau đó gói vào ở người đối diện. Lặp lại đủ nhiều lần, điều đó cho ra một liên kết.
- Dòng ngụy trang làm khó việc đối chiếu này, nhưng không ngăn chặn nó. Nó giấu từng tin nhắn riêng lẻ, không giấu khối lượng: Ai gửi rất nhiều làm tăng lưu lượng tổng của thiết bị mình.
- Một liên hệ là nút láng giềng cố định của bạn biết **khi nào** và **bao nhiêu** bạn gửi và nhận -- không phải với ai và không phải cái gì. Nếu nguy hiểm đến từ môi trường xung quanh bạn, bạn có thể loại từng liên hệ ra (xem chương 3, "Không bao giờ dùng làm nút láng giềng cố định").
- Nếu hai người dùng mới chỉ có cùng một nút láng giềng, tin nhắn của họ chạy qua đúng nút đó, và nó thấy cả hai đầu. Ngay khi một trong hai có thêm nút láng giềng khác, điều đó chấm dứt.
- Lời mời của bạn chứa các địa chỉ Internet của bạn. Ai có dòng văn bản, thấy bạn đang trực tuyến ở đâu -- chỉ đưa nó cho những người bạn tin điều đó.
- Một nút láng giềng chuyển tiếp thấy hai mã đang trao đổi gói -- không phải ai đằng sau, và không phải cái gì bên trong.
- Một tín hiệu của một cuộc gọi đang chạy, khi nút láng giềng đầu tiên vừa lúc không trả lời, có thể đi qua một nút thấy cả hai đầu; nó biết rằng hai bạn đang gọi điện thoại cùng nhau.
- Một tệp lớn mà bạn đã đồng ý, máy tính chuyển tiếp hoặc giữ nó thấy ở cả hai đầu (xem chương 4).
- Với cuộc gọi, sự bảo vệ trước nhà cung cấp không áp dụng, và liên hệ của bạn thấy địa chỉ Internet của bạn (xem chương 7).

### Điều gì xảy ra khi người đối diện ngoại tuyến?

1. Cleona khởi động mọi đường phù hợp cùng lúc: trong cùng WLAN trực tiếp, trên Internet qua hai nút -- và thêm hộp thư.
2. Đối với hộp thư, Cleona đặt tin nhắn đã mã hóa tại ba nút láng giềng. Ngay khi hai cái xác nhận đã nhận, nó được coi là đã để lại.
3. Cleona cho việc đó ưu tiên các nút mà người đối diện cũng tra cứu -- trước hết nút mà lời mời của họ nêu.
4. Tin nhắn đợi đó tối đa 7 ngày. Khi người đối diện trở lại, họ lấy ra và xác nhận đã nhận cho bạn. Chỉ khi đó bạn thấy hai dấu tích.

Chỉ người đối diện mới có thể dọn hộp thư: Việc lấy ra và xóa chỉ chạy với một khóa mà chỉ họ có, và xóa chỉ thực hiện khi họ đã xác nhận đã nhận. Các nút láng giềng chỉ thấy các gói đã mã hóa dưới một giá trị đổi mỗi ngày.

### Người lạ không lọt qua

Từ một người không phải liên hệ của bạn và cũng không phải thành viên của một nhóm chung, Cleona chấp nhận đúng hai thứ: câu hỏi về các khóa công khai của bạn, miễn là một lời mời của bạn còn mở, và một yêu cầu liên hệ. Yêu cầu phải mang một lời mời hợp lệ từ bạn, và người gửi phải đã giải một bài toán tính toán trước đó. Mọi thứ khác -- tin nhắn, cuộc gọi, tệp -- bị hủy trước khi nó đến được ứng dụng. Ai chỉ có danh thiếp in của bạn, vì thế không thể đơn giản gọi cho bạn. Một thành viên của một nhóm chung chỉ tiếp cận được bạn trong nhóm đó -- bằng tin nhắn nhóm và cuộc gọi nhóm, không bao giờ riêng lẻ.

### Chống kiểm duyệt

Cleona được xây dựng sao cho khó bị chặn:

- **Không máy chủ, không địa chỉ cố định.** Trong ứng dụng không có địa chỉ nào có thể bị khóa, và mạng không phụ thuộc một nút đơn lẻ.
- **Không cổng cố định.** Mỗi thiết bị chọn một cổng ngẫu nhiên khi khởi động lần đầu. Không có số cổng đã biết nào để nhận ra lưu lượng Cleona.
- **Như dữ liệu ngẫu nhiên.** Việc thiết lập kết nối giữa hai thiết bị được mã hóa sao cho không phân biệt được với dữ liệu ngẫu nhiên.
- **Nhiều lối vào.** Mỗi lời mời, mỗi nút láng giềng và mỗi thiết bị trong cùng WLAN là một đường khả năng trở lại mạng.

### Lưu khóa an toàn

Trên các nền tảng được hỗ trợ, Cleona lưu các khóa mã hóa của bạn trong vòng khóa an toàn của hệ điều hành (Android Keystore, iOS Keychain, macOS Keychain). Khi có, điều đó cho bảo vệ phần cứng cho các khóa của bạn.

### Mã hóa cơ sở dữ liệu

Tin nhắn và cuộc trò chuyện của bạn nằm trong một cơ sở dữ liệu đã mã hóa -- một cơ sở riêng cho mỗi định danh, mỗi cái có khóa riêng. Không chỉ bản thân cơ sở dữ liệu được mã hóa, mà cả các tệp tạm của nó; không gì được viết ra đĩa chưa mã hóa, dù chỉ ngắn ngủi. Cài đặt, liên hệ và phương tiện cũng được lưu mã hóa.

Các khóa được phái sinh từ 24 từ của bạn và chỉ tồn tại trên thiết bị. Ngay cả ai lấy được thiết bị của bạn và đọc dữ liệu, cũng chỉ thấy dữ liệu không đọc được nếu không có các khóa này.

Chưa mã hóa chỉ xảy ra ở những nơi bạn tự đưa nội dung ra khỏi Cleona:
- khi bạn lưu một tệp từ một trò chuyện lên thiết bị của mình,
- khi bạn dùng nút chụp màn hình đặt một hình vào Ảnh của mình,
- khi bạn chia sẻ một thứ sang một ứng dụng khác,
- khi bạn thiết lập lưu trữ phương tiện (chương 13): Các bản gốc đã lưu trữ nằm chưa mã hóa trên ổ lưu trữ mạng ở nhà, để bạn cũng mở được chúng ở đó mà không cần Cleona,
- khi bạn phản chiếu các sự kiện sang lịch hệ thống Android: Ở đó, các ứng dụng khác có quyền truy cập lịch có thể đọc chúng.

Những gì đã đi ra như thế không bị xóa cùng tin nhắn và cũng không hết hạn cùng nó.

### Bảo vệ trên màn hình

Trên Android, Windows và macOS, Cleona không cho các ứng dụng khác quay màn hình. Nếu bạn cần một hình, dùng nút chụp màn hình trên thanh trên: Nó đặt hình vào Ảnh của bạn -- chưa mã hóa. Trong một cuộc trò chuyện không cho phép chuyển tiếp, không có chụp màn hình.

---

## 15. Cập nhật phần mềm

### Làm sao tôi nhận được cập nhật?

Cleona có thể được cập nhật qua nhiều đường. Mục tiêu là bạn vẫn nhận được cập nhật ngay cả khi các kênh phân phối đơn lẻ hỏng hoặc bị khóa:

1. **App Store / Play Store:** Ngay khi Cleona xuất hiện ở đó và bạn cài nó qua một store, bạn nhận cập nhật như thường qua store. Trên iPhone, cập nhật đến qua TestFlight.
2. **GitHub Releases:** Trên trang GitHub của dự án, bạn tìm các gói cài đặt đã ký cho mọi nền tảng.
3. **Cập nhật qua mạng:** Cleona có thể lấy một cập nhật trực tiếp qua mạng -- không cần máy chủ tải về. Phiên bản mới được cắt thành các mảnh sửa lỗi, phân tán trong mạng; một phần trong số chúng thậm chí đi theo dòng ngụy trang. Thiết bị của bạn thu thập đủ mảnh và ráp cập nhật lại. Được truyền thường chỉ là phần thay đổi -- vài MB thay vì cả ứng dụng. Điều này áp dụng cho Linux, Windows và Android; trên macOS, bạn tải các phiên bản mới từ trang web hoặc từ GitHub.
4. **Liên kết mời:** Bạn có thể tạo các liên kết mời, chứa mọi thứ một người dùng mới cần để cài Cleona và kết nối với mạng.
5. **Chuyển giao vật lý:** Trong môi trường không Internet, bạn có thể chuyển Cleona cho người khác qua USB hoặc trong mạng cục bộ.

### Một cập nhật diễn ra thế nào

1. Cleona thu thập các mảnh của một cập nhật mới tự động trong nền và ráp chúng lại.
2. Chỉ khi cập nhật **đầy đủ** và **chữ ký đã được kiểm**, Cleona mới đưa nó cho bạn. Bạn vì thế không bao giờ được đề nghị một cập nhật nửa vời hay chưa kiểm.
3. Khi bạn nhấn "Cài đặt", việc cài đặt bắt đầu không hỏi thêm. Trên Android, hệ thống cũng hiện hộp thoại cài đặt của nó.

Các phiên bản cũ hơn không được đề nghị -- một cập nhật luôn chỉ đi về trước. Nếu một phiên bản quá cũ đến mức không còn cộng tác được với mạng, Cleona cho biết rõ và yêu cầu bạn cập nhật.

### Kiểm chữ ký

Mỗi cập nhật được ký kép: bằng một phương pháp cổ điển và một phương pháp hậu lượng tử. Cleona tự động kiểm cả hai chữ ký. Như vậy đảm bảo chỉ các cập nhật từ nhà phát triển chính thức mới được chấp nhận -- ngay cả khi cập nhật đến qua mạng từ các thiết bị lạ. Một cập nhật không bao giờ sinh ra tự động từ quá trình phát triển, mà chỉ khi nhà phát triển ký nó bằng tay.

---
## 16. Câu hỏi thường gặp

### "Tôi có thể dùng Cleona không cần Internet không?"

Cleona cần một kết nối mạng, nhưng không nhất thiết Internet: Trong cùng WLAN, các thiết bị Cleona tự tìm thấy nhau và có thể viết cho nhau hoàn toàn không cần truy cập Internet. Bạn cũng không cần trực tuyến cùng lúc với người đối diện: Nếu họ ngoại tuyến, tin nhắn đợi tối đa 7 ngày trong hộp thư tại ba nút láng giềng, cho đến khi họ lấy ra.

### "Nếu tôi mất cụm từ hạt thì sao?"

Miễn là còn một thiết bị chạy với định danh của bạn, không gì mất -- ở đó bạn đơn giản viết tiếp. Trên thiết bị mà bạn đã tạo định danh, bạn phần lớn còn có thể đọc lại 24 từ (xem chương 2). Đừng dựa vào đó: Một lần cài lại dọn sạch bản sao này, và trên Android, việc gỡ hay đổi khóa màn hình cũng hủy diệt nó. Nếu bạn không còn cả từ lẫn thiết bị, không có đường quay lại -- cũng không qua danh bạ, nhà phát triển hay bất kỳ ai khác. Vì thế mới quan trọng phải giữ 24 từ an toàn.

### "Ai đó có thể đọc lén tin nhắn của tôi không?"

Không. Mỗi tin nhắn được mã hóa bằng một khóa dùng một lần, chỉ dành cho đúng tin nhắn đó. Chỉ bạn và người đối diện mới có thể giải mã tin nhắn. Không có máy chủ trung tâm, không có khóa chung và không có lối cho nhà phát triển. Ngay cả nếu một thiết bị trên đường chuyển tiếp tin nhắn, nó cũng chỉ thấy một mớ dữ liệu đã mã hóa và một mã. Nút láng giềng của bạn biết gói đến từ bạn, nhưng không biết nó đi đến ai; nút láng giềng của người đối diện biết nó đi đến ai, nhưng không biết từ ai.

### "Tại sao tôi không cần số điện thoại?"

Vì định danh của bạn thuần túy mật mã. Thay vì một số điện thoại hay địa chỉ email gắn với tên thật của bạn, bạn được định danh bằng một cặp khóa được tạo trên thiết bị của bạn. Bạn thêm liên hệ qua mã QR, NFC hoặc dòng văn bản của lời mời -- không qua sổ điện thoại. Điều đó có nghĩa
nhiều riêng tư hơn, vì tài khoản nhắn tin của bạn không gắn với định danh thực của bạn.

### "Làm sao tôi tìm người trên Cleona?"

Cleona cố ý không có tìm liên hệ theo số điện thoại hay tên -- đó sẽ là vấn đề riêng tư. Thay vào đó, bạn trao đổi lời mời trực tiếp: qua mã QR, NFC hoặc dòng văn bản qua một đường khác. Đó như trao đổi danh thiếp thay vì tra sổ điện thoại.

### "Cleona có hoạt động ở nước ngoài không?"

Có. Miễn là bạn có kết nối Internet, Cleona hoạt động ở mọi nơi trên thế giới. Vì không có máy chủ trung tâm và không có địa chỉ cố định, dịch vụ không thể bị tắt đơn giản cho các quốc gia nhất định. Việc Cleona làm khó việc chặn như thế nào, nằm trong chương "Bảo mật" dưới "Chống kiểm duyệt". Một quốc gia chặn mọi lưu lượng lạ ở biên giới, tuy nhiên, cũng có thể chặn Cleona.

### "Cleona có miễn phí không?"

Có. Cleona miễn phí và không có quảng cáo. Vì không có máy chủ trung tâm, cũng không phát sinh chi phí máy chủ cho việc vận hành. Trong Cài đặt, dưới "Hỗ trợ Cleona" -> "Quyên góp", bạn có thể ủng hộ việc phát triển một cách tự nguyện.

### "Tin nhắn của tôi chỉ có một dấu tích -- nghĩa là gì?"

Tin nhắn đang trên đường, nhưng người đối diện chưa xác nhận đã nhận -- phần lớn vì họ đang ngoại tuyến. Đó không phải lỗi: Tin nhắn đợi tối đa 7 ngày trong hộp thư. Ngay khi họ lấy ra, bạn thấy hai dấu tích. Một đồng hồ nghĩa là chưa đường nào mang tin nhắn đi -- nó tự khởi hành ngay khi có một đường; một dấu cảnh báo nghĩa là suốt 14 ngày không tìm được đường nào và bạn có thể gửi lại.

### "Vì sao tin nhắn đến chậm trên iPhone của tôi?"

iOS không cho ứng dụng chạy vĩnh viễn trong nền. Cleona chỉ được đánh thức thỉnh thoảng trong chốc lát; iOS quyết định lúc nào. Nó khi đó lấy mọi thứ. Ngay khi bạn mở ứng dụng, Cleona lấy những gì được giữ cho bạn.

### "Tôi có thể chuyển từ WhatsApp sang Cleona không?"

Có, nhưng bạn không thể chuyển các trò chuyện WhatsApp của mình. Cleona và WhatsApp là các hệ thống khác nhau về cơ bản. Bạn phải thêm từng liên hệ vào Cleona. Dễ nhất là bạn gửi dòng văn bản của lời mời đến các liên hệ. Mỗi yêu cầu đến thế nào, bạn tự xác nhận dưới "Yêu cầu".

### "Tôi có thể dùng Cleona trên nhiều thiết bị cùng lúc không?"

Chưa. Một thiết bị thứ hai cho cùng định danh sẽ có trong một phiên bản sau (chương 11). Trên nhiều thiết bị, hôm nay bạn có thể dùng các định danh khác nhau.

### "Làm sao tôi nhận cập nhật khi App Store bị khóa?"

Cleona có thể lấy cập nhật trực tiếp qua mạng, không phụ thuộc vào App Store, một trang web hay một máy chủ tải về. Nếu một thiết bị khác trong mạng có phiên bản mới nhất, thiết bị của bạn có thể tải cập nhật từ đó. Tính xác thực được kiểm qua chữ ký số của nhà phát triển. Ngoài ra, một liên hệ có thể đưa cho bạn ứng dụng qua liên kết mời hoặc USB. Thêm trong chương "Cập nhật phần mềm".

---

## Trợ giúp và liên hệ

Nếu bạn có câu hỏi hoặc vấp phải một vấn đề, bạn tìm thông tin cập nhật trên trang web Cleona và trên GitHub. Vì Cleona là một dự án phi tập trung, không có bộ phận hỗ trợ khách hàng cổ điển -- nhưng một cộng đồng tích cực sẵn sàng giúp đỡ.

---

*Sổ tay này mô tả Cleona Chat phiên bản 4.2. Các tính năng đơn lẻ có thể thay đổi hoặc mở rộng trong các phiên bản mới hơn.*