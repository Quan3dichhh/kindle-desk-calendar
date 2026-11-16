# Kindle Desk Calendar / Lịch bàn Kindle

Ứng dụng lịch bàn ngoại tuyến cho KOReader trên Kindle, bố cục ngang.

## Cập nhật qua Wi-Fi
Từ bản 1.2.1: vào Lịch bàn → Cập nhật qua Wi-Fi → Tải và cài, rồi thoát và mở lại KOReader.
Phiên bản mới: **1.4.1**. Manifest ở `update.json`, mỗi tệp được tải từ một commit
cố định và kiểm tra kích thước/SHA-256 trước khi đổi phiên bản đang dùng.
Bản cũ được giữ lại để khôi phục. Cập nhật thủ công, không cần PC chạy sau khi phát hành.

## Tính năng
- Đồng hồ 12h, lịch dương, lịch âm Việt Nam và lịch tháng; hai giao diện ngang.
- 06:00–19:00: 5 phút/lần, phút nhỏ bằng 2/3 giờ; 19:00–23:00: mỗi phút.
- 23:00–06:00: chỉ lịch. Cuối tuần có thể chọn tần suất riêng.
- Từ vựng/châm ngôn mỗi giờ, đèn sáng rồi mờ dần đầu giờ.
- Log pin CSV có version, thời điểm đo thực tế, trạng thái nguồn và độ sáng.
- Giới hạn sạc MAX77696: từ 80% ngừng, dưới 20% bật lại; giữa hai ngưỡng giữ trạng thái.
- Chỉ điều khiển sạc khi lịch mở và nhận diện được giao diện driver hỗ trợ.

## Trạng thái kiểm thử
Đã kiểm thử logic trên PC và đường nâng cấp từ bộ cập nhật 1.2.1 bằng mô phỏng
tải tệp. Ngủ/RTC, đèn và ngắt/bật sạc vẫn cần kiểm chứng trên Kindle thực tế.
Giám sát khôi phục sạc không thay thế bảo vệ phần cứng và không bảo đảm khôi
phục sau mất nguồn hoặc khởi động lại cưỡng bức. Xem README trong thư mục phiên bản.

## Giấy phép
Không áp dụng một giấy phép chung cho toàn bộ dự án. Điều kiện dùng lịch âm
cho mục đích cá nhân, phi thương mại được giữ trong NOTICE.txt của từng bản.
Thông tin giấy phép MIT liên quan điều khiển sạc ở CHARGE-LICENSE.txt.
Không chứa sách, dữ liệu pin hoặc thông tin cá nhân của thiết bị.
