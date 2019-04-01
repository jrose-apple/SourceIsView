import SourceIsView
import SwiftSyntax

import AppKit

// Add your own file here!
let source = #fileLiteral(resourceName: "Result.swift")

let sourceFile = try SyntaxTreeParser.parse(source)
let cells = generateCells(from: sourceFile)

let image = cells.toImage(prerenderedCellDirectory: #fileLiteral(resourceName: "cells"))

// Copy to clipboard because this image is potentially huge...
NSPasteboard.general.clearContents()
NSPasteboard.general.writeObjects([image])
