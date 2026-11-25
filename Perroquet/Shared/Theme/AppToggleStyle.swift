import SwiftUI

/// Switch that is parrot green when on and gray when off.
struct AppToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            Button {
                configuration.isOn.toggle()
            } label: {
                Capsule()
                    .fill(configuration.isOn ? AppColors.accent : AppColors.button)
                    .frame(width: 34, height: 20)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(configuration.isOn ? AppColors.accentMuted : AppColors.textSecondary)
                            .padding(3)
                    }
            }
            .buttonStyle(.plain)
            .opacity(isEnabled ? 1 : 0.45)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
            }
        }
    }
}

extension ToggleStyle where Self == AppToggleStyle {
    static var app: AppToggleStyle { AppToggleStyle() }
}

#Preview("Toggles") {
    VStack(spacing: 12) {
        Toggle(isOn: .constant(true)) { Text(verbatim: "On") }
        Toggle(isOn: .constant(false)) { Text(verbatim: "Off") }
    }
    .toggleStyle(.app)
    .foregroundStyle(AppColors.text)
    .frame(width: 240)
    .padding(16)
    .background(AppColors.background)
}
