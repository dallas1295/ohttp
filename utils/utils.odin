package utils

import "core:fmt"
import "core:strings"
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
		"{}, {:02d} {} {} {:02d}:{:02d}:{:02d} GMT",
		http_weekdays[int(weekday)],
		day,
		http_months[int(month)],
		year,
		hour,
		minute,
		second,
	)
}
lower_ascii :: proc(s: string) -> string {
	b := make([]byte, len(s))

	for i in 0 ..< len(s) {
		c := s[i]
		b[i] = c + 32 if c >= 'A' && c <= 'Z' else c
	}

	return string(b)
}

has_token :: proc(value, token: string) -> bool {
	for piece in strings.split(value, ",") {
		if lower_ascii(strings.trim_space(piece)) == token {
			return true
		}
	}
	return false
}
