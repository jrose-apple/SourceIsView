struct Entity {
  enum Kind {
    case `struct`
    case `class`
    case `enum`
    case `protocol`
    case assocType
    case `typealias`
    case `import`
    case `func`
    case initializer
    case `let`
    case `var`
    case `case`
    case `subscript`
    case `deinit`
    case `extension`
  }

  var name: String
  var kind: Kind
  var genericArguments: [String]
  var children: [Entity]
  var descriptors: [Descriptor]
  var genericRequirements: [Requirement]
  var predicates: [Predicate]

  var isExtension: Bool {
    if case .extension = self.kind { return true }
    return false
  }
}

struct Predicate {
  var name: String
  var arguments: [RenderableValue]

  init(_ name: String, _ arguments: [RenderableValue]) {
    self.name = name
    self.arguments = arguments
  }
}

struct Requirement {
  enum Kind {
    case equals
    case isa
  }

  var typeA: TypeRepr
  var typeB: TypeRepr
  var kind: Kind

  init(_ typeA: TypeRepr, _ kind: Kind, _ typeB: TypeRepr) {
    self.typeA = typeA
    self.kind = kind
    self.typeB = typeB
  }
}

struct Descriptor {
  var name: String

  init(_ name: String) {
    self.name = name
  }
}

struct TypeRepr {
  enum Kind {
    case named(String)
    case any
    case existential
    case optional
    case iuo
    case array
    case dictionary
    case tuple
    case `inout`
    indirect case function(returning: TypeRepr)
  }
  var kind: Kind
  var arguments: [TypeRepr]

  init(_ kind: Kind, _ arguments: [TypeRepr]) {
    self.kind = kind
    self.arguments = arguments
  }
  init(_ kind: Kind, _ singleArgument: TypeRepr) {
    self.init(kind, [singleArgument])
  }
  init(_ kind: Kind) {
    self.init(kind, [])
  }
}
