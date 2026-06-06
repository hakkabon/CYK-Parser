//
//  GenerlizedParser.swift
//  Grammar
//
//  Created by Ulf Akerstedt-Inoue on 2023/08/11.
//  Copyright © 2023 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import Tokenizer

/// The outcome of a parse attempt.
public enum ParseResult {
    /// Parse succeeded; the BSR set and SPPF graph are available.
    case success(bsr: Set<BSR>, sppf: SPPFGraph)
    
    /// Parse failed; `position` is the furthest token that was consumed.
    case failure(position: Int, message: String)

    public var hasAmbiguity: Bool {
        switch self {
        case let .success(_, graph):
            return graph.getAllNodes().contains { node in
                graph.getChildren(of: node).filter { $0.isPacked }.count > 1
            }
        default: return false
        }
    }
}

extension ParseResult {
    /// Returns all possible concrete syntax trees (ParseTree) for a successful parse.
    /// Returns an empty array if the parse failed.
    public func allSyntaxTrees(startSymbol: NonTerminal, originalStart: NonTerminal, tokens: [Token]) -> [ParseTree] {
        switch self {
        case .success(_, let sppf):
            let rootNode = SPPFNode.symbol(symbol: .nonTerminal(startSymbol), i: 0, j: tokens.count)
            let rawTrees = sppf.allParseTrees(for: rootNode, tokens: tokens)
            let transformer = TreeTransformer(originalStart: originalStart)
            return rawTrees.map { transformer.transform($0) }
        case .failure:
            return []
        }
    }
}

/// A parser that can parse ambiguous grammars and retrieve every possible syntax tree.
public protocol GeneralizedParser {
    /// Generates the parse result containing BSR and SPPF.
    ///
    /// - Parameter string: Input word, for which a parse result should be generated.
    /// - Returns: ParseResult containing BSR set and SPPF graph on success, or error information on failure.
    func parse(_ string: String) throws -> ParseResult
}

/// Compatibility typealias for the legacy spelling
public typealias GereralizedParser = GeneralizedParser
