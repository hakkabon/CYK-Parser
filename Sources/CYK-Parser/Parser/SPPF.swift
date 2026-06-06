//
//  SPPF.swift
//  CYK-Parser
//
//  Created by Ulf Akerstedt-Inoue on 2026/05/27.
//

import Foundation
import Grammar
import Tokenizer

public enum SPPFNode: Hashable, CustomStringConvertible {
    /// A symbol node representing a non-terminal or terminal spanning from `i` to `j`.
    case symbol(symbol: Symbol, i: Int, j: Int)
    
    /// A packed node representing a partition/derivation of a symbol node, with pivot `k`.
    case packed(rule: CNFRule, k: Int, i: Int, j: Int)
    
    public var isPacked: Bool {
        switch self {
        case .packed: return true
        case .symbol: return false
        }
    }
    
    public var description: String {
        switch self {
        case .symbol(let symbol, let i, let j):
            return "(\(symbol), \(i), \(j))"
        case .packed(let rule, let k, let i, let j):
            return "(\(rule), \(k), [\(i), \(j)])"
        }
    }
    
    public var idString: String {
        switch self {
        case .symbol(let symbol, let i, let j):
            let symClean = sanitize("\(symbol)")
            return "sym_\(symClean)_\(i)_\(j)"
        case .packed(let rule, let k, let i, let j):
            let ruleClean = sanitize("\(rule)")
            return "pack_\(ruleClean)_\(k)_\(i)_\(j)"
        }
    }
    
    private func sanitize(_ string: String) -> String {
        return string.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "_")
    }
}

public class SPPFGraph: CustomStringConvertible {
    public private(set) var nodes: Set<SPPFNode> = []
    public private(set) var edges: [SPPFNode: Set<SPPFNode>] = [:]
    
    public init() {}
    
    public func addNode(_ node: SPPFNode) {
        nodes.insert(node)
    }
    
    public func addEdge(from parent: SPPFNode, to child: SPPFNode) {
        addNode(parent)
        addNode(child)
        edges[parent, default: []].insert(child)
    }
    
    public func getChildren(of node: SPPFNode) -> Set<SPPFNode> {
        return edges[node] ?? []
    }
    
    public func getAllNodes() -> Set<SPPFNode> {
        return nodes
    }
    
    public var description: String {
        return graphviz
    }
    
    public var graphviz: String {
        var result = "digraph SPPF {\n"
        let sortedNodes = nodes.sorted { $0.description < $1.description }
        for node in sortedNodes {
            let label = node.description.replacingOccurrences(of: "\"", with: "\\\"")
            let shape = node.isPacked ? "ellipse" : "box"
            let color = node.isPacked ? "lightgray" : "lightblue"
            result += "  \"\(node.idString)\" [label=\"\(label)\" shape=\(shape) style=filled fillcolor=\(color)];\n"
        }
        for parent in sortedNodes {
            if let children = edges[parent] {
                let sortedChildren = children.sorted { $0.description < $1.description }
                for child in sortedChildren {
                    result += "  \"\(parent.idString)\" -> \"\(child.idString)\";\n"
                }
            }
        }
        result += "}"
        return result
    }
}

extension SPPFGraph {
    /// Extracts all possible `ParseTree`s from a given symbol node in the SPPF graph.
    public func allParseTrees(for node: SPPFNode, tokens: [Token]) -> [ParseTree] {
        switch node {
        case .symbol(let sym, let i, let j):
            switch sym {
            case .terminal:
                // Terminal symbols return the range of the token at index i
                guard i < tokens.count else { return [] }
                return [.leaf(tokens[i].range)]
                
            case .nonTerminal(let A):
                let packedNodes = getChildren(of: node).filter { $0.isPacked }
                if packedNodes.isEmpty {
                    return []
                }
                var results: [ParseTree] = []
                for packed in packedNodes {
                    guard case .packed(let rule, _, _, _) = packed else { continue }
                    let childrenOfPacked = getChildren(of: packed)
                    
                    switch rule {
                    case .terminal:
                        guard let termChild = childrenOfPacked.first else { continue }
                        let subTrees = allParseTrees(for: termChild, tokens: tokens)
                        results.append(contentsOf: subTrees)
                        
                    case .binary(let parentA, let B, let C):
                        // Binary rule A -> B C spanning from i to j
                        // Find child symbol nodes (B, i, k) and (C, k, j)
                        let leftChild = childrenOfPacked.first { c in
                            if case .symbol(let childSym, let ci, _) = c,
                               case .nonTerminal(let childNT) = childSym {
                                return childNT == B && ci == i
                            }
                            return false
                        }
                        let rightChild = childrenOfPacked.first { c in
                            if case .symbol(let childSym, _, let cj) = c,
                               case .nonTerminal(let childNT) = childSym {
                                return childNT == C && cj == j
                            }
                            return false
                        }
                        
                        guard let left = leftChild, let right = rightChild else { continue }
                        
                        let leftTrees = allParseTrees(for: left, tokens: tokens)
                        let rightTrees = allParseTrees(for: right, tokens: tokens)
                        
                        for lTree in leftTrees {
                            for rTree in rightTrees {
                                results.append(.node(parentA, children: [lTree, rTree]))
                            }
                        }
                    }
                }
                return results
                
            case .metaSymbol:
                return []
            }
        case .packed:
            return []
        }
    }
}
