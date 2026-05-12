import SwiftUI

/// Countdown screen between sets. Auto-advances on hit-zero (via the manager's
/// countdown Task); Skip button advances immediately.
struct RestStepView: View {
    let secondsRemaining: Int
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Rest")
                .font(.title.weight(.bold))
                .foregroundStyle(.secondary)

            Text("\(secondsRemaining)s")
                .font(.system(size: 96, weight: .heavy, design: .rounded).monospacedDigit())
                .contentTransition(.numericText(countsDown: true))

            Text("Next set starts when the timer hits 0.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button {
                onSkip()
            } label: {
                Label("Skip Rest", systemImage: "forward.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}
