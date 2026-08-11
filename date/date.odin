package date

import "core:fmt"
import "core:time"

http_weekdays := [7]string{"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}
http_months := [13]string {
	"",
	"Jan",
	"Feb",
	"Mar",
	"Apr",
	"May",
	"Jun",
	"Jul",
	"Aug",
	"Sep",
	"Oct",
	"Nov",
	"Dec",
}

get_date :: proc(t: time.Time) -> string {
	year, month, day := time.date(t)
	weekday := time.weekday(t)
	hour, minute, second := time.clock_from_time(t)
	return fmt.tprintf(
		"{}, {:02} {} {} {:02}:{:02}:{:02} GMT",
		http_weekdays[int(weekday)],
		day,
		http_months[int(month)],
		year,
		hour,
		minute,
		second,
	)
}
