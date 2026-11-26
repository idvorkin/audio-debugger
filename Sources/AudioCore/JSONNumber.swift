import Foundation

/// A number for a JSON file, rounded to `places` decimals. A Decimal, not a Double: JSONSerialization writes the
/// Double -69.4 as -69.400000000000006 and 17.94 s as 17.940000000000001 (both seen on the Mac).
public func jsonNumber(_ value: Double, places: Int) -> NSDecimalNumber {
    let scale = pow(10, Double(places))
    let rounded = Decimal(Int((value * scale).rounded())) / pow(Decimal(10), places)
    return NSDecimalNumber(decimal: rounded)
}
