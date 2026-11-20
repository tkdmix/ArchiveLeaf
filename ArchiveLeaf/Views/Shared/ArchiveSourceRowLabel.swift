import SwiftUI

/// The shared content of a selectable source row on SwiftUI platforms.
///
/// The surrounding navigation stays native to each platform and width. Keeping the label here
/// prevents folders, tags, favorites, and Trash from quietly acquiring different count rules or
/// label layouts merely because they were introduced in different screens. Row sizing remains the
/// responsibility of the platform's native `List` or outline view.
///
/// Two marks can sit on a row, and they are not the same mark:
///
/// - the triangle at the **leading** edge opens what is inside this row, where it has anything
///   inside. It is where the Mac's outline puts it, and where every outline the system draws puts
///   it. `List` would have placed it at the trailing edge, beside a number and beside the other
///   chevron, where three unrelated things read as one control.
/// - the chevron at the **trailing** edge says that tapping goes somewhere. A pane that only
///   chooses what the pane beside it shows — the Mac's and the iPad's — shows none.
struct ArchiveSourceRowLabel: View {
    let name: String
    let systemImage: String
    let itemCount: Int
    /// Whether what is inside is open, or `nil` where the row has nothing inside it. The space is
    /// kept either way, so names down one level still line up.
    var disclosure: Binding<Bool>?
    /// Whether tapping this row pushes a screen rather than selecting.
    var navigates = false

    /// The triangle's own width, kept whether or not there is a triangle in it.
    private static let disclosureWidth: CGFloat = 22

    var body: some View {
        HStack(spacing: 0) {
            disclosureControl
            LabeledContent {
                HStack(spacing: 8) {
                    if itemCount > 0 {
                        Text(itemCount.formatted())
                    }
                    if navigates {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            } label: {
                Label(name, systemImage: systemImage)
            }
        }
    }

    @ViewBuilder
    private var disclosureControl: some View {
        if let disclosure {
            Button {
                disclosure.wrappedValue.toggle()
            } label: {
                Image(systemName: disclosure.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tint)
                    .frame(width: Self.disclosureWidth, alignment: .leading)
                    .contentShape(.rect)
            }
            // Plain, or pressing the triangle would fire the row's own tap as well.
            .buttonStyle(.plain)
            .accessibilityLabel(disclosure.wrappedValue ? "Collapse" : "Expand")
        } else {
            Color.clear.frame(width: Self.disclosureWidth, height: 0)
        }
    }
}
