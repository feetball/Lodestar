import SwiftUI
import UIKit
import LodestarKit

/// Settings ▸ Mount Control (also shown from the Aim screen): choose the kind of mount and its address, connect, see
/// what the mount can do, and set the limits and safety rules for slewing.
struct MountConnectionView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    private var service: MountService { MountService.shared }

    var body: some View {
        Form {
            MountStatusSection()
            switch service.connection {
            case .connected:
                if service.usesLodestarAlignment {
                    SettingsSection(title: "Set up this mount", footer: MountSkyWatcherSetupRows.footer) {
                        MountSkyWatcherSetupRows(onSync: nil)
                    }
                }
                MountControlsSection()
            case .connecting:
                EmptyView()
            case .disconnected, .lost:
                MountTypeSection()
                MountAddressSection()
                if service.selectedOption.discovery != nil {
                    MountDiscoverySection()
                }
                if service.selectedOption.usesLodestarAlignment {
                    SettingsSection(title: "Home Position") {
                        MountHomeGuide(arrangement: service.settings.arrangement)
                    }
                }
                MountConnectSection()
            }
            MountLimitsSection()
            MountAdvancedSection()
            MountSafetySection()
        }
        .themedList(palette)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Mount Control")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { service.updateObserver(app.observerContext?.observer) }
        .onDisappear { service.cancelDiscovery() }
    }
}

// MARK: - Status

