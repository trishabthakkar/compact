/// Maps decibels (-60 dB → 0, 0 dB → 1, linear, clamped) to a 0...1 meter level.
public func normalizedLevel(decibels: Float) -> Double {
    guard decibels.isFinite else { return decibels > 0 ? 1 : 0 }
    return min(1, max(0, (Double(decibels) + 60) / 60))
}
