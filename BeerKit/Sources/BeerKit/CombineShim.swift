// Linux (tim-server) has no Combine. Provide the two Combine symbols BeerKit uses so the
// package and its tests build on any platform. On Apple platforms the real Combine is used
// and this file contributes nothing, so the App's SwiftUI integration is unaffected.
#if !canImport(Combine)
public protocol ObservableObject: AnyObject {}

@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
#endif
