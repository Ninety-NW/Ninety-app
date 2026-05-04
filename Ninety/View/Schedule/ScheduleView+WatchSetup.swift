import SwiftUI

extension ScheduleView {
    var watchSetupBannerSlot: some View {
        ZStack(alignment: .top) {
            Color.clear

            if let summary = watchSetupSummary {
                watchSetupBanner(summary)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: watchBannerSlotHeight, alignment: .top)
    }

    func watchSetupBanner(_ summary: WatchSetupSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(summary.tint.opacity(colorScheme == .light ? 0.16 : 0.24))
                        .frame(width: 32, height: 32)

                    Image(systemName: summary.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(summary.tint)
                }

                Text(summary.title)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .layoutPriority(1)

                Spacer(minLength: 0)
            }

            Text(summary.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            watchSetupProgressRow(for: summary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: 340, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(summary.tint.opacity(colorScheme == .light ? 0.14 : 0.18))
                        .frame(width: 120, height: 120)
                        .blur(radius: 28)
                        .offset(x: -20, y: -50)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(summary.tint.opacity(colorScheme == .light ? 0.22 : 0.30), lineWidth: 1)
        }
        .shadow(color: summary.tint.opacity(colorScheme == .light ? 0.10 : 0.15), radius: 20, y: 10)
    }

    func watchSetupStatusPill(_ label: String, tint: Color) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(colorScheme == .light ? 0.12 : 0.18))
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(colorScheme == .light ? 0.18 : 0.26), lineWidth: 1)
            }
    }

    func watchSetupProgressRow(for summary: WatchSetupSummary) -> some View {
        HStack(alignment: .top, spacing: 0) {
            watchSetupProgressNode(
                label: "Alarm saved".localized(for: appLanguage),
                symbol: "checkmark",
                style: .complete,
                tint: accent
            )
            watchSetupConnector(isActive: summary.state.rawValue >= WatchSetupState.ready.rawValue, tint: summary.tint)
            watchSetupProgressNode(
                label: "Open Watch".localized(for: appLanguage),
                symbol: summary.state == .needsAction ? "applewatch" : "checkmark",
                style: summary.state == .needsAction ? .current : .complete,
                tint: summary.state == .needsAction ? summary.tint : Color(red: 0.18, green: 0.70, blue: 0.48)
            )
            watchSetupConnector(isActive: summary.state == .active, tint: summary.tint)
            watchSetupProgressNode(
                label: "Tracking".localized(for: appLanguage),
                symbol: summary.state == .active ? "waveform.path.ecg" : "moon.zzz",
                style: summary.state == .active ? .complete : .upcoming,
                tint: summary.tint
            )
        }
    }

    enum WatchProgressStyle {
        case complete
        case current
        case upcoming
    }

    func watchSetupProgressNode(label: String, symbol: String, style: WatchProgressStyle, tint: Color) -> some View {
        let circleFill: Color
        let circleStroke: Color
        let iconColor: Color

        switch style {
        case .complete:
            circleFill = tint
            circleStroke = tint.opacity(0.0)
            iconColor = .white
        case .current:
            circleFill = tint.opacity(colorScheme == .light ? 0.14 : 0.20)
            circleStroke = tint.opacity(colorScheme == .light ? 0.30 : 0.36)
            iconColor = tint
        case .upcoming:
            circleFill = Color.white.opacity(colorScheme == .light ? 0.42 : 0.08)
            circleStroke = Color.primary.opacity(colorScheme == .light ? 0.08 : 0.16)
            iconColor = .secondary
        }

        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(circleFill)
                    .frame(width: 24, height: 24)
                Circle()
                    .strokeBorder(circleStroke, lineWidth: 1)
                    .frame(width: 24, height: 24)
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    func watchSetupConnector(isActive: Bool, tint: Color) -> some View {
        Capsule(style: .continuous)
            .fill(isActive ? tint.opacity(0.55) : Color.primary.opacity(0.10))
            .frame(width: 18, height: 2)
            .padding(.top, 11)
    }

    func syncInternalTime() {
        internalHour = viewModel.selectedDayHour
        internalMinute = viewModel.selectedDayMinute
    }
}
