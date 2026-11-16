# Lịch bàn Kindle 1.4.1

## Lịch hoạt động mặc định (giờ Việt Nam)
- 06:00–19:00: cập nhật 5 phút/lần, phần phút nhỏ bằng 2/3 phần giờ.
- 19:00–23:00: cập nhật mỗi phút.
- 23:00–06:00: chỉ hiện lịch, đèn tắt.
- Cuối tuần có thể chọn cập nhật mỗi phút ban ngày.
- Đánh thức bằng nút nguồn: hiện giờ ngay, cập nhật mỗi phút trong 5 phút.
- Nhấn giữ để thoát; vuốt để xem ngày trước/sau.

## Giới hạn sạc 20–80% (mới trong 1.4.1)

Trong Lịch bàn → Pin, đèn và lịch hoạt động:
- Giới hạn sạc 20–80% (khi mở lịch): bật/tắt chức năng.
- Trạng thái giới hạn sạc: xem bộ điều khiển, trạng thái và lỗi nếu có.

Quy tắc: từ 80% ngừng sạc; dưới 20% bật lại; 20–79% giữ trạng thái trước.
20% chính xác vẫn giữ trạng thái ngừng sạc nếu trước đó đã ngừng.
Ứng dụng nhớ giai đoạn charge/hold, kể cả khi rút và cắm lại nguồn.
Mặc định cho phép chức năng khi mở lịch, chỉ áp dụng sau khi nhận đúng driver
MAX77696 tương thích và khởi động thành công giám sát khôi phục sạc.
Máy không tương thích hoặc phát hiện Charge Limit khác thì không điều khiển.
Không cần cài thêm Charge Limit; mã điều khiển nằm trong gói Lịch bàn này.

Chỉ hoạt động khi lịch đang mở. Tắt giới hạn hoặc thoát lịch sẽ yêu cầu cho
phép sạc bình thường và kiểm tra lại trạng thái driver. Khi đang thức, kiểm
tra 30 giây/lần; khi ngủ mà đang cắm nguồn, hẹn kiểm tra tối đa khoảng một
phút/lần qua KOReader. Lịch 5 phút vẫn chỉ đổi giờ theo lịch 5 phút; các lần
kiểm tra sạc trung gian không đẩy đồng hồ chạy nhanh hơn.
Vì là kiểm tra định kỳ, ngưỡng được áp dụng khi đọc được mẫu tương ứng,
không phải bộ ngắt cứng ngay khoảnh khắc % pin đổi.

Trạng thái cắm nguồn đọc từ connected, độc lập với trạng thái đang nạp pin.
Khi ngừng sạc do giới hạn, màn hình ghi Ngừng sạc (20–80%).
Không khẳng định điện từ củ sạc đã thay thế hoàn toàn pin trên máy thực tế.

Các sự kiện charge_hold, charge_resume, charge_restore, charge_error và
charge_restore_error được ghi ngay vào CSV, kèm version, kể cả trong cùng
một giờ hoặc khi tắt log định kỳ. Log cũ giữ nguyên và không đổi cấu trúc cột.

Giám sát chạy riêng trong phiên dùng lịch: kiểm tra PID và thời điểm bắt đầu
của KOReader, để yêu cầu khôi phục sạc nếu KOReader kết thúc bất thường.
Ứng dụng cũng kiểm tra tiến trình giám sát trước khi ra lệnh ngừng sạc.
Nếu lệnh ghi/đọc lại thất bại hoặc dữ liệu pin lỗi, chức năng dừng và yêu cầu
khôi phục sạc bình thường. Chỉ ghi hai giao diện driver đã biết, không chạm
thanh ghi I2C, điện áp sạc hoặc cài đặt firmware.

Giám sát chưa được chạy trên Kindle thực tế. Nó không bảo đảm khôi phục khi
cả máy bị tắt cưỡng bức, mất nguồn hoặc khởi động lại; không cài dịch vụ khởi
động hệ thống. Sau sự cố như vậy, mở lại lịch và kiểm tra trạng thái sạc.
Nếu còn MODE 4, có thể khôi phục bằng lệnh allow_charging=1 của driver
MAX77696 đã xác định, rồi kiểm tra MODE 5. Không thử lệnh này trên driver khác.

## Cắm sạc thường xuyên
Tùy chọn Dùng khi cắm sạc thường xuyên giữ ứng dụng hoạt động khi nhận thấy
nguồn sạc, vẫn giữ nguyên lịch hiển thị 5 phút / mỗi phút / chỉ lịch.
Giới hạn sạc là tùy chọn riêng. Rút nguồn thì lịch trở lại chế độ ngủ nếu hỗ trợ.

## Đèn báo đầu giờ
Từ 06:00 tới 22:00, đèn sáng lên (ít nhất khoảng 65% thang đèn), rồi mờ dần
trong 60 giây về mức trước đó. Không giảm mức sáng đang đặt nếu nó cao hơn.
Thay đổi độ sáng thủ công sẽ hủy hiệu ứng. Thoát ứng dụng khôi phục độ sáng.
Có thể tắt hiệu ứng trong menu. Máy ngủ sẽ cần thức ngắn để chạy hiệu ứng.

