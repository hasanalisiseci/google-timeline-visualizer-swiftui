import SwiftUI
import UniformTypeIdentifiers

/// Import a Timeline.json export, pick a date range and style, then hand off to export.
struct NewVideoView: View {
    @EnvironmentObject private var library: VideoLibrary
    @AppStorage("defaultCameraMovement") private var defaultCameraMovementRaw = CameraMovement.dynamic.rawValue
    @AppStorage("defaultQuality") private var defaultQualityRaw = VideoQuality.p1080.rawValue

    @State private var isImporting = false
    @State private var allPoints: [GeoPoint] = []
    @State private var months: [MonthOption] = []
    @State private var startMonth = ""
    @State private var endMonth = ""
    @State private var title = "My Journey"
    @State private var cameraMovement: CameraMovement = .dynamic
    @State private var quality: VideoQuality = .p1080
    @State private var speed: VideoSpeed = .normal
    @State private var errorMessage: String?
    @State private var exportRequest: VideoExportRequest?

    var body: some View {
        NavigationStack {
            Form {
                Section("Timeline data") {
                    Button(allPoints.isEmpty ? "Import Timeline.json" : "Re-import Timeline.json") {
                        isImporting = true
                    }
                    if !allPoints.isEmpty {
                        Text("\(allPoints.count) location points loaded")
                            .foregroundStyle(.secondary)
                    }
                }

                if !months.isEmpty {
                    Section("Date range") {
                        Picker("From", selection: $startMonth) {
                            ForEach(months) { Text($0.label).tag($0.key) }
                        }
                        Picker("To", selection: $endMonth) {
                            ForEach(months) { Text($0.label).tag($0.key) }
                        }
                    }

                    Section("Style") {
                        TextField("Title", text: $title)
                        Picker("Camera", selection: $cameraMovement) {
                            ForEach(CameraMovement.allCases) { Text($0.label).tag($0) }
                        }
                        Picker("Quality", selection: $quality) {
                            ForEach(VideoQuality.allCases) { Text($0.label).tag($0) }
                        }
                        Picker("Speed", selection: $speed) {
                            ForEach(VideoSpeed.allCases) { Text($0.label).tag($0) }
                        }
                    }

                    Section {
                        Button("Create Video") { prepareExport() }
                    }
                }
            }
            .navigationTitle("New Video")
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .alert("Couldn't load Timeline data", isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
                Button("OK") { errorMessage = nil }
            } message: { message in
                Text(message)
            }
            .fullScreenCover(item: $exportRequest) { request in
                ExportProgressView(request: request) { exportRequest = nil }
            }
            .onAppear {
                cameraMovement = CameraMovement(rawValue: defaultCameraMovementRaw) ?? .dynamic
                quality = VideoQuality(rawValue: defaultQualityRaw) ?? .p1080
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let url):
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let json = try JSONSerialization.jsonObject(with: data)
                let points = try TimelineParser.parseTimelineJson(json)
                allPoints = points
                months = TimelineParser.availableMonths(points)
                startMonth = months.first?.key ?? ""
                endMonth = months.last?.key ?? ""
            } catch let parseError as TimelineParseError {
                errorMessage = parseError.message
            } catch {
                errorMessage = "This file isn't valid JSON."
            }
        }
    }

    private func prepareExport() {
        let selected = TimelineParser.selectRange(allPoints, startMonth: startMonth, endMonth: endMonth)
        guard let journey = Journey.prepare(points: selected, size: Double(quality.pixelSize), cameraMovement: cameraMovement) else {
            errorMessage = "No points in the selected range."
            return
        }
        let periodLabel = startMonth == endMonth
            ? (months.first { $0.key == startMonth }?.label ?? "")
            : "\(months.first { $0.key == startMonth }?.label ?? startMonth) – \(months.first { $0.key == endMonth }?.label ?? endMonth)"
        exportRequest = VideoExportRequest(journey: journey, title: title, periodLabel: periodLabel, quality: quality, cameraMovement: cameraMovement, speed: speed)
    }
}

extension VideoExportRequest: Identifiable {
    var id: String { title + periodLabel + quality.rawValue + speed.rawValue }
}
