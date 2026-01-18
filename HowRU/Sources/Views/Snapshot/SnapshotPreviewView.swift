import SwiftUI

/// View for previewing captured snapshot before confirming
struct SnapshotPreviewView: View {
    let imageData: Data
    let onConfirm: () -> Void
    let onRetake: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                // Image preview
                if let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .scaleEffect(isAnimating ? 1.0 : 1.05)
                        .animation(.howruSmooth, value: isAnimating)
                }

                // UI Overlay
                VStack {
                    // Top bar with close button
                    HStack {
                        Button(action: {
                            HowRUHaptics.light()
                            onRetake()
                        }) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                        }

                        Spacer()
                    }
                    .padding(.horizontal, HowRUSpacing.screenEdge)
                    .padding(.top, HowRUSpacing.md)

                    Spacer()

                    // Info about expiration
                    HStack(spacing: HowRUSpacing.sm) {
                        Image(systemName: "clock")
                            .font(.system(size: 14, weight: .medium))
                        Text("Expires in 24 hours")
                            .font(HowRUFont.caption())
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, HowRUSpacing.lg)
                    .padding(.vertical, HowRUSpacing.sm)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Capsule())

                    Spacer()

                    // Bottom controls
                    HStack(spacing: HowRUSpacing.lg) {
                        // Retake button
                        Button(action: {
                            HowRUHaptics.light()
                            onRetake()
                        }) {
                            VStack(spacing: HowRUSpacing.xs) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 24, weight: .medium))
                                Text("Retake")
                                    .font(HowRUFont.caption())
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, HowRUSpacing.md)
                            .background(Color.black.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: HowRURadius.md))
                        }

                        // Confirm button
                        Button(action: {
                            HowRUHaptics.success()
                            onConfirm()
                        }) {
                            VStack(spacing: HowRUSpacing.xs) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 24, weight: .medium))
                                Text("Use Photo")
                                    .font(HowRUFont.caption())
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, HowRUSpacing.md)
                            .background(HowRUColors.coral)
                            .clipShape(RoundedRectangle(cornerRadius: HowRURadius.md))
                        }
                    }
                    .padding(.horizontal, HowRUSpacing.screenEdge)
                    .padding(.bottom, HowRUSpacing.xxl)
                }
            }
        }
        .onAppear {
            withAnimation {
                isAnimating = true
            }
        }
    }
}

// MARK: - Preview

#Preview("Snapshot Preview") {
    // Create a sample image
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400))
    let sampleImage = renderer.image { context in
        UIColor.systemBlue.setFill()
        context.fill(CGRect(origin: .zero, size: CGSize(width: 300, height: 400)))
    }

    return SnapshotPreviewView(
        imageData: sampleImage.jpegData(compressionQuality: 0.8) ?? Data(),
        onConfirm: { print("Confirmed") },
        onRetake: { print("Retake") }
    )
}
