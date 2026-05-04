import Foundation

let queuedSchedule: TimeInterval? = nil
let message: [String: Any] = [
    "watchStatus": "status",
    "watchConnectionStatus": "conn",
    "queuedSchedule": queuedSchedule as Any
]

print(message)
let isPlist = PropertyListSerialization.propertyList(message, isValidFor: .xml)
print("Is Plist: \(isPlist)")
