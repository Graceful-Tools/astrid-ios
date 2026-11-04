import Foundation

/// The countdown length a task's timer opens at (AITD-593).
///
/// A task that was timed before keeps its own `timerDuration`. One that never was — a new timer —
/// opens at whatever the user last set on any task, remembered on this device, rather than a
/// hardcoded 25 minutes that undid their choice every time.
struct TimerDurationMemory {
    /// What the countdown picker offers, in minutes.
    static let pickerRange = 1...120
    static let fallbackMinutes = 25

    private static let key = "timer.lastSetDurationMinutes"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Remembers a duration the user picked or started, if the picker could have shown it.
    func remember(_ minutes: Int) {
        guard Self.pickerRange.contains(minutes) else { return }
        defaults.set(minutes, forKey: Self.key)
    }

    /// The task's own duration when it is one the picker can show, else the last one set.
    func initialDuration(for taskDuration: Int?) -> Int {
        if let taskDuration, Self.pickerRange.contains(taskDuration) {
            return taskDuration
        }
        let remembered = defaults.integer(forKey: Self.key)
        return Self.pickerRange.contains(remembered) ? remembered : Self.fallbackMinutes
    }
}
