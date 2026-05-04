import AppIntents

enum WatchNinetyWeekday: String, CaseIterable, AppEnum {
    case sunday
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Giorno"

    static let caseDisplayRepresentations: [WatchNinetyWeekday: DisplayRepresentation] = [
        .sunday: DisplayRepresentation(title: "domenica", synonyms: ["Sunday"]),
        .monday: DisplayRepresentation(title: "lunedì", synonyms: ["lunedi", "Monday"]),
        .tuesday: DisplayRepresentation(title: "martedì", synonyms: ["martedi", "Tuesday"]),
        .wednesday: DisplayRepresentation(title: "mercoledì", synonyms: ["mercoledi", "Wednesday"]),
        .thursday: DisplayRepresentation(title: "giovedì", synonyms: ["giovedi", "Thursday"]),
        .friday: DisplayRepresentation(title: "venerdì", synonyms: ["venerdi", "Friday"]),
        .saturday: DisplayRepresentation(title: "sabato", synonyms: ["Saturday"])
    ]

    var calendarWeekday: Int {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        }
    }
}
