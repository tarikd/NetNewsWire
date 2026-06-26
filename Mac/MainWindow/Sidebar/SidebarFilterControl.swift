//
//  SidebarFilterControl.swift
//  NetNewsWire
//
//  A small SwiftUI segmented pill shown at the bottom of the sidebar that
//  switches between showing all feeds and hiding read feeds (only feeds with
//  unread articles). The selected segment shows its icon and label; the other
//  shows just its icon.
//

import SwiftUI

@MainActor
final class SidebarFilterModel: ObservableObject {

	/// `true` hides read feeds (unread only); `false` shows all feeds.
	@Published var hideReadFeeds = false

	/// Called when the user picks a segment (not when the value is set in code).
	var onUserChange: ((Bool) -> Void)?

	func userSelected(hideReadFeeds: Bool) {
		guard self.hideReadFeeds != hideReadFeeds else { return }
		self.hideReadFeeds = hideReadFeeds
		onUserChange?(hideReadFeeds)
	}
}

struct SidebarFilterView: View {

	@ObservedObject var model: SidebarFilterModel

	var body: some View {
		HStack(spacing: 2) {
			segment(label: NSLocalizedString("Unread", comment: "Unread"),
					systemImage: "circle.fill",
					isSelected: model.hideReadFeeds) {
				model.userSelected(hideReadFeeds: true)
			}
			segment(label: NSLocalizedString("All", comment: "All"),
					systemImage: "line.3.horizontal.decrease",
					isSelected: !model.hideReadFeeds) {
				model.userSelected(hideReadFeeds: false)
			}
		}
		.padding(3)
		.background(.quaternary, in: Capsule())
		.animation(.easeInOut(duration: 0.18), value: model.hideReadFeeds)
	}

	private func segment(label: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			HStack(spacing: 5) {
				Image(systemName: systemImage)
					.font(.system(size: 11, weight: .semibold))
				if isSelected {
					Text(label)
						.font(.system(size: 11, weight: .semibold))
				}
			}
			.foregroundStyle(isSelected ? Color.primary : Color.secondary)
			.padding(.horizontal, 10)
			.padding(.vertical, 4)
			.background {
				if isSelected {
					Capsule().fill(Color(nsColor: .controlBackgroundColor))
				}
			}
			.contentShape(Capsule())
		}
		.buttonStyle(.plain)
	}
}
