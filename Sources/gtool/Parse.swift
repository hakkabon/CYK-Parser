//
//  Parse.swift
//  gtool
//
//  Created by Ulf Akerstedt-Inoue on 2024/03/16.
//  Copyright © 2024 hakkabon software. All rights reserved.
//

import Foundation
import ArgumentParser
import Grammar
import CYK_Parser
import Parser
import ShellOut

///  Parses any input sentence based on its given grammar specification.
///  It renders the result as a syntax tree, a DOT parse-tree diagram,
///  or the full SPPF graph in DOT format.

extension GrammarTool {
    
    struct Parse: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Generate parse tree of input applied to given grammar.")

        @OptionGroup var options: Options

        @Option(name: [.long, .short], help: "Input to be parsed using the grammar.", transform: Source.init)
        var input: Source = Source("")
        
        @Option(name: [.long, .short], help: "Use { tree | graph | sppf } to display result of parse.")
        var analysis: Analysis = .tree

        mutating func run() throws {
            
            let grammar: Grammar = switch Notation(argument: options.grammar.pathExtension) {
            case .bnf: try Grammar(bnf: try String(contentsOf: options.grammar), start: options.start)
            case .ebnf: try Grammar(ebnf: try String(contentsOf: options.grammar), start: options.start)
            case .gen: try Grammar(gen: try String(contentsOf: options.grammar))
            case .wsn: try Grammar(wsn: try String(contentsOf: options.grammar), start: options.start)
            case .custom(_):
                //TODO: not implemented yet!
                try Grammar(bnf: try String(contentsOf: options.grammar), start: options.start)
            }
            
            let parser = CYKParser(grammar: grammar)
            
            switch input {
            case .arg(let inputString): // String input
                guard !inputString.isEmpty else { return }
                try runAnalysis(analysis, parser: parser, input: inputString, grammar: grammar)
                
            case .url(let url): // File input
                let content = try String(contentsOf: url)
                try runAnalysis(analysis, parser: parser, input: content, grammar: grammar)
            }
        }
                
        private func runAnalysis(_ analysis: Analysis, parser: CYKParser, input: String, grammar: Grammar) throws {
            
            switch analysis {
            case .tree:
                let parsetree = try parser.syntaxTree(for: input).mapLeafs{ String(input[$0]) }
                print("\(parsetree)")
                
            case .graph:
                let parsetree = try parser.syntaxTree(for: input).mapLeafs { String(input[$0]) }
                let dotfile = parsetree.graphviz
                try shellOut(to: ["echo '\(dotfile)' | dot -Tpdf > parse-tree.pdf", "open parse-tree.pdf"])
                
            case .sppf:
                let result = try parser.parse(input)
                if result.isSuccessful, let sppf = result.sppfGraph {
                    print("Parse successful!")
                    print("Has ambiguity: \(result.hasAmbiguity)")
                    print("BSR Set:")
                    for entry in result.bsr.sorted(by: { $0.description < $1.description }) {
                        print("  \(entry)")
                    }
                    let dotfile = sppf.graphviz
                    print("SPPF Graphviz generated.")
                    try shellOut(to: ["echo '\(dotfile)' | dot -Tpdf > sppf.pdf", "open sppf.pdf"])
                } else {
                    print("Parse failed: input not recognized by the grammar.")
                }
            }
        }
    }
}
