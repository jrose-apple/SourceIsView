#if canImport(AppKit)
import AppKit

extension Cell {
  public static let renderedDimension: CGFloat = 32

  public func draw(at origin: CGPoint) {
    guard !self.value.isEmpty else { return }
    var stringToDraw = self.value.uppercased(with: Locale.current)

    // Figure out the best drawing options for this string.
    // Basically chosen by me eyeballing what looks good.
    let lineHeight: CGFloat
    let fontSize: CGFloat
    let xOffset: CGFloat
    var truncateOption: NSString.DrawingOptions = []
    switch stringToDraw.count {
    case 0:
      fatalError("handled above")
    case 1...2:
      lineHeight = 30
      fontSize = 24
      xOffset = 0
    case 3:
      lineHeight = 21
      fontSize = 14
      xOffset = 1
    case 4:
      lineHeight = 14
      fontSize = 14
      xOffset = 1
      stringToDraw = """
        \(stringToDraw.prefix(2))
        \(stringToDraw.suffix(2))
        """
    case 5...6:
      lineHeight = 14
      fontSize = 14
      xOffset = 1
    case 7:
      lineHeight = 10
      fontSize = 11
      xOffset = 2
      stringToDraw = """
        \(stringToDraw.prefix(3))
        \(stringToDraw.dropFirst(3).prefix(2))
        \(stringToDraw.dropFirst(5))
        """
    case 8...9:
      lineHeight = 10
      fontSize = 11
      xOffset = 2
      stringToDraw = """
        \(stringToDraw.prefix(3))
        \(stringToDraw.dropFirst(3).prefix(3))
        \(stringToDraw.dropFirst(6))
        """
    case 10...:
      lineHeight = 10
      fontSize = 11
      xOffset = 2
      truncateOption = .truncatesLastVisibleLine
    default:
      fatalError("count cannot be negative")
    }

    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.maximumLineHeight = lineHeight
    style.minimumLineHeight = lineHeight

    // Fall back to Chalkboard, installed by default on macOS, if Bryndan Write
    // isn't installed.
    let font = NSFont(name: "Bryndan Write", size: fontSize) ??
               NSFont(name: "Chalkboard", size: fontSize)!

    // FIXME: hashValue is different on each run, but this should really pick
    // a deterministic color for each identifier.
    let hueHash = stringToDraw.hashValue
    // Extremely hacky way to form a moderately-well-distributed Double value
    // in the range 0..<1. I don't know why I did it this way instead of looking
    // up a proper way to do it.
    let hue = Double(sign: .plus,
                     exponentBitPattern: 1.0.exponentBitPattern,
                     significandBitPattern: UInt64(bitPattern: Int64(hueHash))) - 1.0
    let color = NSColor(hue: CGFloat(hue), saturation: 0.2, brightness: 1.0, alpha: 1.0)

    // Note: These have fully-qualified keys to help with code completion.
    // Hopefully that gets better in the future!
    let attStr = NSAttributedString(string: stringToDraw, attributes: [
      NSAttributedString.Key.paragraphStyle: style,
      NSAttributedString.Key.font: font,
      NSAttributedString.Key.foregroundColor: color
    ])

    attStr.draw(with: NSRect(x: origin.x + xOffset,
                             y: origin.y,
                             width: Cell.renderedDimension - (xOffset * 2),
                             height: Cell.renderedDimension - 2),
                options: [.usesLineFragmentOrigin, truncateOption])
  }
}

extension CGPoint {
  func offsetBy(x deltaX: CGFloat = 0, y deltaY: CGFloat = 0) -> CGPoint {
    return CGPoint(x: self.x + deltaX, y: self.y + deltaY)
  }
}
extension CGSize {
  init(square dimension: CGFloat) {
    self.init(width: dimension, height: dimension)
  }
}

private func loadPrerenderedCell(_ name: String, from directory: URL?) -> NSImage? {
  guard let directory = directory else { return nil }
  guard !name.isEmpty else { return nil }
  return NSImage(contentsOf: directory.appendingPathComponent(name).appendingPathExtension("png"))
}

extension Array where Element == Cell {
  public func draw(at origin: CGPoint, prerenderedCellDirectory: URL? = nil) {
    for (i, cell) in self.enumerated() {
      let nextOrigin = origin.offsetBy(x: Cell.renderedDimension * CGFloat(i))
      if let prerenderedCell = loadPrerenderedCell(cell.value, from: prerenderedCellDirectory) {
        prerenderedCell.draw(in: CGRect(origin: nextOrigin, size: CGSize(square: Cell.renderedDimension)))
      } else {
        cell.draw(at: nextOrigin)
      }
    }
  }
}

extension NSImage {
  func withLockedFocus<ResultType>(_ block: () -> ResultType) -> ResultType {
    self.lockFocus()
    defer { self.unlockFocus() }
    return block()
  }
}

extension Array where Element == [Cell] {
  public func draw(at origin: CGPoint, prerenderedCellDirectory: URL? = nil) {
    for (i, line) in self.lazy.reversed().enumerated() {
      line.draw(at: CGPoint(x: 0, y: Cell.renderedDimension * CGFloat(i)),
                prerenderedCellDirectory: prerenderedCellDirectory)
    }
  }

  public func toImage(prerenderedCellDirectory: URL? = nil) -> NSImage {
    let longestLineLength = self.lazy.map { $0.count }.max() ?? 0

    let image = NSImage(size: CGSize(width: Cell.renderedDimension * CGFloat(longestLineLength),
                                     height: Cell.renderedDimension * CGFloat(self.count)))
    guard longestLineLength != 0 else { return image }

    image.withLockedFocus {
      NSColor.black.setFill()
      CGRect(origin: .zero, size: image.size).fill()
      self.draw(at: .zero, prerenderedCellDirectory: prerenderedCellDirectory)
    }
    return image
  }
}
#endif // canImport(AppKit)
