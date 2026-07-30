import Foundation

/// Reminder strings from original Astrid app
/// Ported from web app's reminder-constants.ts
///
/// Each set is the BUILT-IN voice, used unless the connected deployment supplies its
/// own through `BrandCopyStore` (task 97208a72). The nags carry a personality, so a
/// partner usually replaces them wholesale rather than translating Astrid's — and now
/// does so once, in the brand profile, rather than once per platform.
struct ReminderConstants {

    // MARK: - General Reminders

    /// The brand's nags if it supplied any, otherwise Astrid's.
    static var reminders: [String] {
        BrandCopyStore.shared.reminders(.general) ?? builtInReminders
    }

    static var remindersDue: [String] {
        BrandCopyStore.shared.reminders(.due) ?? builtInRemindersDue
    }

    static var reminderResponses: [String] {
        BrandCopyStore.shared.reminders(.responses) ?? builtInReminderResponses
    }

    // `builtInReminders` names the app in one entry, so it is computed rather than a
    // stored literal — mirrors the web's `{appName} here!` reminder copy.
    static let builtInReminders = [
        "Hi there! Have a sec?",
        "Can I see you for a sec?",
        "Have a few minutes?",
        "Did you forget?",
        "Excuse me!",
        "When you have a minute:",
        "On your agenda:",
        "Free for a moment?",
        "\(Brand.appName) here!",
        "Hi! Can I bug you?",
        "A minute of your time?",
        "It's a great day to"
    ]

    // MARK: - Due Date Reminders

    static let builtInRemindersDue = [
        "Time to work!",
        "Due date is here!",
        "Ready to start?",
        "You said you would do:",
        "You're supposed to start:",
        "Time to start:",
        "It's time!",
        "Excuse me! Time for",
        "You free? Time to"
    ]

    // MARK: - Encouraging Responses

    static let builtInReminderResponses = [
        "I've got something for you!",
        "Ready to put this in the past?",
        "Why don't you get this done?",
        "How about it? Ready tiger?",
        "Ready to do this?",
        "Can you handle this?",
        "You can be happy! Just finish this!",
        "I promise you'll feel better if you finish this!",
        "Won't you do this today?",
        "Please finish this, I'm sick of it!",
        "Can you finish this? Yes you can!",
        "Are you ever going to do this?",
        "Feel good about yourself! Let's go!",
        "I'm so proud of you! Lets get it done!",
        "A little snack after you finish this?",
        "Just this one task? Please?",
        "Time to shorten your todo list!",
        "Are you on Team Order or Team Chaos? Team Order! Let's go!",
        "Have I mentioned you are awesome recently? Keep it up!",
        "A task a day keeps the clutter away... Goodbye clutter!",
        "How do you do it? Wow, I'm impressed!",
        "You can't just get by on your good looks. Let's get to it!",
        "Lovely weather for a job like this, isn't it?",
        "A spot of tea while you work on this?",
        "If only you had already done this, then you could go outside and play.",
        "It's time. You can't put off the inevitable.",
        "I die a little every time you ignore me."
    ]

    // MARK: - UI Strings

    struct UI {
        static let reminderTitle = "Reminder:"
        static let snooze = "Snooze"
        static let complete = "Complete!"
        static let completedToast = "Congratulations on finishing!"
    }

    // MARK: - Helper Functions

    /// Get a random reminder string based on type
    static func getRandomReminderString(isDue: Bool = false) -> String {
        let array = isDue ? remindersDue : reminders
        // `builtInReminders` is the last resort rather than `reminders[0]`: the resolved
        // set is what might be empty, so indexing it would be the crash it guards against.
        return array.randomElement() ?? builtInReminders[0]
    }

    /// Get a random encouraging response
    static func getRandomResponse() -> String {
        return reminderResponses.randomElement() ?? builtInReminderResponses[0]
    }

    /// Get a complete reminder phrase (greeting + response)
    static func getReminderPhrase(isDue: Bool = false) -> String {
        let greeting = getRandomReminderString(isDue: isDue)
        let response = getRandomResponse()
        return "\(greeting) \(response)"
    }
}
