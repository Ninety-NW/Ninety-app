import Foundation
let date = Date()
let locale = Locale(identifier: "it")
let day = date.formatted(.dateTime.weekday(.abbreviated).locale(locale))
let time = date.formatted(Date.FormatStyle().locale(locale).hour().minute())
print(day)
print(time)
