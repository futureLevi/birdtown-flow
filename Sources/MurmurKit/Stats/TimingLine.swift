import Foundation

/// One key=value log line. Values are numbers or fixed tokens, never user text.
///
/// The app logs one per dictation and one per Retry (`Log.timing`), so each stage's cost can
/// be read straight off `log show`:
/// `dictation 3F2A9C1B audio=372.4s stop=11ms transcribe=612ms transcribe(windows=31 tail=298ms)`.
public struct TimingLine: Sendable, Equatable {
    private let label: String
    private var fields: [String] = []

    public init(_ label: String) {
        self.label = label
    }

    /// `key=123ms`. A `nil` value (a stage that didn't run) leaves the key out.
    public mutating func ms(_ key: String, _ value: Int?) {
        guard let value else { return }
        fields.append("\(key)=\(value)ms")
    }

    /// `key=372.4s`, to a tenth of a second.
    public mutating func seconds(_ key: String, _ value: Double) {
        fields.append("\(key)=\(String(format: "%.1f", value))s")
    }

    /// `key=7`.
    public mutating func count(_ key: String, _ value: Int) {
        fields.append("\(key)=\(value)")
    }

    /// `key=segmentedLive`: a fixed token such as an enum's raw value.
    public mutating func tag(_ key: String, _ value: String) {
        fields.append("\(key)=\(value)")
    }

    /// `key(a=1ms b=2)`: another line's fields, without its label. An empty line adds nothing.
    public mutating func group(_ key: String, _ inner: TimingLine) {
        guard !inner.fields.isEmpty else { return }
        fields.append("\(key)(\(inner.fields.joined(separator: " ")))")
    }

    /// The label, then every field in the order it was added.
    public var text: String {
        ([label] + fields).joined(separator: " ")
    }
}
