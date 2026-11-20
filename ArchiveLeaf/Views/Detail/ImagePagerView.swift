#if !os(macOS)
import SwiftUI
import UIKit

/// Looking through pictures the way the system photo viewer does: the neighbour arrives with the
/// finger and can be abandoned halfway.
///
/// Leaving is the navigation stack's own edge swipe. It begins at the very edge and never meets a
/// swipe through the middle, so carrying the picture downwards as well would be a second way back
/// to keep working for nothing.
///
/// A paging `UIScrollView` holding one zooming scroll view per picture — the arrangement Apple's
/// own photo browser uses. Nesting a zooming scroll view inside SwiftUI's paging `TabView` looked
/// equivalent but left neither gesture tracking: the page turned and the picture left, both in one
/// step, once enough distance had been covered.
struct ImagePagerView: UIViewRepresentable {
    let pictureIDs: [UUID]
    let contents: [UUID: LoadedImageContent]
    @Binding var selection: UUID
    /// A one-shot request from the toolbar, cleared once carried out.
    @Binding var zoomCommand: ImageZoomCommand?

    func makeUIView(context: Context) -> ImagePagerContainerView {
        let view = ImagePagerContainerView()
        view.onSelect = { selection = $0 }
        return view
    }

    func updateUIView(_ view: ImagePagerContainerView, context: Context) {
        view.onSelect = { selection = $0 }
        view.update(pictureIDs: pictureIDs, contents: contents, selection: selection)
        guard let command = zoomCommand else { return }
        view.apply(command)
        // Clearing during the update itself would be a write back into the same pass.
        DispatchQueue.main.async { zoomCommand = nil }
    }
}

final class ImagePagerContainerView: UIView, UIScrollViewDelegate {
    var onSelect: ((UUID) -> Void)?

    /// Transformed while leaving, which is why it sits inside a plain container rather than being
    /// the root: the root's frame belongs to SwiftUI, and a transform on it fights the layout.
    private let pager = UIScrollView()
    private var pages: [Int: ZoomingImagePageView] = [:]
    private var pictureIDs: [UUID] = []
    private var contents: [UUID: LoadedImageContent] = [:]
    private var currentIndex = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        pager.delegate = self
        pager.isPagingEnabled = true
        pager.showsHorizontalScrollIndicator = false
        pager.showsVerticalScrollIndicator = false
        pager.contentInsetAdjustmentBehavior = .never
        pager.backgroundColor = .clear
        addSubview(pager)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Contents

    func update(pictureIDs: [UUID], contents: [UUID: LoadedImageContent], selection: UUID) {
        let listChanged = pictureIDs != self.pictureIDs
        self.pictureIDs = pictureIDs
        self.contents = contents

        if let index = pictureIDs.firstIndex(of: selection), index != currentIndex || listChanged {
            currentIndex = index
            // Jumped rather than animated: this path is the list alongside changing the
            // selection, where there is no gesture to carry the movement.
            if bounds.width > 0 {
                pager.contentOffset = CGPoint(x: CGFloat(index) * bounds.width, y: 0)
            }
        }
        setNeedsLayout()
        layoutPages()
    }

    func apply(_ command: ImageZoomCommand) {
        pages[currentIndex]?.apply(command)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        if pager.frame != bounds {
            pager.frame = bounds
            pager.contentOffset = CGPoint(x: CGFloat(currentIndex) * bounds.width, y: 0)
        }
        pager.contentSize = CGSize(
            width: bounds.width * CGFloat(pictureIDs.count),
            height: bounds.height
        )
        layoutPages()
    }

    /// Only the picture on screen and the one either side exist. Paging through a long folder
    /// otherwise leaves every picture it passed still loaded.
    private func layoutPages() {
        guard bounds.width > 0 else { return }
        let wanted = Set((currentIndex - 1...currentIndex + 1).filter { pictureIDs.indices.contains($0) })

        for (index, page) in pages where !wanted.contains(index) {
            page.removeFromSuperview()
            pages[index] = nil
        }
        for index in wanted {
            let page = pages[index] ?? makePage(at: index)
            page.frame = CGRect(
                x: CGFloat(index) * bounds.width,
                y: 0,
                width: bounds.width,
                height: bounds.height
            )
            page.show(contents[pictureIDs[index]])
        }
    }

