import SwiftSyntax

enum TranslationError: Error {
  case badType(TypeSyntax)
  case badRequirement(Syntax)
  case otherBadness(Syntax)
  case incompleteSource(Syntax)
}

protocol NominalTypeSyntax {
  var identifier: TokenSyntax { get }
  var genericParameterClause: GenericParameterClauseSyntax? { get }
  var genericWhereClause: GenericWhereClauseSyntax? { get }
  var modifiers: ModifierListSyntax? { get }
  var inheritanceClause: TypeInheritanceClauseSyntax? { get }
  var members: MemberDeclBlockSyntax { get }
}
extension StructDeclSyntax: NominalTypeSyntax {}
extension EnumDeclSyntax: NominalTypeSyntax {
  // FIXME: SwiftSyntax should be uniform here
  var genericParameterClause: GenericParameterClauseSyntax? {
    return self.genericParameters
  }
}
extension ClassDeclSyntax: NominalTypeSyntax {}
extension ProtocolDeclSyntax: NominalTypeSyntax {
  var genericParameterClause: GenericParameterClauseSyntax? {
    return nil
  }
}

class Translator: SyntaxVisitor {
  var entities: [Entity] = []

  func translateType(_ node: TypeSyntax) throws -> TypeRepr {
    switch node {
    case let ident as SimpleTypeIdentifierSyntax:
      return TypeRepr(.named(ident.name.text),
                      try ident.genericArgumentClause?.arguments.map {
        try translateType($0.argumentType)
      } ?? [])
    case let array as ArrayTypeSyntax:
      return TypeRepr(.array, try translateType(array.elementType))
    case let dict as DictionaryTypeSyntax:
      return TypeRepr(.dictionary, [
        try translateType(dict.keyType),
        try translateType(dict.valueType)])
    case let opt as OptionalTypeSyntax:
      return TypeRepr(.optional, try translateType(opt.wrappedType))
    case let iuo as ImplicitlyUnwrappedOptionalTypeSyntax:
      return TypeRepr(.iuo, try translateType(iuo.wrappedType))
    case let tuple as TupleTypeSyntax:
      return TypeRepr(.tuple, try tuple.elements.map {
        try translateType($0.type)
      })
    case let attr as AttributedTypeSyntax:
      if attr.specifier?.tokenKind == .inoutKeyword {
        return TypeRepr(.inout, try translateType(attr.baseType))
      }
      // Ignore other attributes for now.
      return try translateType(attr.baseType)
    case let fn as FunctionTypeSyntax:
      // Ignore "throws" for now.
      let arguments = try fn.arguments.map {
        try translateType($0.type)
      }
      return TypeRepr(.function(returning: try translateType(fn.returnType)),
                      arguments.isEmpty ? [TypeRepr(.tuple)] : arguments)
    case let comp as CompositionTypeSyntax:
      return TypeRepr(.existential, try comp.elements.map {
        try translateType($0.type)
      })
    case is ClassRestrictionTypeSyntax:
      return TypeRepr(.named("AnyObject"))
    default:
      // FIXME: Metatypes and member types
      throw TranslationError.badType(node)
    }
  }

  // Hack for optional inout parameter.
  func collectModifiers(_ modifiers: ModifierListSyntax?, isMutating: UnsafeMutablePointer<Bool>? = nil) -> [Descriptor] {
    guard let modifiers = modifiers else {
      isMutating?.pointee = false
      return []
    }

    var descriptors: [Descriptor] = []
    for modifier in modifiers {
      switch modifier.name.text {
      case "open":
        descriptors.append(Descriptor("OPEN"))
      case "public":
        descriptors.append(Descriptor("PUBLIC"))
      case "internal":
        descriptors.append(Descriptor("INTERN"))
      case "fileprivate":
        descriptors.append(Descriptor("FILE"))
      case "private":
        descriptors.append(Descriptor("PRIVAT"))

      case "class":
        descriptors.append(Descriptor("CLASS"))
      case "convenience":
        descriptors.append(Descriptor("CONV"))
      case "final":
        descriptors.append(Descriptor("FINAL"))
      case "indirect":
        descriptors.append(Descriptor("INDIRECT"))
      case "lazy":
        descriptors.append(Descriptor("LAZY"))
      case "override":
        descriptors.append(Descriptor("OVER"))
      case "static":
        descriptors.append(Descriptor("STATIC"))

      case "mutating":
        // Note the special treatment here!
        isMutating?.pointee = true
      default:
        break
      }
    }
    return descriptors
  }

