//
//  CYK.swift
//  Grammar
//
//  Created by Ulf Akerstedt-Inoue on 2025/12/07.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import Tokenizer

public class CYKParser: Parser, GeneralizedParser {    
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
    
    public func syntaxTree(for string: String) throws -> ParseTree {
        let tokenizer = Tokenizer(string, symbols: Set(symbols), keywords: [])
        let tokens = tokenizer.tokenize()
        if tokens.isEmpty {
            return .empty
        }
        let result = try parse(string)
        switch result {
        case .success:
            let trees = result.allSyntaxTrees(startSymbol: startSymbol, originalStart: originalStartSymbol, tokens: tokens)
            guard let firstTree = trees.first else {
                throw ParseError.internalError("Succeeded parsing but could not build any syntax tree.")
            }
            return firstTree
        case .failure(_, let message):
            throw ParseError.unexpectedToken(token: message, state: -1)
        }
    }

    public func allSyntaxTrees(for string: String) throws -> [ParseTree] {
        let tokenizer = Tokenizer(string, symbols: Set(symbols), keywords: [])
        let tokens = tokenizer.tokenize()
        if tokens.isEmpty {
            return [.empty]
        }
        let result = try parse(string)
        switch result {
        case .success:
            return result.allSyntaxTrees(startSymbol: startSymbol, originalStart: originalStartSymbol, tokens: tokens)
        case .failure(_, let message):
            throw ParseError.unexpectedToken(token: message, state: -1)
        }
    }

    public func parse(_ source: String) throws -> ParseResult {
        let tokenizer = Tokenizer(source, symbols: Set(symbols), keywords: [])
        let tokens: [Token] = tokenizer.tokenize()
        let n = tokens.count
        if n == 0 {
            return .success(bsr: Set(), sppf: SPPFGraph())
        }
        
        // Initialize DP Table: table[start_index][span_length] -> Set<NonTerminal>
        var table = Array(repeating: Array(repeating: Set<NonTerminal>(), count: n + 1), count: n)
        var bsrSet = Set<BSR>()
        
        // Base Case: Length 1 (Terminals)
        for i in 0..<n {
            let token = tokens[i]
            let terminal = extractTerminal(token)
            
            for rule in rules {
                if case .terminal(let lhs, let rhs) = rule, rhs == terminal {
                    table[i][1].insert(lhs)
                    let bsr = BSR(rule: rule, i: i, k: i + 1, j: i + 1)
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
                                        let bsr = BSR(rule: rule, i: s, k: s + p, j: s + length)
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
            return .failure(position: 0, message: "Parsing failed: start symbol '\(startSymbol)' not derived over full input.")
        }
        
        // Build SPPF Graph
        let sppf = SPPFGraph()
        let rootNode = SPPFNode.symbol(symbol: .nonTerminal(startSymbol), i: 0, j: n)
        var visited = Set<SPPFNode>()
        buildSPPF(symbolNode: rootNode, bsrSet: bsrSet, tokens: tokens, sppf: sppf, visited: &visited)
        
        return .success(bsr: bsrSet, sppf: sppf)
    }
    
    private func buildSPPF(
        symbolNode: SPPFNode,
        bsrSet: Set<BSR>,
        tokens: [Token],
        sppf: SPPFGraph,
        visited: inout Set<SPPFNode>
    ) {
        guard !visited.contains(symbolNode) else { return }
        visited.insert(symbolNode)
        sppf.addNode(symbolNode)
        
        guard case .symbol(let sym, let i, let j) = symbolNode else { return }
        
        switch sym {
        case .nonTerminal(let A):
            let matchingBSRs = bsrSet.filter { bsr in
                bsr.i == i && bsr.j == j && bsr.rule.goal == A
            }
            
            for bsr in matchingBSRs {
                let packedNode = SPPFNode.packed(rule: bsr.rule, k: bsr.k, i: i, j: j)
                sppf.addEdge(from: symbolNode, to: packedNode)
                
                switch bsr.rule {
                case .terminal(_, let t):
                    let termNode = SPPFNode.symbol(symbol: .terminal(t), i: i, j: j)
                    sppf.addEdge(from: packedNode, to: termNode)
                    
                case .binary(_, let B, let C):
                    let leftNode = SPPFNode.symbol(symbol: .nonTerminal(B), i: i, j: bsr.k)
                    let rightNode = SPPFNode.symbol(symbol: .nonTerminal(C), i: bsr.k, j: j)
                    
                    sppf.addEdge(from: packedNode, to: leftNode)
                    sppf.addEdge(from: packedNode, to: rightNode)
                    
                    buildSPPF(symbolNode: leftNode, bsrSet: bsrSet, tokens: tokens, sppf: sppf, visited: &visited)
                    buildSPPF(symbolNode: rightNode, bsrSet: bsrSet, tokens: tokens, sppf: sppf, visited: &visited)
                }
            }
            
        case .terminal:
            break
            
        case .metaSymbol:
            break
        }
    }
    
    private func extractTerminal(_ token: Token) -> Terminal {
        switch token.type {
        case .symbol(let s): return Terminal(string: s)
        case .literal(let s): return Terminal(string: s)
        case .identifier(let s): return Terminal(string: s)
        case .number(let n): return Terminal(string: "\(n)") // simplified
        default: return Terminal(string: token.description)
        }
    }
}
