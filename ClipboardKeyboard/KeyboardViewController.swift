import UIKit

final class KeyboardViewController: UIInputViewController {
    private enum Section: Int { case recent, favorites }
    private let titleLabel = UILabel()
    private let sectionControl = UISegmentedControl(items: [String(localized: "Recent"), String(localized: "Favorites")])
    private let header = UIStackView()
    // A plain table keeps the keyboard compact. Cells use UIKit's list background
    // configuration so each snippet has system-provided rounded edges without the
    // extra top inset of an inset-grouped table in an input view.
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private let globeButton = UIButton(type: .system)
    private let accessLabel = UILabel()
    private let saveFromClipboardButton = UIButton(type: .system)
    private let actions = UIStackView()
    private var tableHeightConstraint: NSLayoutConstraint!
    private var allItems: [ClipboardItem] = []
    private var visibleItems: [ClipboardItem] = []
    private var store: ClipboardStore?
    private let ioQueue = DispatchQueue(label: "com.iosclipboard.keyboard-storage", qos: .userInitiated)

    override func loadView() {
        // UIKit supplies the keyboard's own tinting and blur when this view is hosted
        // by the custom keyboard extension. Do not cover that surface with a color.
        view = UIInputView(frame: .zero, inputViewStyle: .keyboard)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        inputView?.allowsSelfSizing = true
        setupInterface()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: KeyboardViewController, _) in
            self.updateHeaderLayout()
        }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let controller = Unmanaged<KeyboardViewController>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { controller.configureStoreAndReload() }
            },
            AppGroup.changeNotification as CFString, nil, .deliverImmediately)
    }

    deinit {
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), CFNotificationName(AppGroup.changeNotification as CFString), nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureStoreAndReload()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        configureStoreAndReload()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateKeyboardHeight()
    }

    private func updateHeaderLayout() {
        let accessibilitySize = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        header.axis = accessibilitySize ? .vertical : .horizontal
        header.alignment = accessibilitySize ? .fill : .center
        updateKeyboardHeight()
    }

    private func updateKeyboardHeight() {
        guard tableHeightConstraint != nil else { return }
        let compactHeight = traitCollection.verticalSizeClass == .compact
        let accessibilitySize = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        tableHeightConstraint.constant = compactHeight ? 116 : (accessibilitySize ? 178 : 190)
    }

    private func setupInterface() {
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)

        titleLabel.text = "Clipboard"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        sectionControl.selectedSegmentIndex = 0
        sectionControl.accessibilityIdentifier = "clipboardKeyboardSections"
        sectionControl.addTarget(self, action: #selector(sectionChanged), for: .valueChanged)

        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(sectionControl)
        header.spacing = 12
        updateHeaderLayout()

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.accessibilityIdentifier = "clipboardKeyboardSnippets"
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 52
        tableView.register(SnippetCell.self, forCellReuseIdentifier: SnippetCell.reuseIdentifier)

        emptyLabel.textAlignment = .center
        emptyLabel.font = .preferredFont(forTextStyle: .subheadline)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.numberOfLines = 2

        globeButton.setImage(UIImage(systemName: "globe"), for: .normal)
        globeButton.accessibilityLabel = String(localized: "Next keyboard")
        globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

        accessLabel.font = .preferredFont(forTextStyle: .caption1)
        accessLabel.accessibilityIdentifier = "clipboardKeyboardStatus"
        accessLabel.textColor = .secondaryLabel
        accessLabel.numberOfLines = 2
        accessLabel.adjustsFontForContentSizeCategory = true

        var saveConfiguration = UIButton.Configuration.filled()
        saveConfiguration.title = String(localized: "Save from clipboard")
        saveConfiguration.baseBackgroundColor = .systemBlue
        saveConfiguration.baseForegroundColor = .white
        saveConfiguration.cornerStyle = .capsule
        saveFromClipboardButton.configuration = saveConfiguration
        saveFromClipboardButton.accessibilityIdentifier = "clipboardSaveFromClipboardControl"
        saveFromClipboardButton.accessibilityLabel = String(localized: "Save from clipboard")
        saveFromClipboardButton.setContentHuggingPriority(.required, for: .horizontal)
        saveFromClipboardButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        saveFromClipboardButton.titleLabel?.numberOfLines = 1
        saveFromClipboardButton.addTarget(self, action: #selector(saveFromClipboard), for: .touchUpInside)

        actions.axis = .horizontal
        actions.spacing = 8
        actions.alignment = .center
        actions.addArrangedSubview(globeButton)
        actions.addArrangedSubview(accessLabel)
        actions.addArrangedSubview(UIView())
        actions.addArrangedSubview(saveFromClipboardButton)
        globeButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        globeButton.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let root = UIStackView(arrangedSubviews: [header, tableView, emptyLabel, actions])
        root.translatesAutoresizingMaskIntoConstraints = false
        root.axis = .vertical
        root.spacing = 6
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor),
        ])
        tableHeightConstraint = tableView.heightAnchor.constraint(equalToConstant: 190)
        tableHeightConstraint.isActive = true
        updateKeyboardHeight()
    }

    private func configureStoreAndReload() {
        do {
            store = try ClipboardStore(access: hasFullAccess ? .readWrite : .readOnly)
            showStatus(hasFullAccess ? nil : String(localized: "Enable Full Access to save from clipboard, favorite, or delete snippets here."))
            loadItems()
        } catch {
            store = nil
            allItems = []
            visibleItems = []
            showStatus(error.localizedDescription)
        }
        globeButton.isHidden = !needsInputModeSwitchKey
        saveFromClipboardButton.isHidden = !hasFullAccess || store == nil
        saveFromClipboardButton.isEnabled = hasFullAccess && store != nil
        updateActionsVisibility()
        if store == nil { updateSnapshot(); tableView.reloadData() }
    }

    @objc private func sectionChanged() { updateSnapshot(); tableView.reloadData() }

    private func loadItems() {
        guard let store else { return }
        ioQueue.async { [weak self] in
            let result = Result { try store.load() }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case let .success(items): self.allItems = items
                case let .failure(error): self.allItems = []; self.showStatus(error.localizedDescription)
                }
                self.updateSnapshot(); self.tableView.reloadData()
            }
        }
    }

    private func updateSnapshot() {
        switch Section(rawValue: sectionControl.selectedSegmentIndex) ?? .recent {
        case .recent: visibleItems = allItems
        case .favorites: visibleItems = allItems.filter(\.isFavorite)
        }
        updateEmptyState()
    }

    private func updateEmptyState() {
        let isEmpty = visibleItems.isEmpty
        emptyLabel.isHidden = !isEmpty
        if isEmpty {
            emptyLabel.text = String(localized: sectionControl.selectedSegmentIndex == Section.favorites.rawValue
                ? "No favorite snippets."
                : "Save from clipboard or create snippets in the app.")
        }
    }

    private func showStatus(_ message: String?) {
        accessLabel.text = message
        accessLabel.isHidden = message?.isEmpty != false
        updateActionsVisibility()
    }

    private func updateActionsVisibility() {
        actions.isHidden = globeButton.isHidden && accessLabel.isHidden && saveFromClipboardButton.isHidden
    }

    @objc private func saveFromClipboard() {
        guard hasFullAccess, store != nil else {
            showStatus(ClipboardStoreError.readOnly.localizedDescription)
            return
        }
        let text = UIPasteboard.general.string ?? UIPasteboard.general.url?.absoluteString
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showStatus(String(localized: "Clipboard has no text to save."))
            return
        }
        mutate({ try $0.add(text: text) }) { [weak self] success in
            if success { self?.showStatus(String(localized: "Saved from clipboard.")) }
        }
    }

    private func mutate(_ action: @escaping (ClipboardStore) throws -> Void, completion: @escaping (Bool) -> Void = { _ in }) {
        guard hasFullAccess, let store else { showStatus(ClipboardStoreError.readOnly.localizedDescription); completion(false); return }
        ioQueue.async { [weak self] in
            let result = Result { try action(store); return try store.load() }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case let .success(items): self.allItems = items; completion(true)
                case let .failure(error): self.showStatus(error.localizedDescription); completion(false)
                }
                self.updateSnapshot(); self.tableView.reloadData()
            }
        }
    }
}