/// The connection at a glance, with Connect's counterpart: Cancel while connecting, Reconnect after a loss, Disconnect.
private struct MountStatusSection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    private var service: MountService { MountService.shared }

    var body: some View {
        SettingsSection(title: "Mount") {
            switch service.connection {
            case .disconnected:
                disconnectedRows
            case .connecting:
                connectingRows
            case .connected:
                connectedRows
            case .lost(let reason):
                lostRows(reason)
            }
            problemRows
        }
    }

    private var disconnectedRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatusChip(systemImage: "antenna.radiowaves.left.and.right.slash", text: "Not connected")
                Spacer(minLength: 0)
            }
            SettingsCaption("Connect to a computerised telescope mount over Wi-Fi. Then the Aim screen can slew it to "
                            + "your target, sync it, nudge it and stop it.")
        }
    }

    private var connectingRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(palette.accent)
                Text("Connecting to \(service.displayName)\u{2026}")
                    .foregroundStyle(palette.primaryText)
                Spacer(minLength: 0)
            }
            SettingsCaption("This can take a few seconds. The first time, iOS asks whether Lodestar may use the local "
                            + "network: tap Allow.")
            Button("Cancel") { service.cancelConnect() }
                .buttonStyle(.lodestarSecondary)
        }
    }

    private func lostRows(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatusChip(systemImage: "wifi.exclamationmark", text: "Connection lost", tone: .critical)
                Spacer(minLength: 0)
            }
            // The reason itself says whether the mount may still be moving (`MountService` words it where the loss is found).
            Text(reason)
                .font(.subheadline)
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var connectedRows: some View {
        let status = service.status
        HStack {
            StatusChip(systemImage: "checkmark.seal", text: service.isDemo ? "Demo mount" : "Connected", tone: .positive)
            Spacer(minLength: 0)
        }
        InfoRow(label: "Mount", value: service.displayName)
        if let option = service.connectedOption, !service.isDemo {
            InfoRow(label: "Type", value: option.title)
        }
        if let address = service.connectedAddress {
            InfoRow(label: "Address", value: address)
        }
        if let capabilities = service.capabilities {
            InfoRow(label: "Firmware", value: capabilities.firmware ?? AppFormat.missing)
            InfoRow(label: "Lodestar can", value: MountStatusText.capabilities(capabilities))
        }
        if let position = status.position {
            InfoRow(label: "Pointing", value: MountStatusText.pointing(position, style: app.settings.coordinateStyle))
        }
        InfoRow(label: "State", value: MountStatusText.phaseLine(status, targetName: service.slewTargetName))
        if let line = service.alignmentLine {
            InfoRow(label: "Alignment", value: line)
        }
        if let side = service.pierSideLine {
            InfoRow(label: "Pier side", value: side)
        }
        if service.usesLodestarAlignment, let tracking = service.trackingLine {
            InfoRow(label: "Tracking", value: tracking)
        }
        if let warning = service.alignmentWarning ?? (service.needsFirstSync ? MountAlignmentText.notAlignedYet : nil) {
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let stop = service.trackingStopText {
            Label(stop, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
        MountMessages()
        MountStopButton(minHeight: 52)
        Button {
            service.disconnect()
        } label: {
            Label("Disconnect", systemImage: "xmark.circle")
                .foregroundStyle(palette.critical)
        }
        SettingsCaption("Disconnecting stops the mount first if it is moving.")
    }

    /// What went wrong with the last attempt, and what to try.
    @ViewBuilder
    private var problemRows: some View {
        if service.connection != .connected, let text = service.errorText {
            VStack(alignment: .leading, spacing: 8) {
                Label(text, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = service.connectError, let advice = MountStatusText.connectionAdvice(for: error) {
                    SettingsCaption(advice)
                }
                if service.connectError?.isCommunicationFailure == true {
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}

// MARK: - Connecting

/// Which kind of mount: one row each, with a line about it.
private struct MountTypeSection: View {
    @Environment(\.palette) private var palette
    private var service: MountService { MountService.shared }

    var body: some View {
        SettingsSection(title: "Mount Type",
                        footer: "Join the mount's Wi-Fi network in the iOS Settings app first. A mount's own network has "
                            + "no internet, which is fine: Lodestar talks to the mount directly.") {
            ForEach(MountConnectionOption.all) { option in
                let isSelected = option.id == service.selectedOption.id
                Button {
                    service.selectedOptionID = option.id
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.title)
                                .font(.body.weight(.medium))
                                .foregroundStyle(palette.primaryText)
                            Text(option.summary)
                                .font(.footnote)
                                .foregroundStyle(palette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? palette.accent : palette.tertiaryText)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// The host and the port, with the usual addresses one tap away.
private struct MountAddressSection: View {
    @Environment(\.palette) private var palette
    private var service: MountService { MountService.shared }

    var body: some View {
        let option = service.selectedOption
        SettingsSection(title: "Address", footer: option.addressNote) {
            HStack(spacing: 8) {
                Text("Address")
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                TextField("Address", text: hostBinding,
                          prompt: Text(option.defaultHost.isEmpty ? "192.168.1.20" : option.defaultHost)
                              .foregroundStyle(palette.tertiaryText))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(palette.primaryText)
            }
            HStack(spacing: 8) {
                Text("Port")
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                TextField("Port", text: portBinding, prompt: Text(String(option.defaultPort)).foregroundStyle(palette.tertiaryText))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(palette.primaryText)
                    .frame(maxWidth: 120)
            }
            if option.links.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connection")
                        .accessibilityHidden(true)
                    Picker("Connection", selection: linkBinding) {
                        ForEach(option.links) { link in
                            Text(link.title).tag(link)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            if !option.presets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Usual addresses")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                    AimFlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(option.presets) { preset in
                            Button(preset.title) { apply(preset) }
                                .buttonStyle(.lodestarSecondary)
                        }
                    }
                }
            }
        }
    }

    private func apply(_ preset: MountConnectionPreset) {
        service.updateForm { form in
            if let host = preset.host { form.host = host }
            form.port = preset.port
            form.link = preset.link
            form.deviceName = nil
            form.deviceNumber = 0
        }
    }

    private var hostBinding: Binding<String> {
        Binding(get: { service.form.host }, set: { text in
            service.updateForm { form in
                form.host = text
                form.deviceName = nil
                form.deviceNumber = 0
            }
        })
    }

    private var portBinding: Binding<String> {
        Binding(get: { service.form.port > 0 ? String(service.form.port) : "" }, set: { text in
            let digits = text.filter { $0.isASCII && $0.isNumber }
            service.updateForm { form in
                form.port = Int(digits.prefix(5)) ?? 0
                form.deviceName = nil
                form.deviceNumber = 0
            }
        })
    }

    private var linkBinding: Binding<MountLinkKind> {
        Binding(get: { service.form.link }, set: { link in
            service.updateForm { $0.link = link }
        })
    }
}

/// "Find Alpaca devices": looks on the Wi-Fi network and lists the telescopes that answer.
private struct MountDiscoverySection: View {
    @Environment(\.palette) private var palette
    private var service: MountService { MountService.shared }

    var body: some View {
        if let kind = service.selectedOption.discovery {
            SettingsSection(title: kind.sectionTitle, footer: kind.footer) {
                Button {
                    service.startDiscovery()
                } label: {
                    HStack {
                        Label(kind.buttonTitle, systemImage: "magnifyingglass")
                        Spacer(minLength: 0)
                        if service.discoveryState == .searching {
                            ProgressView()
                                .tint(palette.accent)
                        }
                    }
                }
                .disabled(service.discoveryState == .searching)
                ForEach(service.discovered) { device in
                    deviceRow(device, kind: kind)
                }
                if case .finished(let servers, let devices) = service.discoveryState {
                    SettingsCaption(kind.summary(servers: servers, devices: devices))
                }
            }
        }
    }

    private func deviceRow(_ device: MountFoundDevice, kind: MountDiscoveryKind) -> some View {
        let form = service.form
        let isSelected = form.host == device.host && form.port == device.port
            && form.deviceNumber == device.deviceNumber && form.deviceName != nil
        let detail: String
        switch kind {
        case .alpaca: detail = "\(device.addressText) \u{00B7} device \(device.deviceNumber)"
        case .skyWatcher: detail = device.addressText
        }
        return Button {
            service.choose(device)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.primaryText)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? palette.accent : palette.tertiaryText)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The Connect button, and the way to try everything without a mount.
private struct MountConnectSection: View {
    @Environment(AppModel.self) private var app
    private var service: MountService { MountService.shared }

    private static let demoCaption = """
        A mount without hardware, to see how Go to, Sync and the nudge arrows work. The Sky-Watcher one also shows the \
        set-up and the alignment on stars.
        """

    var body: some View {
        let form = service.form
        let address = MountAddress(text: form.host, defaultPort: form.port)
        let canConnect = !address.host.isEmpty && (1...65_535).contains(address.port)
        let isLost: Bool = {
            if case .lost = service.connection { return !service.isDemo }
            return false
        }()
        SettingsSection(title: "Connect",
                        footer: "Connecting does not move the mount. Nothing moves until you tap GoTo or an arrow.") {
            Button {
                service.connect(observer: app.observerContext?.observer)
            } label: {
                Label(isLost ? "Reconnect" : "Connect", systemImage: "wifi")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.lodestarPrimary)
            .disabled(!canConnect)
            ForEach(MountConnectionOption.demos) { demo in
                Button {
                    service.connectDemo(demo, observer: app.observerContext?.observer)
                } label: {
                    Label(demo.title, systemImage: "play.circle")
                }
            }
            SettingsCaption(Self.demoCaption)
        }
    }
}

// MARK: - Connected

/// Tracking and the clock of the mount.
private struct MountControlsSection: View {
    @Environment(AppModel.self) private var app
    private var service: MountService { MountService.shared }

    var body: some View {
        let status = service.status
        let capabilities = service.capabilities
        SettingsSection(title: "Mount Controls") {
            if capabilities?.canSetTracking == true {
                SettingsToggleRow(
                    title: "Tracking",
                    caption: "Keeps the stars still in the camera. Turn it off only to park or to let the sky drift on purpose.",
                    isOn: Binding(get: { status.isTracking ?? false }, set: { service.setTracking($0) }))
                    .disabled(status.phase == .slewing)
            }
            // A mount that Lodestar aligns is sent nothing (see `MountAlignmentText.siteAndTime`), so there is nothing to send.
            if capabilities?.canSetSiteAndTime == true, !service.usesLodestarAlignment,
               let observer = app.observerContext?.observer {
                VStack(alignment: .leading, spacing: 4) {
                    Button("Send location and time to the mount") {
                        Task { await service.sendSiteAndTime(location: observer.location) }
                    }
                    SettingsCaption("Sends your location and the iPhone's clock (UTC) to the mount, for mounts that work "
                                    + "out their own sky. Do it again after moving to a new place.")
                }
            }
            SettingsCaption("Move the mount with the Nudge button on the Aim screen.")
        }
    }
}

// MARK: - Limits and safety

/// The altitude limit and the other rules Lodestar keeps for the mount.
private struct MountLimitsSection: View {
    private static let syncOptions = [
        SettingsMenuOption(title: "No limit", value: 180.0),
        SettingsMenuOption(title: "45\u{00B0}", value: 45.0),
        SettingsMenuOption(title: "20\u{00B0}", value: 20.0),
        SettingsMenuOption(title: "10\u{00B0}", value: 10.0),
        SettingsMenuOption(title: "5\u{00B0}", value: 5.0),
        SettingsMenuOption(title: "2\u{00B0}", value: 2.0),
    ]
    private static let timeoutOptions = [
        SettingsMenuOption(title: "1 minute", value: 60.0),
        SettingsMenuOption(title: "2 minutes", value: 120.0),
        SettingsMenuOption(title: "5 minutes", value: 300.0),
        SettingsMenuOption(title: "10 minutes", value: 600.0),
        SettingsMenuOption(title: "30 minutes", value: 1_800.0),
    ]
    private static let rateOptions = MountNudgeRate.allCases.map {
        SettingsMenuOption(title: MountNudgeCard.title(of: $0), value: $0)
    }

    var body: some View {
        @Bindable var service = MountService.shared
        let option = service.displayedOption
        SettingsSection(title: "Limits") {
            SettingsSliderRow(title: "Altitude limit", valueText: AppFormat.altitude(service.settings.altitudeLimit),
                              value: $service.settings.altitudeLimit, range: MountUserSettings.altitudeLimitRange,
                              step: 1)
            SettingsCaption("Lodestar never slews to a target lower than this above the horizon, now or a minute from "
                            + "now. Set it above trees, buildings and anything the telescope could hit. The mount "
                            + "has limits of its own as well.")
            SettingsMenuPicker(title: "Largest sync correction", selection: $service.settings.maximumSyncOffset,
                               options: Self.syncOptions)
            SettingsCaption("""
                A sync that would move the mount's idea of its position by more than this is refused, which catches a \
                wrong star. Sky-Watcher Wi-Fi mounts ignore this: they judge a star by how well it fits the others.
                """)
            SettingsMenuPicker(title: "Nudge speed", selection: $service.settings.nudgeRate, options: Self.rateOptions)
            SettingsMenuPicker(title: "Stop a slew after", selection: $service.settings.slewTimeout,
                               options: Self.timeoutOptions)
            if option.usesLodestarAlignment {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Location and time")
                    SettingsCaption(MountAlignmentText.siteAndTime)
                }
            } else {
                SettingsToggleRow(
                    title: "Send location and time when connecting",
                    caption: "Sends your location and the iPhone's clock (UTC) to the mount, for mounts that work out their "
                        + "own sky, such as OnStep and hand controls without GPS.",
                    isOn: $service.settings.sendsSiteAndTime)
            }
        }
    }
}

/// Rarely needed choices, out of the way.
private struct MountAdvancedSection: View {
    @State private var isExpanded = false

    private static let axisSenseCaption = """
        Check after the first star, with tracking on: tap East on the nudge pad. The view must move east, so the stars \
        drift west in the camera. Tap North: the view must move north. If East and North are swapped, or one of them runs \
        backwards, reverse an axis here. Changing these applies the next time you connect and clears the alignment.
        """

    var body: some View {
        @Bindable var service = MountService.shared
        let fields = service.displayedOption.advancedFields
        if !fields.isEmpty {
            SettingsSection(title: "Advanced", footer: "These apply the next time you connect.") {
                DisclosureGroup("Advanced options", isExpanded: $isExpanded) {
                    if fields.contains(.epoch) {
                        VStack(alignment: .leading, spacing: 4) {
                            SettingsMenuPicker(
                                title: "Coordinate system", selection: $service.settings.epochChoice,
                                options: MountEpochChoice.allCases.map { SettingsMenuOption(title: $0.title, value: $0) })
                            SettingsCaption("Mounts take either the current epoch (JNow) or J2000. Leave it on Automatic "
                                            + "unless GoTo always lands a fraction of a degree off.")
                        }
                    }
                    if fields.contains(.swapEastWest) {
                        SettingsToggleRow(
                            title: "Reverse east and west",
                            caption: "For a mount whose nudges to the east and west go the wrong way.",
                            isOn: $service.settings.reversesEastWest)
                    }
                    if fields.contains(.arrangement) {
                        VStack(alignment: .leading, spacing: 4) {
                            SettingsMenuPicker(
                                title: "Mount arrangement", selection: $service.settings.arrangement,
                                options: MountArrangementChoice.allCases.map { SettingsMenuOption(title: Self.title(of: $0), value: $0) })
                            SettingsCaption("""
                                Automatic takes it from the mount model when it connects: the AZ-GTi and AZ-GTe are \
                                alt-azimuth, the Star Adventurer GTi and EQ mounts equatorial. Choose Equatorial for an \
                                AZ-GTi on a wedge. Applies the next time you connect.
                                """)
                        }
                    }
                    if fields.contains(.reverseAxis1) || fields.contains(.reverseAxis2) {
                        SettingsCaption(Self.axisSenseCaption)
                    }
                    if fields.contains(.reverseAxis1) {
                        SettingsToggleRow(
                            title: "Reverse axis 1",
                            caption: """
                                The azimuth axis of an alt-azimuth mount, the right ascension axis of an equatorial one. \
                                Turn on if East and West move the view the wrong way.
                                """,
                            isOn: $service.settings.reversesAxis1)
                    }
                    if fields.contains(.reverseAxis2) {
                        SettingsToggleRow(
                            title: "Reverse axis 2",
                            caption: """
                                The altitude axis of an alt-azimuth mount, the declination axis of an equatorial one. \
                                Turn on if North and South move the view the wrong way.
                                """,
                            isOn: $service.settings.reversesAxis2)
                    }
                }
            }
        }
    }

    private static func title(of choice: MountArrangementChoice) -> String {
        choice.mode.map(mountArrangementTitle) ?? choice.title
    }
}

/// What to keep in mind before a mount moves.
private struct MountSafetySection: View {
    @Environment(\.palette) private var palette

    private struct Note {
        let symbol: String
        let text: String
    }

    private static let notes = [
        Note(symbol: "person.2.slash", text: """
            Keep people, hands and cables clear of the mount and of everything it carries before a slew. \
            It can swing through a wide arc and does not stop for obstacles.
            """),
        Note(symbol: "sun.max.trianglebadge.exclamationmark", text: """
            Lodestar never slews to the Sun, but it does not check the path or the field of view. \
            Do not use GoTo by day unless the optics have a certified solar filter.
            """),
        Note(symbol: "arrow.down.to.line", text: """
            Targets below your altitude limit are refused. The limit is no substitute for looking: \
            check the path of the telescope yourself.
            """),
        Note(symbol: "stop.circle", text: """
            Stop is always one tap away on the Aim screen. If the app cannot reach the mount, \
            stop it on its hand controller or switch it off.
            """),
        Note(symbol: "iphone.slash", text: "When Lodestar goes to the background it stops the mount and disconnects."),
        Note(symbol: "scope", text: """
            Align the mount on its own hand controller before the first GoTo, and sync on a star you have \
            centred to improve it.
            """),
        Note(symbol: "lock.shield", text: """
            Lodestar talks to the mount only over your local network. Nothing is sent to the internet.
            """),
    ]

    var body: some View {
        SettingsSection(title: "Safety") {
            ForEach(Self.notes.indices, id: \.self) { index in
                let note = Self.notes[index]
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: note.symbol)
                        .foregroundStyle(palette.accent)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(note.text)
                        .font(.subheadline)
                        .foregroundStyle(palette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
