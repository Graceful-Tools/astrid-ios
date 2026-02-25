import SwiftUI
import AVFoundation
import AudioToolbox

struct TaskTimerView: View {
    @Binding var task: Task
    var onUpdate: (Task) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var duration: Int
    @State private var timeLeft: Int
    @State private var isActive = false
    @State private var isFinished = false
    @State private var timer: Timer?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var saveTask: _Concurrency.Task<Void, Never>? = nil
    @State private var isEditingDuration = false

    // Track the absolute end time for accurate background resumption
    @State private var timerEndTime: Date?

    init(task: Binding<Task>, onUpdate: @escaping (Task) -> Void) {
        self._task = task
        self.onUpdate = onUpdate

        // Use task's saved duration, or default to 25 minutes
        // Timer duration is per-task, not global
        let taskDuration = task.wrappedValue.timerDuration
        let initialDuration = (taskDuration != nil && taskDuration! > 0) ? taskDuration! : 25

        _duration = State(initialValue: initialDuration)
        _timeLeft = State(initialValue: initialDuration * 60)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 48) {
                HStack {
                    Spacer()
                    Button(action: {
                        stopTimer()
                        stopSound()
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                            .padding()
                    }
                }
                
                Spacer()
                
                Text(task.title)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                if isEditingDuration {
                    // Vertical scroll to set minutes
                    VStack(spacing: 0) {
                        Picker("Duration", selection: $duration) {
                            ForEach(1...120, id: \.self) { min in
                                Text("\(min)")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                                    .tag(min)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 200)
                        .onChange(of: duration) { _, newValue in
                            timeLeft = newValue * 60
                            saveDuration()
                        }
                        
                        Button(action: {
                            isEditingDuration = false
                            // Save the duration to this task when user taps Done
                            saveDuration()
                        }) {
                            Text("Done")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 24)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(20)
                        }
                        .padding(.top, 10)
                    }
                } else {
                    VStack(spacing: 8) {
                        Text(formatTime(timeLeft))
                            .font(.system(size: 100, weight: .bold, design: .monospaced))
                            .foregroundColor(isFinished ? .red : .white)
                        
                        if !isActive && !isFinished {
                            Text("minutes")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .onTapGesture {
                        if !isActive && !isFinished {
                            isEditingDuration = true
                        }
                    }
                }
                
                HStack(spacing: 40) {
                    if isFinished {
                        VStack(spacing: 24) {
                            Button(action: completeTask) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text(NSLocalizedString("timer.complete_task", comment: "COMPLETE TASK"))
                                }
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.black)
                                .frame(width: 260, height: 60)
                                .background(Color.green)
                                .cornerRadius(30)
                            }

                            Button(action: stopAlarm) {
                                Text(NSLocalizedString("timer.dismiss_alarm", comment: "Dismiss Alarm"))
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    } else {
                        Button(action: resetTimer) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                                .frame(width: 80, height: 80)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        
                        Button(action: toggleTimer) {
                            Image(systemName: isActive ? "pause.fill" : "play.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.black)
                                .frame(width: 100, height: 100)
                                .background(Color.white)
                                .clipShape(Circle())
                        }
                        
                        // Spacer for symmetry
                        Color.clear.frame(width: 80, height: 80)
                    }
                }
                
                if !isActive && !isFinished && !isEditingDuration {
                    Text(NSLocalizedString("timer.tap_to_change", comment: "Tap the time to change duration"))
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                Spacer()
            }
            .padding()
        }
        .onDisappear {
            stopTimerAndClearState()
            stopSound()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            handleAppWillResignActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            handleAppDidBecomeActive()
        }
        .onAppear {
            // Check if there's a saved timer state for this task (e.g., after app restart)
            checkForSavedTimerState()
        }
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func toggleTimer() {
        if isActive {
            stopTimer()
        } else {
            startTimer()
        }
    }
    
    private func startTimer() {
        isEditingDuration = false
        // Cancel any pending save task since we'll save immediately
        saveTask?.cancel()

        isActive = true
        isFinished = false

        // Calculate and store the absolute end time
        timerEndTime = Date().addingTimeInterval(TimeInterval(timeLeft))

        // Save timer state for background persistence
        _Concurrency.Task { @MainActor in
            TimerBackgroundManager.shared.saveTimerState(
                taskId: task.id,
                taskTitle: task.title,
                durationSeconds: duration * 60,
                remainingSeconds: timeLeft,
                isPaused: false
            )
            // Schedule notification for when timer completes
            await TimerBackgroundManager.shared.scheduleTimerNotification(
                taskId: task.id,
                taskTitle: task.title,
                remainingSeconds: timeLeft
            )
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timeLeft > 0 {
                timeLeft -= 1
            } else {
                stopTimer()
                handleCompletion()
            }
        }

        // Update server immediately when starting
        _Concurrency.Task {
            do {
                let savedTask = try await TaskService.shared.updateTask(
                    taskId: task.id,
                    timerDuration: duration
                )
                await MainActor.run {
                    onUpdate(savedTask)
                }
            } catch {
                print("Error updating task on timer start: \(error)")
            }
        }
    }

    private func stopTimer() {
        // Pause the timer (used for toggle pause/play)
        isActive = false
        timer?.invalidate()
        timer = nil
        timerEndTime = nil

        // Save paused state for background persistence
        if timeLeft > 0 && !isFinished {
            _Concurrency.Task { @MainActor in
                TimerBackgroundManager.shared.saveTimerState(
                    taskId: task.id,
                    taskTitle: task.title,
                    durationSeconds: duration * 60,
                    remainingSeconds: timeLeft,
                    isPaused: true
                )
                // Cancel any pending notification since timer is paused
                await TimerBackgroundManager.shared.cancelTimerNotification()
            }
        }
    }

    private func stopTimerAndClearState() {
        // Completely stop and clear timer (used when dismissing view)
        isActive = false
        timer?.invalidate()
        timer = nil
        timerEndTime = nil

        // Clear saved timer state
        _Concurrency.Task { @MainActor in
            TimerBackgroundManager.shared.clearTimerState()
            await TimerBackgroundManager.shared.cancelTimerNotification()
        }
    }

    private func resetTimer() {
        isEditingDuration = false
        stopTimerAndClearState()
        stopSound()
        isFinished = false
        timeLeft = duration * 60
        timerEndTime = nil
    }
    
    private func handleCompletion() {
        timeLeft = 0
        isFinished = true
        playSound()

        // Clear timer state since timer is complete
        _Concurrency.Task { @MainActor in
            TimerBackgroundManager.shared.clearTimerState()
            await TimerBackgroundManager.shared.cancelTimerNotification()
        }

        _Concurrency.Task {
            let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
            let commentContent = "Completed \(duration) minutes on \(dateStr)"

            do {
                // 1. Add comment
                _ = try await CommentService.shared.createComment(taskId: task.id, content: commentContent)

                // 2. Update task timerDuration and lastTimerValue
                let savedTask = try await TaskService.shared.updateTask(
                    taskId: task.id,
                    timerDuration: duration,
                    lastTimerValue: commentContent
                )
                await MainActor.run {
                    onUpdate(savedTask)
                }
            } catch {
                print("Error completing timer: \(error)")
            }
        }
    }

    private func playSound() {
        // Ensure audio session is set up for playback (ignores silent switch)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }

        // Try multiple paths for a pleasant repeating sound
        let soundPaths = [
            "/System/Library/Audio/UISounds/Modern/timer_complete.caf",
            "/System/Library/Audio/UISounds/nano/Alarm_Nightstand_Loop.caf",
            "/System/Library/Audio/UISounds/New/Alarm.caf",
            "/System/Library/Audio/UISounds/Modern/Alarm.caf"
        ]
        
        var played = false
        for path in soundPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    audioPlayer = try AVAudioPlayer(contentsOf: url)
                    audioPlayer?.numberOfLoops = -1 // Loop indefinitely
                    audioPlayer?.volume = 1.0
                    audioPlayer?.prepareToPlay()
                    audioPlayer?.play()
                    played = true
                    break
                } catch {
                    print("Failed to play sound at \(path): \(error)")
                }
            }
        }
        
        if !played {
            // Fallback to system alert sound if AVAudioPlayer fails
            // 1005 is "Alarm", 1304 is "Calendar Alert"
            AudioServicesPlayAlertSound(1005)
        }
        
        // Add haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    private func stopSound() {
        audioPlayer?.stop()
        audioPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    private func stopAlarm() {
        stopSound()
        isFinished = false
        timeLeft = duration * 60
    }

    private func completeTask() {
        stopSound()
        isFinished = false

        // Clear timer state since task is being completed
        _Concurrency.Task { @MainActor in
            TimerBackgroundManager.shared.clearTimerState()
            await TimerBackgroundManager.shared.cancelTimerNotification()
        }

        _Concurrency.Task {
            do {
                // Use completeTask() with timer metadata in a single request
                // This ensures daily/weekly repeating tasks roll forward correctly
                let savedTask = try await TaskService.shared.completeTask(
                    id: task.id,
                    completed: true,
                    task: task,
                    timerDuration: duration,
                    lastTimerValue: "Completed \(duration)m timer"
                )
                await MainActor.run {
                    onUpdate(savedTask)
                    dismiss()
                }
            } catch {
                print("Error completing task: \(error)")
            }
        }
    }

    // MARK: - Background/Foreground Handling

    private func handleAppWillResignActive() {
        // App going to background - pause the in-memory timer but keep tracking
        // The notification is already scheduled when timer starts
        if isActive && !isFinished {
            print("📱 [TaskTimerView] App resigning active with \(timeLeft)s remaining")
            // Stop the in-memory timer (it won't run in background anyway)
            timer?.invalidate()
            timer = nil
            // Keep isActive = true so we know to resume
            // Keep timerEndTime so we can calculate remaining time on resume
        }
    }

    private func handleAppDidBecomeActive() {
        // App returning to foreground - recalculate remaining time and resume if needed
        guard isActive && !isFinished else {
            return
        }

        // If we have an end time, calculate remaining time from wall clock
        if let endTime = timerEndTime {
            let now = Date()
            let remaining = Int(endTime.timeIntervalSince(now))

            if remaining <= 0 {
                // Timer completed while in background
                print("⏰ [TaskTimerView] Timer completed in background!")
                timeLeft = 0
                isActive = false
                timerEndTime = nil
                handleCompletion()
            } else {
                // Timer still has time - update display and restart
                print("▶️ [TaskTimerView] Resuming timer with \(remaining)s remaining (was \(timeLeft)s)")
                timeLeft = remaining

                // Restart the in-memory timer
                timer?.invalidate()
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    if timeLeft > 0 {
                        timeLeft -= 1
                    } else {
                        stopTimer()
                        handleCompletion()
                    }
                }
            }
        } else {
            // Fallback: check saved state from TimerBackgroundManager
            resumeFromSavedState()
        }
    }

