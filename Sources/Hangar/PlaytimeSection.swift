import Charts
import HangarKit
import SwiftUI

/// Playtime over time on a game's Overview (S-044): hours per week for twelve weeks, and the sessions.
struct PlaytimeSection: View {
    let game: Game
    @State private var showsSessions = false

    var body: some View {
        if !game.sessions.isEmpty {
            let weeks = PlayHistory.weeks(game.sessions)
            Section {
                Chart(weeks, id: \.start) { week in
                    BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Hours", week.hours))
                        .foregroundStyle(Palette.accent)
                }
                .chartYAxisLabel(String(localized: "Hours per week"))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 140)
                .accessibilityLabel(Text("Hours per week"))
                .accessibilityValue(Text(summary(weeks)))
                .accessibilityChartDescriptor(PlaytimeChartDescriptor(weeks: weeks))
                Text(summary(weeks))
                    .foregroundStyle(.secondary)
                DisclosureGroup(isExpanded: $showsSessions) {
                    ForEach(Array(game.sessions.suffix(30).reversed().enumerated()), id: \.offset) { _, session in
                        LabeledContent(session.start.formatted(date: .abbreviated, time: .shortened), value: PlaytimeText.short(session.length))
                    }
                } label: {
                    Text("Sessions (\(game.sessions.count))")
                }
            } header: {
                Text("Playtime")
            }
        }
    }

    /// "3 h this week, 12 h in 12 weeks"
    private func summary(_ weeks: [PlayWeek]) -> String {
        let week = PlaytimeText.short(weeks.last?.seconds ?? 0)
        let all = PlaytimeText.short(weeks.map(\.seconds).reduce(0, +))
        return String(localized: "\(week) this week, \(all) in 12 weeks")
    }
}

/// The audio graph for the chart.
struct PlaytimeChartDescriptor: AXChartDescriptorRepresentable {
    let weeks: [PlayWeek]

    func makeChartDescriptor() -> AXChartDescriptor {
        let names = weeks.map { $0.start.formatted(.dateTime.month(.abbreviated).day()) }
        let x = AXCategoricalDataAxisDescriptor(title: String(localized: "Week"), categoryOrder: names)
        let top = max(weeks.map(\.hours).max() ?? 0, 1)
        let y = AXNumericDataAxisDescriptor(title: String(localized: "Hours"), range: 0...top, gridlinePositions: []) {
            String(localized: "\(String(format: "%.1f", $0)) h")
        }
        let series = AXDataSeriesDescriptor(name: String(localized: "Playtime"), isContinuous: false,
                                            dataPoints: zip(names, weeks).map { AXDataPoint(x: $0, y: $1.hours) })
        return AXChartDescriptor(title: String(localized: "Hours per week"), summary: nil, xAxis: x, yAxis: y, additionalAxes: [], series: [series])
    }
}
