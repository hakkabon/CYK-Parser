//
//  BSR.swift
//  CYK-Parser
//
//  Created by Ulf Akerstedt-Inoue on 2026/05/27.
//

import Foundation
import Grammar

public struct BSR: Hashable, CustomStringConvertible {
    public let rule: CNFRule
    public let i: Int // start index of token span
    public let k: Int // pivot / split point
    public let j: Int // end index of token span
    
    public init(rule: CNFRule, i: Int, k: Int, j: Int) {
        self.rule = rule
        self.i = i
        self.k = k
        self.j = j
    }
    
    public var description: String {
        return "(\(rule), \(i), \(k), \(j))"
    }
}

public typealias BSRSet = Set<BSR>
