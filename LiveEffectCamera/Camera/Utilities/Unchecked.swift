//
//  Unchecked.swift
//  LiveEffectCamera
//
//  Created by Владимир Костин on 01.07.2025.
//


struct Unchecked<Value>: @unchecked Sendable {
	let wrappedValue: Value
}
