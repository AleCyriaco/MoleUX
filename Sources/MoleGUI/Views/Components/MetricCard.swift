import SwiftUI

struct MetricCard: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var progress: Double? = nil
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                }
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                Spacer()
            }

            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(tint)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ActionButton: View {
    let title: String
    var systemImage: String
    var role: ButtonRole? = nil
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isLoading)
    }
}

struct SecondaryActionButton: View {
    let title: String
    var systemImage: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .disabled(isLoading)
    }
}

struct HealthRing: View {
    let score: Int
    let label: String

    private var progress: Double { Double(score) / 100.0 }
    private var tint: Color {
        switch score {
        case 85...100: return .green
        case 70..<85: return .yellow
        case 50..<70: return .orange
        default: return .red
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: 12)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 140, height: 140)
    }
}
