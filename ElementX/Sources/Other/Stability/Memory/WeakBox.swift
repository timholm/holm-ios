//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// A box holding a weak reference to an object.
///
/// Useful for breaking retain cycles in collections or caches that must not keep
/// their values alive, e.g. `[String: WeakBox<SomeDelegate>]`.
final class WeakBox<T: AnyObject> {
    weak var value: T?
    
    init(_ value: T? = nil) {
        self.value = value
    }
}

/// Returns a closure that calls `body` with `object` only while `object` is alive.
///
/// Use it to break the retain cycle created when `self` stores a closure (in a
/// `cancellables` set, a `Task` property, or a notification observer) that captures
/// `self` strongly:
///
/// ```swift
/// cancellable = publisher.sink(receiveValue: weakified(self) { strongSelf, value in
///     strongSelf.handle(value)
/// })
/// ```
///
/// - Parameters:
///   - object: The object to hold weakly.
///   - body: Called with a strong reference to `object` and the published value.
/// - Returns: A closure that no-ops after `object` deallocates.
func weakified<T: AnyObject, Value>(_ object: T, _ body: @escaping (T, Value) -> Void) -> (Value) -> Void {
    { [weak object] value in
        guard let object else { return }
        body(object, value)
    }
}

/// Returns a closure that calls `body` with `object` only while `object` is alive.
///
/// Value-less overload of ``weakified(_:_:)`` for closures that take no arguments,
/// e.g. notification handlers or completion callbacks:
///
/// ```swift
/// observer = NotificationCenter.default.addObserver(forName: .didFinish,
///                                                   object: nil,
///                                                   queue: .main,
///                                                   using: weakified(self) { strongSelf in
///     strongSelf.refresh()
/// })
/// ```
func weakified<T: AnyObject>(_ object: T, _ body: @escaping (T) -> Void) -> () -> Void {
    { [weak object] in
        guard let object else { return }
        body(object)
    }
}
