//
//  AsyncSource.swift
//  LiveEffectCamera
//
//  Created by Владимир Костин on 01.07.2025.
//


struct AsyncSource<Element> {
	
	typealias Continuation = AsyncStream<Element>.Continuation
	
	let stream: AsyncStream<Element>
	let continuation: Continuation
	
	init(bufferingPolicy: Continuation.BufferingPolicy = .unbounded) {
		let (stream, continuation) = AsyncStream<Element>.makeStream(of: Element.self, bufferingPolicy: bufferingPolicy)
		
		self.stream = stream
		self.continuation = continuation
	}
}

extension AsyncSource: Sendable where Element: Sendable {}

