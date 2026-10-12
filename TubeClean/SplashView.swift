import Observation
import SwiftUI

/// Whether the first page has loaded. Drives the splash screen.
@MainActor
@Observable
final class LoadState {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    var phase: Phase = .loading
}

/// Shown over the web view until YouTube's first page has loaded, so the
/// child never stares at a blank white page.
struct SplashView: View {
    let phase: LoadState.Phase
    let retry: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                Image("Logo")
                    .resizable()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                    .shadow(radius: 6, y: 3)
                Text("TubeClean")
                    .font(.title2.weight(.semibold))
                switch phase {
                case .failed(let message):
                    VStack(spacing: 12) {
                        Text("Can't reach YouTube")
                            .font(.headline)
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                        Button("Try again", action: retry)
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 8)
                default:
                    ProgressView()
                        .controlSize(.large)
                        .padding(.top, 8)
                }
            }
        }
    }
}
