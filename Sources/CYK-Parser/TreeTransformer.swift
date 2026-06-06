//
//  TreeTransformer.swift
//  Grammar
//
//  Created by Ulf Akerstedt-Inoue on 2025/12/07.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import Foundation
import Grammar

class TreeTransformer {
    
    /// prefixes used by the CNFConverter in the previous step
    private let binPrefix = "BIN"
    private let termPrefix = "T_"
    private let startName = "CNF_Start"
    
    private let originalStart: NonTerminal?
    
    public init(originalStart: NonTerminal? = nil) {
        self.originalStart = originalStart
    }
    
    /// Reconstructs a natural tree from a CNF-based ParseTree
    public func transform(_ tree: ParseTree) -> ParseTree {
        switch tree {
        case .leaf, .empty:
            // Base cases: cannot transform these further
            return tree
            
        case .node(let nonTerminal, let originalChildren):
            
            // 1. RECURSION & FLATTENING
            // We process children first (bottom-up transformation).
            // While doing so, if we encounter a child that is a "BIN" node,
            // we hoist its children up to this level.
            
            var newChildren: [ParseTree] = []
            
            for child in originalChildren {
                let transformedChild = transform(child)
                
                if case .node(let childNt, let grandChildren) = transformedChild,
                   childNt.name.hasPrefix(binPrefix) {
                    // Logic: A -> B BIN_1, BIN_1 -> C D
                    // The tree looks like Node(A, [B, Node(BIN_1, [C, D])])
                    // We change it to: Node(A, [B, C, D])
                    newChildren.append(contentsOf: grandChildren)
                } else {
                    newChildren.append(transformedChild)
                }
            }
            
            // 2. TERMINAL UNWRAPPING
            // Logic: The CNF converter turned 'A -> B +' into 'A -> B T_+', 'T_+ -> +'
            // If the current node is 'T_...' and has exactly one leaf child, return the leaf directly.
            if nonTerminal.name.hasPrefix(termPrefix) {
                if newChildren.count == 1 {
                    // Check if the child is a leaf
                    if case .leaf = newChildren[0] {
                        return newChildren[0]
                    }
                }
            }
            
            // 3. START SYMBOL UNWRAPPING
            // Logic: Rename the artificial 'CNF_Start' root to the original start symbol,
            // or fallback to returning its first child.
            if nonTerminal.name == startName {
                if let original = originalStart {
                    return .node(original, children: newChildren)
                }
                if let firstChild = newChildren.first {
                    return firstChild
                }
            }
            
            // 4. RECONSTRUCT
            return .node(nonTerminal, children: newChildren)
        }
    }
}
