import SwiftUI

struct TokenUsageSection: View {
    @Environment(\.appAccent) private var appAccent
    let state: TokenUsageUiState
    @State private var selectedDayID: Int64?
    @ScaledMetric(relativeTo: .caption) private var cellSize = 20.0

    private var calendar: TokenUsageCalendar {
        TokenUsageCalendar(points: state.daily, rangeDays: state.rangeDays, referenceDate: state.lastUpdated ?? Date())
    }

    var body: some View {
        Section {
            summary
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            if state.totals.requestCount > 0 {
                activity
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                DisclosureGroup("トークンの内訳") {
                    tokenDetails(
                        input: state.totals.inputTokens, output: state.totals.outputTokens,
                        cached: state.totals.cachedInputTokens, creation: state.totals.cacheCreationInputTokens,
                        reasoning: state.totals.reasoningTokens
                    )
                }
                .font(.subheadline)
            } else {
                Label {
                    Text("まだ利用履歴がありません。会話を始めると、ここに日々の利用量が表示されます。")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "chart.bar.xaxis")
                        .foregroundStyle(appAccent.color)
                }
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
                .padding(.vertical, 8)
            }
        } header: {
            HStack {
                Text("利用状況")
                Spacer()
                Text("直近\(state.rangeDays)日")
                    .font(.caption.weight(.regular))
            }
        } footer: {
            if let updated = state.lastUpdated {
                Text("更新: \(updated.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
            }
        }

        if !state.byModel.isEmpty {
            Section {
                ForEach(state.byModel) { item in
                    modelRow(item)
                }
            } header: {
                Text("モデル別の利用量")
            } footer: {
                Text("バーは期間内の総トークンに占める割合です。")
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("利用費用")
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
                Text(usd(state.totals.totalCostUsd))
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("USD")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
            }
            HStack(alignment: .top, spacing: 28) {
                metric("リクエスト", value: count(state.totals.requestCount))
                metric("総トークン", value: count(state.totals.totalTokens))
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var activity: some View {
        let calendar = calendar
        let selected = calendar.days.first { $0.id == selectedDayID } ?? calendar.days.last
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("アクティビティ")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("トークン数")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
            }

            ViewThatFits(in: .horizontal) {
                HStack {
                    Spacer(minLength: 0)
                    calendarGrid(calendar)
                    Spacer(minLength: 0)
                }
                ScrollView(.horizontal) { calendarGrid(calendar) }
            }
            .scrollIndicators(.hidden)

            dayDetail(selected)

            HStack(spacing: 4) {
                Text("少ない")
                    .padding(.trailing, 4)
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(activityColor(level))
                        .frame(width: 11, height: 11)
                        .accessibilityHidden(true)
                }
                Text("多い")
                    .padding(.leading, 4)
            }
            .font(.caption2)
            .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
            .frame(maxWidth: .infinity, alignment: .trailing)

            if state.totals.requestCount == 0 {
                Text("まだ利用履歴がありません。会話を始めると、ここに日々の利用量が表示されます。")
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
            }
        }
        .padding(.vertical, 8)
    }

    private func calendarGrid(_ calendar: TokenUsageCalendar) -> some View {
        HStack(alignment: .top, spacing: 5) {
            VStack(spacing: 5) {
                ForEach(0..<7) { weekday in
                    Text(weekdayLabel(weekday))
                        .font(.caption2)
                        .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
                        .frame(width: cellSize, height: cellSize)
                }
            }
            ForEach(0..<calendar.weekCount, id: \.self) { week in
                VStack(spacing: 5) {
                    ForEach(0..<7) { weekday in
                        if let day = calendar.day(week: week, weekday: weekday) {
                            Button {
                                selectedDayID = day.id
                            } label: {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(activityColor(day.level))
                                    .overlay {
                                        if day.id == (selectedDayID ?? calendar.days.last?.id) {
                                            RoundedRectangle(cornerRadius: 4)
                                                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                                        }
                                    }
                                    .frame(width: cellSize, height: cellSize)
                                    // Expand the touch area into the space between cells.
                                    .contentShape(Rectangle().inset(by: -2.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(dateLabel(day.date))、\(day.tokens)トークン、\(day.requests)リクエスト")
                            .accessibilityAddTraits(day.id == (selectedDayID ?? calendar.days.last?.id) ? .isSelected : [])
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(uiColor: .amoledSecondarySystemFill).opacity(0.35))
                                .frame(width: cellSize, height: cellSize)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .fixedSize()
    }

    private func dayDetail(_ day: TokenUsageCalendar.Day?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let day {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(dateLabel(day.date))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(count(day.tokens))
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                    Text("トークン")
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
                }
                Text("\(day.requests)回 · \(usd(day.cost))")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
            }
        }
        .frame(minWidth: 100, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func modelRow(_ item: TokenUsageByModel) -> some View {
        DisclosureGroup {
            tokenDetails(input: item.inputTokens, output: item.outputTokens,
                         cached: item.cachedInputTokens, creation: item.cacheCreationInputTokens,
                         reasoning: item.reasoningTokens)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.model)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("\(count(item.totalTokens)) トークン · \(item.requestCount)回")
                        Spacer(minLength: 12)
                        Text(usd(item.totalCostUsd))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(count(item.totalTokens)) トークン · \(item.requestCount)回")
                        Text(usd(item.totalCostUsd))
                    }
                }
                .font(.caption)
                .foregroundStyle(Color(uiColor: .amoledSecondaryLabel))
                .monospacedDigit()
                GeometryReader { proxy in
                    let ratio = min(1, max(0, Double(item.totalTokens) / Double(max(1, state.totals.totalTokens))))
                    Capsule().fill(Color.secondary.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Capsule().fill(appAccent.color)
                                .frame(width: proxy.size.width * ratio)
                        }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
        }
        .tint(.secondary)
    }

    @ViewBuilder
    private func tokenDetails(input: Int64, output: Int64, cached: Int64, creation: Int64?, reasoning: Int64) -> some View {
        detail("入力", value: count(input))
        detail("出力", value: count(output))
        detail("キャッシュ読込", value: count(cached))
        detail("キャッシュ作成", value: creation.map(count) ?? "不明")
        detail("推論", value: count(reasoning))
    }

    private func detail(_ title: String, value: String) -> some View {
        LabeledContent(title) { Text(value).monospacedDigit() }
            .font(.subheadline)
    }

    private func activityColor(_ level: Int) -> Color {
        switch level {
        case 1: return appAccent.color.opacity(0.22)
        case 2: return appAccent.color.opacity(0.45)
        case 3: return appAccent.color.opacity(0.7)
        case 4: return appAccent.color
        default: return Color(uiColor: .amoledSecondarySystemFill)
        }
    }

    private func weekdayLabel(_ weekday: Int) -> String {
        let formatter = DateFormatter()
        return formatter.veryShortWeekdaySymbols[weekday]
    }

    private func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }

    private func usd(_ value: Double) -> String {
        String(format: value == 0 || value >= 0.01 ? "$%.2f" : "$%.5f", value)
    }

    private func count(_ value: Int64) -> String {
        let magnitude = abs(Double(value))
        if magnitude >= 1_000_000_000 { return String(format: "%.1fB", Double(value) / 1_000_000_000) }
        if magnitude >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if magnitude >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }
}
