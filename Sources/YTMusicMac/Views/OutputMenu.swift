import SwiftUI
import AVKit

/// Player-bar button that lists where the sound can go: this Mac's outputs and AirPlay.
struct OutputButton: View {
    @ViewState var open = false

    var body: some View {
        let outputs = AudioOutputs.shared
        ToolbarIconButton(system: "airplayaudio", size: 14, active: outputs.activeUID != nil,
                          help: "Ses çıkışı") { open.toggle() }
            .popover(isPresented: $open, arrowEdge: .top) { OutputList() }
    }
}

private struct OutputList: View {
    var body: some View {
        let outputs = AudioOutputs.shared
        VStack(alignment: .leading, spacing: 2) {
            Text("Bu Mac'te")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 2)
            OutputRow(symbol: "gearshape", title: "Sistem çıkışı", detail: outputs.systemName,
                      selected: outputs.chosenUID == nil) { outputs.choose(nil) }
            ForEach(outputs.devices) { device in
                OutputRow(symbol: device.kind.symbol, title: device.name, detail: nil,
                          selected: outputs.chosenUID == device.uid) { outputs.choose(device) }
            }
            if outputs.chosenUID != nil, outputs.activeUID == nil {
                Text("\(outputs.chosenName ?? "Seçilen cihaz") bağlı değil; bağlanana kadar sistem çıkışı kullanılıyor.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
            }
            Divider().padding(.vertical, 6)
            HStack(spacing: 10) {
                Image(systemName: "airplayaudio")
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("AirPlay").font(.system(size: 13))
                    Text("Apple TV, HomePod, AirPlay destekli TV ve hoparlörler")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                AirPlayButton()
                    .frame(width: 30, height: 30)
                    .help("AirPlay cihazı seç")
            }
            .padding(.horizontal, 8)
        }
        .padding(10)
        .frame(width: 300)
    }
}

private struct OutputRow: View {
    let symbol: String
    let title: String
    let detail: String?
    let selected: Bool
    let action: () -> Void
    @ViewState var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(selected ? Color.brand : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13)).lineLimit(1)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.brand)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hover ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// The system AirPlay menu. It is given no player on purpose: on macOS a picker tied to
/// a player ignores the choice, while a free one routes the app's sound.
struct AirPlayButton: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView(frame: .zero)
        picker.isRoutePickerButtonBordered = false
        return picker
    }

    func updateNSView(_ picker: AVRoutePickerView, context: Context) {}
}
