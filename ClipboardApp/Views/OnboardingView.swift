import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var page = 0
    @State private var selectedDetent: PresentationDetent = .medium
    private let pages: [(title: LocalizedStringKey, image: String, description: LocalizedStringKey)] = [
        ("Your clipboard, ready to type", "doc.on.clipboard", "Save text snippets and insert them from your clipboard."),
        ("Enable and switch", "globe", "In Settings, go to General > Keyboard > Keyboards > Add New Keyboard, then select Clipboard. Tap the globe key while typing to switch to it."),
        ("Private by design", "lock", "Snippets stay on your device unless you turn on iCloud sync in the app’s Settings. Full Access is only needed to save, favorite, or delete snippets from the keyboard.")
    ]

    var body: some View {
        // Keeping the scroller and the controls as siblings gives the footer a fixed
        // place without covering content at accessibility sizes. They intentionally
        // share the presentation's system material instead of adding a second bar.
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: pages[page].image)
                        .font(.system(size: 56))
                        .symbolRenderingMode(.hierarchical)
                    Text(pages[page].title)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("onboardingPageTitle")
                    Text(pages[page].description)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.vertical, 36)
            }

            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.35))
                            .frame(width: index == page ? 24 : 8, height: 8)
                    }
                }

                Button {
                    if page == pages.count - 1 {
                        hasCompletedOnboarding = true
                    } else {
                        withAnimation {
                            page += 1
                        }
                    }
                } label: {
                    Text(LocalizedStringKey(page == pages.count - 1 ? "Get Started" : "Continue"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint(Text(LocalizedStringKey(page == pages.count - 1 ? "Completes onboarding" : "Shows the next onboarding step")))
                .accessibilityIdentifier("onboardingPrimaryButton")
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
        .onAppear {
            selectedDetent = detent(for: dynamicTypeSize)
        }
        .onChange(of: dynamicTypeSize) { _, newSize in
            selectedDetent = detent(for: newSize)
        }
    }

    private func detent(for size: DynamicTypeSize) -> PresentationDetent {
        size.isAccessibilitySize ? .large : .medium
    }
}
