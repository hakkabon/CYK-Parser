//
//  CYK.swift
//  Grammar
//
//  Created by Ulf Akerstedt-Inoue on 2025/12/07.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import Parser

// MARK: - Extensions for Logic
// Helper to generate unique names for new non-terminals created during CNF conversion
class IDGenerator {
    private var counter = 0
    func next(prefix: String) -> String {
        counter += 1
        return "\(prefix)_\(counter)"
    }
}

// A specific production type for CNF: Either A -> BC or A -> a
public enum CNFRule: Hashable, Codable, CustomStringConvertible, SPPFLabel {
    case binary(NonTerminal, NonTerminal, NonTerminal) // A -> B C
    case terminal(NonTerminal, Terminal)               // A -> a
    
    public var goal: NonTerminal {
        switch self {
        case .binary(let lhs, _, _): return lhs
        case .terminal(let lhs, _): return lhs
        }
    }

    /// The right-hand-side symbols of this rule — `[B, C]` for `A -> B C`,
    /// or `[a]` for `A -> a`. Required by `SPPFLabel`.
    public var symbols: [Symbol] {
        switch self {
        case .binary(_, let b, let c): return [.nonTerminal(b), .nonTerminal(c)]
        case .terminal(_, let t): return [.terminal(t)]
        }
    }

    /// A CYK packed node always represents a fully-applied production — CYK
    /// has no notion of a partially-matched dotted item — so the dot sits at
    /// the end of `symbols`. Required by `SPPFLabel`.
    public var position: Int {
        return symbols.count
    }
    
    public var description: String {
        switch self {
        case .binary(let a, let b, let c): return "\(a) -> \(b) \(c)"
        case .terminal(let a, let t): return "\(a) -> \(t)"
        }
    }
}

// MARK: - CNF Converter
class CNFConverter {
    let generator = IDGenerator()
    
    func convert(_ grammar: Grammar) -> (start: NonTerminal, rules: Set<CNFRule>) {
        var pendingRules = grammar.productions
        var finalRules = Set<CNFRule>()
        
        // 1. ELIMINATE START RECURSION
        // Create S0 -> S
        let newStart = NonTerminal(name: "CNF_Start")
        pendingRules.append(Production(goal: newStart, rule: [.nonTerminal(grammar.start)]))
        
        // 2. TERM: Isolate Terminals
        // Convert rules like A -> B + C into A -> B T_plus C, T_plus -> +
        // Also map terminals to temporary NonTerminals
        var termMap: [Terminal: NonTerminal] = [:]
        
        var step2Rules: [Production] = []
        
        for prod in pendingRules {
            var newRHS: [Symbol] = []
            
            // If rule is A -> a (just one terminal), keep it as is for now
            if prod.rule.count == 1, case .terminal = prod.rule[0] {
                step2Rules.append(prod)
                continue
            }
            
            for sym in prod.rule {
                if case .terminal(let t) = sym {
                    // Create or reuse a NonTerminal for this terminal
                    let termNT: NonTerminal
                    if let existing = termMap[t] {
                        termNT = existing
                    } else {
                        termNT = NonTerminal(name: "T_\(t.description)") // Simplified naming
                        termMap[t] = termNT
                        // Add immediate rule T -> t
                        step2Rules.append(Production(goal: termNT, rule: [.terminal(t)]))
                    }
                    newRHS.append(.nonTerminal(termNT))
                } else {
                    newRHS.append(sym)
                }
            }
            step2Rules.append(Production(goal: prod.goal, rule: newRHS))
        }
        
        // 3. BIN: Binarize long rules
        // Convert A -> B C D into A -> B X, X -> C D
        var step3Rules: [Production] = []
        
        for prod in step2Rules {
            if prod.rule.count <= 2 {
                step3Rules.append(prod)
                continue
            }
            
            // Extract NonTerminals (Step 2 ensured RHS is all NonTerminals now)
            let nts = prod.rule.map { s -> NonTerminal in
                guard case .nonTerminal(let n) = s else { fatalError("Bug in Step 2") }
                return n
            }
            
            var currentLHS = prod.goal
            
            for i in 0..<(nts.count - 2) {
                let newNT = NonTerminal(name: generator.next(prefix: "BIN"))
                // Create rule: currentLHS -> nts[i] newNT
                step3Rules.append(Production(goal: currentLHS, rule: [.nonTerminal(nts[i]), .nonTerminal(newNT)]))
                currentLHS = newNT
            }
            
            // Final rule: currentLHS -> last two
            step3Rules.append(Production(goal: currentLHS, rule: [.nonTerminal(nts[nts.count-2]), .nonTerminal(nts.last!)]))
        }
        
        // 4. UNIT: Eliminate Unit Rules (A -> B)
        // Find unit pairs and non-unit rules
        var unitPairs: [NonTerminal: Set<NonTerminal>] = [:] // A -> {B, C}
        var nonUnitRules: [Production] = []
        
        // Organize
        for prod in step3Rules {
            if prod.rule.count == 1, case .nonTerminal(let target) = prod.rule[0] {
                unitPairs[prod.goal, default: []].insert(target)
            } else {
                nonUnitRules.append(prod)
            }
        }
        
        // Compute closure of Unit Pairs (If A->B and B->C, add A->C)
        // Fixed point iteration
        var changed = true
        while changed {
            changed = false
            for (lhs, targets) in unitPairs {
                for target in targets {
                    if let subTargets = unitPairs[target] {
                        if !subTargets.isSubset(of: targets) {
                            unitPairs[lhs]?.formUnion(subTargets)
                            changed = true
                        }
                    }
                }
            }
        }
        
        // Create final CNF Rules
        // 1. Add all non-unit rules as they are (mapped to CNF type)
        for prod in nonUnitRules {
            addToFinal(prod, into: &finalRules)
        }
        
        // 2. Add propagated rules from Units
        // If A ->* B (unit) and B -> alpha (non-unit), add A -> alpha
        for (lhs, targets) in unitPairs {
            for target in targets {
                // Find all non-unit rules for 'target'
                let targetRules = nonUnitRules.filter { $0.goal == target }
                for targetProd in targetRules {
                    let newProd = Production(goal: lhs, rule: targetProd.rule)
                    addToFinal(newProd, into: &finalRules)
                }
            }
        }
        
        return (newStart, finalRules)
    }
    
    private func addToFinal(_ p: Production, into set: inout Set<CNFRule>) {
        if p.rule.count == 1, case .terminal(let t) = p.rule[0] {
            set.insert(.terminal(p.goal, t))
        } else if p.rule.count == 2,
                  case .nonTerminal(let b) = p.rule[0],
                  case .nonTerminal(let c) = p.rule[1] {
            set.insert(.binary(p.goal, b, c))
        } else {
            // Should not happen if logic is correct
            print("Warning: Skipping non-CNF rule in final pass: \(p)")
        }
    }
}

