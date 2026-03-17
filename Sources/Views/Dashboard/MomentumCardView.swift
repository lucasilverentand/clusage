import SwiftUI

// MARK: - Streak Card

struct StreakCard: View {
    let streak: UsageStreak

    private var streakDescription: String {
        var desc = "\(streak.currentStreak) day streak"
        if streak.currentStreak == streak.longestStreak && streak.longestStreak > 1 {
            desc += ", personal best"
        } else if streak.longestStreak > streak.currentStreak {
            desc += ", best is \(streak.longestStreak) days"
        }
        return desc
    }

    var body: some View {
        GlassCard {
            HStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(streak.currentStreak) day streak")
                        .font(.subheadline.weight(.semibold))

                    if streak.currentStreak == streak.longestStreak && streak.longestStreak > 1 {
                        Text("Personal best!")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if streak.longestStreak > streak.currentStreak {
                        Text("Best: \(streak.longestStreak) days")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(streakDescription)
        }
    }
}
