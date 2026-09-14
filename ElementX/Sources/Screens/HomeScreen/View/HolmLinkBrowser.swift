//
// Copyright 2026 Holm.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Compound
import SwiftUI
import WebKit

/// A saved site, pushed onto the chat list's stack like a room: the same back arrow,
/// the same header shape, the same sideways animation. It uses the app's persistent
/// website data store, so a signed-in session survives leaving and relaunching.
struct HolmLinkBrowser: View {
    let link: HolmLink
    let mediaProvider: MediaProviderProtocol?

    @State private var navigator = HolmWebNavigator()

    var body: some View {
        ZStack(alignment: .top) {
            HolmWebView(url: link.url, navigator: navigator)

            if navigator.isLoading {
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.compound.iconAccentPrimary)
                        .frame(width: geometry.size.width * navigator.progress, height: 2)
                }
                .frame(height: 2)
                .animation(.linear(duration: 0.2), value: navigator.progress)
            }
        }
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(RoomHeaderView.toolbarRole)
        .toolbar {
            // The same shape a room wears: icon and name, nothing on the right.
            ToolbarItem(placement: .principal) {
                header
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .accessibilityHidden(true)

            Text(link.title)
                .font(.compound.bodyLGSemibold)
                .foregroundStyle(.compound.textPrimary)
                .lineLimit(1)
        }
        .padding(6)
        .padding(.trailing, 6)
        .backportGlassEffect()
    }

    @ViewBuilder
    private var icon: some View {
        if let icon = link.icon {
            Image(uiImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Color.compound.bgSubtlePrimary
                .overlay {
                    Text(link.initial)
                        .font(.compound.bodyMDSemibold)
                        .foregroundStyle(.compound.textSecondary)
                }
        }
    }
}

private extension View {
    @ViewBuilder
    func backportGlassEffect() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive())
        } else {
            self
        }
    }
}

/// The bits of the web view the surrounding chrome needs to know about.
@Observable
final class HolmWebNavigator {
    var isLoading = false
    var progress = 0.0

    private weak var webView: WKWebView?
    private var observations: [NSKeyValueObservation] = []

    func attach(_ webView: WKWebView) {
        self.webView = webView

        observations = [
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] view, _ in
                Task { @MainActor in self?.isLoading = view.isLoading }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] view, _ in
                Task { @MainActor in self?.progress = view.estimatedProgress }
            }
        ]
    }
}

private struct HolmWebView: UIViewRepresentable {
    let url: URL
    let navigator: HolmWebNavigator

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // The default store is the persistent one: cookies and local storage are kept,
        // which is what makes a signed-in session survive leaving the site.
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .compound.bgCanvasDefault
        navigator.attach(webView)
        webView.load(URLRequest(url: url))

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) { }
}
