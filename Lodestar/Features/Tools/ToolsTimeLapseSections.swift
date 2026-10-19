import SwiftUI
import LodestarKit

/// The sections of the time-lapse plan: timing, playback, camera and storage, and the plan.
struct ToolsTimeLapseSections: View {
    @Binding var inputs: ToolsLapseInputs

    var body: some View {
        timingSection
        playbackSection
        storageSection
        planSection
    }

    // MARK: Inputs

    private var timingSection: some View {
        SettingsSection(
            title: "Timing",
            footer: "The interval is the time from the start of one picture to the start of the next. What is left "
                + "after the exposure is the time the camera has to save the picture.") {
            SettingsNumberField(title: "Interval", unit: "s", value: $inputs.interval,
                                range: 0.1...TimeLapsePlanner.maximumIntervalSeconds, fractionDigits: 1)
            SettingsNumberField(title: "Exposure", unit: "s", value: $inputs.exposure,
                                range: 0.1...TimeLapsePlanner.maximumIntervalSeconds, fractionDigits: 1)
            InfoRow(label: "Gap between pictures",
                    value: ToolsPlannerText.seconds(inputs.interval - inputs.exposure))
        }
    }

    private var playbackSection: some View {
        SettingsSection(
            title: "Playback",
            footer: "Give the length of the finished clip, the time you will shoot, or the number of pictures; the "
                + "other two follow.") {
            SettingsNumberField(title: "Frame rate", unit: "fps", value: $inputs.frameRate,
                                range: 1...TimeLapsePlanner.maximumFrameRate, fractionDigits: 0)
            Picker("What the length is given by", selection: $inputs.basis) {
                ForEach(ToolsLapseInputs.Basis.allCases) { basis in
                    Text(basis.title).tag(basis)
                }
            }
            .pickerStyle(.segmented)
            switch inputs.basis {
            case .clipLength:
                SettingsNumberField(title: "Clip length", unit: "s", value: $inputs.clipSeconds,
                                    range: 0.1...86_400, fractionDigits: 1)
            case .shootingTime:
                SettingsNumberField(title: "Shooting time", unit: "min", value: $inputs.shootingMinutes,
                                    range: 0.1...14_400, fractionDigits: 1)
            case .frames:
                SettingsNumberField(title: "Pictures", value: $inputs.frameCount,
                                    range: 1...Double(TimeLapsePlanner.maximumFrameCount), fractionDigits: 0)
            }
        }
    }

    private var storageSection: some View {
        SettingsSection(
            title: "Camera & Storage",
            footer: "A raw picture from a 24 MP camera is about 25 MB, from a 45 MP camera about 50 MB. Leave the "
                + "size empty if you do not need the storage.") {
            SettingsNumberField(title: "Size of a picture", unit: "MB", optionalValue: $inputs.pictureMegabytes,
                                range: 0.1...TimeLapsePlanner.maximumFrameSizeMegabytes, fractionDigits: 1)
            SettingsNumberField(title: "Time to save a picture", unit: "s", value: $inputs.writeSeconds,
                                range: 0...TimeLapsePlanner.maximumMinimumGapSeconds, fractionDigits: 1)
        }
    }

    // MARK: Results

    private var planSection: some View {
        let result = Result { try TimeLapsePlanner.plan(
            interval: inputs.interval, exposure: inputs.exposure, frameRate: inputs.frameRate, target: inputs.target,
            frameSizeMegabytes: inputs.pictureMegabytes, minimumGapSeconds: inputs.writeSeconds) }
        return SettingsSection(title: "Time-Lapse") {
            switch result {
            case .success(let plan):
                ToolsHeadline(
                    title: "\(ToolsPlannerText.count(plan.frameCount)) pictures",
                    subtitle: "one every \(ToolsPlannerText.seconds(plan.interval)), each "
                        + "\(ToolsPlannerText.seconds(plan.exposure)) long")
                InfoRow(label: "Shooting time", value: AngleFormatter.formatDuration(seconds: plan.shootingTime))
                InfoRow(label: "Clip length",
                        value: "\(AngleFormatter.formatDuration(seconds: plan.clipLength)) at "
                            + "\(plan.frameRate.formatted(.number.precision(.fractionLength(0...1)))) fps")
                InfoRow(label: "Speed-up",
                        value: "\(plan.speedUp.formatted(.number.precision(.fractionLength(0...1))))\u{00D7}")
                InfoRow(label: "Gap between pictures", value: ToolsPlannerText.seconds(plan.gap, maximumDigits: 2))
                if let megabytes = plan.storageMegabytes {
                    InfoRow(label: "Storage", value: ToolsPlannerText.storage(megabytes: megabytes))
                } else {
                    SettingsCaption("Enter the size of a picture to see how much storage the pictures need.")
                }
                InfoRow(label: "Battery", value: ToolsPlannerText.battery(plan.batteryDemand))
                SettingsCaption(plan.batteryNote)
            case .failure(let error):
                let failure = ToolsPlannerText.failure(for: error)
                ToolsProblemRow(message: failure.message)
                if let interval = failure.suggestedInterval {
                    Button("Use an interval of \(ToolsPlannerText.seconds(interval, maximumDigits: 2))") {
                        inputs.interval = min(interval, TimeLapsePlanner.maximumIntervalSeconds)
                    }
                }
            }
        }
    }
}
