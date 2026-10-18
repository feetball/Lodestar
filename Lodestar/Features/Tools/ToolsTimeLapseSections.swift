import SwiftUI
import LodestarKit

/// The sections of the time-lapse plan: the shots, the playback, the pictures and the numbers that follow.
struct ToolsTimeLapseSections: View {
    @Environment(\.palette) private var palette
    @Binding var inputs: ToolsLapseInputs

    var body: some View {
        let result = Result { try TimeLapsePlanner.plan(
            interval: inputs.interval, exposure: inputs.exposure, frameRate: inputs.frameRate, target: inputs.target,
            frameSizeMegabytes: inputs.pictureMegabytes, minimumGapSeconds: inputs.writeSeconds) }
        shotSection
        playbackSection
        pictureSection
        resultSection(result)
    }

    // MARK: Inputs

    private var shotSection: some View {
        SettingsSection(
            title: "Shots",
            footer: "The interval runs from the start of one exposure to the start of the next. What is left after "
                + "the exposure is the gap: the time the camera needs to write the picture and be ready again. If the "
                + "gap is too short, the camera skips frames.") {
            SettingsNumberField(title: "Interval", unit: "s", value: $inputs.interval,
                                range: 0.1...TimeLapsePlanner.maximumIntervalSeconds, fractionDigits: 1)
            SettingsNumberField(title: "Exposure", unit: "s", value: $inputs.exposure,
                                range: 0.1...TimeLapsePlanner.maximumIntervalSeconds, fractionDigits: 1)
            SettingsNumberField(title: "Camera write time", unit: "s", value: $inputs.writeSeconds,
                                range: 0...TimeLapsePlanner.maximumMinimumGapSeconds, fractionDigits: 1)
        }
    }

    private var playbackSection: some View {
        SettingsSection(title: "Clip") {
            SettingsNumberField(title: "Playback", unit: "fps", value: $inputs.frameRate,
                                range: 1...TimeLapsePlanner.maximumFrameRate, fractionDigits: 2)
            Picker("Plan for", selection: $inputs.goal) {
                ForEach(ToolsLapseInputs.Goal.allCases) { goal in
                    Text(goal.title).tag(goal)
                }
            }
            .pickerStyle(.segmented)
            switch inputs.goal {
            case .clipLength:
                SettingsNumberField(title: "Clip length", unit: "s", value: $inputs.clipSeconds,
                                    range: 0.1...3600, fractionDigits: 1)
            case .shootingTime:
                SettingsNumberField(title: "Shooting time", unit: "min", value: $inputs.shootingMinutes,
                                    range: 1...6000, fractionDigits: 0)
            case .frameCount:
                SettingsNumberField(title: "Frames", value: $inputs.frames,
                                    range: 1...Double(TimeLapsePlanner.maximumFrameCount), fractionDigits: 0)
            }
        }
    }

    private var pictureSection: some View {
        SettingsSection(
            title: "Pictures",
            footer: "The size of one picture, for the storage estimate. A raw file from a high-resolution camera is "
                + "often 25 MB or more.") {
            SettingsNumberField(title: "Picture size", unit: "MB", optionalValue: $inputs.pictureMegabytes,
                                range: 0.1...TimeLapsePlanner.maximumFrameSizeMegabytes, fractionDigits: 1,
                                placeholder: "Optional")
        }
    }

    // MARK: Results

    @ViewBuilder
    private func resultSection(_ result: Result<TimeLapsePlan, Error>) -> some View {
        switch result {
        case .success(let plan):
            planSection(plan)
        case .failure(let error):
            SettingsSection(title: "Time-Lapse") {
                ToolsProblemRow(message: ToolsPlannerText.message(forLapse: error))
                if let timeLapseError = error as? TimeLapseError,
                   case .gapTooShort(_, _, let minimumInterval) = timeLapseError {
                    SettingsCaption("Use an interval of at least \(ToolsPlannerText.seconds(minimumInterval)): the "
                                    + "exposure plus the camera\u{2019}s write time. Or shorten the exposure.")
                    Button {
                        inputs.interval = minimumInterval
                    } label: {
                        Label("Use \(ToolsPlannerText.seconds(minimumInterval)) Interval", systemImage: "timer")
                    }
                }
            }
        }
    }

    private func planSection(_ plan: TimeLapsePlan) -> some View {
        SettingsSection(title: "Time-Lapse") {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(ToolsPlannerText.count(plan.frameCount)) \(plan.frameCount == 1 ? "frame" : "frames")")
                    .font(.largeTitle.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.accent)
                Text("Every \(ToolsPlannerText.seconds(plan.interval)), \(ToolsPlannerText.seconds(plan.exposure)) "
                     + "exposures")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
            .accessibilityElement(children: .combine)
            InfoRow(label: "Shooting time", value: AngleFormatter.formatDuration(seconds: plan.shootingTime))
            InfoRow(label: "Clip length", value: AngleFormatter.formatDuration(seconds: plan.clipLength))
            InfoRow(label: "Playback speed",
                    value: "\u{00D7}\(plan.speedUp.formatted(.number.precision(.fractionLength(0...1)))) real time")
            InfoRow(label: "Gap between exposures", value: ToolsPlannerText.seconds(plan.gap))
            if let megabytes = plan.storageMegabytes {
                InfoRow(label: "Storage", value: ToolsPlannerText.storage(megabytes: megabytes))
            } else {
                InfoRow(label: "Storage", value: AppFormat.missing)
            }
            SettingsCaption(plan.batteryNote)
        }
    }
}
