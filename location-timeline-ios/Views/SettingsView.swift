import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultCameraMovement") private var defaultCameraMovementRaw = CameraMovement.dynamic.rawValue
    @AppStorage("defaultQuality") private var defaultQualityRaw = VideoQuality.p1080.rawValue
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.kilometers.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section("Defaults for new videos") {
                    Picker("Camera movement", selection: $defaultCameraMovementRaw) {
                        ForEach(CameraMovement.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Picker("Quality", selection: $defaultQualityRaw) {
                        ForEach(VideoQuality.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Picker("Distance unit", selection: $distanceUnitRaw) {
                        ForEach(DistanceUnit.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                }
                Section {
                    Text("Timeline data is processed entirely on this device. Nothing is uploaded anywhere except the public map tile service used to draw the basemap.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
