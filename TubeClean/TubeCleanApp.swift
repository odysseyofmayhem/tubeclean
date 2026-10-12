import AVFoundation
import SwiftUI

@main
struct TubeCleanApp: App {
    @State private var browser = BrowserController(rules: RulesStore())
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Play sound even when the iPad is set to silent.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                BrowserView(controller: browser)
                    .ignoresSafeArea(.container, edges: .bottom)
                if browser.load.phase != .ready {
                    SplashView(phase: browser.load.phase, retry: browser.retry)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.35), value: browser.load.phase)
            .task { await browser.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await browser.rules.refreshIfDue() }
            }
        }
    }
}

struct BrowserView: UIViewRepresentable {
    let controller: BrowserController

    func makeUIView(context: Context) -> WKWebViewContainer {
        WKWebViewContainer(webView: controller.webView)
    }

    func updateUIView(_ uiView: WKWebViewContainer, context: Context) {}
}
