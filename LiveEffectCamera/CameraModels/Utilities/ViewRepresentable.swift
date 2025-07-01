//
//  ViewRepresentable.swift
//  LiveEffectCamera
//
//  Created by Владимир Костин on 01.07.2025.
//

import SwiftUI

public protocol ViewRepresentable: UIViewRepresentable {

	associatedtype ViewType: UIView

	@MainActor
	func makeView(context: Context) -> ViewType

	@MainActor
	func updateView(_ view: ViewType, context: Context)

	@MainActor
	static func dismantleView(_ view: ViewType, coordinator: Coordinator)

	@MainActor
	func sizeThatFits(_ proposal: ProposedViewSize, view: ViewType, context: Context) -> CGSize?
}


@MainActor
public extension ViewRepresentable {

	func makeUIView(context: Context) -> ViewType {
		makeView(context: context)
	}

	func updateUIView(_ uiView: ViewType, context: Context) {
		updateView(uiView, context: context)
	}

	static func dismantleUIView(_ uiView: ViewType, coordinator: Coordinator) {
		dismantleView(uiView, coordinator: coordinator)
	}

	func sizeThatFits(_ proposal: ProposedViewSize, uiView: ViewType, context: Context) -> CGSize? {
		sizeThatFits(proposal, view: uiView, context: context)
	}

}

@MainActor
public extension ViewRepresentable {

	static func dismantleView(_ view: ViewType, coordinator: Coordinator) { }

	func sizeThatFits(_ proposal: ProposedViewSize, view: ViewType, context: Context) -> CGSize? {
		if let width = proposal.width, let height = proposal.height {
			return CGSize(width: width, height: height)
		} else {
			return nil
		}
	}
}
