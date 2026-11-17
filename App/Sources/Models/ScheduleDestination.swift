import Foundation

/// 외부 캘린더 객체 대신 화면에 전달하는 이름과 sRGB 색.
public struct ScheduleDestination: Hashable, Sendable {
    public struct Color: Hashable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double
        public init(red: Double, green: Double, blue: Double) { self.red = red; self.green = green; self.blue = blue }
    }
    public let name: String
    public let color: Color?
    public init(name: String, color: Color? = nil) { self.name = name; self.color = color }
}
