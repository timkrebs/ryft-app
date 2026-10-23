import Foundation

/// Whose work this is: the signed-in account, or demo data, when the work started. Anything that outlives an await
/// (an export's archive, an import's upload, a long read) captures it first and checks `isCurrent` before it writes,
/// shows or sends the result, so one account's data never lands as another's, or as demo data's.
struct AccountBinding: Equatable, Sendable {
    let account: String?
    let demo: Bool

    @MainActor
    init(_ env: AppEnvironment) {
        account = env.auth.accountID
        demo = env.isDemo
    }

    /// Still the same account, and still demo data or not.
    @MainActor
    func isCurrent(in env: AppEnvironment) -> Bool {
        self == AccountBinding(env)
    }
}