extension KeyboardViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { visibleItems.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SnippetCell.reuseIdentifier, for: indexPath) as! SnippetCell
        cell.configure(visibleItems[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = visibleItems[indexPath.row]
        textDocumentProxy.insertText(item.text)
        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard hasFullAccess else { return nil }
        let item = visibleItems[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: String(localized: "Delete")) { [weak self] _, _, done in
            self?.mutate({ try $0.delete(id: item.id) }) { done($0) }
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard hasFullAccess else { return nil }
        let item = visibleItems[indexPath.row]
        let favorite = UIContextualAction(style: .normal, title: String(localized: item.isFavorite ? "Unfavorite" : "Favorite")) { [weak self] _, _, done in
            self?.mutate({ try $0.toggleFavorite(id: item.id) }) { done($0) }
        }
        favorite.backgroundColor = .systemYellow
        return UISwipeActionsConfiguration(actions: [favorite])
    }
}

private final class SnippetCell: UITableViewCell {
    static let reuseIdentifier = "SnippetCell"
    private let snippetLabel = UILabel()
    private let starView = UIImageView(image: UIImage(systemName: "star.fill"))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = .systemBackground
        background.cornerRadius = 12
        background.backgroundInsets = NSDirectionalEdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0)
        self.backgroundConfiguration = background

        snippetLabel.translatesAutoresizingMaskIntoConstraints = false
        snippetLabel.font = .preferredFont(forTextStyle: .body)
        snippetLabel.adjustsFontForContentSizeCategory = true
        snippetLabel.numberOfLines = 2
        snippetLabel.lineBreakMode = .byTruncatingTail
        starView.translatesAutoresizingMaskIntoConstraints = false
        starView.tintColor = .systemYellow
        starView.contentMode = .scaleAspectFit
        starView.setContentCompressionResistancePriority(.required, for: .horizontal)
        starView.setContentHuggingPriority(.required, for: .horizontal)
        starView.setContentHuggingPriority(.required, for: .vertical)
        starView.accessibilityLabel = String(localized: "Favorite")
        contentView.addSubview(snippetLabel); contentView.addSubview(starView)
        NSLayoutConstraint.activate([
            snippetLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            snippetLabel.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            snippetLabel.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            snippetLabel.trailingAnchor.constraint(equalTo: starView.leadingAnchor, constant: -8),
            starView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            starView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ item: ClipboardItem) {
        snippetLabel.text = item.text
        starView.isHidden = !item.isFavorite
        accessibilityLabel = item.isFavorite ? "\(item.text), \(String(localized: "Favorite"))" : item.text
    }
}
