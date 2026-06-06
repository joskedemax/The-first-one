import Foundation

final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let enabled = "jostype.enabled"
        static let learning = "jostype.learning"
        static let minPrefix = "jostype.minPrefixLength"
        static let model = "jostype.selectedModel"
        static let completedSetup = "jostype.completedSetup"
    }

    private init() {
        defaults.register(defaults: [
            Keys.enabled: true,
            Keys.learning: true,
            Keys.minPrefix: 2,
            Keys.model: JosTypeModel.gemma4_4b.rawValue
        ])
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.enabled) }
        set { defaults.set(newValue, forKey: Keys.enabled) }
    }

    var isLearningEnabled: Bool {
        get { defaults.bool(forKey: Keys.learning) }
        set { defaults.set(newValue, forKey: Keys.learning) }
    }

    var minPrefixLength: Int {
        get { max(1, defaults.integer(forKey: Keys.minPrefix)) }
        set { defaults.set(newValue, forKey: Keys.minPrefix) }
    }

    var hasCompletedSetup: Bool {
        get { defaults.bool(forKey: Keys.completedSetup) }
        set { defaults.set(newValue, forKey: Keys.completedSetup) }
    }

    var selectedModel: JosTypeModel {
        get {
            let raw = defaults.string(forKey: Keys.model) ?? JosTypeModel.gemma4_4b.rawValue
            return JosTypeModel(rawValue: raw) ?? .gemma4_4b
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.model) }
    }
}
