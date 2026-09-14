//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

/// The app's logo styled to fit on various launch pages.
struct AuthenticationStartLogo: View {
    /// Set to specify a custom size for the Logo, otherwise the default size of 158pt will be used.
    var size: CGFloat?
    /// Set to `true` to skip the brand chrome.
    let hideBrandChrome: Bool
    /// Set to `true` when using on top of `Asset.Images.launchBackground`.
    let isOnGradient: Bool
    
    private let appLogoImage = Image(asset: Asset.Images.appLogo)
    
    struct SizeMetrics {
        let scale: CGFloat
        let imageSize: CGFloat
    }
    
    private var sizeMetrics: SizeMetrics? {
        size.map { customSize in
            let scale = customSize / 158
            return SizeMetrics(scale: scale,
                               imageSize: hideBrandChrome ? customSize : 110 * scale)
        }
    }
    
    /// The real wordmark: a speech bubble outline around "holm". It's a template
    /// image (transparent, single-colour line art) so it can sit in white on the
    /// dark auth gradient and in the primary label colour anywhere else.
    var body: some View {
        appLogoImage
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(isOnGradient ? .white : Color.compound.textPrimary)
            .frame(width: sizeMetrics?.imageSize ?? 148, height: sizeMetrics?.imageSize ?? 148)
    }
}

/// Applies the brand chrome styling (rounded card with shadows and border) to any image,
/// as seen on the authentication start screen.
private struct AuthenticationBrandLogoModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    
    /// Scale factor relative to the original 158pt design.
    let scale: CGFloat
    /// Set to `true` to skip the brand chrome.
    let hideBrandChrome: Bool
    /// Set to `true` when using on top of `Asset.Images.launchBackground`.
    let isOnGradient: Bool
    
    private let outerShapeShadowColor = Color(red: 0.11, green: 0.11, blue: 0.13)
    private var isLight: Bool {
        colorScheme == .light
    }
    
    /// Extra padding needed to avoid cropping the shadows.
    private var extra: CGFloat {
        64 * scale
    }
    
    /// The shape that the logo is composed on top of.
    private var outerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 44 * scale)
    }
    
    func body(content: Content) -> some View {
        if hideBrandChrome {
            content
        } else {
            styledContent(content)
        }
    }
    
    /// Holm's mark stands on its own — no card, border or glass chrome. The serif
    /// monogram floats directly on the gradient with only a soft shadow for depth.
    private func styledContent(_ content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.45), radius: 24 * scale, y: 8 * scale)
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 0) {
        HStack(spacing: 0) {
            AuthenticationStartLogo(hideBrandChrome: false, isOnGradient: false)
                .padding()
            AuthenticationStartLogo(hideBrandChrome: false, isOnGradient: true)
                .padding()
                .background {
                    AuthenticationStartScreenBackgroundImage().offset(y: 70)
                }
                .clipped()
        }
        .background(.compound.bgCanvasDefault)
        
        HStack(spacing: 0) {
            AuthenticationStartLogo(hideBrandChrome: false, isOnGradient: false)
                .padding()
            AuthenticationStartLogo(hideBrandChrome: false, isOnGradient: true)
                .padding()
                .background {
                    AuthenticationStartScreenBackgroundImage().offset(y: 70)
                }
                .clipped()
        }
        .background(.compound.bgCanvasDefault)
        .colorScheme(.dark)
        
        HStack(spacing: 0) {
            AuthenticationStartLogo(size: 54, hideBrandChrome: false, isOnGradient: false)
                .padding()
                .background(.compound.bgCanvasDefault)
            AuthenticationStartLogo(size: 54, hideBrandChrome: false, isOnGradient: false)
                .padding()
                .background(.compound.bgCanvasDefault)
                .colorScheme(.dark)
        }
        .padding(.top)
    }
}
