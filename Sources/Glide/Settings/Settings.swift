import Foundation

/// User-facing preferences, backed by `UserDefaults`.
final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let enabled = "glide.enabled"
        static let learning = "glide.learning"
        static let minPrefix = "glide.minPrefixLength"
    }

    private init() {
        defaults.register(defaults: [
            Keys.enabled: true,
            Keys.learning: true,
            Keys.minPrefix: 2
        ])
    }

    /// Master on/off for suggestions.
    var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.enabled) }
        set { defaults.set(newValue, forKey: Keys.enabled) }
    }

    /// Whether Glide trains on the user's typing.
    var isLearningEnabled: Bool {
        get { defaults.bool(forKey: Keys.learning) }
        set { defaults.set(newValue, forKey: Keys.learning) }
    }

    /// Minimum characters typed before completions appear.
    var minPrefixLength: Int {
        get { max(1, defaults.integer(forKey: Keys.minPrefix)) }
        set { defaults.set(newValue, forKey: Keys.minPrefix) }
    }
}
