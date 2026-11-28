import Foundation

#if DEBUG && targetEnvironment(simulator)
/// Synthetic data only. Never compiled into the release app.
enum FinamiQAFixtures {
    static func reset(file: URL, settingsFile: URL) throws {
        let manager = FileManager.default
        if ProcessInfo.processInfo.arguments.contains("--finami-qa"), ProcessInfo.processInfo.arguments.contains("--finami-qa-reset") {
          if manager.fileExists(atPath:file.path) { try manager.removeItem(at:file) }
          try? manager.removeItem(at:settingsFile)
          // Only synthetic QA paths are cleared.
          try? manager.removeItem(at: FinamiScanStorage.files(for: file).folder)
          try? manager.removeItem(at: FinamiLocalSnapshots.folder(for: file))
          // Clean only the synthetic queue entry, never a real captured payment.
          if let folder = try? CaptureInbox.folder() {
            try? manager.removeItem(at: folder.appendingPathComponent("00000000-0000-4000-8000-000000000068.json"))
          }
        }
    }
    static func populate(_ loaded: inout Database, file: URL) throws {
        let manager = FileManager.default
        if ProcessInfo.processInfo.arguments.contains("--finami-qa"), !manager.fileExists(atPath:file.path) {
          if ProcessInfo.processInfo.arguments.contains("--finami-qa-hidden-subscription-fixture") {
            let r = SubscriptionRecord(id: "qa-private-subscription", name: "QA Private Subscription", amount: 123456)
            loaded.subscriptions = [r]
            loaded.paidRecords = [FinamiPaidRecord(id: "qa-private-history", paymentID: r.id, scheduledDate: Date(), paidDate: Date(), amount: 654321, currency: "UAH")]
            var p = AppearancePreferences()
            p.designHiddenSubscriptions = [r.id]
            loaded.preferences = p
          }
          if ProcessInfo.processInfo.arguments.contains("--finami-qa-recurring-fixture") {
            loaded.accounts.append(Account(id:"qa-recurring",name:"QA subscription card",opening:100000))
            let cal = Calendar.current
            loaded.operations = [-2,-1,0].map { offset in
                Operation(kind:.expense,amount:10000,date:cal.date(byAdding:.month,value:offset,to:Date().addingTimeInterval(-86400)) ?? Date(),category:"📺 Підписки",note:"QA Streaming",account:"qa-recurring")
            }
          }
          if ProcessInfo.processInfo.arguments.contains("--finami-qa-inbox-fixture") {
            loaded.accounts.append(Account(id: "qa-inbox-card", name: "QA Inbox Card"))
            let event = CapturedPayment(id: "00000000-0000-4000-8000-000000000068", account: "qa-inbox-card", currency: "UAH", minor: 12345, merchant: "QA Inbox Shop", source: "Apple Pay", incoming: false, clearPurchase: true)
            try CaptureInbox.enqueue(event, in: CaptureInbox.folder())
          }
          if ProcessInfo.processInfo.arguments.contains("--finami-qa-home-review-fixture") {
            loaded.accounts.append(Account(id:"qa-review-account",name:"QA Review"))
            loaded.operations = [
              Operation(id:"qa-review-in",kind:.unclassifiedCredit,amount:10000,note:"QA Unclassified credit",account:"qa-review-account"),
              Operation(id:"qa-review-out",kind:.unclassifiedDebit,amount:5000,note:"QA Unclassified debit",account:"qa-review-account"),
              Operation(id:"qa-reviewed",kind:.income,amount:20000,note:"QA Already classified",account:"qa-review-account"),
              Operation(id:"qa-review-previous",kind:.unclassifiedDebit,amount:3000,date:Calendar.current.date(byAdding:.month,value:-1,to:Date()) ?? Date(),note:"QA Previous month",account:"qa-review-account")
            ]
            loaded.dashboard = [.init(kind:.review,enabled:true,size:.medium)]
          }
          if ProcessInfo.processInfo.arguments.contains("--finami-qa-reports-fixture") {
            loaded.accounts.append(Account(id:"qa-pumb",name:"QA Pumb"))
            loaded.accounts.append(Account(id:"qa-otp",name:"QA OTP"))
            loaded.operations = [Operation(kind:.expense,amount:30000,account:"qa-pumb"),Operation(kind:.income,amount:100000,account:"qa-pumb"),Operation(kind:.expense,amount:10000,account:"qa-otp"),Operation(kind:.income,amount:20000,account:"qa-otp")]
            var p = AppearancePreferences(); p.reportsShowComparison=false; p.reportsShowCategories=false; p.reportsShowChart=false; loaded.preferences=p
          }
          if ProcessInfo.processInfo.arguments.contains("--finami-qa-design-fixture") {
            loaded.accounts = [Account(id:"qa-design-credit",name:"QA Credit Card",opening:-10000,accountType:"credit",creditLimit:100000),Account(id:"qa-design-debit",name:"QA Debit",opening:50000,accountType:"debit")]
            var p=AppearancePreferences();p.modernAccountGrid=true;p.designLayout="grid";p.accountsMode="all";loaded.preferences=p
          }
          if ProcessInfo.processInfo.arguments.contains("--finami-qa-home-accounts-fixture") {
            loaded.accounts = [Account(id:"qa-home-account",name:"QA Home Account",opening:50000,accountType:"debit")]
            var p = AppearancePreferences(); p.modernAccountGrid = true; p.designLayout = "grid"; loaded.preferences = p
            loaded.dashboard = [.init(kind:.accounts,enabled:true,size:.medium)]
          }
          if ProcessInfo.processInfo.arguments.contains("--finami-qa-upcoming-fixture") {
            loaded.obligations = (1...6).map { i in Obligation(id: "qa-upcoming-" + String(i), kind: .installment, name: "QA payment " + String(i), target: 100000, monthly: 10000, due: Date().addingTimeInterval(Double(i) * 86400)) }
            loaded.dashboard = [.init(kind: .obligations, enabled: true, size: .large)]
          }
          if ProcessInfo.processInfo.arguments.contains("--finami-qa-payment-fixture") || ProcessInfo.processInfo.arguments.contains("--finami-qa-link-fixture") {
            loaded.accounts.append(Account(id:"qa-card",name:"QA Card",opening:100000))
            loaded.obligations.append(Obligation(id:"qa-loan",kind:.installment,name:"QA installment",target:30000,paid:10000,monthly:10000,due:Date().addingTimeInterval(-86400)))
            if ProcessInfo.processInfo.arguments.contains("--finami-qa-link-fixture") { loaded.operations.append(Operation(kind:.creditRepayment,amount:10000,note:"QA existing debit",account:"qa-card")) }
          }
        }
    }
}
#endif
