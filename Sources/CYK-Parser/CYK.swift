//
//  CYK.swift
//  Grammar
//
//  Created by Ulf Akerstedt-Inoue on 2025/12/07.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import Lexer
import Parser

public final class CYKParser: DeterministicParser, GeneralizedParser {
    public typealias Label = CNFRule

    let startSymbol: NonTerminal
    let originalStartSymbol: NonTerminal
    let rules: Set<CNFRule>
    let symbols = ["|", "\\", "^", ":", ",", "$", ".", "\"", "¶", ">", "#", "+", "-", "{","[", "<", "(",
                   "'", "}", "]", ":]", ")", ";", "/", "*", "?", "??", ":="]

    public init(grammar: Grammar) {
        let converter = CNFConverter()
        let result = converter.convert(grammar)
        self.startSymbol = result.start
        self.originalStartSymbol = grammar.start
        self.rules = result.rules
    }

    // MARK: - DeterministicParser / GeneralizedParser protocols

    public func syntaxTree(for string: String) throws -> ParseTree {
        let stream = TokenizerStream(source: string, symbols: Set(symbols), keywords: [])
        if stream.count == 0 {
            return .empty
        }
        let (terminals, ranges) = try streamTerminals(stream)
        let result = runCYK(terminals: terminals)
        guard result.isSuccessful, let sppfGraph = result.sppfGraph else {
            throw ParseError.unexpectedToken(token: failureMessage(for: string), state: -1)
        }
        let trees = parseTrees(from: sppfGraph, ranges: ranges, string: string)
        guard let firstTree = trees.first else {
            throw ParseError.internalError("Succeeded parsing but could not build any syntax tree.")
        }
        return firstTree
    }

    public func allSyntaxTrees(for string: String) throws -> [ParseTree] {
        let stream = TokenizerStream(source: string, symbols: Set(symbols), keywords: [])
        if stream.count == 0 {
            return [.empty]
        }
        let (terminals, ranges) = try streamTerminals(stream)
        let result = runCYK(terminals: terminals)
        guard result.isSuccessful, let sppfGraph = result.sppfGraph else {
            throw ParseError.unexpectedToken(token: failureMessage(for: string), state: -1)
        }
        return parseTrees(from: sppfGraph, ranges: ranges, string: string)
    }

    /// Parses `source` text using GrammarTokenizer's general-purpose
    /// `Tokenizer` (configured with this parser's fixed `symbols` list), then
    /// runs the CYK algorithm.
    public func parse(_ source: String) throws -> ParseResult<CNFRule> {
        let stream = TokenizerStream(source: source, symbols: Set(symbols), keywords: [])
        let (terminals, _) = try streamTerminals(stream)
        return runCYK(terminals: terminals)
    }

    // MARK: - Lexer integration

    /// Parses any `TokenStream` — the DFA-driven `LexerTokenStream` (built via
    /// a `LexerBuilder` bootstrapped from a `GrammarVocabulary`) and the
    /// hand-written `TokenizerStream` are both accepted interchangeably, as
    /// is any other conformance — and runs the same CYK algorithm core as
    /// `parse(_ string:)`.
    ///
    /// - Parameter stream: A positioned sequence of tokens, each resolvable
    ///   to a `Terminal` and a source `Range<String.Index>`.
    /// - Returns: A `ParseResult` describing success, the BSR set, and the SPPF graph.
    /// - Throws: whatever error `stream.terminal(at:)` throws for a lexical failure.
    public func parse<S: TokenStream>(stream: S) throws -> ParseResult<CNFRule> {
        let (terminals, _) = try streamTerminals(stream)
        return runCYK(terminals: terminals)
    }

    /// Materialises a `TokenStream` into parallel `Terminal` and
    /// `Range<String.Index>` arrays, one entry per position.
    private func streamTerminals<S: TokenStream>(_ stream: S) throws -> (terminals: [Terminal], ranges: [Range<String.Index>]) {
        var terminals: [Terminal] = []
        var ranges: [Range<String.Index>] = []
        terminals.reserveCapacity(stream.count)
        ranges.reserveCapacity(stream.count)
        for position in 0..<stream.count {
            let (terminal, range) = try stream.terminal(at: position)
            terminals.append(terminal)
            ranges.append(range)
        }
        return (terminals, ranges)
    }

    /// Builds the natural-grammar parse trees for a successful parse's SPPF
    /// graph, un-doing the CNF conversion via `TreeTransformer`.
    private func parseTrees(from sppfGraph: SPPFGraph<CNFRule>, ranges: [Range<String.Index>], string: String) -> [ParseTree] {
        let rawTrees = sppfGraph.buildAllParseTrees(startSymbol: startSymbol.name, ranges: ranges, string: string)
        let transformer = TreeTransformer(originalStart: originalStartSymbol)
        return rawTrees.map { transformer.transform($0) }
    }

    private func failureMessage(for string: String) -> String {
        return "Parsing failed: input '\(string)' not derived from start symbol '\(originalStartSymbol)'."
    }

    // MARK: - Algorithm core

