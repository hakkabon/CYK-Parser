# CYK-Parser

A Swift implementation of the **Cocke–Younger–Kasami (CYK)** parsing algorithm — a general-purpose, chart-based parser that can recognize and parse any context-free grammar (CFG). The library handles ambiguous grammars natively, returning all possible syntax trees via a Shared Packed Parse Forest (SPPF).

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)  
[![Platforms](https://img.shields.io/badge/platforms-macOS%2011%20%7C%20iOS%2014-blue.svg)](https://developer.apple.com/swift/)  
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)  

---

## Features

- **Full CFG support** — parses any context-free grammar, including ambiguous ones
- **Automatic CNF conversion** — transforms arbitrary BNF/EBNF grammars into Chomsky Normal Form internally, with transparent tree reconstruction afterward
- **Ambiguity detection** — detects ambiguous parses and reports all derivations
- **SPPF-based representation** — uses a Shared Packed Parse Forest to compactly represent all parse results without redundancy
- **BSR set tracking** — records Binary Subtree Representations for full derivation traceability
- **Multiple grammar notations** — accepts BNF, EBNF, WSN, and `.gen` format grammars through the `Grammar` package
- **Tree visualization** — renders syntax trees as colored terminal output or Graphviz DOT diagrams
- **SPPF visualization** — exports the SPPF graph in Graphviz DOT format for inspection
- **`gtool` CLI** — a command-line tool for grammar-based parsing experiments

---

## Quick Start

### Basic Parsing

```swift
import Grammar
import CYK_Parser

// 1. Define a grammar in BNF
let grammarString = """
<E> ::= <T> | <E> "+" <T>
<T> ::= "id"
"""

// 2. Build the grammar and parser
let grammar = try Grammar(bnf: grammarString, start: "E")
let parser = CYKParser(grammar: grammar)

// 3. Parse an input string
let tree = try parser.syntaxTree(for: "id + id")
print(tree)
```

### Membership Recognition

```swift
let isValid = parser.recognizes("id + id")   // true
let isInvalid = parser.recognizes("id id")   // false
```

### Handling Ambiguous Grammars

```swift
let ambiguousGrammar = """
<E> ::= <E> "+" <E> | <E> "*" <E> | "id"
"""

let grammar = try Grammar(bnf: ambiguousGrammar, start: "E")
let parser = CYKParser(grammar: grammar)

// Retrieve all possible parse trees
let trees = try parser.allSyntaxTrees(for: "id + id * id")
print("Number of parse trees: \(trees.count)") // 2 — different operator groupings
```

### Inspecting the SPPF and BSR Set

```swift
let result = try parser.parse("id + id * id")

switch result {
case .success(let bsr, let sppf):
    print("Ambiguous: \(result.hasAmbiguity)")
    print("BSR entries: \(bsr.count)")
    print(sppf.graphviz) // DOT output for Graphviz
case .failure(let position, let message):
    print("Parse failed at \(position): \(message)")
}
```

---

## Command-Line Tool (`gtool`)

The package includes `gtool`, a CLI for quickly experimenting with grammars.

```
USAGE: gtool parse --grammar <grammar> [--start <start>] [--input <input>] [--analysis <analysis>]

OPTIONS:
  -g, --grammar <file>    Grammar file (.bnf, .ebnf, .wsn, .gen)
  -s, --start <rule>      Start rule (required for BNF/EBNF/WSN)
  -i, --input <string>    Input string to parse (or path to a file)
  -a, --analysis <mode>   Output mode: tree | graph | sppf  (default: tree)
```

**Examples:**

```bash
# Print the parse tree to the terminal
gtool parse -g expr.bnf -s E -i "id + id"

# Open a PDF of the parse tree (requires Graphviz)
gtool parse -g expr.bnf -s E -i "id + id" -a graph

# Open a PDF of the SPPF graph
gtool parse -g expr.bnf -s E -i "id + id * id" -a sppf
```

---

## Package Structure

```
CYK-Parser/
├── Sources/
│   ├── CYK-Parser/
│   │   ├── CYK.swift                    # Core CYKParser class
│   │   ├── ChomskyNormalForm.swift       # CNF conversion pipeline
│   │   ├── TreeTransformer.swift         # Post-parse CNF artifact removal
│   │   ├── Parser/
│   │   │   ├── BSR.swift                # Binary Subtree Representation
│   │   │   ├── SPPF.swift               # Shared Packed Parse Forest
│   │   │   ├── DeterministicParser.swift # Parser protocol
│   │   │   ├── GenerlizedParser.swift    # GeneralizedParser protocol + ParseResult
│   │   │   └── ParseError.swift         # Error types
│   │   └── Syntax-Tree/
│   │       ├── SyntaxTree.swift         # Generic SyntaxTree<Node, Leaf>
│   │       ├── SyntaxTreePrinter.swift  # Colored terminal rendering
│   │       └── SyntaxTreeGraphviz.swift # Graphviz DOT export
│   └── gtool/                           # CLI executable
│       ├── GrammarTool.swift
│       ├── Parse.swift
│       └── Definitions.swift
└── Tests/
    └── CYK-ParserTests/
        └── CYK_ParserTests.swift
```

---

## Dependencies

| Package | Role |  
|---------|------|  
| [hakkabon/Grammar](https://github.com/hakkabon/Grammar) | Grammar types, BNF/EBNF/WSN parsing |  
| [hakkabon/GrammarTokenizer](https://github.com/hakkabon/GrammarTokenizer) | Input tokenization |  
| [hakkabon/GrammarDiagram](https://github.com/hakkabon/GrammarDiagram) | Railroad diagram generation |  
| [hakkabon/TerminalColors](https://github.com/hakkabon/TerminalColors) | Colored terminal output |  
| [apple/swift-argument-parser](https://github.com/apple/swift-argument-parser) | CLI argument parsing (gtool) |  
| [JohnSundell/ShellOut](https://github.com/JohnSundell/ShellOut) | Shell command execution (gtool) |  

---

## Installation

### Swift Package Manager

Add the dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/hakkabon/CYK-Parser.git", branch: "main"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "CYK-Parser", package: "CYK-Parser"),
        ]
    ),
]
```

---

## License

MIT License — see [LICENSE](LICENSE) for details.  