## Log pin có phiên bản
CSV tự lưu theo tháng tại koreader/settings/deskcalendar-battery-YYYY-MM.csv.
Log nằm ngoài thư mục releases nên giữ nguyên qua các lần cập nhật.

Các cột:
timestamp_vietnam, epoch, battery_percent, delta_percentage_points,
elapsed_minutes, power_state, display_mode, frontlight_native, version, event.

version là phiên bản ứng dụng tại từng mẫu (ví dụ 1.4.1).
delta_percentage_points là số điểm % thay đổi, có thể âm hoặc dương khi sạc.
elapsed_minutes là khoảng thời gian thực từ mẫu trước, không mặc định 60 phút.
frontlight_native là mức sáng theo thang KOReader trên máy, không phải phần trăm.

Ghi khi mở ứng dụng và vào đầu giờ. Không nội suy hoặc tạo dòng giả cho giờ bị
bỏ lỡ. Mỗi mẫu ghi thời điểm đo thực tế; mẫu khi RTC đánh thức có thể trễ vài
giây. Muốn đo lúc máy ngủ, ứng dụng hẹn thức ngắn mỗi giờ; việc đo cũng tiêu
thụ một lượng pin. Có thể tắt ghi log để ngủ lâu hơn. Log không dùng Wi-Fi.
Trạng thái % pin chỉ có độ phân giải do thiết bị cung cấp; nên so sánh nhiều giờ.

## Ngủ và hẹn thức
Chỉ sử dụng trên Kindle có KOReader wakeup_mgr và hỗ trợ screensaver.
Ngủ giữa các lần cập nhật 5 phút; ban đêm hẹn cập nhật lịch lúc đổi ngày và
hẹn log mỗi giờ nếu bật log. Khi tới giờ học buổi tối, tự trở lại mỗi phút.
Giữ nguyên các khóa chống ngủ đã có của ứng dụng khác.
Nếu thiếu API, ứng dụng giữ cách hoạt động thông thường; không thể khẳng định
tiết kiệm pin. Các kiểm thử trên PC dùng mô phỏng sự kiện ngủ/thức, KHÔNG thay
cho kiểm thử trên Kindle. Cần đo log thực tế trước khi kết luận giảm hao pin.

## Cài qua USB
Thoát KOReader. Chép deskcalendar.koplugin vào koreader/plugins/, ghi đè các
tệp trùng tên. Không xóa thư mục settings. Eject USB, mở lại KOReader.
Chọn Lịch bàn → Chọn giao diện → Đồng hồ phía trên để dùng đồng hồ lớn.
Gói này giữ bản trước 1.3.0 và bản dự phòng 1.1.0 để có thể khôi phục.
Nguồn phát hành: https://github.com/Quan3dichhh/kindle-desk-calendar
Từ bản 1.2.1, chọn Lịch bàn → Cập nhật qua Wi-Fi để tải bản mới rồi mở lại KOReader.
Tệp giám sát có tên charge-watchdog.txt để tương thích danh sách tệp của bộ
cập nhật cũ; nó vẫn được gọi rõ ràng bằng sh, không thay đổi cách điều khiển sạc.

## Kiểm thử trên PC
Mã kiểm thử ở validation/ và harness ở DeskCalendar_dev/.
Cần Python, Pillow, lupa (Lua 5.1), và font Windows dùng trong harness.
Chạy python DeskCalendar_dev/test_charge.py từ thư mục đã giải nén.
Kiểm thử bao gồm lịch trong tuần, bố cục, log/version, hiệu ứng đèn,
và mô phỏng RTC/khóa ngủ/dọn hẹn giờ. Không kiểm thử phần cứng sạc.

## Nguồn kỹ thuật của điều khiển MAX77696
https://github.com/chengandre/ereader-charge-limit/blob/main/src/chargectl.c
Mã nguồn của André Cheng xác định MODE 4 là ngừng sạc, MODE 5 là cho phép
sạc, và allow_charging=1 là đường khôi phục của driver. Thông tin tương thích
được tác giả công bố cho Paperwhite thế hệ 7, firmware 5.14.2; chưa xác nhận
trên firmware của chiếc máy này. Giấy phép liên quan ở CHARGE-LICENSE.txt.

## Kiểm tra sau khi cài
Mở lịch, vào Trạng thái giới hạn sạc và kiểm tra báo MAX77696 thay vì lỗi.
Cắm sạc tường, giữ lịch mở. Kiểm tra trạng thái khi pin đạt 80% và log CSV.
Chưa coi thử logic trên PC là bằng chứng đã ngắt sạc trên máy.
Tắt Giới hạn sạc hoặc thoát lịch để quay về sạc bình thường.
Giữ gói 1.3.0 nếu cần khôi phục phiên bản trước qua USB.
