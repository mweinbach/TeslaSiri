import SwiftUI
import UIKit

/// Pragmatic hybrid example: embed a UIKit `UICollectionView` + `NSDiffableDataSourceSnapshot`
/// inside SwiftUI when you need guaranteed 120Hz cell recycling on 1,000+ rich rows,
/// paired with a native UIKit Liquid Glass floating pill cluster using
/// `UIGlassContainerEffect` + `UIGlassEffect` + `UIScrollEdgeElementContainerInteraction`.
@available(iOS 26, *)
struct HighFPSFeedScreen: View {
    let items: [FeedItem]
    let onPrimaryAction: () -> Void
    let onFilterAction: () -> Void

    var body: some View {
        HighFPSCollectionBridge(
            items: items,
            onPrimaryAction: onPrimaryAction,
            onFilterAction: onFilterAction
        )
        .ignoresSafeArea()
    }
}

struct FeedItem: Hashable, Sendable {
    let id: UUID
    let title: String
    let metric: String
}

@available(iOS 26, *)
private struct HighFPSCollectionBridge: UIViewControllerRepresentable {
    let items: [FeedItem]
    let onPrimaryAction: () -> Void
    let onFilterAction: () -> Void

    func makeUIViewController(context: Context) -> HighFPSFeedViewController {
        HighFPSFeedViewController(
            onPrimaryAction: onPrimaryAction,
            onFilterAction: onFilterAction
        )
    }

    func updateUIViewController(_ vc: HighFPSFeedViewController, context: Context) {
        vc.onPrimaryAction = onPrimaryAction
        vc.onFilterAction = onFilterAction
        vc.apply(items: items)
    }
}

@available(iOS 26, *)
private final class HighFPSFeedViewController: UIViewController {
    var onPrimaryAction: () -> Void
    var onFilterAction: () -> Void

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, FeedItem>!
    private var lastAppliedItems: [FeedItem] = []

    // Parent glass container batches child glass passes and enables fluid proximity merging
    private let glassContainerView: UIVisualEffectView = {
        let container = UIGlassContainerEffect()
        container.spacing = 12
        let view = UIVisualEffectView(effect: container)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    init(onPrimaryAction: @escaping () -> Void, onFilterAction: @escaping () -> Void) {
        self.onPrimaryAction = onPrimaryAction
        self.onFilterAction = onFilterAction
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupCollectionView()
        setupFloatingGlassDock()
    }

    private func setupCollectionView() {
        var listConfig = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        listConfig.backgroundColor = .systemBackground
        let layout = UICollectionViewCompositionalLayout.list(using: listConfig)

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Leave comfortable room at bottom for the floating glass dock
        collectionView.contentInset.bottom = 96
        view.addSubview(collectionView)

        let cellReg = UICollectionView.CellRegistration<UICollectionViewListCell, FeedItem> { cell, _, item in
            // Content cells remain clean opaque surfaces — NEVER put UIGlassEffect inside scrolling cells
            var content = cell.defaultContentConfiguration()
            content.text = item.title
            content.secondaryText = item.metric
            content.secondaryTextProperties.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
            cell.contentConfiguration = content
        }

        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, item in
            cv.dequeueConfiguredReusableCell(using: cellReg, for: indexPath, item: item)
        }
    }

    private func setupFloatingGlassDock() {
        view.addSubview(glassContainerView)

        // Register the floating container for native scroll-edge coordination
        let edgeInteraction = UIScrollEdgeElementContainerInteraction()
        edgeInteraction.scrollView = collectionView
        edgeInteraction.edge = .bottom
        glassContainerView.addInteraction(edgeInteraction)

        let filterPill = makeGlassButton(
            systemImage: "line.3.horizontal.decrease",
            tint: nil,
            action: UIAction { [weak self] _ in self?.onFilterAction() }
        )
        let primaryPill = makeGlassButton(
            systemImage: "plus",
            tint: .systemBlue,
            action: UIAction { [weak self] _ in self?.onPrimaryAction() }
        )

        let stack = UIStackView(arrangedSubviews: [filterPill, primaryPill])
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        glassContainerView.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            glassContainerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            glassContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: glassContainerView.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: glassContainerView.contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: glassContainerView.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: glassContainerView.contentView.trailingAnchor)
        ])
    }

    private func makeGlassButton(systemImage: String, tint: UIColor?, action: UIAction) -> UIVisualEffectView {
        let glass = UIGlassEffect(style: .regular)
        glass.isInteractive = true
        glass.tintColor = tint

        let effectView = UIVisualEffectView(effect: glass)
        effectView.cornerConfiguration = .capsule()
        effectView.translatesAutoresizingMaskIntoConstraints = false

        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: systemImage)
        config.baseForegroundColor = tint == nil ? .label : .white
        let button = UIButton(configuration: config, primaryAction: action)
        button.translatesAutoresizingMaskIntoConstraints = false

        effectView.contentView.addSubview(button)
        NSLayoutConstraint.activate([
            effectView.widthAnchor.constraint(equalToConstant: 48),
            effectView.heightAnchor.constraint(equalToConstant: 48),
            button.centerXAnchor.constraint(equalTo: effectView.contentView.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: effectView.contentView.centerYAnchor)
        ])
        return effectView
    }

    func apply(items: [FeedItem]) {
        guard items != lastAppliedItems else { return }
        lastAppliedItems = items
        var snapshot = NSDiffableDataSourceSnapshot<Int, FeedItem>()
        snapshot.appendSections([0])
        snapshot.appendItems(items)
        dataSource.apply(snapshot, animatingDifferences: true)
    }
}
