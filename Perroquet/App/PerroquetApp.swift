import SwiftUI

/// Application entry point: a menu bar item plus a single main window.
@main
struct PerroquetApp: App {
    @State private var transcriber: Transcriber
    @State private var permissions: Permissions
    @State private var controller: DictationController
    @State private var annotation: AnnotationStore
    @State private var validated: ValidatedStore
    @State private var microphone: MicrophoneSelection
    @State private var launchAtLogin: LaunchAtLogin
    @State private var navigation = MainNavigation()

    init() {
        let dataset = DatasetStore()
        let transcriber = Transcriber()
        let microphone = MicrophoneSelection()
        let recorder = AudioRecorder(selectedUID: { microphone.selectedUID })
        microphone.onSelect = { Task { recorder.prepare() } }
        let controller = DictationController(
            recorder: recorder,
            transcriber: transcriber,
            paster: Paster.system(),
            store: dataset)
        _transcriber = State(initialValue: transcriber)
        let permissions = Permissions()
        permissions.onGranted = {
            recorder.prepare()
            MainWindowPresenter.bringToFront()
        }
        _permissions = State(initialValue: permissions)
        _controller = State(initialValue: controller)
        _microphone = State(initialValue: microphone)
        _launchAtLogin = State(initialValue: LaunchAtLogin())
        _annotation = State(initialValue: AnnotationStore(dataset: dataset))
        _validated = State(initialValue: ValidatedStore(dataset: dataset))

        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            DictationHotkey.install(for: controller)
            // Deferred: a cold audio stack can take over a second, which must not hold up the launch.
            Task { recorder.prepare() }
            Task { await transcriber.load() }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environment(controller)
                .environment(transcriber)
                .environment(navigation)
        } label: {
            MenuBarLabel(icon: controller.menuBarIcon)
        }
        .menuBarExtraStyle(.menu)

        Window(Bundle.main.appName, id: MainWindow.id) {
            MainWindow()
                .environment(controller)
                .environment(transcriber)
                .environment(permissions)
                .environment(microphone)
                .environment(launchAtLogin)
                .environment(annotation)
                .environment(validated)
                .environment(navigation)
        }
        .defaultSize(width: 900, height: 600)
        .commands { SettingsCommand(navigation: navigation) }
    }
}
