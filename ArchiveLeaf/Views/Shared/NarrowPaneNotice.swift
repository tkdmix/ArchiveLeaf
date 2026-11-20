import SwiftUI

/// What a pane says when it has nothing to show, said in as much room as there is.
///
/// Below a certain width the words stop being words: they wrap to one character a line and read
/// vertically. The symbol alone still says the pane is empty, and it is the pane's content the
/// reader wanted the room for.
struct PaneNotice: View {
    let title: LocalizedStringResource
    let systemImage: String
    let description: LocalizedStringResource?
    let width: CGFloat
    @ViewBuilder var actions: () -> AnyView

    init(
        _ title: LocalizedStringResource,
        systemImage: String,
        description: LocalizedStringResource? = nil,
        width: CGFloat,
        @ViewBuilder actions: @escaping () -> AnyView = { AnyView(EmptyView()) }
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.width = width
        self.actions = actions
    }

    var body: some View {
        if width >= 260 {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 42))
                    .foregroundStyle(.tertiary)
                Text(title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let description {
                    Text(description)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                actions()
            }
            // ContentUnavailableView keeps a fairly wide intrinsic label on iPadOS 17. In a
            // split column it can be clipped instead of wrapping; this explicit maximum makes
            // the notice obey the pane it belongs to.
            .frame(maxWidth: min(max(width - 40, 0), 420))
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
                .accessibilityLabel(Text(title))
                // Filling, so that whatever measures this pane measures the pane and not the
                // symbol standing in the middle of it.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
