import SwiftUI

/// Walks the user through exporting a Google Timeline JSON file — the app has no access to their
/// Google account, so this is the one manual step they have to do themselves.
struct HowToExportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var platform: Platform = .iPhone

    private enum Platform: String, CaseIterable, Identifiable {
        case iPhone = "iPhone / iPad"
        case android = "Android"
        var id: String { rawValue }
    }

    private struct Step: Identifiable {
        var id: Int
        var icon: String
        var text: String
    }

    private var iPhoneSteps: [Step] {
        [
            Step(id: 1, icon: "map", text: "Open **Google Maps**"),
            Step(id: 2, icon: "person.crop.circle", text: "Tap your profile picture, then **Settings**"),
            Step(id: 3, icon: "person.text.rectangle", text: "Tap **Personal content**, then **Export Timeline data**"),
            Step(id: 4, icon: "square.and.arrow.down", text: "Save the JSON file — to Files or iCloud Drive works well"),
            Step(id: 5, icon: "square.and.arrow.up.on.square", text: "Come back here and tap **Import Timeline.json** to pick that file"),
        ]
    }

    private var androidSteps: [Step] {
        [
            Step(id: 1, icon: "gearshape", text: "Open **Phone Settings → Location → Location services → Timeline**"),
            Step(id: 2, icon: "square.and.arrow.down", text: "Tap **Export Timeline data** and save the JSON file"),
            Step(id: 3, icon: "arrow.triangle.2.circlepath", text: "AirDrop, email, or cloud-sync that file over to this iPhone"),
            Step(id: 4, icon: "square.and.arrow.up.on.square", text: "Come back here and tap **Import Timeline.json** to pick it"),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Getting your Timeline file")
                            .font(.title2.bold())
                        Text("This app has no access to your Google account — you export the file yourself, once, and import it here. Nothing is uploaded anywhere.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Platform", selection: $platform) {
                        ForEach(Platform.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(platform == .iPhone ? iPhoneSteps : androidSteps) { step in
                            HStack(alignment: .top, spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.15))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: step.icon)
                                        .foregroundStyle(Color.accentColor)
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                Text(.init(step.text))
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 6)
                            }
                        }
                    }

                    if platform == .iPhone {
                        calloutBox(
                            icon: "clock.arrow.circlepath",
                            text: "Missing older trips? You likely need to restore a Timeline backup in Google Maps first — search “restore Google Maps Timeline” in Google's help center for the current steps."
                        )
                    }

                    calloutBox(
                        icon: "lock.shield",
                        text: "Everything after import happens on this device. The app only reaches out to the public map-tile service (to draw the basemap) and Apple's geocoding service (to resolve city names)."
                    )
                }
                .padding()
            }
            .navigationTitle("How to Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func calloutBox(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
