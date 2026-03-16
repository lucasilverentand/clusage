import SwiftUI

struct AccountListView: View {
    @Bindable var accountStore: AccountStore
    @Binding var selectedItem: SidebarItem?

    var body: some View {
        List(selection: $selectedItem) {
            Section("Accounts") {
                ForEach(accountStore.accounts) { account in
                    Label {
                        Text(account.displayName)
                    } icon: {
                        Image(systemName: "person.crop.circle.fill")
                    }
                    .tag(SidebarItem.account(account.id))
                }
                .onMove { source, destination in
                    accountStore.moveAccounts(from: source, to: destination)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .accessibilityLabel("Account list")
        .safeAreaInset(edge: .bottom) {
            List(selection: $selectedItem) {
                Label("Schedule", systemImage: "calendar")
                    .tag(SidebarItem.schedule)
                Label("Disclaimer", systemImage: "exclamationmark.triangle")
                    .tag(SidebarItem.disclaimer)
                Label("Accounts", systemImage: "person.2")
                    .tag(SidebarItem.accounts)
                Label("Samples", systemImage: "list.bullet.rectangle")
                    .tag(SidebarItem.samples)
                Label("Settings", systemImage: "gear")
                    .tag(SidebarItem.settings)
            }
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .frame(height: 160)
            .padding(.bottom, 8)
        }
    }
}
