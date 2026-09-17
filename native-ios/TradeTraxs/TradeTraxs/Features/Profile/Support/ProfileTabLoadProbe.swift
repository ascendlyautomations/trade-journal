import Foundation

#if DEBUG
enum ProfileTabLoadProbe {
    static func selectedTab(_ section: ProfileSection) {
        print("[ProfileTab] selected tab=\(section.rawValue)")
    }

    static func loadStarted(_ section: ProfileSection) {
        print("[ProfileTab] load.started tab=\(section.rawValue)")
    }

    static func cache(_ section: ProfileSection, count: Int) {
        print("[ProfileTab] cache tab=\(section.rawValue) count=\(count)")
    }

    static func loadCompleted(_ section: ProfileSection, count: Int) {
        print("[ProfileTab] load.completed tab=\(section.rawValue) count=\(count)")
    }

    static func state(
        _ section: ProfileSection,
        loaded: Bool,
        loading: Bool,
        count: Int
    ) {
        print(
            "[ProfileTab] state tab=\(section.rawValue) loaded=\(loaded) loading=\(loading) count=\(count)"
        )
    }
}
#else
enum ProfileTabLoadProbe {
    static func selectedTab(_ section: ProfileSection) {}
    static func loadStarted(_ section: ProfileSection) {}
    static func cache(_ section: ProfileSection, count: Int) {}
    static func loadCompleted(_ section: ProfileSection, count: Int) {}
    static func state(_ section: ProfileSection, loaded: Bool, loading: Bool, count: Int) {}
}
#endif
