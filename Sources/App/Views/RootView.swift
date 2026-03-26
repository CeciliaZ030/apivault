import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    @State private var searchText = ""
    @State private var selectedProviderIdentity: String?
    @State private var selectedEnvironmentName: String?
    @State private var selectedID: UUID?
    @State private var detailError: String?
    @State private var revealedSecrets: [UUID: String] = [:]
    @State private var isCreatingEnvironment = false
    @State private var draftEnvironmentName = ""
    @State private var draftRows = [DraftKeyRow()]
    @State private var currentEnvironmentDraftRows: [DraftKeyRow] = []
    @State private var isCreatingPlatform = false
    @State private var draftPlatformName = ""
    @State private var draftPlatformEnvironment = ""
    @State private var draftPlatformRows = [DraftKeyRow()]
    @State private var isEditingKeys = false
    @State private var editedKeyNames: [UUID: String] = [:]
    @State private var editedValues: [UUID: String] = [:]
    @State private var isEditingMetadata = false
    @State private var editedPageTitle = ""
    @State private var editedPlatformURL = ""
    @State private var editedSourceURL = ""
    @State private var editedNotes = ""
    @State private var editedProviderName = ""
    @State private var editedEnvironment = ""
    @State private var editedKeyName = ""
    @State private var showingUsageLogs = false
    @State private var isEditingUsageLogs = false
    @State private var editedUsage: [UUID: String] = [:]
    @State private var editedUsedSite: [UUID: String] = [:]
    @State private var editedConfigLink: [UUID: String] = [:]
    @State private var editedServerIP: [UUID: String] = [:]
    @State private var editedUsageNotes: [UUID: String] = [:]
    @FocusState private var focusedField: FocusField?

    private static let draftEnvironmentSelectionID = "__draft_environment__"

    private struct DraftKeyRow: Identifiable, Equatable {
        let id = UUID()
        var keyName = ""
        var value = ""
    }

    private enum FocusField: Hashable {
        case platformName
        case environmentName
        case keyName(UUID)
    }

    private var items: [VaultItemRecord] {
        _ = appState.dataRevision
        return appState.vaultItems()
    }

    private var usageLogs: [UsageLogRecord] {
        _ = appState.dataRevision
        return appState.usageLogItems()
    }

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

    private var isDraftEnvironmentSelected: Bool {
        isCreatingEnvironment && selectedEnvironmentName == Self.draftEnvironmentSelectionID
    }

    private var selectedEnvironment: String? {
        guard let group = selectedGroup else { return nil }
        if isDraftEnvironmentSelected {
            let trimmed = draftEnvironmentName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "New Environment" : trimmed
        }
        if let selectedEnvironmentName,
           group.environments.contains(selectedEnvironmentName) {
            return selectedEnvironmentName
        }

        return group.environments.first
    }

    private var visibleItems: [VaultItemRecord] {
        guard let group = selectedGroup else { return [] }
        guard !isDraftEnvironmentSelected else { return [] }
        guard let selectedEnvironment else { return group.items }
        return group.items.filter {
            EnvironmentPreset.canonicalName(for: $0.environmentName) == selectedEnvironment
        }
    }

    private var visibleUsageLogs: [UsageLogRecord] {
        guard let group = selectedGroup else { return [] }
        return usageLogs.filter { $0.sourceProviderIdentity == group.id }
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
            resetCurrentEnvironmentDraftRows()
            cancelEditingKeys()
            cancelEditingMetadata()
            cancelDraftEnvironment()
            cancelEditingUsageLogs()
            showingUsageLogs = false
        }
        .onChange(of: selectedEnvironmentName) { _, newValue in
            if newValue != Self.draftEnvironmentSelectionID {
                cancelDraftEnvironment()
            }
            synchronizeSelection()
            detailError = nil
            refreshVisibleSecrets()
            resetCurrentEnvironmentDraftRows()
            cancelEditingKeys()
            cancelEditingMetadata()
            cancelEditingUsageLogs()
            showingUsageLogs = false
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

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(providerGroups) { group in
                        Button {
                            isCreatingPlatform = false
                            selectedProviderIdentity = group.id
                            selectedEnvironmentName = group.environments.first
                            selectedID = group.items.first?.id
                        } label: {
                            let isSelected = selectedProviderIdentity == group.id && !isCreatingPlatform
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.displayName)
                                    .font(.headline)
                                    .foregroundStyle(isSelected ? .white : .primary)
                                Text("Updated \(group.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(isSelected ? Color.white.opacity(0.88) : .secondary)
                                Text("Created \(group.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(isSelected ? Color.white.opacity(0.88) : .secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(
                                        isSelected
                                            ? Color.accentColor.opacity(0.35)
                                            : Color(nsColor: .separatorColor),
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            Button {
                startCreatingPlatform()
            } label: {
                Label("New Platform", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var managerPane: some View {
        Group {
            if isCreatingPlatform {
                newPlatformEditor
            } else if let group = selectedGroup {
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

            if isEditingMetadata {
                Button("Save") {
                    saveEditedMetadata()
                }
                .buttonStyle(.borderedProminent)

                Button("Cancel") {
                    cancelEditingMetadata()
                }
                .buttonStyle(.bordered)
            } else if let item = focusedItem ?? group.items.first {
                Button("Edit") {
                    startEditingMetadata(for: item, group: group)
                }
                .buttonStyle(.bordered)
            }

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
        VStack(alignment: .leading, spacing: 12) {
            if isEditingMetadata {
                editableMetadataRow(label: "Platform", text: $editedProviderName)
                metadataRow(label: "Records", value: "\(group.items.count)")
                editableMetadataRow(label: "Environment", text: $editedEnvironment)
                metadataRow(label: "Usage Logs", value: "\(usageCount(for: group))")
                metadataRow(label: "Bridge", value: appState.bridgeStatusMessage ?? "Bridge unavailable")
                Divider()
                editableMetadataRow(label: "Key Name", text: $editedKeyName)
                editableMetadataRow(label: "Page Title", text: $editedPageTitle)
                editableMetadataRow(label: "Platform Link", text: $editedPlatformURL)
                editableMetadataRow(label: "Current Link", text: $editedSourceURL)
                editableMetadataRow(label: "Notes", text: $editedNotes)
            } else {
                metadataRow(label: "Platform", value: group.displayName)
                metadataRow(label: "Records", value: "\(group.items.count)")
                metadataRow(label: "Environments", value: group.environments.joined(separator: ", "))
                metadataRow(label: "Usage Logs", value: "\(usageCount(for: group))")
                metadataRow(label: "Bridge", value: appState.bridgeStatusMessage ?? "Bridge unavailable")

                if let item = focusedItem ?? group.items.first {
                    Divider()
                    metadataRow(label: "Page Title", value: item.pageTitle ?? "None")
                    metadataRow(label: "Platform Link", value: item.platformURL ?? "None")
                    metadataRow(label: "Current Link", value: item.sourceURL)
                    metadataRow(label: "Notes", value: item.notes ?? "None")
                }
            }
        }
        .textSelection(.enabled)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
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

            if isCreatingEnvironment {
                ZStack {
                    Text(draftEnvironmentName.isEmpty ? "Empty" : draftEnvironmentName)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .opacity(0)

                    TextField("Empty", text: $draftEnvironmentName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .fixedSize()
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                )
                .focused($focusedField, equals: .environmentName)
                .onSubmit {
                    if let firstRow = draftRows.first {
                        focusedField = .keyName(firstRow.id)
                    }
                }
            } else {
                Button("+") {
                    startDraftEnvironment(for: group)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(showingUsageLogs ? "Usage Logs" : (selectedEnvironment ?? "Keys"))
                    .font(.headline)

                Button {
                    showingUsageLogs.toggle()
                    if !showingUsageLogs {
                        cancelEditingUsageLogs()
                    }
                } label: {
                    Image(systemName: showingUsageLogs ? "key.fill" : "list.bullet.clipboard")
                        .help(showingUsageLogs ? "Show Keys" : "Show Usage Logs")
                }
                .buttonStyle(.bordered)

                Spacer()

                if !showingUsageLogs, !isDraftEnvironmentSelected {
                    Button("-") {
                        removeCurrentEnvironmentDraftRow()
                    }
                    .disabled(currentEnvironmentDraftRows.isEmpty)
                    .buttonStyle(.bordered)

                    Button("+") {
                        addCurrentEnvironmentDraftRow()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let detailError {
                Text(detailError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if showingUsageLogs {
                usageLogSection
            } else if isDraftEnvironmentSelected, let group = selectedGroup {
                draftEnvironmentEditor(for: group)
            } else if visibleItems.isEmpty, currentEnvironmentDraftRows.isEmpty {
                ContentUnavailableView(
                    "No Keys In This Environment",
                    systemImage: "key.viewfinder",
                    description: Text("Use + to add one or more keys inline.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    if !visibleItems.isEmpty {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                                    keyRow(for: item, index: index)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    if !currentEnvironmentDraftRows.isEmpty {
                        currentEnvironmentDraftEditor
                    }
                }
            }

            if !showingUsageLogs {
                HStack {
                    Spacer()

                    if !isDraftEnvironmentSelected, !visibleItems.isEmpty {
                        if isEditingKeys {
                            Button("Cancel") {
                                cancelEditingKeys()
                            }
                            .buttonStyle(.bordered)

                            Button("Save") {
                                saveEditedKeys()
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button("Edit") {
                                startEditingKeys()
                            }
                            .disabled(!appState.unlockManager.isUnlocked)
                            .buttonStyle(.bordered)
                        }
                    }

                    if !isEditingKeys {
                        Button(isDraftEnvironmentSelected ? "Save Environment" : "Save") {
                            if let group = selectedGroup, isDraftEnvironmentSelected {
                                saveDraftEnvironment(for: group)
                            } else if let group = selectedGroup {
                                saveCurrentEnvironmentDraftRows(for: group)
                            }
                        }
                        .disabled(!isDraftEnvironmentSelected && currentEnvironmentDraftRows.isEmpty)
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private var usageLogSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if visibleUsageLogs.isEmpty {
                ContentUnavailableView(
                    "No Usage Logs",
                    systemImage: "list.bullet.clipboard",
                    description: Text("Usage logs are created from the Safari extension.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(visibleUsageLogs, id: \.id) { record in
                            usageLogRow(for: record)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if !visibleUsageLogs.isEmpty {
                HStack {
                    Spacer()

                    if isEditingUsageLogs {
                        Button("Cancel") {
                            cancelEditingUsageLogs()
                        }
                        .buttonStyle(.bordered)

                        Button("Save") {
                            saveEditedUsageLogs()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Edit") {
                            startEditingUsageLogs()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func usageLogRow(for record: UsageLogRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if isEditingUsageLogs {
                editableField(
                    title: "Usage",
                    text: Binding(
                        get: { editedUsage[record.id] ?? record.usage },
                        set: { editedUsage[record.id] = $0 }
                    ),
                    tint: Color.purple.opacity(0.10),
                    border: Color.purple.opacity(0.35)
                )

                editableField(
                    title: "Used Site",
                    text: Binding(
                        get: { editedUsedSite[record.id] ?? record.usedSite },
                        set: { editedUsedSite[record.id] = $0 }
                    ),
                    tint: Color.green.opacity(0.10),
                    border: Color.green.opacity(0.35)
                )

                editableField(
                    title: "Config Link",
                    text: Binding(
                        get: { editedConfigLink[record.id] ?? record.configurationLink ?? "" },
                        set: { editedConfigLink[record.id] = $0 }
                    ),
                    tint: Color(nsColor: .controlBackgroundColor),
                    border: Color(nsColor: .separatorColor)
                )

                editableField(
                    title: "Server IP",
                    text: Binding(
                        get: { editedServerIP[record.id] ?? record.serverIP ?? "" },
                        set: { editedServerIP[record.id] = $0 }
                    ),
                    tint: Color(nsColor: .controlBackgroundColor),
                    border: Color(nsColor: .separatorColor)
                )

                editableField(
                    title: "Notes",
                    text: Binding(
                        get: { editedUsageNotes[record.id] ?? record.notes ?? "" },
                        set: { editedUsageNotes[record.id] = $0 }
                    ),
                    tint: Color(nsColor: .controlBackgroundColor),
                    border: Color(nsColor: .separatorColor)
                )
            } else {
                highlightedField(
                    title: "Usage",
                    value: record.usage,
                    tint: Color.purple.opacity(0.10),
                    border: Color.purple.opacity(0.35),
                    font: .headline
                )

                highlightedField(
                    title: "Used Site",
                    value: record.usedSite,
                    tint: Color.green.opacity(0.10),
                    border: Color.green.opacity(0.35),
                    font: .body
                )

                if let configLink = record.configurationLink, !configLink.isEmpty {
                    highlightedField(
                        title: "Config Link",
                        value: configLink,
                        tint: Color(nsColor: .controlBackgroundColor),
                        border: Color(nsColor: .separatorColor),
                        font: .body
                    )
                }

                if let ip = record.serverIP, !ip.isEmpty {
                    highlightedField(
                        title: "Server IP",
                        value: ip,
                        tint: Color(nsColor: .controlBackgroundColor),
                        border: Color(nsColor: .separatorColor),
                        font: .system(.body, design: .monospaced)
                    )
                }

                if let notes = record.notes, !notes.isEmpty {
                    highlightedField(
                        title: "Notes",
                        value: notes,
                        tint: Color(nsColor: .controlBackgroundColor),
                        border: Color(nsColor: .separatorColor),
                        font: .body
                    )
                }
            }

            HStack(spacing: 10) {
                Text(record.loggedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Delete", role: .destructive) {
                    deleteUsageLog(record)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var newPlatformEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Platform")
                .font(.largeTitle)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 14) {
                editableField(
                    title: "Platform Name",
                    text: $draftPlatformName,
                    tint: Color.orange.opacity(0.14),
                    border: Color.orange.opacity(0.40)
                )
                .focused($focusedField, equals: .platformName)

                editableField(
                    title: "Environment",
                    text: $draftPlatformEnvironment,
                    tint: Color(nsColor: .controlBackgroundColor),
                    border: Color(nsColor: .separatorColor)
                )
            }

            HStack {
                Text("Keys")
                    .font(.headline)

                Spacer()

                Button("-") {
                    guard draftPlatformRows.count > 1 else { return }
                    draftPlatformRows.removeLast()
                }
                .disabled(draftPlatformRows.count <= 1)
                .buttonStyle(.bordered)

                Button("+") {
                    let newRow = DraftKeyRow()
                    draftPlatformRows.append(newRow)
                    DispatchQueue.main.async {
                        focusedField = .keyName(newRow.id)
                    }
                }
                .buttonStyle(.bordered)
            }

            LazyVStack(spacing: 12) {
                ForEach($draftPlatformRows) { $row in
                    draftKeyRowEditor(row: $row)
                }
            }

            if let detailError {
                Text(detailError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    cancelCreatingPlatform()
                }
                .buttonStyle(.bordered)

                Button("Create Platform") {
                    saveNewPlatform()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func startCreatingPlatform() {
        isCreatingPlatform = true
        draftPlatformName = ""
        draftPlatformEnvironment = "Production"
        draftPlatformRows = [DraftKeyRow()]
        detailError = nil

        DispatchQueue.main.async {
            focusedField = .platformName
        }
    }

    private func cancelCreatingPlatform() {
        guard isCreatingPlatform else { return }
        isCreatingPlatform = false
        draftPlatformName = ""
        draftPlatformEnvironment = ""
        draftPlatformRows = [DraftKeyRow()]
        detailError = nil
    }

    private func saveNewPlatform() {
        let platformName = draftPlatformName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !platformName.isEmpty else {
            detailError = "Platform name is required."
            focusedField = .platformName
            return
        }

        let environment = draftPlatformEnvironment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !environment.isEmpty else {
            detailError = "Environment is required."
            return
        }

        guard let populatedRows = validatedRows(from: draftPlatformRows) else { return }

        let drafts = buildDrafts(
            rows: populatedRows,
            providerSlug: nil,
            providerDisplayName: platformName,
            environment: environment,
            platformURL: "",
            sourceURL: "",
            pageTitle: platformName,
            notes: nil
        )

        do {
            try appState.saveManualDrafts(drafts)
            let identity = platformName.lowercased()
            isCreatingPlatform = false
            draftPlatformName = ""
            draftPlatformEnvironment = ""
            draftPlatformRows = [DraftKeyRow()]
            detailError = nil
            selectedProviderIdentity = identity
            selectedEnvironmentName = EnvironmentPreset.canonicalName(for: environment)
            synchronizeSelection()
        } catch {
            detailError = error.localizedDescription
        }
    }

    private func keyRow(for item: VaultItemRecord, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if isEditingKeys {
                editableField(
                    title: "Key name",
                    text: Binding(
                        get: { editedKeyNames[item.id] ?? keyLabel(for: item, index: index) },
                        set: { editedKeyNames[item.id] = $0 }
                    ),
                    tint: Color.orange.opacity(0.14),
                    border: Color.orange.opacity(0.40)
                )

                editableField(
                    title: "Value",
                    text: Binding(
                        get: { editedValues[item.id] ?? revealedSecrets[item.id] ?? "" },
                        set: { editedValues[item.id] = $0 }
                    ),
                    tint: Color.blue.opacity(0.10),
                    border: Color.blue.opacity(0.28),
                    isMonospaced: true
                )
            } else {
                highlightedField(
                    title: "Key name",
                    value: keyLabel(for: item, index: index),
                    tint: Color.orange.opacity(0.16),
                    border: Color.orange.opacity(0.40),
                    font: .headline
                )

                highlightedField(
                    title: "Value",
                    value: displayValue(for: item),
                    tint: Color.blue.opacity(0.10),
                    border: Color.blue.opacity(0.28),
                    font: .system(.body, design: .monospaced)
                )
            }

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
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var currentEnvironmentDraftEditor: some View {
        LazyVStack(spacing: 12) {
            ForEach($currentEnvironmentDraftRows) { $row in
                draftKeyRowEditor(row: $row)
            }
        }
    }

    private func draftEnvironmentEditor(for group: ProviderGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Keys and Values")
                    .font(.headline)

                Spacer()

                Button("-") {
                    removeDraftRow()
                }
                .disabled(draftRows.count <= 1)
                .buttonStyle(.bordered)

                Button("+") {
                    addDraftRow()
                }
                .buttonStyle(.bordered)
            }

            ForEach($draftRows) { $row in
                draftKeyRowEditor(row: $row)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func editableMetadataRow(label: String, text: Binding<String>) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            TextField(label, text: text)
                .textFieldStyle(.plain)
                .font(.callout)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                )
        }
    }

    private func highlightedField(title: String, value: String, tint: Color, border: Color, font: Font) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(font)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(border, lineWidth: 1)
                )
                .textSelection(.enabled)
        }
    }

    private func editableField(title: String, text: Binding<String>, tint: Color, border: Color, isMonospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("", text: text)
                .font(isMonospaced ? .system(.body, design: .monospaced) : .body)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(border, lineWidth: 1)
                )
        }
    }

    private func startEditingKeys() {
        editedKeyNames.removeAll()
        editedValues.removeAll()
        for (index, item) in visibleItems.enumerated() {
            editedKeyNames[item.id] = keyLabel(for: item, index: index)
            editedValues[item.id] = revealedSecrets[item.id] ?? ""
        }
        isEditingKeys = true
        detailError = nil
    }

    private func cancelEditingKeys() {
        isEditingKeys = false
        editedKeyNames.removeAll()
        editedValues.removeAll()
        detailError = nil
    }

    private func saveEditedKeys() {
        do {
            for item in visibleItems {
                if let newName = editedKeyNames[item.id] {
                    let currentName = item.keyName ?? ""
                    if newName != currentName {
                        try appState.updateKeyName(for: item, newName: newName)
                    }
                }
                if let newValue = editedValues[item.id],
                   let originalValue = revealedSecrets[item.id],
                   newValue != originalValue {
                    try appState.updateSecret(for: item, newValue: newValue)
                }
            }
            isEditingKeys = false
            editedKeyNames.removeAll()
            editedValues.removeAll()
            detailError = nil
            refreshVisibleSecrets()
        } catch {
            detailError = error.localizedDescription
        }
    }

    private func startEditingUsageLogs() {
        editedUsage.removeAll()
        editedUsedSite.removeAll()
        editedConfigLink.removeAll()
        editedServerIP.removeAll()
        editedUsageNotes.removeAll()
        for record in visibleUsageLogs {
            editedUsage[record.id] = record.usage
            editedUsedSite[record.id] = record.usedSite
            editedConfigLink[record.id] = record.configurationLink ?? ""
            editedServerIP[record.id] = record.serverIP ?? ""
            editedUsageNotes[record.id] = record.notes ?? ""
        }
        isEditingUsageLogs = true
        detailError = nil
    }

    private func cancelEditingUsageLogs() {
        isEditingUsageLogs = false
        editedUsage.removeAll()
        editedUsedSite.removeAll()
        editedConfigLink.removeAll()
        editedServerIP.removeAll()
        editedUsageNotes.removeAll()
        detailError = nil
    }

    private func saveEditedUsageLogs() {
        do {
            for record in visibleUsageLogs {
                let newUsage = editedUsage[record.id] ?? record.usage
                let newSite = editedUsedSite[record.id] ?? record.usedSite
                let newConfig = editedConfigLink[record.id] ?? record.configurationLink ?? ""
                let newIP = editedServerIP[record.id] ?? record.serverIP ?? ""
                let newNotes = editedUsageNotes[record.id] ?? record.notes ?? ""

                let changed = newUsage != record.usage
                    || newSite != record.usedSite
                    || newConfig != (record.configurationLink ?? "")
                    || newIP != (record.serverIP ?? "")
                    || newNotes != (record.notes ?? "")

                if changed {
                    try appState.updateUsageLog(
                        for: record,
                        usage: newUsage,
                        usedSite: newSite,
                        configurationLink: newConfig,
                        serverIP: newIP,
                        notes: newNotes
                    )
                }
            }
            cancelEditingUsageLogs()
        } catch {
            detailError = error.localizedDescription
        }
    }

    private func deleteUsageLog(_ record: UsageLogRecord) {
        do {
            try appState.deleteUsageLog(record)
            detailError = nil
        } catch {
            detailError = error.localizedDescription
        }
    }

    private func startEditingMetadata(for item: VaultItemRecord, group: ProviderGroup) {
        editedProviderName = group.displayName
        editedEnvironment = item.environmentName
        editedKeyName = item.keyName ?? ""
        editedPageTitle = item.pageTitle ?? ""
        editedPlatformURL = item.platformURL ?? ""
        editedSourceURL = item.sourceURL
        editedNotes = item.notes ?? ""
        isEditingMetadata = true
    }

    private func cancelEditingMetadata() {
        isEditingMetadata = false
        detailError = nil
    }

    private func saveEditedMetadata() {
        guard let item = focusedItem ?? selectedGroup?.items.first else { return }
        do {
            try appState.updateMetadata(
                for: item,
                providerDisplayName: editedProviderName,
                environment: editedEnvironment,
                keyName: editedKeyName,
                platformURL: editedPlatformURL,
                sourceURL: editedSourceURL,
                pageTitle: editedPageTitle,
                notes: editedNotes
            )
            isEditingMetadata = false
            detailError = nil
        } catch {
            detailError = error.localizedDescription
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

        revealedSecrets = (try? appState.revealSecrets(for: visibleItems)) ?? [:]
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

    private func startDraftEnvironment(for group: ProviderGroup) {
        isCreatingEnvironment = true
        draftEnvironmentName = ""
        draftRows = [DraftKeyRow()]
        selectedProviderIdentity = group.id
        selectedEnvironmentName = Self.draftEnvironmentSelectionID
        selectedID = nil
        detailError = nil

        DispatchQueue.main.async {
            focusedField = .environmentName
        }
    }

    private func cancelDraftEnvironment() {
        guard isCreatingEnvironment else { return }
        isCreatingEnvironment = false
        draftEnvironmentName = ""
        draftRows = [DraftKeyRow()]
        focusedField = nil
        detailError = nil
    }

    private func addDraftRow() {
        let newRow = DraftKeyRow()
        draftRows.append(newRow)
        DispatchQueue.main.async {
            focusedField = .keyName(newRow.id)
        }
    }

    private func removeDraftRow() {
        guard draftRows.count > 1 else { return }
        draftRows.removeLast()
    }

    private func addCurrentEnvironmentDraftRow() {
        let newRow = DraftKeyRow()
        currentEnvironmentDraftRows.append(newRow)
        detailError = nil

        DispatchQueue.main.async {
            focusedField = .keyName(newRow.id)
        }
    }

    private func removeCurrentEnvironmentDraftRow() {
        guard currentEnvironmentDraftRows.count > 1 else {
            currentEnvironmentDraftRows.removeAll()
            detailError = nil
            return
        }

        currentEnvironmentDraftRows.removeLast()
    }

    private func saveDraftEnvironment(for group: ProviderGroup) {
        let environmentName = draftEnvironmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !environmentName.isEmpty else {
            detailError = "Give the new tab an environment name."
            focusedField = .environmentName
            return
        }

        guard let populatedRows = validatedRows(from: draftRows) else { return }

        let sourceItem = focusedItem ?? group.items.first
        let canonicalEnvironment = EnvironmentPreset.canonicalName(for: environmentName)

        let drafts = buildDrafts(
            rows: populatedRows,
            providerSlug: sourceItem?.providerSlug,
            providerDisplayName: group.displayName,
            environment: canonicalEnvironment,
            platformURL: sourceItem?.platformURL ?? "",
            sourceURL: sourceItem?.sourceURL ?? (sourceItem?.platformURL ?? ""),
            pageTitle: sourceItem?.pageTitle ?? group.displayName,
            notes: sourceItem?.notes
        )

        do {
            try appState.saveManualDrafts(drafts)
            isCreatingEnvironment = false
            draftEnvironmentName = ""
            draftRows = [DraftKeyRow()]
            focusedField = nil
            detailError = nil
            selectedEnvironmentName = canonicalEnvironment
            synchronizeSelection()
        } catch {
            detailError = error.localizedDescription
        }
    }

    private func saveCurrentEnvironmentDraftRows(for group: ProviderGroup) {
        guard let selectedEnvironment else {
            detailError = "Select an environment before saving keys."
            return
        }

        guard let populatedRows = validatedRows(from: currentEnvironmentDraftRows) else { return }

        let sourceItem = focusedItem ?? visibleItems.first ?? group.items.first

        let drafts = buildDrafts(
            rows: populatedRows,
            providerSlug: sourceItem?.providerSlug,
            providerDisplayName: group.displayName,
            environment: selectedEnvironment,
            platformURL: sourceItem?.platformURL ?? "",
            sourceURL: sourceItem?.sourceURL ?? (sourceItem?.platformURL ?? ""),
            pageTitle: sourceItem?.pageTitle ?? group.displayName,
            notes: sourceItem?.notes
        )

        do {
            try appState.saveManualDrafts(drafts)
            currentEnvironmentDraftRows.removeAll()
            detailError = nil
            synchronizeSelection()
        } catch {
            detailError = error.localizedDescription
        }
    }

    private func synchronizeSelection() {
        if let group = selectedGroup {
            selectedProviderIdentity = group.id
        } else {
            selectedProviderIdentity = nil
        }

        if isDraftEnvironmentSelected {
            selectedID = nil
            return
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

    private func resetCurrentEnvironmentDraftRows() {
        currentEnvironmentDraftRows.removeAll()
        focusedField = nil
    }

    private func usageCount(for group: ProviderGroup) -> Int {
        usageLogs.filter { $0.sourceProviderIdentity == group.id }.count
    }

    private func draftKeyRowEditor(row: Binding<DraftKeyRow>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            editableField(
                title: "Key name",
                text: row.keyName,
                tint: Color.orange.opacity(0.14),
                border: Color.orange.opacity(0.40)
            )
            .focused($focusedField, equals: .keyName(row.wrappedValue.id))

            editableField(
                title: "Value",
                text: row.value,
                tint: Color.blue.opacity(0.10),
                border: Color.blue.opacity(0.28),
                isMonospaced: true
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func validatedRows(from rows: [DraftKeyRow]) -> [DraftKeyRow]? {
        let populated = rows.filter {
            !$0.keyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard !populated.isEmpty else {
            detailError = "Add at least one key and value."
            return nil
        }

        if populated.contains(where: {
            $0.keyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            detailError = "Every row needs both a key name and value."
            return nil
        }

        return populated
    }

    private func buildDrafts(
        rows: [DraftKeyRow],
        providerSlug: String?,
        providerDisplayName: String,
        environment: String,
        platformURL: String,
        sourceURL: String,
        pageTitle: String,
        notes: String?
    ) -> [CaptureDraft] {
        let now = Date()
        return rows.map { row in
            CaptureDraft(
                providerSlug: providerSlug,
                providerDisplayName: providerDisplayName,
                keyName: row.keyName.trimmingCharacters(in: .whitespacesAndNewlines),
                apiKey: row.value.trimmingCharacters(in: .whitespacesAndNewlines),
                platformURL: platformURL,
                sourceURL: sourceURL,
                pageTitle: pageTitle,
                notes: notes,
                environment: environment,
                capturedAt: now
            )
        }
    }
}
