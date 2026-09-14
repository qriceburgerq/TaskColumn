import SwiftUI

public struct CalendarMonthView: View {
    @ObservedObject private var dataManager = DataManager.shared
    
    @State private var currentMonth: Date = Date()
    @State private var showingQuickAddForDate: Date? = nil
    @State private var quickAddTitle: String = ""
    
    public var onSelectTask: ((String) -> Void)? = nil
    
    public init(onSelectTask: ((String) -> Void)? = nil) {
        self.onSelectTask = onSelectTask
    }
    
    private let calendar = Calendar.current
    private let daysOfWeek = ["週日", "週一", "週二", "週三", "週四", "週五", "週六"]
    
    public var body: some View {
        VStack(spacing: 0) {
            // Calendar Top Navigation Bar
            monthHeaderBar
            
            Divider()
            
            // Weekday Header
            HStack(spacing: 0) {
                ForEach(daysOfWeek, id: \.self) { day in
                    Text(day)
                        .font(.appScale(11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
            
            Divider()
            
            // Month Grid
            GeometryReader { geo in
                let weeks = daysInMonthGrid()
                let rowHeight = max(70, (geo.size.height - 10) / CGFloat(weeks.count))
                
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(0..<weeks.count, id: \.self) { weekIdx in
                            HStack(spacing: 1) {
                                ForEach(weeks[weekIdx], id: \.self) { date in
                                    dayCell(for: date, height: rowHeight)
                                }
                            }
                        }
                    }
                    .background(Color(NSColor.separatorColor).opacity(0.2))
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(item: Binding<DateWrapper?>(
            get: { showingQuickAddForDate.map { DateWrapper(date: $0) } },
            set: { showingQuickAddForDate = $0?.date }
        )) { wrapper in
            quickAddSheet(for: wrapper.date)
        }
    }
    
    // MARK: - Header Bar
    
    private var monthHeaderBar: some View {
        HStack(spacing: 12) {
            // Month title
            Text(monthYearString(for: currentMonth))
                .font(.appScale(16, weight: .bold))
            
            Spacer()
            
            // Navigation controls
            HStack(spacing: 6) {
                Button(action: { changeMonth(by: -1) }) {
                    Image(systemName: "chevron.left")
                        .font(.appScale(11, weight: .semibold))
                        .padding(5)
                }
                .buttonStyle(PlainButtonStyle())
                .help("上一個月")
                
                Button("今天") {
                    withAnimation {
                        currentMonth = Date()
                    }
                }
                .font(.appScale(11, weight: .medium))
                .buttonStyle(BorderedButtonStyle())
                .controlSize(.small)
                
                Button(action: { changeMonth(by: 1) }) {
                    Image(systemName: "chevron.right")
                        .font(.appScale(11, weight: .semibold))
                        .padding(5)
                }
                .buttonStyle(PlainButtonStyle())
                .help("下一個月")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    // MARK: - Day Cell
    
    private func dayCell(for date: Date, height: CGFloat) -> some View {
        let isCurrentMonth = calendar.isDate(date, equalTo: currentMonth, toGranularity: .month)
        let isToday = calendar.isDateInToday(date)
        let tasksOnDay = tasksForDate(date)
        
        return VStack(alignment: .leading, spacing: 3) {
            // Cell Header (Day Number + Add button)
            HStack {
                Text("\(calendar.component(.day, from: date))")
                    .font(.appScale(11, weight: isToday ? .bold : .medium))
                    .foregroundColor(isToday ? .white : (isCurrentMonth ? .primary : .secondary.opacity(0.4)))
                    .frame(width: 20, height: 20)
                    .background(isToday ? Color.accentColor : Color.clear)
                    .clipShape(Circle())
                
                Spacer()
                
                // Quick add button on hover / subtle
                Button(action: {
                    showingQuickAddForDate = date
                    quickAddTitle = ""
                }) {
                    Image(systemName: "plus")
                        .font(.appScale(9))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())
                .help("於此日新增待辦")
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            
            // Tasks Chips
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(tasksOnDay) { task in
                        taskChip(for: task)
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
        .background(
            isToday
                ? Color.accentColor.opacity(0.04)
                : (isCurrentMonth ? Color(NSColor.windowBackgroundColor) : Color(NSColor.controlBackgroundColor).opacity(0.3))
        )
    }
    
    private func taskChip(for task: TaskItem) -> some View {
        let isSelected = dataManager.selectedTaskId == task.id
        
        return Button(action: {
            dataManager.selectedTaskId = task.id
            onSelectTask?(task.id)
        }) {
            HStack(spacing: 4) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.appScale(9))
                    .foregroundColor(task.isCompleted ? .secondary : (task.isOverdue ? .red : .accentColor))
                
                Text(task.title)
                    .font(.appScale(10))
                    .lineLimit(1)
                    .strikethrough(task.isCompleted)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08))
            .cornerRadius(4)
        }
        .buttonStyle(PlainButtonStyle())
        .help("點選可於右側編輯備忘: \(task.title)")
    }
    
    // MARK: - Quick Add Sheet
    
    private func quickAddSheet(for date: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("新增待辦事項 - \(formatShortDate(date))")
                .font(.appScale(14, weight: .bold))
            
            TextField("輸入待辦事項名稱...", text: $quickAddTitle)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.appScale(13))
            
            HStack {
                Spacer()
                Button("取消") {
                    showingQuickAddForDate = nil
                }
                .keyboardShortcut(.cancelAction)
                
                Button("新增") {
                    let trimmed = quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        let created = dataManager.addTask(title: trimmed, due: date)
                        dataManager.selectedTaskId = created.id
                    }
                    showingQuickAddForDate = nil
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(BorderedProminentButtonStyle())
                .disabled(quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
    
    // MARK: - Helpers
    
    private func tasksForDate(_ date: Date) -> [TaskItem] {
        return dataManager.allTasks.filter { task in
            guard let due = task.due, task.parent == nil else { return false }
            return calendar.isDate(due, inSameDayAs: date)
        }
    }
    
    private func daysInMonthGrid() -> [[Date]] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth) else {
            return []
        }
        
        let firstOfMonth = monthInterval.start
        let lastOfMonth = monthInterval.end - 1
        
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth) // 1 = Sunday
        let leadDays = firstWeekday - 1
        
        var gridDates: [Date] = []
        
        if let startGridDate = calendar.date(byAdding: .day, value: -leadDays, to: firstOfMonth) {
            var curr = startGridDate
            while curr <= lastOfMonth || gridDates.count % 7 != 0 || gridDates.count < 35 {
                gridDates.append(curr)
                guard let next = calendar.date(byAdding: .day, value: 1, to: curr) else { break }
                curr = next
            }
        }
        
        var weeks: [[Date]] = []
        for i in stride(from: 0, to: gridDates.count, by: 7) {
            let end = min(i + 7, gridDates.count)
            weeks.append(Array(gridDates[i..<end]))
        }
        return weeks
    }
    
    private func changeMonth(by val: Int) {
        if let next = calendar.date(byAdding: .month, value: val, to: currentMonth) {
            withAnimation {
                currentMonth = next
            }
        }
    }
    
    private func monthYearString(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "yyyy 年 M 月"
        return f.string(from: date)
    }
    
    private func formatShortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M 月 d 日 (E)"
        return f.string(from: date)
    }
}

private struct DateWrapper: Identifiable {
    let id = UUID()
    let date: Date
}
