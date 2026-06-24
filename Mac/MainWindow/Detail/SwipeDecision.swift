//
//  SwipeDecision.swift
//  NetNewsWire
//
//  Maps a horizontal swipe on the detail pane to an action: open the current
//  article in the in-app webview (right-to-left while reading) or return to the
//  article (left-to-right while browsing).
//

import Foundation

enum SwipeAction: Equatable {
	case openWeb
	case returnToArticle
	case ignore
}

enum SwipeDecider {

	/// AppKit reports a right-to-left page swipe as a negative deltaX.
	static func action(deltaX: CGFloat, isBrowsing: Bool) -> SwipeAction {
		if deltaX < 0 {
			return isBrowsing ? .ignore : .openWeb
		}
		if deltaX > 0 {
			return isBrowsing ? .returnToArticle : .ignore
		}
		return .ignore
	}
}
