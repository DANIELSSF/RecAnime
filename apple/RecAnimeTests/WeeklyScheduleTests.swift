import Foundation
@testable import RecAnime
import Testing

/// `WeeklyScheduleView.Day` is the pure weekday <-> API-string helper the calendar screen is built
/// on: the raw values are what `/v1/schedules?day=` expects, and `today` decides the initial tab.
@Suite("WeeklyScheduleView.Day")
struct WeeklyScheduleTests {
    @Test("raw values match the API's day strings")
    func rawValues() {
        #expect(WeeklyScheduleView.Day.monday.rawValue == "monday")
        #expect(WeeklyScheduleView.Day.tuesday.rawValue == "tuesday")
        #expect(WeeklyScheduleView.Day.wednesday.rawValue == "wednesday")
        #expect(WeeklyScheduleView.Day.thursday.rawValue == "thursday")
        #expect(WeeklyScheduleView.Day.friday.rawValue == "friday")
        #expect(WeeklyScheduleView.Day.saturday.rawValue == "saturday")
        #expect(WeeklyScheduleView.Day.sunday.rawValue == "sunday")
    }

    @Test("allCases lists the week starting on Monday, as in Spain")
    func caseOrder() {
        #expect(WeeklyScheduleView.Day.allCases == [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday])
    }

    @Test("short and title labels are the Spanish day names")
    func labels() {
        #expect(WeeklyScheduleView.Day.monday.short == "Lun")
        #expect(WeeklyScheduleView.Day.monday.title == "Lunes")
        #expect(WeeklyScheduleView.Day.wednesday.short == "Mié")
        #expect(WeeklyScheduleView.Day.wednesday.title == "Miércoles")
        #expect(WeeklyScheduleView.Day.sunday.short == "Dom")
        #expect(WeeklyScheduleView.Day.sunday.title == "Domingo")
    }

    @Test("today maps Calendar's Sunday-first weekday onto the Monday-first Day")
    func today() {
        let weekday = Calendar.current.component(.weekday, from: .now)
        let expected: WeeklyScheduleView.Day = switch weekday {
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        case 7: .saturday
        default: .sunday
        }
        #expect(WeeklyScheduleView.Day.today == expected)
    }
}
