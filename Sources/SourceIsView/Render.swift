protocol RenderableValue {
  var asCells: [Cell] { get }
  var hasTrailingArguments: Bool { get }
}

extension Entity.Kind {
  var asCell: Cell {
    switch self {
    case .struct: return "STRUCT"
    case .class: return "CLASS"
    case .enum: return "ENUM"
    case .protocol: return "PROTO"
    case .assocType: return "ASSOC"
    case .typealias: return "ALIAS"
    case .import: return "IMPORT"
    case .func: return "FUNC"
    case .initializer: return "INIT"
    case .let: return "LET"
    case .var: return "VAR"
    case .case: return "CASE"
    case .subscript: return "SUBSCRIPT"
    case .deinit: return "DEINIT"
    case .extension: fatalError("extensions don't get cells")
    }
  }
}

extension Entity {
  var basePredicateAsCells: [Cell] {
    assert(!self.isExtension)
    var basePredicate = [Cell(name), "IS", kind.asCell]
    if !genericArguments.isEmpty || !genericRequirements.isEmpty {
      if !genericArguments.isEmpty {
        var genericArgsAsCells: [Cell] = genericArguments.flatMap { ["AND", Cell($0)] }
        genericArgsAsCells[0] = "OF"
        basePredicate += genericArgsAsCells
      }
      if !genericRequirements.isEmpty {
        basePredicate += ["WHERE"] + joinArgumentsAsCells(genericRequirements)
      }
    } else if !descriptors.isEmpty {
      basePredicate += ["AND"] + joinArgumentsAsCells(descriptors)
    }
    return basePredicate
  }

  var childrenPredicateAsCells: [Cell]? {
    guard !children.isEmpty else { return nil }
    var childNamesAsCells: [Cell] = children.flatMap { ["AND", Cell($0.name)] }
    childNamesAsCells[0] = "HAS"
    return [Cell(name)] + childNamesAsCells
  }

  var flatPredicatesAsCells: [[Cell]] {
    var descriptorPredicate: [Cell]?
    if !genericArguments.isEmpty || !genericRequirements.isEmpty || self.isExtension {
      if !descriptors.isEmpty {
        descriptorPredicate = [Cell(name), "IS"] + joinArgumentsAsCells(descriptors)
      }
    }

    var result: [[Cell]] = []
    if let descriptorPredicate = descriptorPredicate {
      result += [descriptorPredicate]
    }
    result += predicates.map { [Cell(name)] + $0.asCells }
    return result
  }

  var flatPredicatesAsCellsIncludingChildren: [[Cell]] {
    if let children = self.childrenPredicateAsCells {
      return self.flatPredicatesAsCells + [children]
    }
    return self.flatPredicatesAsCells
  }

  var asFlatCells: [[Cell]] {
    guard !self.isExtension else {
      return self.flatPredicatesAsCellsIncludingChildren.flatMap { [$0, []] }.dropLast()
    }
    return [self.basePredicateAsCells] + self.flatPredicatesAsCellsIncludingChildren.flatMap { [[], [.empty] + $0] }
  }

  var asHierarchicalCells: [[Cell]] {
    var result: [[Cell]] = []
    if self.isExtension {
      result.append([Cell(self.name), .empty] + (self.flatPredicatesAsCells.first ?? []))
    } else {
      result.append(self.basePredicateAsCells)
    }
    guard !self.children.isEmpty else {
      if self.isExtension {
        return self.asFlatCells + [[]]
      }
      for subpredicate in self.flatPredicatesAsCells {
        result.append([])
        result.append([.empty] + subpredicate)
      }
      result.append([])
      return result
    }
    result.append(["HAS"])

    let remainingFlatPredicates: ArraySlice<[Cell]>
    if self.isExtension {
      remainingFlatPredicates = self.flatPredicatesAsCells.dropFirst()
    } else {
      remainingFlatPredicates = self.flatPredicatesAsCells[...]
    }
    for subpredicate in remainingFlatPredicates {
      result.append(["…", .empty] + subpredicate)
      result.append(["…"])
    }

    for child in children {
      result.append(child.basePredicateAsCells)
      result.append(["AND"])
      for subpredicate in child.flatPredicatesAsCells {
        result.append(["…", .empty] + subpredicate)
        result.append(["…"])
      }
    }
    // Clean up extra … and AND.
    for i in result.indices.lazy.reversed() {
      if result[i].count == 1 {
        result[i] = []
        continue
      }
      if result[i][0].value == "…" {
        result[i][0] = .empty
        continue
      }
      break
    }
    // One extra blank line to end the section.
    result.append([])
    return result
  }
}

extension Requirement: RenderableValue {
  var asCells: [Cell] {
    let op: Cell
    switch kind {
    case .equals: op = "IS"
    case .isa: op = "ISA"
    }
    return typeA.asCells + [op] + typeB.asCells
  }

  var hasTrailingArguments: Bool {
    return typeB.hasTrailingArguments
  }
}

extension Predicate {
  var asCells: [Cell] {
    return [Cell(name)] + joinArgumentsAsCells(arguments)
  }
}

extension Descriptor: RenderableValue {
  var asCells: [Cell] { return [Cell(name)] }
  var hasTrailingArguments: Bool { return false }
}

extension TypeRepr: RenderableValue {
  var hasTrailingArguments: Bool {
    switch kind {
    case .function(returning: let result):
      return result.hasTrailingArguments
    case .inout:
      return arguments.first!.hasTrailingArguments
    default:
      return !arguments.isEmpty
    }
  }

  var asCells: [Cell] {
    let base: [Cell]
    switch kind {
    case .any:
      return ["ANY"]
    case .inout:
      assert(arguments.count == 1)
      return ["INOUT"] + arguments.first!.asCells
    case .function(returning: let resultType):
      return ["CLOSUR", "OF"] + joinArgumentsAsCells(arguments) + ["TO"] + resultType.asCells

    case .named(let name):
      base = [Cell(name)]
    case .existential:
      base = ["ANY"]
    case .optional:
      base = ["OPT"]
    case .iuo:
      base = ["IUO"]
    case .array:
      base = ["ARRAY"]
    case .dictionary:
      base = ["DICT"]
    case .tuple:
      if arguments.isEmpty {
        return ["EMPTY"]
      }
      base = ["TUPLE"]
    }

    guard !arguments.isEmpty else {
      return base
    }
    return base + ["OF"] + joinArgumentsAsCells(arguments)
  }
}

private func joinArgumentsAsCells(_ arguments: [RenderableValue]) -> [Cell] {
  let allCellsButLast = arguments.dropLast().lazy.map { (next: RenderableValue) -> [Cell] in
    let joiner: [Cell] = next.hasTrailingArguments ? ["AND", "THEN"] : ["AND"]
    return next.asCells + joiner
  }.joined()
  return Array(allCellsButLast) + (arguments.last?.asCells ?? [])
}

extension RenderableValue {
  var debugDescription: String {
    return self.asCells.lazy.map { $0.value }.joined(separator: " ")
  }
}
