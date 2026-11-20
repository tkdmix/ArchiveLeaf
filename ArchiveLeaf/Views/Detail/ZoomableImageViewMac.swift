#if os(macOS)
import AppKit
import SwiftUI

/// Paging through a folder's pictures with the trackpad, following the fingers.
///
/// `NSPageController` in horizontal-strip mode is AppKit's own answer to this: it tracks the swipe
/// live, brings the neighbour in as the fingers move, and puts it back if the gesture is abandoned.
/// Rolling this by hand out of `trackSwipeEvent` would be re-deriving what it already does.
struct PagingImageView: NSViewControllerRepresentable {
    let images: [ArchiveFile]
    let contents: [UUID: LoadedImageContent]
    @Binding var selection: UUID
    /// A one-shot request from the toolbar, cleared once carried out.
    @Binding var zoomCommand: ImageZoomCommand?

    func makeNSViewController(context: Context) -> ImagePageController {
        let controller = ImagePageController()
        controller.onSelect = { selection = $0 }
        return controller
    }

    func updateNSViewController(_ controller: ImagePageController, context: Context) {
        controller.onSelect = { selection = $0 }
        controller.update(pictureIDs: images.map(\.id), contents: contents, selection: selection)
        guard let command = zoomCommand else { return }
        controller.apply(command)
        // Clearing during the update itself would be a write back into the same pass.
        DispatchQueue.main.async { zoomCommand = nil }
    }
}

final class ImagePageController: NSPageController, NSPageControllerDelegate {
    var onSelect: ((UUID) -> Void)?
    private var contents: [UUID: LoadedImageContent] = [:]
    /// Pages are moved, not resized, while the strip animates; laying them out then would fight it.
    private var isTransitioning = false

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        transitionStyle = .horizontalStrip
    }

    /// The strip places a page once and leaves it at that size. Without this a page built in a
    /// small window keeps those bounds when the window grows — the picture ends up off to one
    /// side, or off screen entirely.
    override func viewDidLayout() {
        super.viewDidLayout()
        guard !isTransitioning else { return }
        for page in children {
            page.view.frame = view.bounds
        }
    }

    func update(pictureIDs: [UUID], contents: [UUID: LoadedImageContent], selection: UUID) {
        self.contents = contents
        if arrangedObjects as? [UUID] != pictureIDs {
            arrangedObjects = pictureIDs
        }
        if let index = pictureIDs.firstIndex(of: selection), index != selectedIndex {
            // Assigned rather than animated: this path is the list alongside changing the
            // selection, where there is no gesture to carry the movement.
            selectedIndex = index
        }
        // A picture can arrive after its page was prepared, which is the usual case for the
        // neighbours: the page is built empty and filled once the bytes are here.
        currentPage?.content = contents[selection]
    }

    func apply(_ command: ImageZoomCommand) {
        currentPage?.apply(command)
    }

    private var currentPage: ImagePageViewController? {
        selectedViewController as? ImagePageViewController
    }

    // MARK: - NSPageControllerDelegate

    /// One identifier for every page, so the controllers are reused rather than accumulating as
    /// the user works through a large folder.
    func pageController(
        _ pageController: NSPageController,
        identifierFor object: Any
    ) -> NSPageController.ObjectIdentifier {
        "picture"
    }

    func pageController(
        _ pageController: NSPageController,
        viewControllerForIdentifier identifier: NSPageController.ObjectIdentifier
    ) -> NSViewController {
        ImagePageViewController()
    }

    func pageController(
        _ pageController: NSPageController,
        prepare viewController: NSViewController,
        with object: Any?
    ) {
        guard let page = viewController as? ImagePageViewController, let id = object as? UUID else {
            return
        }
        page.content = contents[id]
    }

    func pageControllerWillStartLiveTransition(_ pageController: NSPageController) {
        isTransitioning = true
    }

    func pageControllerDidEndLiveTransition(_ pageController: NSPageController) {
        isTransitioning = false
        // Without this the strip stays mid-transition; it is how the snapshot is swapped for the
        // live view again.
        pageController.completeTransition()
        guard let ids = arrangedObjects as? [UUID], ids.indices.contains(selectedIndex) else {
            return
        }
        onSelect?(ids[selectedIndex])
    }
}