    private func makePage(at index: Int) -> ZoomingImagePageView {
        let page = ZoomingImagePageView()
        pager.addSubview(page)
        pages[index] = page
        return page
    }

    // MARK: - Paging

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settle() }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { settle() }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate: Bool) {
        if !willDecelerate { settle() }
    }

    private func settle() {
        guard bounds.width > 0 else { return }
        let index = Int((pager.contentOffset.x / bounds.width).rounded())
        guard pictureIDs.indices.contains(index), index != currentIndex else { return }
        // A picture left behind keeps whatever zoom it was given; coming back to it should show
        // the whole thing again, as the viewer it was left for does.
        pages[currentIndex]?.resetZoom()
        currentIndex = index
        layoutPages()
        onSelect?(pictureIDs[index])
    }

}

/// One picture, zoomable, panning that stops at its own edge.
///
/// A `UIScrollView` rather than anything assembled in SwiftUI: an image smaller than the page has
/// to stay put in the middle, and a larger one has to stop where it ends.
final class ZoomingImagePageView: UIScrollView, UIScrollViewDelegate {
    private let pictureView = UIImageView()
    private var content: LoadedImageContent?
    private var lastBoundsSize: CGSize = .zero
    private var hasFitted = false

    init() {
        super.init(frame: .zero)
        delegate = self
        // No drifting past the picture, and no drifting at all when it is smaller than the page.
        bounces = false
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        addSubview(pictureView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var isFitted: Bool { zoomScale <= minimumZoomScale + imageZoomEpsilon }

    func show(_ content: LoadedImageContent?) {
        guard content?.data != self.content?.data else { return }
        self.content = content
        pictureView.image = content.flatMap { UIImage(data: $0.data) }
        // Sized in pixels rather than from the decoded image, so "actual size" means one stored
        // pixel to one point on both platforms.
        let pixelSize = content.map { CGSize(width: $0.pixelWidth, height: $0.pixelHeight) } ?? .zero
        pictureView.frame = CGRect(origin: .zero, size: pixelSize)
        contentSize = pixelSize
        hasFitted = false
        lastBoundsSize = .zero
        setNeedsLayout()
    }

    func resetZoom() {
        guard !isFitted else { return }
        setZoomScale(minimumZoomScale, animated: false)
    }

    func apply(_ command: ImageZoomCommand) {
        let scale: CGFloat
        switch command {
        case .fit:
            scale = minimumZoomScale
        case .actualSize:
            // One stored pixel to one point, which is what the Mac window has always meant.
            scale = 1
        case .zoomIn:
            scale = zoomScale * ImageZoomCommand.step
        case .zoomOut:
            scale = zoomScale / ImageZoomCommand.step
        }
        setZoomScale(min(max(scale, minimumZoomScale), maximumZoomScale), animated: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, contentSize != .zero else { return }
        if bounds.size != lastBoundsSize {
            // Recomputed on every bounds change so rotation keeps the same meaning of "fits".
            let wasFitted = !hasFitted || isFitted
            lastBoundsSize = bounds.size
            updateZoomLimits()
            if wasFitted {
                zoomScale = minimumZoomScale
                hasFitted = true
            }
        }
        centerContent()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { pictureView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard !isFitted else {
            let scale = min(minimumZoomScale * ImageZoomCommand.doubleTapFactor, maximumZoomScale)
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            let point = recognizer.location(in: pictureView)
            zoom(
                to: CGRect(
                    x: point.x - size.width / 2,
                    y: point.y - size.height / 2,
                    width: size.width,
                    height: size.height
                ),
                animated: true
            )
            return
        }
        setZoomScale(minimumZoomScale, animated: true)
    }

    private func updateZoomLimits() {
        guard pictureView.bounds.width > 0, pictureView.bounds.height > 0, bounds.width > 0 else {
            return
        }
        let fitScale = min(
            bounds.width / pictureView.bounds.width,
            bounds.height / pictureView.bounds.height
        )
        minimumZoomScale = fitScale
        maximumZoomScale = ImageZoomCommand.maximumScale(fittingScale: fitScale)
    }

    private func centerContent() {
        let insetX = max(0, (bounds.width - contentSize.width) / 2)
        let insetY = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }
}
#endif
