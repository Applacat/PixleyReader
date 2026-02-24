import SwiftUI
import AppKit

// MARK: - Error Banner

/// A status bar banner that slides up from the bottom to display errors/warnings.
/// Auto-dismisses after 5 seconds or can be manually dismissed via X button.
struct ErrorBanner: View {

    let error: AppError
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Indicator icon (scales with Dynamic Type)
            Image(systemName: error.isWarning ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(indicatorColor)
                .accessibilityHidden(true)

            // Error message (scales with Dynamic Type)
            Text(error.message)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer()

            // Dismiss button (scales with Dynamic Type)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(bannerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var indicatorColor: Color {
        error.isWarning ? .orange : .red
    }

    private var bannerBackground: some ShapeStyle {
        .regularMaterial
    }
}

// MARK: - Error Banner Container

/// View modifier that overlays an error banner when coordinator.ui has a currentError.
struct ErrorBannerOverlay: ViewModifier {

    @Environment(\.coordinator) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let errorDismissTimeout: Duration = .seconds(5)

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let error = coordinator.ui.currentError {
                ErrorBanner(error: error) {
                    coordinator.dismissError()
                }
                .animation(
                    reduceMotion
                        ? .none
                        : .spring(response: 0.4, dampingFraction: 0.8),
                    value: coordinator.ui.currentError
                )
            }
        }
        .task(id: coordinator.ui.currentError) {
            guard coordinator.ui.currentError != nil else { return }
            try? await Task.sleep(for: errorDismissTimeout)
            guard !Task.isCancelled else { return }
            coordinator.dismissError()
        }
    }
}

extension View {
    /// Adds an error banner overlay that displays AppState.currentError
    func errorBannerOverlay() -> some View {
        modifier(ErrorBannerOverlay())
    }
}

// MARK: - Preview
// Note: #Preview macros require Xcode - not available in CLI builds
