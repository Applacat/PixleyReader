import SwiftUI

// MARK: - Error Banner

/// A status bar banner that slides up from the bottom to display errors/warnings.
/// Auto-dismisses after 5 seconds or can be manually dismissed via X button.
struct ErrorBanner: View {

    let error: AppError
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Indicator icon
            Image(systemName: error.isWarning ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(indicatorColor)

            // Error message
            Text(error.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer()

            // Dismiss button
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
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

/// View modifier that overlays an error banner when AppState has a currentError.
struct ErrorBannerOverlay: ViewModifier {

    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let error = appState.currentError {
                ErrorBanner(error: error) {
                    appState.dismissError()
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appState.currentError)
            }
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

#Preview("Warning") {
    VStack {
        Spacer()
        ErrorBanner(error: .warning(message: "Content exceeds size limit. Some features may be disabled.")) { }
    }
    .frame(width: 400, height: 200)
    .background(.gray.opacity(0.2))
}

#Preview("Error") {
    VStack {
        Spacer()
        ErrorBanner(error: .error(message: "File too large (15.2 MB). Maximum is 10 MB.")) { }
    }
    .frame(width: 400, height: 200)
    .background(.gray.opacity(0.2))
}
