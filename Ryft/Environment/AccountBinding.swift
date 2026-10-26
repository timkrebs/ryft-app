import Foundation

/// Whose work this is: the signed-in account, or demo data, when the work started. Anything that outlives an await
/// (an export's archive, an import's upload, a long read) captures it first and checks `isCurrent` before it writes,
/// shows or sends the result, so one account's data never lands as another's, or as demo data's.
struct AccountBinding: Equatable, Sendable {
    let account: String?
    let demo: Bool
    /// `AuthService.accountChanges` then: an account that went and came back (A, B, then A again) is another session
    /// whose wipe ran in between, so the work isn't current either.
    let changes: Int

    @MainActor
    init(_ env: AppEnvironment) {
        account = env.auth.accountID
        demo = env.isDemo
        changes = env.auth.accountChanges
    }

    /// Still the same account without a change in between, and still demo data or not.
    @MainActor
    func isCurrent(in env: AppEnvironment) -> Bool {
        self == AccountBinding(env)
    }
}
