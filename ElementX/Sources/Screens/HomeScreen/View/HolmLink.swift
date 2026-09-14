//
// Copyright 2026 Holm.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SwiftUI

/// A website kept alongside your spaces — a fediverse instance, a dashboard, anything
/// you want one tap away. The site's own favicon stands in for an avatar.
struct HolmLink: Identifiable, Codable, Hashable {
    let id: UUID
    var url: URL
    var title: String
    /// The favicon, stored with the link so the row draws instantly and offline.
    var iconData: Data?

    init(id: UUID = UUID(), url: URL, title: String, iconData: Data? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.iconData = iconData
    }

    var host: String {
        url.host() ?? url.absoluteString
    }

    var icon: UIImage? {
        iconData.flatMap(UIImage.init(data:))
    }

    /// The first letter, for sites that don't give us an icon.
    var initial: String {
        String(title.first ?? host.first ?? "?").uppercased()
    }
}

/// Reads a site's name and icon so a saved link looks like itself rather than a URL.
enum HolmLinkMetadata {
    /// Best effort: a missing title or icon is normal and never an error.
    static func fetch(for url: URL) async -> HolmLink {
        let fallbackTitle = url.host() ?? url.absoluteString
        var html: String?

        if let (data, _) = try? await URLSession.shared.data(from: url) {
            html = String(data: data.prefix(200_000), encoding: .utf8)
        }

        let title = html.flatMap(pageTitle) ?? fallbackTitle
        let declared = html.flatMap { declaredIconURL(in: $0, relativeTo: url) }
        let fallback = URL(string: "/favicon.ico", relativeTo: url)?.absoluteURL

        guard let iconAddress = declared ?? fallback else {
            return HolmLink(url: url, title: title, iconData: nil)
        }

        let iconData = await downloadIcon(iconAddress)

        return HolmLink(url: url, title: title, iconData: iconData)
    }

    private static func pageTitle(in html: String) -> String? {
        guard let range = html.range(of: "<title[^>]*>(.*?)</title>",
                                     options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }

        let tag = String(html[range])
        guard let open = tag.firstIndex(of: ">"),
              let close = tag.range(of: "</", options: .backwards)?.lowerBound else { return nil }

        let title = tag[tag.index(after: open)..<close]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&")

        return title.isEmpty ? nil : title
    }

    /// Finds `<link rel="… icon …" href="…">`, preferring whichever the page lists first.
    private static func declaredIconURL(in html: String, relativeTo base: URL) -> URL? {
        let pattern = "<link[^>]+rel=[\"'][^\"']*icon[^\"']*[\"'][^>]*>"
        var searchRange = html.startIndex..<html.endIndex

        while let tagRange = html.range(of: pattern, options: [.regularExpression, .caseInsensitive], range: searchRange) {
            let tag = String(html[tagRange])

            if let hrefRange = tag.range(of: "href=[\"'][^\"']+[\"']", options: [.regularExpression, .caseInsensitive]) {
                let href = String(tag[hrefRange])
                    .replacingOccurrences(of: "href=", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

                if let resolved = URL(string: href, relativeTo: base)?.absoluteURL {
                    return resolved
                }
            }

            searchRange = tagRange.upperBound..<html.endIndex
        }

        return nil
    }

    private static func downloadIcon(_ url: URL) async -> Data? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        return thumbnail(from: data)
    }

    /// Squares and shrinks an image so it rides comfortably in user defaults.
    static func thumbnail(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let side: CGFloat = 128
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        // Fill the square from the middle rather than squashing a wide photo.
        let scale = max(side / image.size.width, side / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2)

        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: size))
        }.pngData()
    }
}
