import AppKit
import SwiftUI

@MainActor
struct ShelfOpeningSettings: View {
    @ObservedObject var preferences: ShelfOpenPreferences
    @State private var applications: [String: [ShelfOpenApplication]] = [:]
    @State private var isChoosingApplication = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Open with")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 4)

            ForEach(ShelfOpenCategory.allCases) { category in
                openingRow(for: category)
            }
        }
        .disabled(isChoosingApplication)
        .onAppear {
            applications = Dictionary(uniqueKeysWithValues: ShelfOpenCategory.allCases.map {
                ($0.rawValue, ShelfOpeningApplications.candidates(for: $0))
            })
        }
    }

    private func openingRow(for category: ShelfOpenCategory) -> some View {
        let options = applications(for: category)
        return HStack {
            Text(categoryTitle(category))
            Spacer(minLength: 12)
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
            .controlSize(.large)
            .buttonSizing(.flexible)
            .frame(width: 180, height: 28, alignment: .trailing)
            .accessibilityLabel(category.title)
            .accessibilityValue(destinationTitle(for: category))
        }
        .frame(minHeight: 32)
    }

    private func categoryTitle(_ category: ShelfOpenCategory) -> String {
        switch category {
        case .textAndCode: "Text & code"
        case .imagesAndPDFs: "Images & PDFs"
        case .folders: "Folders"
        case .webLinks: "Web links"
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
