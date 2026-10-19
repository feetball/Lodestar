import SwiftUI

/// In the star alignment sheet, while a GoTo mount is connected: the choice to sync the mount to the same star, and the
/// outcome of that sync. The camera sits on the mount, so the star that is centred for the phone's alignment is centred
/// for the mount as well.
struct MountAlignmentSyncRow: View {
    @Binding var isOn: Bool
    let objectName: String
    @Environment(\.palette) private var palette
    private var service: MountService { MountService.shared }

    var body: some View {
        if service.isConnected, service.capabilities?.canSync == true {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Also sync the mount to \(objectName)", isOn: $isOn)
                    .font(.subheadline)
                    .disabled(service.status.phase != .idle)
                if let text = service.errorText {
                    Label(text, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let text = service.noticeText {
                    Label(text, systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.positive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