/// One picture in the strip.
final class ImagePageViewController: NSViewController {
    var content: LoadedImageContent? {
        didSet {
            guard content?.data != oldValue?.data else { return }
            showContent()
        }
    }

    private var scrollView: BoundedZoomScrollView?

    override func loadView() {
        view = NSView()
        view.autoresizingMask = [.width, .height]
    }

    func apply(_ command: ImageZoomCommand) {
        scrollView?.apply(command)
    }

    private func showContent() {
        scrollView?.removeFromSuperview()
        scrollView = nil
        guard let content else { return }

        let scrollView = BoundedZoomScrollView()
        scrollView.contentView = CenteringClipView()
        scrollView.allowsMagnification = true
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        // Without this the picture rubber-bands past its own edge, which is the drifting the
        // gesture work set out to remove.
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none

        // Sized in pixels rather than from the decoded image, whose own size carries the file's
        // DPI: "actual size" has always meant one stored pixel to one point.
        let pixelSize = NSSize(width: content.pixelWidth, height: content.pixelHeight)
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: pixelSize))
        imageView.image = NSImage(data: content.data)
        imageView.imageScaling = .scaleAxesIndependently
        scrollView.documentView = imageView

        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.width, .height]
        view.addSubview(scrollView)
        self.scrollView = scrollView
    }
}

/// Keeps the picture inside its own bounds and centred when it is smaller than the window.
final class BoundedZoomScrollView: NSScrollView {
    private var lastFrameSize: NSSize = .zero
    private var hasFitted = false

    override func layout() {
        super.layout()
        frameChanged()
    }

    /// Also here because a scroll view laid out by hand is resized without a layout pass.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        frameChanged()
    }

    private func frameChanged() {
        guard frame.size != lastFrameSize else { return }
        // Magnification starts at 1 against a default minimum, so the first pass has to be told
        // to fit rather than asked whether it already does.
        let wasFitted = !hasFitted || magnification <= minMagnification + imageZoomEpsilon
        lastFrameSize = frame.size
        updateMagnificationLimits()
        if wasFitted {
            magnification = minMagnification
            hasFitted = true
        }
    }

    func apply(_ command: ImageZoomCommand) {
        let target: CGFloat
        switch command {
        case .fit:
            target = minMagnification
        case .actualSize:
            target = 1
        case .zoomIn:
            target = magnification * ImageZoomCommand.step
        case .zoomOut:
            target = magnification / ImageZoomCommand.step
        }
        animate(to: min(max(target, minMagnification), maxMagnification))
    }

    /// Two-finger double tap on the trackpad. The Mac's answer to iOS's double tap, and mapped to
    /// the same pair of destinations.
    override func smartMagnify(with event: NSEvent) {
        guard magnification <= minMagnification + imageZoomEpsilon else {
            animate(to: minMagnification)
            return
        }
        let target = min(minMagnification * ImageZoomCommand.doubleTapFactor, maxMagnification)
        setMagnification(target, centeredAt: convert(event.locationInWindow, from: nil))
    }

    /// While the whole picture is on screen there is nothing here to scroll, and a sideways swipe
    /// belongs to the page controller above. A scroll view swallows the event unless handed on.
    override func scrollWheel(with event: NSEvent) {
        if magnification <= minMagnification + imageZoomEpsilon,
           abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            nextResponder?.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    private func animate(to magnification: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.allowsImplicitAnimation = true
            animator().magnification = magnification
        }
    }

    private func updateMagnificationLimits() {
        guard let documentView, documentView.frame.width > 0, documentView.frame.height > 0,
              frame.width > 0, frame.height > 0 else {
            return
        }
        let fitScale = min(
            frame.width / documentView.frame.width,
            frame.height / documentView.frame.height
        )
        minMagnification = fitScale
        maxMagnification = ImageZoomCommand.maximumScale(fittingScale: fitScale)
    }
}

/// `NSClipView` pins an undersized document to a corner; this holds it in the middle instead.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        if rect.width > documentView.frame.width {
            rect.origin.x = (documentView.frame.width - rect.width) / 2
        }
        if rect.height > documentView.frame.height {
            rect.origin.y = (documentView.frame.height - rect.height) / 2
        }
        return rect
    }
}
#endif
