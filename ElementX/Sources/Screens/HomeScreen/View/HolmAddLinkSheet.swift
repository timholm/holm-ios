//
// Copyright 2026 Holm.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Compound
import PhotosUI
import SwiftUI

/// Add a website to sit alongside your spaces — your fediverse instance, a dashboard,
/// anything you keep going back to. We fetch its name and icon so it looks like itself.
struct HolmAddLinkSheet: View {
    let onAdd: (HolmLink) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var name = ""
    @State private var isFetching = false
    @State private var photoItem: PhotosPickerItem?
    @State private var chosenIcon: Data?
    @FocusState private var isFocused: Bool

    /// Accepts "holm.community" as readily as a full URL.
    private var resolvedURL: URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.contains(".") else { return nil }

        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme), url.host() != nil else { return nil }

        return url
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                // Pick your own picture, or leave it and we'll take the site's icon.
                PhotosPicker(selection: $photoItem, matching: .images) {
                    ZStack {
                        if let chosenIcon, let image = UIImage(data: chosenIcon) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Circle()
                                .strokeBorder(Color.compound.borderInteractivePrimary,
                                              style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .overlay {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.compound.iconSecondary)
                                }
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)

                TextField(text: $address) {
                    Text("holm.community")
                        .foregroundStyle(.compound.textSecondary)
                }
                .focused($isFocused)
                .textFieldStyle(.compound(.raised))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .disabled(isFetching)
                .onSubmit(add)

                TextField(text: $name) {
                    Text("Name (optional)")
                        .foregroundStyle(.compound.textSecondary)
                }
                .textFieldStyle(.compound(.raised))
                .disabled(isFetching)
                .onSubmit(add)

                Text("The site opens inside Holm and stays signed in, so your instance is one tap away.")
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)

                Spacer()

                Button(action: add) {
                    if isFetching {
                        ProgressView()
                    } else {
                        Text("Add")
                    }
                }
                .buttonStyle(.compound(.primary))
                .disabled(resolvedURL == nil || isFetching)
            }
            .padding(16)
            .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
            .navigationTitle("Add a link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.actionCancel) { dismiss() }
                        .disabled(isFetching)
                }
            }
            .onAppear { isFocused = true }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        chosenIcon = HolmLinkMetadata.thumbnail(from: data)
                    }
                }
            }
        }
    }

    private func add() {
        guard let url = resolvedURL, !isFetching else { return }

        isFetching = true
        Task {
            var link = await HolmLinkMetadata.fetch(for: url)
            if let chosenIcon {
                link.iconData = chosenIcon
            }
            let chosenName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !chosenName.isEmpty {
                link.title = chosenName
            }
            isFetching = false
            dismiss()
            onAdd(link)
        }
    }
}