    /// The CYK dynamic-programming recognizer and SPPF builder, parameterised
    /// purely on a `[Terminal]` — one per input position. Both
    /// `parse(_ string:)` (via a default `TokenizerStream`) and
    /// `parse(stream:)` (via any `TokenStream`) converge here, so the two
    /// front ends can never drift apart on the actual parsing algorithm.
    private func runCYK(terminals: [Terminal]) -> ParseResult<CNFRule> {
        let n = terminals.count
        if n == 0 {
            return ParseResult(isSuccessful: true, bsr: Set(), sppfGraph: SPPFGraph<CNFRule>())
        }

        // Initialize DP Table: table[start_index][span_length] -> Set<NonTerminal>
        var table = Array(repeating: Array(repeating: Set<NonTerminal>(), count: n + 1), count: n)
        var bsrSet = Set<BSR<CNFRule>>()

        // Base Case: Length 1 (Terminals)
        for i in 0..<n {
            let terminal = terminals[i]

            for rule in rules {
                // `rhs` is the grammar's terminal from a CNF rule `A -> a` (possibly
                // a regex/range/list terminal resolved from a `lexical { }`
                // declaration); `terminal` is the concrete lexeme the stream
                // produced at this position. matches(_:) is the asymmetric check
                // for exactly this — see Terminal.matches(_:) in the Grammar package.
                if case .terminal(let lhs, let rhs) = rule, rhs.matches(terminal) {
                    table[i][1].insert(lhs)
                    // A single-symbol production's pivot equals its leftExtent:
                    // there is no split, the one child spans the whole [i, i+1)
                    // range. This matches the convention the shared CST
                    // enumeration algorithm (Parser module) expects for a
                    // packed node with exactly one child.
                    let bsr = BSR(label: rule, leftExtent: i, pivot: i, rightExtent: i + 1)
                    bsrSet.insert(bsr)
                }
            }
        }

        // Main Loop: Length 2 to n
        if n >= 2 {
            for length in 2...n {
                for s in 0...(n - length) { // Start index
                    for p in 1..<length {   // Partition (split point)
                        let leftCell = table[s][p]
                        let rightCell = table[s + p][length - p]

                        for B in leftCell {
                            for C in rightCell {
                                for rule in rules {
                                    if case .binary(let A, let ruleB, let ruleC) = rule,
                                       ruleB == B, ruleC == C {
                                        table[s][length].insert(A)
                                        let bsr = BSR(label: rule, leftExtent: s, pivot: s + p, rightExtent: s + length)
                                        bsrSet.insert(bsr)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Check if startSymbol was successfully derived
        guard table[0][n].contains(startSymbol) else {
            return ParseResult(isSuccessful: false, bsr: bsrSet, sppfGraph: nil)
        }

        // Build SPPF Graph
        let sppf = SPPFGraph<CNFRule>()
        let rootNode = SPPFNode<CNFRule>.symbol(label: startSymbol.name, leftExtent: 0, rightExtent: n)
        var visited = Set<SPPFNode<CNFRule>>()
        buildSPPF(symbolNode: rootNode, bsrSet: bsrSet, sppf: sppf, visited: &visited)

        return ParseResult(isSuccessful: true, bsr: bsrSet, sppfGraph: sppf)
    }

    private func buildSPPF(
        symbolNode: SPPFNode<CNFRule>,
        bsrSet: Set<BSR<CNFRule>>,
        sppf: SPPFGraph<CNFRule>,
        visited: inout Set<SPPFNode<CNFRule>>
    ) {
        guard !visited.contains(symbolNode) else { return }
        visited.insert(symbolNode)
        sppf.add(symbolNode)

        guard case let .symbol(label, i, j) = symbolNode else { return }
        let A = NonTerminal(name: label)

        let matchingBSRs = bsrSet.filter { bsr in
            bsr.leftExtent == i && bsr.rightExtent == j && bsr.label.goal == A
        }

        for bsr in matchingBSRs {
            let packedNode = SPPFNode<CNFRule>.packed(label: bsr.label, leftExtent: i, rightExtent: j, pivot: bsr.pivot)
            sppf.add(packedNode)
            sppf.addEdge(from: symbolNode, to: packedNode)

            switch bsr.label {
            case .terminal(_, let t):
                let leafNode = SPPFNode<CNFRule>.leaf(label: t.description, leftExtent: i, rightExtent: j)
                sppf.add(leafNode)
                sppf.addEdge(from: packedNode, to: leafNode)

            case .binary(_, let B, let C):
                let leftNode = SPPFNode<CNFRule>.symbol(label: B.name, leftExtent: i, rightExtent: bsr.pivot)
                let rightNode = SPPFNode<CNFRule>.symbol(label: C.name, leftExtent: bsr.pivot, rightExtent: j)

                sppf.add(leftNode)
                sppf.add(rightNode)
                sppf.addEdge(from: packedNode, to: leftNode)
                sppf.addEdge(from: packedNode, to: rightNode)

                buildSPPF(symbolNode: leftNode, bsrSet: bsrSet, sppf: sppf, visited: &visited)
                buildSPPF(symbolNode: rightNode, bsrSet: bsrSet, sppf: sppf, visited: &visited)
            }
        }
    }
}