    private func resumeFromSavedState() {
        _Concurrency.Task { @MainActor in
            guard let state = TimerBackgroundManager.shared.loadTimerState() else {
                print("⚠️ [TaskTimerView] No timer state found")
                return
            }

            // Make sure this is the same task
            guard state.taskId == task.id else {
                print("⚠️ [TaskTimerView] Timer state is for different task")
                return
            }

            let remaining = state.remainingSeconds

            if state.isCompleted {
                print("⏰ [TaskTimerView] Timer completed (from saved state)!")
                timeLeft = 0
                isActive = false
                handleCompletion()
            } else if !state.isPaused {
                print("▶️ [TaskTimerView] Resuming timer with \(remaining)s remaining (from saved state)")
                timeLeft = remaining
                timerEndTime = Date().addingTimeInterval(TimeInterval(remaining))

                timer?.invalidate()
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    if timeLeft > 0 {
                        timeLeft -= 1
                    } else {
                        stopTimer()
                        handleCompletion()
                    }
                }
            }
        }
    }

    private func checkForSavedTimerState() {
        // Check if there's a saved timer state for this task (e.g., app was killed and restarted)
        _Concurrency.Task { @MainActor in
            guard let state = TimerBackgroundManager.shared.loadTimerState() else {
                return
            }

            // Only restore if it's for this task
            guard state.taskId == task.id else {
                return
            }

            let remaining = state.remainingSeconds

            if state.isCompleted {
                // Timer completed while app was closed
                print("⏰ [TaskTimerView] Timer completed while app was closed!")
                timeLeft = 0
                handleCompletion()
            } else if !state.isPaused {
                // Timer was running - resume it
                print("▶️ [TaskTimerView] Restoring timer with \(remaining)s remaining")
                timeLeft = remaining
                duration = state.durationSeconds / 60
                startTimer()
            } else {
                // Timer was paused - just restore the state
                print("⏸️ [TaskTimerView] Restoring paused timer with \(remaining)s remaining")
                timeLeft = remaining
                duration = state.durationSeconds / 60
                isActive = false
            }
        }
    }

    private func saveDuration() {
        // Save timer duration to this specific task (per-task, not global)
        // Debounce server update to avoid spamming while scrolling the picker
        saveTask?.cancel()
        saveTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
            if _Concurrency.Task.isCancelled { return }

            do {
                let savedTask = try await TaskService.shared.updateTask(
                    taskId: task.id,
                    timerDuration: duration
                )
                await MainActor.run {
                    onUpdate(savedTask)
                }
            } catch {
                print("Error saving timer duration: \(error)")
            }
        }
    }
}
