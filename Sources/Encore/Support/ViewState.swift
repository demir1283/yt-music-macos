import SwiftUI
import Combine

/// Drop-in replacement for `@State` that doesn't rely on SwiftUI's `@State` macro.
///
/// On recent macOS SDKs `@State` is implemented as a compiler macro whose plugin ships
/// only with Xcode, so it can't be compiled with the Command Line Tools alone. This
/// wrapper stores the value in a `StateObject` (used as a plain stored property, not as
/// an attribute), which SwiftUI keeps alive for the lifetime of the view — the same
/// lifetime `@State` has.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    final class Box: ObservableObject {
        @Published var value: Value
        init(_ value: Value) { self.value = value }
    }

    private let storage: StateObject<Box>

    init(wrappedValue: Value) {
        storage = StateObject(wrappedValue: Box(wrappedValue))
    }

    init() where Value: ExpressibleByNilLiteral {
        self.init(wrappedValue: nil)
    }

    var wrappedValue: Value {
        get { storage.wrappedValue.value }
        nonmutating set { storage.wrappedValue.value = newValue }
    }

    var projectedValue: Binding<Value> {
        let box = storage.wrappedValue
        return Binding(get: { box.value }, set: { box.value = $0 })
    }
}
