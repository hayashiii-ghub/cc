import AppKit
import SwiftUI

@MainActor
struct ShelfOpeningSettings: View {
    @ObservedObject var preferences: ShelfOpenPreferences
    @State private var applications: [String: [ShelfOpenApplication]] = [:]
    @State private var isChoosingApplication = false

    var body: some View {
        Section {
            ForEach(ShelfOpenCategory.allCases) { category in
                openingRow(for: category)
            }
        } header: {
            Text("Open Items")
        } footer: {
            Text(usesFinder
                ? "Finder shows files in their folder. These choices apply only in cc:."
                : "These choices apply only in cc:.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(isChoosingApplication)
        .onAppear {
            applications = Dictionary(uniqueKeysWithValues: ShelfOpenCategory.allCases.map {
                ($0.rawValue, ShelfOpeningApplications.candidates(for: $0))
            })
        }
    }

    private var usesFinder: Bool {
        ShelfOpenCategory.allCases.contains { preferences.destination(for: $0) == .finder }
    }

    private func openingRow(for category: ShelfOpenCategory) -> some View {
        let options = applications(for: category)
        return LabeledContent(category.title) {
            Menu {
                Picker(category.title, selection: selection(for: category, applications: options)) {
                    Text("macOS Default").tag("systemDefault")
                    if category != .webLinks {
                        Text("Finder").tag("finder")
                    }
                    if !options.isEmpty {
                        Divider()
                        ForEach(options, id: \.url) { application in
                            Text(ShelfOpeningApplications.displayName(for: application))
                                .tag(selectionID(for: application))
                        }
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Divider()
                Button("Choose Application") {
                    chooseApplication(for: category)
                }
            } label: {
                Text(destinationTitle(for: category))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .menuStyle(.borderedButton)
            .frame(width: 180)
            .accessibilityLabel(category.title)
            .accessibilityValue(destinationTitle(for: category))
        }
    }

    private func applications(for category: ShelfOpenCategory) -> [ShelfOpenApplication] {
        var options = applications[category.rawValue] ?? []
        if case let .application(current) = preferences.destination(for: category),
           !options.contains(where: { $0.url == current.url }) {
            options.insert(current, at: 0)
        }
        return options
    }

    private func destinationTitle(for category: ShelfOpenCategory) -> String {
        switch preferences.destination(for: category) {
        case .systemDefault: "macOS Default"
        case .finder: "Finder"
        case let .application(application): ShelfOpeningApplications.displayName(for: application)
        }
    }

    private func selection(for category: ShelfOpenCategory, applications: [ShelfOpenApplication]) -> Binding<String> {
        Binding {
            switch preferences.destination(for: category) {
            case .systemDefault: "systemDefault"
            case .finder: "finder"
            case let .application(application): selectionID(for: application)
            }
        } set: { value in
            switch value {
            case "systemDefault":
                preferences.reset(for: category)
            case "finder":
                preferences.setDestination(.finder, for: category)
            default:
                if let application = applications.first(where: { selectionID(for: $0) == value }) {
                    preferences.setDestination(.application(application), for: category)
                }
            }
        }
    }

    private func selectionID(for application: ShelfOpenApplication) -> String {
        "application:\(application.url.absoluteString)"
    }

    private func chooseApplication(for category: ShelfOpenCategory) {
        guard !isChoosingApplication else { return }
        isChoosingApplication = true
        // Let menu tracking finish before entering the application's modal panel.
        DispatchQueue.main.async {
            defer { isChoosingApplication = false }
            let current: ShelfOpenApplication?
            if case let .application(application) = preferences.destination(for: category) {
                current = application
            } else {
                current = nil
            }
            guard let application = ShelfApplicationPicker().chooseApplication(
                for: category, currentApplication: current
            ) else { return }
            preferences.setDestination(.application(application), for: category)
        }
    }
}
