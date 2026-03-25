import AppKit
import SwiftData
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @Query(sort: [SortDescriptor(\VaultItemRecord.updatedAt, order: .reverse)]) private var items: [VaultItemRecord]
    @Query(sort: [SortDescriptor(\UsageLogRecord.updatedAt, order: .reverse)]) private var usageLogs: [UsageLogRecord]

    @State private var searchText = ""
    @State private var selectedProviderIdentity: String?
    @State private var selectedEnvironmentName: String?
    @State private var selectedID: UUID?
    @State private var isShowingAddSheet = false
    @State private var itemBeingEdited: VaultItemRecord?
    @State private var detailError: String?
    @State private var revealedSecrets: [UUID: String] = [:]

    private struct ProviderGroup: Identifiable {
        let id: String
        let displayName: String
        let items: [VaultItemRecord]

        var createdAt: Date {
            items.map(\.createdAt).min() ?? .now
        }

        var updatedAt: Date {
            items.map(\.updatedAt).max() ?? .now
        }

        var environments: [String] {
            let names = Dictionary(
                grouping: items.map { EnvironmentPreset.canonicalName(for: $0.environmentName) },
                by: { $0.lowercased() }
            )
            .compactMap(\.value.first)

            return names.sorted { lhs, rhs in
                Self.environmentSortOrder(lhs) < Self.environmentSortOrder(rhs)
            }
        }

        private static func environmentSortOrder(_ value: String) -> Int {
            switch value.lowercased() {
            case "production":
                return 0
            case "development":
                return 1
            case "staging":
                return 2
            default:
                return 3
            }
        }
    }

    private var filteredItems: [VaultItemRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return items }

        return items.filter { item in
            item.providerDisplayName.lowercased().contains(query) ||
            item.environmentName.lowercased().contains(query) ||
            (item.keyName?.lowercased().contains(query) ?? false) ||
            (item.platformURL?.lowercased().contains(query) ?? false) ||
            item.sourceURL.lowercased().contains(query) ||
            (item.notes?.lowercased().contains(query) ?? false) ||
            (item.pageTitle?.lowercased().contains(query) ?? false)
        }
    }

    private var providerGroups: [ProviderGroup] {
        Dictionary(grouping: filteredItems, by: \.providerIdentity)
            .map { identity, groupedItems in
                ProviderGroup(
                    id: identity,
                    displayName: groupedItems.first?.providerDisplayName ?? "Unknown",
                    items: groupedItems.sorted { $0.updatedAt > $1.updatedAt }
                )
            }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }

                return lhs.updatedAt > rhs.updatedAt
            }
    }

    private var selectedGroup: ProviderGroup? {
        if let selectedProviderIdentity,
           let match = providerGroups.first(where: { $0.id == selectedProviderIdentity }) {
            return match
        }

        return providerGroups.first
    }

    private var selectedEnvironment: String? {
        guard let group = selectedGroup else { return nil }
        if let selectedEnvironmentName,
           group.environments.contains(selectedEnvironmentName) {
            return selectedEnvironmentName
        }

        return group.environments.first
    }

    private var visibleItems: [VaultItemRecord] {
        guard let group = selectedGroup else { return [] }
        guard let selectedEnvironment else { return group.items }
        return group.items.filter {
            EnvironmentPreset.canonicalName(for: $0.environmentName) == selectedEnvironment
        }
    }

    private var focusedItem: VaultItemRecord? {
        if let selectedID,
           let item = visibleItems.first(where: { $0.id == selectedID }) {
            return item
        }

        return visibleItems.first
    }

    private var groupSignature: String {
        providerGroups.map { "\($0.id):\($0.items.count)" }.joined(separator: "|")
    }

    private var visibleSignature: String {
        visibleItems.map { $0.id.uuidString }.joined(separator: "|")
    }

    var body: some View {
        HStack(spacing: 20) {
            sidebar
                .frame(width: 250)

            Divider()

            managerPane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $isShowingAddSheet) {
            AddKeySheet { draft in
                try appState.saveManualDraft(draft)
            }
        }
        .sheet(item: $itemBeingEdited) { item in
            EditMetadataSheet(item: item) { provider, environment, keyName, platformURL, sourceURL, pageTitle, notes in
                try appState.updateMetadata(
                    for: item,
                    providerDisplayName: provider,
                    environment: environment,
                    keyName: keyName,
                    platformURL: platformURL,
                    sourceURL: sourceURL,
                    pageTitle: pageTitle,
                    notes: notes
                )
            }
        }
        .onAppear {
            synchronizeSelection()
            refreshVisibleSecrets()
        }
        .onChange(of: groupSignature) { _, _ in
            synchronizeSelection()
            refreshVisibleSecrets()
        }
        .onChange(of: selectedProviderIdentity) { _, _ in
            synchronizeSelection()
            detailError = nil
            refreshVisibleSecrets()
        }
        .onChange(of: selectedEnvironmentName) { _, _ in
            synchronizeSelection()
            detailError = nil
            refreshVisibleSecrets()
        }
        .onChange(of: visibleSignature) { _, _ in
            refreshVisibleSecrets()
        }
        .onChange(of: appState.unlockManager.unlockState) { _, newState in
            if newState == .locked {
                revealedSecrets.removeAll()
            } else {
                refreshVisibleSecrets()
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if providerGroups.isEmpty {
                ContentUnavailableView(
                    "No Platforms Yet",
                    systemImage: "key.horizontal",
                    description: Text("Save a key from the dashboard or Safari extension to populate the manager.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedProviderIdentity) {
                    ForEach(providerGroups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.displayName)
                                .font(.headline)
                            Text("Updated \(group.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Created \(group.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .tag(group.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var managerPane: some View {
        Group {
            if let group = selectedGroup {
                VStack(alignment: .leading, spacing: 16) {
                    managerHeader(for: group)
                    metadataSection(for: group)
                    environmentBar(for: group)
                    keySection
                }
            } else {
                ContentUnavailableView(
                    "Select a Platform",
                    systemImage: "sidebar.left",
                    description: Text("Your manager view will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func managerHeader(for group: ProviderGroup) -> some View {
        HStack {
            Text(group.displayName)
                .font(.largeTitle)
                .fontWeight(.semibold)

            Spacer()

            Button(appState.unlockManager.isUnlocked ? "Lock" : "Unlock") {
                if appState.unlockManager.isUnlocked {
                    appState.lockVault()
                } else {
                    Task {
                        await appState.unlockVault()
                    }
                }
            }
            .buttonStyle(.borderedProminent)

            Button("Export") {
                do {
                    try appState.exportMetadata()
                    detailError = nil
                } catch {
                    detailError = error.localizedDescription
                }
            }
            .buttonStyle(.bordered)

            Button("Share") {
                shareSummary(for: group)
            }
            .buttonStyle(.bordered)
        }
    }

    private func metadataSection(for group: ProviderGroup) -> some View {
        GroupBox("Metadata") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Platform", value: group.displayName)
                LabeledContent("Records", value: "\(group.items.count)")
                LabeledContent("Environments", value: group.environments.joined(separator: ", "))
                LabeledContent("Usage Logs", value: "\(usageCount(for: group))")
                LabeledContent("Bridge", value: appState.bridgeStatusMessage ?? "Bridge unavailable")

                if let item = focusedItem {
                    Divider()
                    LabeledContent("Page Title", value: item.pageTitle ?? "None")
                    LabeledContent("Platform Link", value: item.platformURL ?? "None")
                    LabeledContent("Current Link", value: item.sourceURL)
                    LabeledContent("Notes", value: item.notes ?? "None")
                }
            }
            .textSelection(.enabled)
        }
    }

    private func environmentBar(for group: ProviderGroup) -> some View {
        HStack(spacing: 10) {
            ForEach(group.environments, id: \.self) { environment in
                if environment == selectedEnvironment {
                    Button(environment) {
                        selectedEnvironmentName = environment
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(environment) {
                        selectedEnvironmentName = environment
                    }
                    .buttonStyle(.bordered)
                }
            }

            Button("+") {
                isShowingAddSheet = true
            }
            .buttonStyle(.bordered)
        }
    }

    private var keySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                if let detailError {
                    Text(detailError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                if visibleItems.isEmpty {
                    ContentUnavailableView(
                        "No Keys In This Environment",
                        systemImage: "key.viewfinder",
                        description: Text("Add a key with the Save button below.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                                keyRow(for: item, index: index)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                HStack {
                    Spacer()

                    Button("Edit") {
                        if let focusedItem {
                            itemBeingEdited = focusedItem
                        }
                    }
                    .disabled(focusedItem == nil)
                    .buttonStyle(.bordered)

                    Button("Save") {
                        isShowingAddSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } label: {
            Text(selectedEnvironment ?? "Keys")
                .font(.headline)
        }
    }

    private func keyRow(for item: VaultItemRecord, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Key name")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(keyLabel(for: item, index: index))
                .font(.headline)
                .textSelection(.enabled)

            Divider()

            Text("Value")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(displayValue(for: item))
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

            HStack(spacing: 10) {
                Button("Copy") {
                    copyAssignment(for: item)
                }
                .disabled(!appState.unlockManager.isUnlocked)
                .buttonStyle(.bordered)

                Button("Delete", role: .destructive) {
                    delete(item)
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(item.id == focusedItem?.id ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(item.id == focusedItem?.id ? Color.accentColor.opacity(0.35) : Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            selectedID = item.id
            detailError = nil
        }
    }

    private func keyLabel(for item: VaultItemRecord, index: Int) -> String {
        if let keyName = item.keyName, !keyName.isEmpty {
            return keyName
        }

        if let pageTitle = item.pageTitle, !pageTitle.isEmpty {
            return pageTitle
        }

        return "KEY_\(index + 1)"
    }

    private func displayValue(for item: VaultItemRecord) -> String {
        if let secret = revealedSecrets[item.id], appState.unlockManager.isUnlocked {
            return secret
        }

        return maskedPreview(for: item)
    }

    private func maskedPreview(for item: VaultItemRecord) -> String {
        let prefix = item.keyFingerprint.prefix(10)
        return "locked • 0x\(prefix)…"
    }

    private func refreshVisibleSecrets() {
        guard appState.unlockManager.isUnlocked else {
            revealedSecrets.removeAll()
            return
        }

        var nextSecrets: [UUID: String] = [:]
        for item in visibleItems {
            if let secret = try? appState.revealSecret(for: item) {
                nextSecrets[item.id] = secret
            }
        }
        revealedSecrets = nextSecrets
    }

    private func copyAssignment(for item: VaultItemRecord) {
        do {
            try appState.copyAssignment(for: item)
            detailError = nil
        } catch {
            detailError = error.localizedDescription
        }
    }

    private func delete(_ item: VaultItemRecord) {
        do {
            try appState.delete(item)
            detailError = nil
            revealedSecrets[item.id] = nil
            if selectedID == item.id {
                selectedID = nil
            }
            synchronizeSelection()
        } catch {
            detailError = error.localizedDescription
        }
    }

    private func shareSummary(for group: ProviderGroup) {
        let summary = """
        \(group.displayName)
        Environments: \(group.environments.joined(separator: ", "))
        Records: \(group.items.count)
        Usage logs: \(usageCount(for: group))
        Latest update: \(group.updatedAt.formatted(date: .abbreviated, time: .shortened))
        """

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        appState.postMessage("Copied platform summary.")
    }

    private func synchronizeSelection() {
        if let group = selectedGroup {
            selectedProviderIdentity = group.id
        } else {
            selectedProviderIdentity = nil
        }

        if let selectedEnvironment,
           visibleItems.contains(where: { EnvironmentPreset.canonicalName(for: $0.environmentName) == selectedEnvironment }) {
            selectedEnvironmentName = selectedEnvironment
        } else {
            selectedEnvironmentName = selectedGroup?.environments.first
        }

        if let selectedID,
           visibleItems.contains(where: { $0.id == selectedID }) {
            return
        }

        selectedID = visibleItems.first?.id
    }

    private func usageCount(for group: ProviderGroup) -> Int {
        usageLogs.filter { $0.sourceProviderIdentity == group.id }.count
    }
}
