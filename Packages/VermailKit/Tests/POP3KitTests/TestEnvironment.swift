import Foundation
import Testing

enum TestEnvironment {
    static let hasGreenMail = ProcessInfo.processInfo.environment["VERMAIL_INTEGRATION"] == "1"
}

extension Trait where Self == ConditionTrait {
    static var greenMail: Self {
        .enabled(if: TestEnvironment.hasGreenMail, "GreenMail is not running (VERMAIL_INTEGRATION != 1)")
    }
}
