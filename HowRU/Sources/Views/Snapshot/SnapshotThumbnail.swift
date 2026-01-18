import SwiftUI

/// Reusable thumbnail component for displaying snapshots
struct SnapshotThumbnail: View {
    let imageData: Data?
    let expiresAt: Date?
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    init(imageData: Data?, expiresAt: Date? = nil, size: CGFloat = 60) {
        self.imageData = imageData
        self.expiresAt = expiresAt
        self.size = size
    }

    private var isExpired: Bool {
        guard let expires = expiresAt else { return true }
        return expires < Date()
    }

    private var expiryText: String? {
        guard let expires = expiresAt, !isExpired else { return nil }

        let remaining = expires.timeIntervalSince(Date())
        let hours = Int(remaining / 3600)

        if hours > 0 {
            return "\(hours)h"
        } else {
            let minutes = max(1, Int(remaining / 60))
            return "\(minutes)m"
        }
    }

    var body: some View {
        ZStack {
            if let data = imageData, let uiImage = UIImage(data: data), !isExpired {
                // Valid image
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: HowRURadius.md))

                // Expiry badge
                if let expiry = expiryText {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 2) {
                                Image(systemName: "clock")
                                    .font(.system(size: 8, weight: .semibold))
                                Text(expiry)
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                            .padding(4)
                        }
                    }
                    .frame(width: size, height: size)
                }
            } else {
                // Placeholder
                RoundedRectangle(cornerRadius: HowRURadius.md)
                    .fill(HowRUColors.divider(colorScheme))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .font(.system(size: size * 0.35, weight: .medium))
                            .foregroundColor(HowRUColors.textSecondary(colorScheme))
                    )
            }
        }
    }
}

// MARK: - Large Snapshot View

/// Full-screen snapshot viewer
struct SnapshotFullView: View {
    let imageData: Data
    let expiresAt: Date?
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    private var expiryText: String? {
        guard let expires = expiresAt, expires > Date() else { return nil }

        let remaining = expires.timeIntervalSince(Date())
        let hours = Int(remaining / 3600)

        if hours > 0 {
            return "Expires in \(hours)h"
        } else {
            let minutes = max(1, Int(remaining / 60))
            return "Expires in \(minutes)m"
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                    .onTapGesture {
                        onDismiss()
                    }

                if let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = value
                                }
                                .onEnded { _ in
                                    withAnimation(.howruSmooth) {
                                        scale = 1.0
                                    }
                                }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    offset = value.translation
                                }
                                .onEnded { value in
                                    if abs(value.translation.height) > 100 {
                                        onDismiss()
                                    } else {
                                        withAnimation(.howruSmooth) {
                                            offset = .zero
                                        }
                                    }
                                }
                        )
                }

                // UI Overlay
                VStack {
                    // Top bar
                    HStack {
                        Spacer()

                        Button(action: {
                            HowRUHaptics.light()
                            onDismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, HowRUSpacing.screenEdge)
                    .padding(.top, HowRUSpacing.md)

                    Spacer()

                    // Expiry info
                    if let expiry = expiryText {
                        HStack(spacing: HowRUSpacing.sm) {
                            Image(systemName: "clock")
                                .font(.system(size: 14, weight: .medium))
                            Text(expiry)
                                .font(HowRUFont.caption())
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, HowRUSpacing.lg)
                        .padding(.vertical, HowRUSpacing.sm)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Capsule())
                        .padding(.bottom, HowRUSpacing.xxl)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Snapshot Thumbnail") {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
    let sampleImage = renderer.image { context in
        UIColor.systemOrange.setFill()
        context.fill(CGRect(origin: .zero, size: CGSize(width: 100, height: 100)))
    }

    return HStack(spacing: 20) {
        SnapshotThumbnail(
            imageData: sampleImage.jpegData(compressionQuality: 0.8),
            expiresAt: Date().addingTimeInterval(3600 * 12),
            size: 60
        )

        SnapshotThumbnail(
            imageData: nil,
            expiresAt: nil,
            size: 60
        )

        SnapshotThumbnail(
            imageData: sampleImage.jpegData(compressionQuality: 0.8),
            expiresAt: Date().addingTimeInterval(60 * 30),
            size: 80
        )
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
