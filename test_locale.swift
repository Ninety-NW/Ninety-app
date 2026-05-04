import Foundation

let codes = ["en", "it", "es", "zh", "ar"]
for code in codes {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: code)
    print("\(code): \(calendar.veryShortWeekdaySymbols)")
}
