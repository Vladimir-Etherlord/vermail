import Foundation
import Testing

enum TestEnvironment {
    /// Set by `scripts/ci.sh` once the GreenMail container is running.
    static let hasGreenMail = ProcessInfo.processInfo.environment["VERMAIL_INTEGRATION"] == "1"
    /// Tests against real servers (mail.ru); run manually with `VERMAIL_LIVE_TESTS=1`.
    static let allowsLiveServers = ProcessInfo.processInfo.environment["VERMAIL_LIVE_TESTS"] == "1"
}

extension Trait where Self == ConditionTrait {
    static var greenMail: Self {
        .enabled(if: TestEnvironment.hasGreenMail, "GreenMail is not running (VERMAIL_INTEGRATION != 1)")
    }

    static var liveServers: Self {
        .enabled(if: TestEnvironment.allowsLiveServers, "Live server tests are disabled (VERMAIL_LIVE_TESTS != 1)")
    }
}
