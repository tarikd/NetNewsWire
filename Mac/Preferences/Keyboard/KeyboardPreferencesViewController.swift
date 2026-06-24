//
//  KeyboardPreferencesViewController.swift
//  NetNewsWire
//
//  Programmatic preferences pane that lists reading/navigation commands grouped
//  by context and lets the user remap, clear, or restore keyboard shortcuts.
//

import AppKit
import RSCore

@MainActor final class KeyboardPreferencesViewController: NSViewController {

	private let store = KeyboardShortcutStore.shared
	private let contentStack = NSStackView()
	private let statusLabel = NSTextField(labelWithString: "")
	private nonisolated(unsafe) var changeObserver: NSObjectProtocol?

	private let titleColumnWidth = CGFloat(220.0)
	private let preferredWidth = CGFloat(512.0)

	deinit {
		if let changeObserver {
			NotificationCenter.default.removeObserver(changeObserver)
		}
	}

	override func loadView() {
		let rootView = NSView(frame: NSRect(x: 0, y: 0, width: preferredWidth, height: 480.0))

		let scrollView = NSScrollView()
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = false
		scrollView.autohidesScrollers = true

		contentStack.orientation = .vertical
		contentStack.alignment = .leading
		contentStack.spacing = 6.0
		contentStack.translatesAutoresizingMaskIntoConstraints = false
		contentStack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)

		let documentView = NSView()
		documentView.translatesAutoresizingMaskIntoConstraints = false
		documentView.addSubview(contentStack)
		scrollView.documentView = documentView

		statusLabel.translatesAutoresizingMaskIntoConstraints = false
		statusLabel.textColor = .secondaryLabelColor
		statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
		statusLabel.lineBreakMode = .byTruncatingTail
		statusLabel.stringValue = ""

		let restoreButton = NSButton(title: NSLocalizedString("Restore Defaults", comment: "Keyboard preferences"),
									 target: self,
									 action: #selector(restoreDefaults(_:)))
		restoreButton.bezelStyle = .rounded
		restoreButton.translatesAutoresizingMaskIntoConstraints = false

		let bottomBar = NSStackView(views: [statusLabel, NSView(), restoreButton])
		bottomBar.orientation = .horizontal
		bottomBar.alignment = .centerY
		bottomBar.spacing = 8.0
		bottomBar.translatesAutoresizingMaskIntoConstraints = false

		rootView.addSubview(scrollView)
		rootView.addSubview(bottomBar)

		NSLayoutConstraint.activate([
			scrollView.topAnchor.constraint(equalTo: rootView.topAnchor),
			scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),

			bottomBar.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8.0),
			bottomBar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20.0),
			bottomBar.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20.0),
			bottomBar.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -16.0),

			documentView.topAnchor.constraint(equalTo: contentStack.topAnchor),
			documentView.bottomAnchor.constraint(equalTo: contentStack.bottomAnchor),
			documentView.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
			documentView.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor),
			documentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
		])

		self.view = rootView

		changeObserver = NotificationCenter.default.addObserver(forName: KeyboardShortcutStore.didChangeNotification,
																object: nil,
																queue: .main) { [weak self] _ in
			MainActor.assumeIsolated {
				self?.reload()
			}
		}

		reload()
	}

	// MARK: - Actions

	@objc private func restoreDefaults(_ sender: Any?) {
		statusLabel.stringValue = ""
		store.restoreDefaults()
		reload()
	}

	@objc private func clearBinding(_ sender: NSButton) {
		guard let identifier = sender.identifier?.rawValue,
			  let (context, action) = decode(identifier) else { return }
		statusLabel.stringValue = ""
		store.clearBinding(forAction: action, in: context)
		reload()
	}

	// MARK: - Building rows

	private func reload() {
		for view in contentStack.arrangedSubviews {
			contentStack.removeArrangedSubview(view)
			view.removeFromSuperview()
		}

		for context in KeyboardShortcutStore.Context.allCases {
			let commands = dedupedCommands(for: context)
			if commands.isEmpty { continue }

			contentStack.addArrangedSubview(makeSectionHeader(context.displayName))

			for command in commands {
				contentStack.addArrangedSubview(makeRow(for: command, in: context))
			}
		}
	}

	// Dedupe by action, keeping the first command per action.
	private func dedupedCommands(for context: KeyboardShortcutStore.Context) -> [KeyboardShortcutStore.Command] {
		var seen = Set<String>()
		var result = [KeyboardShortcutStore.Command]()
		for command in store.commands(for: context) where !seen.contains(command.action) {
			seen.insert(command.action)
			result.append(command)
		}
		return result
	}

	private func makeSectionHeader(_ text: String) -> NSView {
		let label = NSTextField(labelWithString: text)
		label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
		label.translatesAutoresizingMaskIntoConstraints = false
		let container = NSStackView(views: [label])
		container.orientation = .horizontal
		container.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 2, right: 0)
		return container
	}

	private func makeRow(for command: KeyboardShortcutStore.Command,
						 in context: KeyboardShortcutStore.Context) -> NSView {
		let titleLabel = NSTextField(labelWithString: command.title)
		titleLabel.lineBreakMode = .byTruncatingTail
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		titleLabel.widthAnchor.constraint(equalToConstant: titleColumnWidth).isActive = true

		let recorder = ShortcutRecorderView()
		recorder.translatesAutoresizingMaskIntoConstraints = false
		recorder.key = command.currentKey
		let action = command.action
		recorder.onRecord = { [weak self] key in
			guard let self else { return }
			let reassigned = self.store.setBinding(key, forAction: action, in: context)
			if let reassigned {
				let format = NSLocalizedString("Reassigned from “%@”", comment: "Keyboard preferences")
				self.statusLabel.stringValue = String(format: format, reassigned)
			} else {
				self.statusLabel.stringValue = ""
			}
			self.reload()
		}

		let clearButton = NSButton(title: "✕", target: self, action: #selector(clearBinding(_:)))
		clearButton.bezelStyle = .inline
		clearButton.isBordered = false
		clearButton.identifier = NSUserInterfaceItemIdentifier(encode(context: context, action: command.action))
		clearButton.translatesAutoresizingMaskIntoConstraints = false
		clearButton.toolTip = NSLocalizedString("Clear shortcut", comment: "Keyboard preferences")

		let row = NSStackView(views: [titleLabel, recorder, clearButton])
		row.orientation = .horizontal
		row.alignment = .centerY
		row.spacing = 8.0
		return row
	}

	// MARK: - Identifier encoding for the clear button

	private func encode(context: KeyboardShortcutStore.Context, action: String) -> String {
		return "\(context.rawValue)\t\(action)"
	}

	private func decode(_ identifier: String) -> (KeyboardShortcutStore.Context, String)? {
		let parts = identifier.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
		guard parts.count == 2, let context = KeyboardShortcutStore.Context(rawValue: String(parts[0])) else {
			return nil
		}
		return (context, String(parts[1]))
	}
}
