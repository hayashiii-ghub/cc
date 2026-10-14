import AppKit
import SwiftUI

enum NotchIslandPhase: Equatable {
    case compact
    case targeted
    case expanded
    case accepted
}

final class NotchIslandPresentationState: ObservableObject {
    @Published var phase: NotchIslandPhase = .compact

    func showAcceptedDrop() {
        phase = .accepted
    }

    func finishAcceptedDrop() {
        phase = .compact
    }
}

struct NotchIslandView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var presentation: NotchIslandPresentationState
    let topInset: CGFloat
    let notchWidth: CGFloat
    let sideTabWidth: CGFloat
    let contentWidth: CGFloat
    let onToggleExpanded: () -> Void
    let onDismiss: () -> Void
    let onAddFinderSelection: () -> Void
    let onShowMenu: (NSView) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            islandShell

            ZStack(alignment: .top) {
                compactView
                    .opacity(isCompact ? 1 : 0)
                    .allowsHitTesting(isCompact)
                    .accessibilityHidden(!isCompact)

                dropView
                    .opacity(isDropState ? 1 : 0)
                    .allowsHitTesting(isDropState)
                    .accessibilityHidden(!isDropState)

                expandedView
                    .opacity(isExpanded ? 1 : 0)
                    .allowsHitTesting(isExpanded)
                    .accessibilityHidden(!isExpanded)
                    .animation(
                        isExpanded
                            ? .easeOut(duration: 0.12).delay(0.14)
                            : .linear(duration: 0.03),
                        value: isExpanded
                    )
            }
            .frame(width: expandedSize.width, height: expandedSize.height, alignment: .top)
            .mask(alignment: .top) {
                islandMask
            }
        }
        .frame(width: expandedSize.width, height: expandedSize.height, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("cc: Island")
    }

    private var islandShell: some View {
        NotchIslandShape(cornerRadius: shellCornerRadius)
            .fill(Color.black)
            .overlay {
                NotchIslandShape(cornerRadius: shellCornerRadius)
                    .strokeBorder(.white.opacity(isExpanded ? 0.12 : 0), lineWidth: 0.5)
            }
            .frame(width: visibleSize.width, height: visibleSize.height)
            .animation(shellAnimation, value: presentation.phase)
    }

    private var islandMask: some View {
        NotchIslandShape(cornerRadius: shellCornerRadius)
            .frame(width: visibleSize.width, height: visibleSize.height)
            .animation(shellAnimation, value: presentation.phase)
    }

    private var compactView: some View {
        ZStack {
            Color.clear
                .overlay(alignment: .leading) {
                    CCMark()
                        .fill(.white.opacity(0.88))
                        .frame(width: 16, height: 16)
                        .overlay(alignment: .topTrailing) {
                            if !store.unreadItemIDs.isEmpty {
                                Circle().fill(.blue).frame(width: 5, height: 5)
                                    .offset(x: 2, y: -2)
                            }
                        }
                        .accessibilityHidden(true)
                        .padding(.leading, 9)
                }
                .overlay(alignment: .trailing) {
                    Text(itemCountLabel)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 20)
                        .padding(.trailing, 9)
                        .accessibilityLabel("\(store.items.count) items in cc:")
                }
        }
        .frame(width: compactSize.width, height: compactSize.height)
        .contentShape(NotchIslandShape(cornerRadius: 12))
        .onTapGesture(perform: onToggleExpanded)
        .help("Open cc:")
    }

    private var dropView: some View {
        ZStack(alignment: .bottom) {
            Color.clear

            Group {
                switch presentation.phase {
                case .accepted:
                    Label("Added to cc:", systemImage: "checkmark")
                default:
                    Label("Drop to cc:", systemImage: "arrow.down")
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .frame(height: NotchScreenGeometry.dropExtraHeight)
        }
        .frame(width: dropSize.width, height: dropSize.height)
    }

    private var expandedView: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: topInset)
            ShelfContentView(
                store: store,
                surface: .island,
                onDismiss: onDismiss,
                onShowMenu: onShowMenu,
                onAddFiles: onAddFinderSelection
            )
            .preferredColorScheme(.dark)
        }
        .frame(width: expandedSize.width, height: expandedSize.height)
    }

    private var expandedSize: NSSize {
        NSSize(
            width: contentWidth,
            height: topInset + ShelfLayout.size(itemCount: store.items.count).height
        )
    }

    private var visibleSize: NSSize {
        switch presentation.phase {
        case .compact: compactSize
        case .targeted, .accepted: dropSize
        case .expanded: expandedSize
        }
    }

    private var compactSize: NSSize {
        NSSize(width: notchWidth + sideTabWidth * 2, height: topInset)
    }

    private var dropSize: NSSize {
        NSSize(
            width: max(NotchScreenGeometry.dropMinimumWidth, notchWidth + sideTabWidth * 2),
            height: topInset + NotchScreenGeometry.dropExtraHeight
        )
    }

    private var isCompact: Bool {
        presentation.phase == .compact
    }

    private var isDropState: Bool {
        presentation.phase == .targeted || presentation.phase == .accepted
    }

    private var isExpanded: Bool {
        presentation.phase == .expanded
    }

    private var shellCornerRadius: CGFloat {
        switch presentation.phase {
        case .compact: 12
        case .targeted, .accepted: 20
        case .expanded: 22
        }
    }

    private var shellAnimation: Animation {
        .spring(response: 0.34, dampingFraction: 0.86)
    }

    private var itemCountLabel: String {
        store.items.count > 99 ? "99+" : "\(store.items.count)"
    }
}

private struct NotchIslandShape: InsettableShape {
    var cornerRadius: CGFloat
    var inset: CGFloat = 0

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 0,
                bottomLeading: cornerRadius,
                bottomTrailing: cornerRadius,
                topTrailing: 0
            ),
            style: .continuous
        )
        .inset(by: inset)
        .path(in: rect)
    }

    func inset(by amount: CGFloat) -> NotchIslandShape {
        var shape = self
        shape.inset += amount
        return shape
    }
}
