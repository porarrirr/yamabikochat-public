import PhotosUI
import SwiftUI
import UIKit

/// Embeds the system Photos picker (out-of-process, no library permission
/// required) inside the attachment sheet.
struct RecentPhotoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appAccent) private var appAccent
    @Binding var selection: [PhotosPickerItem]
    let maxSelectionCount: Int
    let isAdding: Bool
    let onAddSelected: () -> Void
    let onOpenFullLibrary: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.chatScreenBackground
                .ignoresSafeArea()

            PhotosPicker(
                selection: $selection,
                maxSelectionCount: maxSelectionCount,
                selectionBehavior: .continuousAndOrdered,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Text(L10n.text("写真"))
            }
            .photosPickerStyle(.inline)
            .photosPickerDisabledCapabilities(.selectionActions)
            .photosPickerAccessoryVisibility(.hidden, edges: .all)
            .disabled(isAdding)
            .ignoresSafeArea(edges: .bottom)

            floatingBottomBar
        }
    }

    private var floatingBottomBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color(white: 0.18, opacity: 0.85))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("戻る"))

            Spacer()

            if selection.isEmpty {
                Button {
                    onOpenFullLibrary()
                } label: {
                    Text(L10n.text("すべての写真"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color(white: 0.18, opacity: 0.85))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(isAdding)
            } else {
                Button {
                    onAddSelected()
                } label: {
                    HStack(spacing: 6) {
                        if isAdding {
                            ProgressView()
                                .tint(appAccent.onAccentColor)
                                .controlSize(.small)
                        }
                        Text(selection.count == 1
                            ? L10n.text("1点の写真を追加する")
                            : L10n.format("%d点の写真を追加する", selection.count))
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(appAccent.onAccentColor)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(appAccent.color)
                    .clipShape(Capsule())
                    .shadow(color: appAccent.color.opacity(0.4), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(isAdding)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}
