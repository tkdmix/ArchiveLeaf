import SwiftUI

extension View {
    /// Asks about something, and hands that something to whatever answers.
    ///
    /// A confirmation clears what it is asking about as it closes, and it closes before the work
    /// its button starts has run. Reading the state inside that work found nothing — twice, in the
    /// Trash and again in tag deletion, months apart, both times written by someone who knew the
    /// rule. A rule that can be broken by writing the obvious thing is not a rule.
    ///
    /// So the value never has to be read: the dialog captures it while it is up and passes it to
    /// the button and the message. There is no way to write the broken version here, which is the
    /// point of routing every confirmation through this.
    ///
    /// An alert rather than a confirmation dialog. On a phone the dialog rose from the bottom and
    /// worked; on an iPad it becomes a popover, which needs something on screen to point at, and
    /// asking from a button in the bar along the foot of the screen gave it nothing — the question
    /// appeared and vanished in the same instant, leaving the reader's Trash command silently
    /// undone. An alert needs no anchor and reads the same on every platform.
    func archiveConfirmation<Value>(
        _ title: LocalizedStringKey,
        presenting value: Binding<Value?>,
        confirmTitle: LocalizedStringKey,
        role: ButtonRole? = .destructive,
        message: ((Value) -> Text)? = nil,
        perform: @escaping (Value) -> Void
    ) -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { value.wrappedValue != nil },
                set: { if !$0 { value.wrappedValue = nil } }
            ),
            presenting: value.wrappedValue
        ) { presented in
            Button(confirmTitle, role: role) { perform(presented) }
            Button("Cancel", role: .cancel) { value.wrappedValue = nil }
        } message: { presented in
            if let message {
                message(presented)
            }
        }
    }

    /// The same, for a question about several things at once. Empty means nothing is being asked.
    func archiveConfirmation<Element>(
        _ title: LocalizedStringKey,
        presenting values: Binding<[Element]>,
        confirmTitle: LocalizedStringKey,
        role: ButtonRole? = .destructive,
        message: (([Element]) -> Text)? = nil,
        perform: @escaping ([Element]) -> Void
    ) -> some View {
        archiveConfirmation(
            title,
            presenting: Binding(
                get: { values.wrappedValue.isEmpty ? nil : values.wrappedValue },
                set: { values.wrappedValue = $0 ?? [] }
            ),
            confirmTitle: confirmTitle,
            role: role,
            message: message,
            perform: perform
        )
    }
}
