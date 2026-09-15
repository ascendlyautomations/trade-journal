import Foundation

enum ProfileDictionaryByID {
    /// Builds `[ProfileID: Profile]` without trapping on duplicate IDs. Later profiles win.
    static func build(
        _ layers: [Profile]...,
        onDuplicate: ((ProfileID, Profile, Profile) -> Void)? = nil
    ) -> [ProfileID: Profile] {
        var map: [ProfileID: Profile] = [:]
        for layer in layers {
            for profile in layer {
                if let existing = map[profile.id] {
                    onDuplicate?(profile.id, existing, profile)
                }
                map[profile.id] = profile
            }
        }
        return map
    }
}
