import Foundation

func test(localeIdentifier: String) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: localeIdentifier)
    let firstWeekday = calendar.firstWeekday
    let symbols = calendar.veryShortWeekdaySymbols
    print("Locale: \(localeIdentifier)")
    print("First Weekday ID: \(firstWeekday)")
    print("Symbols: \(symbols)")
    
    // Calculated order
    var indices: [Int] = []
    for i in 0..<7 {
        indices.append(((firstWeekday - 1 + i) % 7))
    }
    
    let orderedSymbols = indices.map { symbols[$0] }
    let orderedIDs = indices.map { $0 + 1 }
    
    print("Ordered Symbols: \(orderedSymbols)")
    print("Ordered IDs: \(orderedIDs)")
    print("---")
}

test(localeIdentifier: "en")
test(localeIdentifier: "it")
