import SwiftUI

/// Application entry point: a menu bar item plus a single main window.
@main
struct PerroquetApp: App {
    @State private var transcriber: Transcriber
    @State private var permissions: Permissions
    @State private var controller: DictationController
    @State private var annotation: AnnotationStore

    init() {
        let dataset = DatasetStore()
        let transcriber = Transcriber()
        let controller = DictationController(
            recorder: AudioRecorder(),
            transcriber: transcriber,
            paster: Paster.system(),
            store: dataset)
        _transcriber = State(initialValue: transcriber)
        let permissions = Permissions()
        permissions.onGranted = { MainWindowPresenter.bringToFront() }
        _permissions = State(initialValue: permissions)
        _controller = State(initialValue: controller)
        _annotation = State(initialValue: AnnotationStore(dataset: dataset))

        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            DictationHotkey.install(for: controller)
            Task { await transcriber.load() }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environment(controller)
        } label: {
            Image(systemName: controller.state.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Window("Perroquet", id: MainWindow.id) {
            MainWindow()
                .environment(controller)
                .environment(transcriber)
                .environment(permissions)
                .environment(annotation)
        }
        .defaultSize(width: 900, height: 600)
    }
}