  func collectGenericRequirements(_ genericParamList: GenericParameterClauseSyntax?,
                                  _ whereClause: GenericWhereClauseSyntax?) throws -> [Requirement] {
    let implicitGenericRequirements: [Requirement] = try genericParamList?.genericParameterList.compactMap {
      guard let inheritedType = $0.inheritedType else {
        return nil
      }

      return Requirement(TypeRepr(.named($0.name.text)), .isa, try translateType(inheritedType))
    } ?? []

    let explicitGenericRequirements: [Requirement] = try whereClause?.requirementList.map {
      switch $0 {
      case let isaRequirement as ConformanceRequirementSyntax:
        return Requirement(try translateType(isaRequirement.leftTypeIdentifier),
                           .isa,
                           try translateType(isaRequirement.rightTypeIdentifier))
      case let eqRequirement as SameTypeRequirementSyntax:
        return Requirement(try translateType(eqRequirement.leftTypeIdentifier),
                           .equals,
                           try translateType(eqRequirement.rightTypeIdentifier))
      default:
        throw TranslationError.badRequirement($0)
      }
    } ?? []

    return implicitGenericRequirements + explicitGenericRequirements
  }

  func ignoringTranslationErrors(_ block: () throws -> Void) {
    do {
      try block()
    } catch is TranslationError {
      // Ignore this node and move on.
    } catch let error {
      fatalError("Unexpected error: \(error)")
    }
  }

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    ignoringTranslationErrors {
      let genericArgs = node.genericParameterClause?.genericParameterList.map { $0.name.text } ?? []
      let genericRequirements = try collectGenericRequirements(node.genericParameterClause, node.genericWhereClause)

      var predicates: [Predicate] = []

      let params: [TypeRepr] = try node.signature.input.parameterList.map {
        guard let paramType = $0.type else {
          throw TranslationError.incompleteSource($0)
        }
        return try translateType(paramType)
      }
      if params.isEmpty {
        // FIXME: there should still be a predicate?
      } else {
        predicates.append(Predicate("TAKES", params))
      }

      if let resultSyntax = node.signature.output?.returnType {
        predicates.append(Predicate("RETURN", [try translateType(resultSyntax)]))
      }

      var descriptors: [Descriptor] = []
      var isMutating = false
      descriptors += collectModifiers(node.modifiers, isMutating: &isMutating)

      var capabilities: [Descriptor] = []
      if isMutating {
        capabilities.append(Descriptor("MUTATE"))
      }
      switch node.signature.throwsOrRethrowsKeyword?.tokenKind {
      case .throwsKeyword?:
        capabilities.append(Descriptor("THROW"))
      case .rethrowsKeyword?:
        capabilities.append(Descriptor("RETHROW"))
      default:
        break
      }
      if !capabilities.isEmpty {
        predicates.append(Predicate("CAN", capabilities))
      }

      let function = Entity(name: node.identifier.text,
                            kind: .func,
                            genericArguments: genericArgs,
                            children: [],
                            descriptors: descriptors,
                            genericRequirements: genericRequirements,
                            predicates: predicates)
      entities.append(function)
    }
    return .skipChildren
  }

  func visitNominal<Nominal: NominalTypeSyntax>(_ node: Nominal, kind: Entity.Kind) -> SyntaxVisitorContinueKind {
    ignoringTranslationErrors {
      let genericArgs = node.genericParameterClause?.genericParameterList.map { $0.name.text } ?? []
      let genericRequirements = try collectGenericRequirements(node.genericParameterClause, node.genericWhereClause)

      let descriptors = collectModifiers(node.modifiers)

      var predicates: [Predicate] = []
      if let inheritanceClause = node.inheritanceClause {
        predicates.append(Predicate("ISA", try inheritanceClause.inheritedTypeCollection.map {
          try translateType($0.typeName)
        }))
      }

      let childrenTranslator = Translator()
      node.members.walk(childrenTranslator)

      let nominal = Entity(name: node.identifier.text,
                           kind: kind,
                           genericArguments: genericArgs,
                           children: childrenTranslator.entities,
                           descriptors: descriptors,
                           genericRequirements: genericRequirements,
                           predicates: predicates)
      entities.append(nominal)
    }
    return .skipChildren
  }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    return visitNominal(node, kind: .struct)
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    return visitNominal(node, kind: .class)
  }

  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    return visitNominal(node, kind: .enum)
  }

  override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
    return visitNominal(node, kind: .protocol)
  }

  override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
    ignoringTranslationErrors {
      let descriptors = collectModifiers(node.modifiers)

      let kind: Entity.Kind
      switch node.letOrVarKeyword.tokenKind {
      case .varKeyword:
        kind = .var
      case .letKeyword:
        kind = .let
      default:
        throw TranslationError.otherBadness(node.letOrVarKeyword)
      }

      node.bindings.forEach { bindingNode in
        ignoringTranslationErrors {
          // FIXME: Handle more complicated patterns?
          guard let simplePattern = bindingNode.pattern as? IdentifierPatternSyntax,
                let type = bindingNode.typeAnnotation?.type else {
            return
          }

          var predicates: [Predicate] = []
          predicates.append(Predicate("HAS", [try translateType(type)]))

          let binding = Entity(name: simplePattern.identifier.text,
                               kind: kind,
                               genericArguments: [],
                               children: [],
                               descriptors: descriptors,
                               genericRequirements: [],
                               predicates: predicates)
          entities.append(binding)
        }
      }
    }
    return .skipChildren
  }

  override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
    ignoringTranslationErrors {
      let descriptors = collectModifiers(node.modifiers)
      let deinitializer = Entity(name: "deinit",
                                 kind: .deinit,
                                 genericArguments: [],
                                 children: [],
                                 descriptors: descriptors,
                                 genericRequirements: [],
                                 predicates: [])
      entities.append(deinitializer)
    }
    return .skipChildren
  }

  override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
    ignoringTranslationErrors {
      let genericArgs = node.genericParameterClause?.genericParameterList.map { $0.name.text } ?? []
      let genericRequirements = try collectGenericRequirements(node.genericParameterClause, node.genericWhereClause)

      var predicates: [Predicate] = []

      let params: [TypeRepr] = try node.parameters.parameterList.map {
        guard let paramType = $0.type else {
          throw TranslationError.incompleteSource($0)
        }
        return try translateType(paramType)
      }
      if params.isEmpty {
        // FIXME: there should still be a predicate?
      } else {
        predicates.append(Predicate("TAKES", params))
      }

      let descriptors: [Descriptor] = collectModifiers(node.modifiers)

      var capabilities: [Descriptor] = []
      switch node.throwsOrRethrowsKeyword?.tokenKind {
      case .throwsKeyword?:
        capabilities.append(Descriptor("THROW"))
      case .rethrowsKeyword?:
        capabilities.append(Descriptor("RETHROW"))
      default:
        break
      }
      switch node.optionalMark?.tokenKind {
      case .postfixQuestionMark?:
        capabilities.append(Descriptor("FAIL"))
      case .exclamationMark?:
        capabilities.append(Descriptor("FAIL!"))
      default:
        break
      }
      if !capabilities.isEmpty {
        predicates.append(Predicate("CAN", capabilities))
      }

      let name = "init(" + node.parameters.parameterList.lazy.map {
        (($0.firstName ?? $0.secondName)?.text ?? "_") + ":"
      }.joined() + ")"
      let initializer = Entity(name: name,
                               kind: .initializer,
                               genericArguments: genericArgs,
                               children: [],
                               descriptors: descriptors,
                               genericRequirements: genericRequirements,
                               predicates: predicates)
      entities.append(initializer)
    }
    return .skipChildren
  }

  override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
    ignoringTranslationErrors {
      let genericArgs = node.genericParameterClause?.genericParameterList.map { $0.name.text } ?? []
      let genericRequirements = try collectGenericRequirements(node.genericParameterClause, node.genericWhereClause)

      var predicates: [Predicate] = []

      let params: [TypeRepr] = try node.indices.parameterList.map {
        guard let paramType = $0.type else {
          throw TranslationError.incompleteSource($0)
        }
        return try translateType(paramType)
      }
      if params.isEmpty {
        // FIXME: there should still be a predicate?
      } else {
        predicates.append(Predicate("TAKES", params))
      }

      predicates.append(Predicate("HAS", [try translateType(node.result.returnType)]))

      let descriptors: [Descriptor] = collectModifiers(node.modifiers)

      let name = "subs(" + node.indices.parameterList.lazy.map {
        ($0.firstName?.text ?? "_") + ":"
      }.joined() + ")"
      let subs = Entity(name: name,
                        kind: .subscript,
                        genericArguments: genericArgs,
                        children: [],
                        descriptors: descriptors,
                        genericRequirements: genericRequirements,
                        predicates: predicates)
      entities.append(subs)
    }
    return .skipChildren
  }

  override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
    ignoringTranslationErrors {
      let descriptors = collectModifiers(node.modifiers)

      node.elements.forEach { elementNode in
        ignoringTranslationErrors {
          var predicates: [Predicate] = []
          if let assocType = elementNode.associatedValue {
            predicates.append(Predicate("HAS", try assocType.parameterList.map {
              guard let type = $0.type else {
                throw TranslationError.incompleteSource($0)
              }
              return try translateType(type)
            }))
          }

          let binding = Entity(name: elementNode.identifier.text,
                               kind: .case,
                               genericArguments: [],
                               children: [],
                               descriptors: descriptors,
                               genericRequirements: [],
                               predicates: predicates)
          entities.append(binding)
        }
      }
    }
    return .skipChildren
  }

  override func visit(_ node: AssociatedtypeDeclSyntax) -> SyntaxVisitorContinueKind {
    ignoringTranslationErrors {
      let descriptors = collectModifiers(node.modifiers)

      let implicitRequirements: [Requirement] = try node.inheritanceClause?.inheritedTypeCollection.map {
        Requirement(TypeRepr(.named(node.identifier.text)), .isa, try translateType($0.typeName))
      } ?? []

      let whereClauseRequirements = try collectGenericRequirements(nil, node.genericWhereClause)

      let binding = Entity(name: node.identifier.text,
                           kind: .assocType,
                           genericArguments: [],
                           children: [],
                           descriptors: descriptors,
                           genericRequirements: implicitRequirements + whereClauseRequirements,
                           predicates: [])
      entities.append(binding)
    }
    return .skipChildren
  }

  override func visit(_ node: TypealiasDeclSyntax) -> SyntaxVisitorContinueKind {
    ignoringTranslationErrors {
      let genericArgs = node.genericParameterClause?.genericParameterList.map { $0.name.text } ?? []
      let genericRequirements = try collectGenericRequirements(node.genericParameterClause, node.genericWhereClause)

      let descriptors = collectModifiers(node.modifiers)

      var predicates: [Predicate] = []
      guard let underlyingType = node.initializer?.value else {
        throw TranslationError.incompleteSource(node)
      }
      predicates.append(Predicate("HAS", [try translateType(underlyingType)]))

      let nominal = Entity(name: node.identifier.text,
                           kind: .typealias,
                           genericArguments: genericArgs,
                           children: [],
                           descriptors: descriptors,
                           genericRequirements: genericRequirements,
                           predicates: predicates)
      entities.append(nominal)
    }
    return .skipChildren
  }

  override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
    ignoringTranslationErrors {
      var predicates: [Predicate] = []
      if let inheritanceClause = node.inheritanceClause {
        predicates.append(Predicate("ISA", try inheritanceClause.inheritedTypeCollection.map {
          try translateType($0.typeName)
        }))
      }

      let childrenTranslator = Translator()
      node.members.walk(childrenTranslator)

      let extendedType = try translateType(node.extendedType)
      guard case .named(let name) = extendedType.kind else {
        // FIXME: Support extensions with type sugar?
        return
      }

      // FIXME: Ignoring constraints!
      let ext = Entity(name: name,
                       kind: .extension,
                       genericArguments: [],
                       children: childrenTranslator.entities,
                       descriptors: [],
                       genericRequirements: [],
                       predicates: predicates)
      entities.append(ext)
    }
    return .skipChildren
  }
}

extension Array {
  fileprivate func padded(to newCount: Int, with element: Element) -> [Element] {
    return self + Array(repeating: element, count: newCount - self.count)
  }
}

public func generateCells(from parsedFile: SourceFileSyntax) -> [[Cell]] {
  let translator = Translator()
  parsedFile.walk(translator)
  var result = [[]] + translator.entities.flatMap { $0.asHierarchicalCells }

  let longestLineLength = result.lazy.map { $0.count }.max() ?? 0

  // The check for 3 vs. 4 here is not a typo; if we have *more* than 3 lines,
  // we need to leave a blank space below "VIEW". (Well, we want to.)
  if result.count >= 3 && result.lazy.prefix(4).allSatisfy({ $0.count < longestLineLength - 1 }) {
    result[0] = result[0].padded(to: longestLineLength - 1, with: .empty) + ["SOURCE"]
    result[1] = result[1].padded(to: longestLineLength - 1, with: .empty) + ["IS"]
    result[2] = result[2].padded(to: longestLineLength - 1, with: .empty) + ["VIEW"]
  }

  return result
}
