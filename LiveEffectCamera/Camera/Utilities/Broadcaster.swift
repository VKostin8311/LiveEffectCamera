//
//  Broadcaster.swift
//  LiveEffectCamera
//
//  Created by Владимир Костин on 01.07.2025.
//

import Observation
import SwiftUI

@Observable @MainActor final class Broadcaster<Value> where Value: Sendable {
	
	var wrappedValue: Value? = nil
	
	private var task: Task<Void, Never>? = nil
	
	func broadcast(stream: AsyncStream<Value>) {
		
		task?.cancel()
		
		task = Task {
			for await value in stream {
				if Task.isCancelled { break }
				wrappedValue = value
			}
		}
	}
	
	func stopBroadcasting() {
		task?.cancel()
		task = nil
	}
}
