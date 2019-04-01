public struct Cell: ExpressibleByStringLiteral, CustomStringConvertible {
  public var value: String

  public init(_ value: String) { self.value = value }
  public init(stringLiteral: String) { self.init(stringLiteral) }

  public static var empty: Cell { return Cell("") }

  public var description: String {
    return value
  }
}
