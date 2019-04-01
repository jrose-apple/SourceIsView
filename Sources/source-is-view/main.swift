import SourceIsView
import SwiftSyntax

import AppKit

guard CommandLine.arguments.count == 2 else {
  // FIXME: should go to stderr
  print("usage: source-is-view file.swift")
  exit(1)
}

// Hack: will only work in the package layout.
let prerenderedCellDirectory = URL(fileURLWithPath: #file)
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .appendingPathComponent("SourceIsView.playground", isDirectory: true)
  .appendingPathComponent("Resources", isDirectory: true)
  .appendingPathComponent("cells", isDirectory: true)

let source = URL(fileURLWithPath: CommandLine.arguments[1])
let sourceFile = try SyntaxTreeParser.parse(source)
let cells = generateCells(from: sourceFile)
let image = cells.toImage(prerenderedCellDirectory: prerenderedCellDirectory)

NSPasteboard.general.clearContents()
NSPasteboard.general.writeObjects([image])
print("Copied to clipboard!")
