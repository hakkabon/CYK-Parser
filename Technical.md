# Technical Reference — CYK-Parser

## Table of Contents

1. [Algorithm Overview](#1-algorithm-overview)
2. [Chomsky Normal Form Conversion](#2-chomsky-normal-form-conversion)
3. [The CYK Dynamic Programming Table](#3-the-cyk-dynamic-programming-table)
4. [Binary Subtree Representations (BSR)](#4-binary-subtree-representations-bsr)
5. [Shared Packed Parse Forest (SPPF)](#5-shared-packed-parse-forest-sppf)
6. [Tree Reconstruction and Transformation](#6-tree-reconstruction-and-transformation)
7. [Syntax Tree Data Structure](#7-syntax-tree-data-structure)
8. [Tokenization](#8-tokenization)
9. [Parser Protocols](#9-parser-protocols)
10. [Error Model](#10-error-model)
11. [Visualization](#11-visualization)
12. [CLI Tool — gtool](#12-cli-tool--gtool)
13. [Complexity Analysis](#13-complexity-analysis)
14. [Known Limitations and Suggested Improvements](#14-known-limitations-and-suggested-improvements)

---

## 1. Algorithm Overview

The **Cocke–Younger–Kasami (CYK)** algorithm is a bottom-up, chart-based parsing algorithm for context-free grammars in Chomsky Normal Form. It was independently discovered by Cocke, Younger (1967), and Kasami (1965).

The algorithm's central idea is dynamic programming over all substrings of the input: for every possible contiguous substring, it computes the set of non-terminals that can derive that substring. The result is a two-dimensional table indexed by `(start position, length)` where each cell holds the set of non-terminals derivable for that span.

### High-Level Pipeline

```
Input String                          any TokenStream
     │                                       │
     ▼                                       │
TokenizerStream  ──► [Terminal]  ◀───────────┘
     │
     ▼
CYKParser.parse() / parse(stream:)
     │
     ├─► CNF DP Table  ──► BSR Set  ──► SPPF Graph
     │
     ▼
ParseResult (.success | .failure)
     │
     ▼
allSyntaxTrees()
     │
     ▼
TreeTransformer (remove CNF artifacts)
     │
     ▼
[ParseTree]  (one per distinct derivation)
```

See [§8](#8-tokenization) for the two `TokenStream` front ends.

---

## 2. Chomsky Normal Form Conversion

Before running CYK, every grammar must be converted to **Chomsky Normal Form (CNF)**, where every production is either:

- **A → B C** (binary rule: right-hand side has exactly two non-terminals), or  
- **A → a** (terminal rule: right-hand side is a single terminal).

The `CNFConverter` class in `ChomskyNormalForm.swift` implements a four-step normalization pipeline.

### Step 0 — New Start Symbol

A fresh non-terminal `CNF_Start` is introduced with the single production:

```
CNF_Start → <original start symbol>
```

This ensures the start symbol never appears on the right-hand side of any rule, which is required for CYK correctness.

### Step 1 — TERM: Terminal Isolation

Any terminal appearing inside a rule with two or more symbols on the right-hand side is replaced by a fresh non-terminal `T_<terminal>`, with a new unit rule added:

```
Before:  A → B "+" C
After:   A → B T_+ C
         T_+ → "+"
```

Terminals appearing alone (unit rules `A → a`) are left unchanged at this step. A `termMap` dictionary caches previously seen terminals to avoid duplicate wrapper non-terminals.

### Step 2 — BIN: Binarization

Rules with three or more symbols on the right-hand side are broken into a right-leaning chain of binary rules using fresh `BIN_n` non-terminals:

```
Before:  A → B C D E
After:   A    → B BIN_1
         BIN_1 → C BIN_2
         BIN_2 → D E
```

The `IDGenerator` class provides monotonically increasing unique suffixes for `BIN_n` names.

### Step 3 — UNIT: Unit Rule Elimination

Unit rules (`A → B` where `B` is a non-terminal) are eliminated by computing the reflexive-transitive closure of the unit-derivation relation and copying the non-unit rules of targets directly to the source:

```
A →* B  and  B → α  ⟹  add A → α
```

A fixed-point loop over the `unitPairs` dictionary propagates transitive chains (e.g., `A → B`, `B → C`, `C → α` produces `A → α` and `B → α`).

### CNFRule Enum

```swift
public enum CNFRule: Hashable {
    case binary(NonTerminal, NonTerminal, NonTerminal) // A → B C
    case terminal(NonTerminal, Terminal)               // A → a
}
```

`CNFRule` is `Hashable` so that rules can be stored in `Set<CNFRule>`, enabling O(1) membership testing used in the main CYK table fill.

---

## 3. The CYK Dynamic Programming Table

### Table Layout

The DP table is a two-dimensional array:

```swift
var table = Array(repeating: Array(repeating: Set<NonTerminal>(), count: n + 1), count: n)
```

`table[s][len]` holds the set of non-terminals that derive the substring from position `s` with length `len`. The outer dimension is indexed by starting token position (0 to n−1); the inner dimension by substring length (1 to n).

### Base Case (Length 1)

For every token at position `i`, all terminal CNF rules `A → token` are matched. Each matching non-terminal is inserted into `table[i][1]`, and a corresponding BSR entry is recorded:

```swift
for i in 0..<n {
    let terminal = extractTerminal(tokens[i])
    for rule in rules {
        if case .terminal(let lhs, let rhs) = rule, rhs == terminal {
            table[i][1].insert(lhs)
            bsrSet.insert(BSR(rule: rule, i: i, k: i + 1, j: i + 1))
        }
    }
}
```

### Inductive Step (Length 2 to n)

For each substring length `length` from 2 to `n`, and for each start position `s`, the algorithm tries every split point `p` (1 to length−1). If non-terminal `B ∈ table[s][p]` and `C ∈ table[s+p][length−p]`, then any rule `A → B C` fires and `A` is added to `table[s][length]`:

```swift
for length in 2...n {
    for s in 0...(n - length) {
        for p in 1..<length {
            for B in table[s][p] {
                for C in table[s + p][length - p] {
                    for rule in rules {
                        if case .binary(let A, let rB, let rC) = rule, rB == B, rC == C {
                            table[s][length].insert(A)
                            bsrSet.insert(BSR(rule: rule, i: s, k: s + p, j: s + length))
                        }
                    }
                }
            }
        }
    }
}
```

### Acceptance

The input is accepted if and only if `table[0][n]` contains the start symbol (the CNF-converted start, `CNF_Start`).

---

## 4. Binary Subtree Representations (BSR)

A `BSR` (Binary Subtree Representation) is a four-tuple recording how a particular CNF rule was used to derive a specific span:

```swift
public struct BSR: Hashable {
    public let rule: CNFRule  // The CNF rule applied
    public let i: Int         // Span start (inclusive token index)
    public let k: Int         // Split point (pivot)
    public let j: Int         // Span end (exclusive token index)
}
```

**Semantics:**

- For a terminal rule `A → a`: `i = k = j - 1` (a single token at position `i`).
- For a binary rule `A → B C`: `B` derives tokens `[i, k)` and `C` derives tokens `[k, j)`.

The complete `bsrSet: Set<BSR>` is the compact representation of all derivations found by the CYK algorithm. It is the bridge between the DP table and the SPPF.

`BSRSet` is a type alias `typealias BSRSet = Set<BSR>` provided for readability.

---

## 5. Shared Packed Parse Forest (SPPF)

The SPPF is a directed acyclic graph (DAG) that compactly represents all parse trees for an input. Rather than materializing each tree individually, shared subtrees are represented once and pointed to by multiple parents.

### Node Types

```swift
public enum SPPFNode: Hashable {
    /// Symbol node: a non-terminal or terminal spanning tokens [i, j)
    case symbol(symbol: Symbol, i: Int, j: Int)

    /// Packed node: one specific derivation (rule + pivot k) within a symbol node's span
    case packed(rule: CNFRule, k: Int, i: Int, j: Int)
}
```

- **Symbol nodes** correspond to a grammar symbol spanning a token range. They may have multiple packed-node children — one per distinct derivation (the source of ambiguity representation).
- **Packed nodes** represent one particular way to split a span using a specific rule. They have exactly one or two symbol-node children (one for terminal rules, two for binary rules).

### Graph Structure

```swift
public class SPPFGraph {
    public private(set) var nodes: Set<SPPFNode>
    public private(set) var edges: [SPPFNode: Set<SPPFNode>]
}
```

The SPPF is built lazily by `buildSPPF(symbolNode:bsrSet:tokens:sppf:visited:)` in `CYK.swift`, using a depth-first traversal from the root symbol node `(CNF_Start, 0, n)`. A `visited` set prevents cycles.

### Ambiguity Detection

A parse result is ambiguous if any symbol node has more than one packed-node child:

```swift
public var hasAmbiguity: Bool {
    graph.getAllNodes().contains { node in
        graph.getChildren(of: node).filter { $0.isPacked }.count > 1
    }
}
```

### Extracting All Parse Trees

`SPPFGraph.allParseTrees(for:tokens:)` performs a recursive descent through the SPPF, collecting all distinct `ParseTree` values by taking the Cartesian product of alternatives at each ambiguous symbol node:

```swift
for lTree in leftTrees {
    for rTree in rightTrees {
        results.append(.node(parentA, children: [lTree, rTree]))
    }
}
```

The leaf nodes carry `Range<String.Index>` values derived from the source token array, enabling callers to extract the original substrings.

---

## 6. Tree Reconstruction and Transformation

Because CYK operates on a CNF-transformed grammar, the raw parse trees contain CNF-specific artifacts:

| Artifact | Origin |
|----------|--------|
| `CNF_Start` root node | New start symbol from Step 0 |
| `T_<terminal>` nodes | Terminal wrapper non-terminals from Step 1 |
| `BIN_n` internal nodes | Binarization helpers from Step 2 |

`TreeTransformer` (in `TreeTransformer.swift`) performs a bottom-up post-processing pass to remove these artifacts and recover trees matching the original grammar structure.

### Transformation Rules

**1. BIN flattening** — When a child is a `BIN_n` node, its grandchildren are hoisted directly into the parent's children list, reversing binarization:

```
Node(A, [B, Node(BIN_1, [C, D])])  →  Node(A, [B, C, D])
```

**2. T_ unwrapping** — A `T_<terminal>` node with a single leaf child is replaced by the leaf directly, removing the terminal wrapper:

```
Node(T_+, [Leaf(range)])  →  Leaf(range)
```

**3. CNF_Start renaming** — The artificial `CNF_Start` root is renamed to the original grammar's start symbol (or replaced by its single child if no original start is provided).

**4. Recursive bottom-up traversal** — All transformations are applied depth-first so that inner BIN/T_ artifacts are cleaned before their parents are processed.

---

## 7. Syntax Tree Data Structure

The `SyntaxTree<Node, Leaf>` generic enum in `SyntaxTree.swift` is the central data structure for representing parse results.

```swift
public enum SyntaxTree<Node: Equatable, Leaf: Equatable> {
    case leaf(Leaf)
    indirect case node(Node, children: [SyntaxTree<Node, Leaf>])
    case empty
}
```

For the CYK parser specifically:

```swift
public typealias ParseTree = SyntaxTree<NonTerminal, Range<String.Index>>
```

Inner nodes carry `NonTerminal` labels; leaf nodes carry `Range<String.Index>` spans into the original input string.

### Key Operations

| Method | Description |
|--------|-------------|
| `mapNodes(_:)` | Transform every inner node's label |
| `mapLeafs(_:)` | Transform every leaf value (e.g., `Range<String.Index>` → `String`) |
| `leafs` | Collect all leaf values in left-to-right order |
| `filter(_:)` | Prune subtrees whose root fails a predicate |
| `explode(_:)` | Inline a node's children into its parent (flatten) |
| `compressed()` | Remove single-child nodes to compact the tree |
| `allNodes(where:)` | Collect all subtrees matching a predicate |

The `Equatable` conformance performs structural comparison: two trees are equal iff they have the same shape, the same node labels, and the same leaf values.

The `CustomStringConvertible` conformance delegates to `SyntaxTreePrinter` for colored, indented terminal output.

---

## 8. Tokenization

`CYKParser` has two front ends that both converge on the same private `runCYK(terminals: [Terminal])` algorithm core, mirroring the split already documented for §4–§7 (which operate purely on `[Terminal]`/BSR/SPPF and have no tokenizer dependency at all):

```
                         Source string
                              │
           ┌───────────────────┴───────────────────┐
           ▼                                        ▼
  parse(_ string:)                          parse(stream: S)
           │                                        │
  TokenizerStream(source:symbols:)            any TokenStream
  (this package's own `symbols` list)         (LexerTokenStream or
           │                                   TokenizerStream)
           └───────────────────┬───────────────────┘
                                ▼  stream.terminal(at:) for each position
                         [Terminal] + [Range<String.Index>]
                                │
                                ▼
                    runCYK(terminals:) — CYK table + BSR + SPPF
```

Both front ends are provided by the [Lexer](https://github.com/hakkabon/Lexer) package's `TokenStream` protocol:

- **`TokenizerStream`** wraps GrammarTokenizer's general-purpose `Tokenizer`, configured with this package's own fixed operator/punctuation `symbols` list (below) and no keywords, so identifier classification stays fully generic. This is what `parse(_ string:)`, `syntaxTree(for:)`, and `allSyntaxTrees(for:)` all use by default.
- **`LexerTokenStream`** wraps a DFA lexer built by `LexerBuilder.loadVocabulary(_:)` from a `GrammarVocabulary` — useful when a grammar's terminals need proper regex-pattern matching or keyword/identifier priority resolution that `TokenizerStream`'s fixed lexical categories can't express.

```swift
let symbols = ["|", "\\", "^", ":", ",", "$", ".", "\"", "¶", ">", "#",
               "+", "-", "{","[", "<", "(", "'", "}", "]", ":]", ")",
               ";", "/", "*", "?", "??", ":="]
```

`TokenStream.terminal(at:)` returns a `(Terminal, Range<String.Index>)` pair directly — there is no separate `extractTerminal(_:)` step here (unlike the token-type switch a hand-rolled tokenizer bridge would need): `Lexer`'s `TokenizerStream` already performs that mapping once, uniformly, for every parser in the toolkit.

`syntaxTree(for:)` and `allSyntaxTrees(for:)` collect both the `[Terminal]` array (fed to `runCYK`) and the parallel `[Range<String.Index>]` array (fed to `allSyntaxTrees(startSymbol:originalStart:ranges:)`, §7) from a single pass over the stream, rather than tokenizing twice as an implementation driven directly by `Tokenizer` would.

---

## 9. Parser Protocols

### `Parser`

```swift
public protocol Parser {
    func syntaxTree(for string: String) throws -> ParseTree
}
```

The base protocol for all parsers. A default extension provides:

```swift
func recognizes(_ string: String) -> Bool
```

### `GeneralizedParser`

```swift
public protocol GeneralizedParser {
    func parse(_ string: String) throws -> ParseResult
}
```

Implemented by `CYKParser`. Returns a `ParseResult` that exposes the raw `BSRSet` and `SPPFGraph` in addition to the high-level syntax trees.

`CYKParser` conforms to both protocols and also provides `allSyntaxTrees(for:)` and `parse<S: TokenStream>(stream:)` — neither is part of either protocol, but both are available directly on the class. `parse(stream:)` is the entry point for driving the parser from a `TokenStream` other than the default `TokenizerStream` (§8).

---

## 10. Error Model

Errors are represented by the `ParseError` enum:

```swift
enum ParseError: Error {
    case generationFailed(String)
    case unexpectedToken(token: String, state: Int)
    case unexpectedEOF(state: Int)
    case internalError(String)
}
```

`ParseError` is currently `internal` (not `public`), which means callers outside the module must catch it as `Error`. The `state` parameter in `unexpectedToken` and `unexpectedEOF` is set to `-1` in the CYK implementation because CYK is not state-machine based — the field is present for protocol compatibility with other parser back-ends in the broader toolchain.

---

## 11. Visualization

### Terminal Tree Rendering

`SyntaxTreePrinter` renders a `SyntaxTree` as a colored box-drawing tree using ANSI escape codes from the `TerminalColors` package:

```
E
├── E
│   └── T
│       └── id
└── T
    └── id
```

Colors used:
- **Bold** — inner nodes
- **Green** — leaf nodes
- **Blue** — branch lines (`├──`, `└──`, `│`)
- **Gray/Dim** — empty nodes

### Graphviz DOT Export — Syntax Tree

`SyntaxTreeGraphviz` (`SyntaxTree+graphviz`) exports the tree as a `digraph` in Graphviz DOT format. Each node is assigned a unique integer ID (wrapping it in the `Unique<T>` struct) to prevent label collisions when the same non-terminal appears multiple times:

```dot
digraph {
    node0 [label="E"]
    node0 -> node1
    node1 [label="T"]
    ...
}
```

### Graphviz DOT Export — SPPF

`SPPFGraph.graphviz` exports the full SPPF as a `digraph` where:
- Symbol nodes are rendered as blue rectangles (`shape=box, fillcolor=lightblue`)
- Packed nodes are rendered as gray ellipses (`shape=ellipse, fillcolor=lightgray`)

This allows visualization of the complete parse forest, including all alternative derivations for ambiguous inputs.

---

## 12. CLI Tool — gtool

The `gtool` executable target provides a command-line interface built with `swift-argument-parser`.

### Command: `parse`

```
gtool parse --grammar <file> [--start <rule>] [--input <input>] [--analysis <mode>]
```

**Options:**

| Flag | Description |
|------|-------------|
| `-g, --grammar` | Grammar file path (`.bnf`, `.ebnf`, `.wsn`, `.gen`) |
| `-s, --start` | Start rule name (required for BNF/EBNF/WSN, embedded in `.gen`) |
| `-i, --input` | Input string or path to a file containing input |
| `-a, --analysis` | Output mode: `tree` (default), `graph`, or `sppf` |

**Analysis modes:**

- `tree` — prints the colored syntax tree to stdout
- `graph` — generates a PDF of the parse tree via Graphviz and opens it (requires `dot` on `PATH`)
- `sppf` — prints the BSR set, detects ambiguity, generates an SPPF PDF, and opens it

### Grammar File Formats

| Extension | Format |
|-----------|--------|
| `.bnf` | Backus–Naur Form |
| `.ebnf` | Extended BNF |
| `.wsn` | Wirth Syntax Notation |
| `.gen` | Internal `.gen` format (includes start declaration) |

---

## 13. Complexity Analysis

| Phase | Time Complexity | Space Complexity |
|-------|-----------------|------------------|
| CNF conversion | O(|G|²) | O(|G|²) |
| CYK table fill | O(n³ · |R|) | O(n² · |N|) |
| SPPF construction | O(n³ · |R|) | O(n³ · |R|) |
| Tree extraction | O(T · n) per tree | O(depth · n) per tree |

Where:
- `n` = number of input tokens
- `|R|` = number of CNF rules
- `|N|` = number of non-terminals
- `|G|` = size of the original grammar
- `T` = number of distinct parse trees (can be exponential for highly ambiguous grammars)

**Note on the inner rule loop:** The current implementation iterates over the full `rules: Set<CNFRule>` set inside the innermost CYK loop, giving an effective O(n³ · |R|) fill cost. An indexed lookup (e.g., a dictionary keyed by `(B, C)`) would reduce this to O(n³) amortized.

---

## 14. Known Limitations and Suggested Improvements

### Issue 1 — O(n³ · |R|) Inner Loop

**Location:** `CYK.swift`, main DP loop (lines 96–107)

**Problem:** The innermost loop iterates over the entire rule set for every `(s, p, B, C)` combination. For grammars with many rules and longer inputs, this is the primary performance bottleneck.

**Suggested fix:** Pre-index binary rules by their RHS pair `(B, C)`:

```swift
var binaryIndex: [NonTerminal: [NonTerminal: [CNFRule]]] = [:]
for rule in rules {
    if case .binary(_, let B, let C) = rule {
        binaryIndex[B, default: [:]][C, default: []].append(rule)
    }
}
```

Then replace the rule-scan loop with a dictionary lookup, reducing the inner loop from O(|R|) to O(matches).

### Issue 2 — Redundant Tokenization

**Location:** `CYK.swift` — `syntaxTree(for:)`, `allSyntaxTrees(for:)`, and `parse(_:)` each call the tokenizer independently on the same input string.

**Suggested fix:** Tokenize once in `parse(_:)` and thread the token array through the call chain, or make `parse(_:)` the single entry point and have the others delegate to it.

### Issue 3 — `ParseError` Accessibility

**Location:** `Parser/ParseError.swift`

**Problem:** `ParseError` is declared `internal`, so callers outside the module cannot catch or match on specific error cases — they must treat all errors opaquely as `Error`.

**Suggested fix:** Declare `public enum ParseError: Error` and add `LocalizedError` conformance for user-facing messages.

### Issue 4 — Typo in Protocol Name

**Location:** `GenerlizedParser.swift`

**Problem:** The file name and legacy alias contain a typo: `GenerlizedParser` (missing 'a'). While a corrected `GeneralizedParser` protocol exists and a `typealias` provides backward compatibility, the file name and the original spelling remain inconsistent.

**Suggested fix:** Rename the file to `GeneralizedParser.swift` and remove the legacy `GereralizedParser` typealias once all dependents are updated.

### Issue 5 — Epsilon (ε) Productions Not Supported

**Location:** `ChomskyNormalForm.swift`, `CYK.swift`

**Problem:** The CNF converter and DP table do not handle ε-productions (rules of the form `A → ε`). Grammars with nullable non-terminals will silently produce incorrect results or miss valid parses.

**Suggested fix:** Add an explicit NULLABLE step before TERM/BIN/UNIT that computes the set of nullable non-terminals and generates all ε-eliminated rule variants.

### Issue 6 — Hardcoded Symbol List

**Location:** `CYK.swift` lines 17–18

**Problem:** The list of recognized operator symbols passed to the `TokenizerStream` (§8) is a hardcoded array in the `CYKParser` initializer. Custom grammars that use symbols not in the list (e.g., `@`, `~`, `§`) will be tokenized incorrectly through the default `parse(_ string:)`/`syntaxTree(for:)`/`allSyntaxTrees(for:)` entry points.

**Suggested fix:** Extract the operator symbol set from the grammar's terminal alphabet at `init` time, so the tokenizer is always aligned with the grammar being parsed.

**Workaround available today:** `parse(stream:)` (§8, §9) bypasses this hardcoded list entirely — build a `GrammarVocabulary` for the target grammar and drive the parser with a `LexerBuilder`-built `LexerTokenStream` instead of relying on the default `TokenizerStream`. The suggested fix above would still be worth doing, since it would make the *default* `parse(_ string:)` path correct without requiring a caller to hand-build a vocabulary.

### Issue 7 — `Unique.Comparable` Tautology

**Location:** `SyntaxTreeGraphviz.swift` lines 113–115

**Problem:** The `<` operator in `Unique<T>` compares `lhs.id < rhs.id` in both branches of a conditional that already handles `lhs.id != rhs.id`, making the `else` branch unreachable and the overall comparison always by `id` only.

```swift
// Current (buggy):
public static func < (lhs: Unique, rhs: Unique) -> Bool {
    return lhs.id != rhs.id ? lhs.id < rhs.id : lhs.id < rhs.id // ← both branches identical
}

// Fixed:
public static func < (lhs: Unique, rhs: Unique) -> Bool {
    return lhs.id < rhs.id
}
```

### Issue 8 — No Explicit `public` on `ParseError` Conformance

**Location:** `ParseError.swift`

`ParseError` conforms to `CustomStringConvertible` but does not expose `LocalizedError`. Adding it would enable integration with SwiftUI's alert system and other error-presenting APIs.

### Issue 9 — `fatalError` in CNF Converter

**Location:** `ChomskyNormalForm.swift` line 103

**Problem:** `fatalError("Bug in Step 2")` crashes the process if the grammar contains a non-terminal in an unexpected position. This is not recoverable and provides a poor developer experience.

**Suggested fix:** Replace with a thrown `ParseError.generationFailed(...)` to allow callers to handle conversion failures gracefully.

### Issue 10 — Missing `Sendable` Conformances

**Location:** `SPPFGraph`, `CYKParser`

**Problem:** `SPPFGraph` is a class with mutable state; `CYKParser` is also a class. Neither declares `Sendable` or `@unchecked Sendable`. In Swift 6 strict concurrency mode these will produce warnings or errors if used across actor boundaries.

**Suggested fix:** Make `SPPFGraph` a struct or add `@unchecked Sendable` with a documented threading policy, and audit `CYKParser` for actor isolation.
