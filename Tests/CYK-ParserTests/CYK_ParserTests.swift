import Testing
import Grammar
@testable import CYK_Parser

@Test func testUnambiguousExpression() async throws {
    let grammarString = """
    <E> ::= <T> | <E> "+" <T>
    <T> ::= "id"
    """
    let grammar = try Grammar(bnf: grammarString, start: "E")
    let parser = CYKParser(grammar: grammar)
    
    // Parse "id + id"
    let input = "id + id"
    let result = try parser.parse(input)
    
    // Check that it parsed successfully and is unambiguous
    switch result {
    case .success(let bsr, let sppf):
        #expect(!result.hasAmbiguity)
        #expect(bsr.count > 0)
        
        let trees = try parser.allSyntaxTrees(for: input)
        #expect(trees.count == 1)
        
        // Let's inspect the tree structure
        let tree = trees[0]
        #expect(tree.root?.name == "E")
    case .failure(_, let msg):
        Issue.record("Failed to parse unambiguous expression: \(msg)")
    }
}

@Test func testAmbiguousGrammarSS() async throws {
    let grammarString = """
    <S> ::= <S> <S> | "a"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)
    
    // Parse "a a a"
    let input = "a a a"
    let result = try parser.parse(input)
    
    switch result {
    case .success(let bsr, let sppf):
        #expect(result.hasAmbiguity)
        #expect(bsr.count > 0)
        
        let trees = try parser.allSyntaxTrees(for: input)
        // Highly ambiguous: S -> S S can group as (S S) S or S (S S).
        // For "a a a", there should be exactly 2 parse trees.
        #expect(trees.count == 2)
        
        // Print the trees for manual sanity check in logs
        for (i, tree) in trees.enumerated() {
            print("Tree \(i + 1):\n\(tree)")
        }
    case .failure(_, let msg):
        Issue.record("Failed to parse ambiguous S ::= S S: \(msg)")
    }
}

@Test func testAmbiguousPrecedence() async throws {
    let grammarString = """
    <E> ::= <E> "+" <E> | <E> "*" <E> | "id"
    """
    let grammar = try Grammar(bnf: grammarString, start: "E")
    let parser = CYKParser(grammar: grammar)
    
    // Parse "id + id * id"
    let input = "id + id * id"
    let result = try parser.parse(input)
    
    switch result {
    case .success(let bsr, let sppf):
        #expect(result.hasAmbiguity)
        
        let trees = try parser.allSyntaxTrees(for: input)
        #expect(trees.count == 2)
        
        // Verify both interpretations exist
        // 1: (id + id) * id
        // 2: id + (id * id)
        print("Trees for 'id + id * id':")
        for (idx, tree) in trees.enumerated() {
            print("Tree \(idx):\n\(tree)")
        }
    case .failure(_, let msg):
        Issue.record("Failed to parse precedence expression: \(msg)")
    }
}

@Test func testEmptyInput() async throws {
    let grammarString = """
    <S> ::= "a"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)
    
    // Empty string
    let tree = try parser.syntaxTree(for: "")
    #expect(tree.root == nil)
    
    let trees = try parser.allSyntaxTrees(for: "")
    #expect(trees.count == 1)
    #expect(trees[0].root == nil)
}

@Test func testSyntaxError() async throws {
    let grammarString = """
    <S> ::= "a"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)
    
    // Invalid input
    #expect(throws: Error.self) {
        try parser.syntaxTree(for: "b")
    }
}

// MARK: - 1. Membership Recognition

@Test("Parser recognizes valid inputs")
func testRecognizesValidInput() throws {
    let grammarString = """
    <S> ::= "a" | <S> "a"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    #expect(parser.recognizes("a"))
    #expect(parser.recognizes("a a"))
    #expect(parser.recognizes("a a a"))
}

@Test("Parser rejects inputs not in the language")
func testRecognizesRejectsInvalidInput() throws {
    let grammarString = """
    <S> ::= "a" | <S> "a"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    #expect(!parser.recognizes("b"))
    #expect(!parser.recognizes("a b"))
    #expect(!parser.recognizes("b a"))
}

// MARK: - 2. Empty Input

@Test("Empty input returns .empty syntax tree")
func testEmptyInputSyntaxTree() throws {
    let grammarString = """
    <S> ::= "a"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    let tree = try parser.syntaxTree(for: "")
    #expect(tree.root == nil)
}

@Test("Empty input allSyntaxTrees returns one .empty tree")
func testEmptyInputAllSyntaxTrees() throws {
    let grammarString = """
    <S> ::= "a"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    let trees = try parser.allSyntaxTrees(for: "")
    #expect(trees.count == 1)
    #expect(trees[0].root == nil)
}

@Test("Empty input parse() returns success with empty BSR set")
func testEmptyInputParseResult() throws {
    let grammarString = """
    <S> ::= "a"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    let result = try parser.parse("")
    switch result {
    case .success(let bsr, _):
        #expect(bsr.isEmpty)
    case .failure(_, let msg):
        Issue.record("Expected success for empty input, got: \(msg)")
    }
}

// MARK: - 3. Syntax Error Handling

@Test("Parsing an invalid token throws an error")
func testSyntaxErrorThrows() throws {
    let grammarString = """
    <S> ::= "a"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    #expect(throws: Error.self) {
        try parser.syntaxTree(for: "b")
    }
}

@Test("parse() returns .failure for invalid input")
func testParseReturnsFailure() throws {
    let grammarString = """
    <S> ::= "a" "b"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    let result = try parser.parse("a c")
    switch result {
    case .success:
        Issue.record("Expected failure but got success.")
    case .failure(let pos, let msg):
        #expect(pos == 0)
        #expect(!msg.isEmpty)
    }
}

// MARK: - 4. Unambiguous Grammar / Single Parse Tree

@Test("Unambiguous grammar produces exactly one parse tree")
func testUnambiguousExpressionSingleTree() throws {
    let grammarString = """
    <E> ::= <T> | <E> "+" <T>
    <T> ::= "id"
    """
    let grammar = try Grammar(bnf: grammarString, start: "E")
    let parser = CYKParser(grammar: grammar)

    let result = try parser.parse("id + id")
    switch result {
    case .success(let bsr, _):
        #expect(!result.hasAmbiguity)
        #expect(bsr.count > 0)
        let trees = try parser.allSyntaxTrees(for: "id + id")
        #expect(trees.count == 1)
        #expect(trees[0].root?.name == "E")
    case .failure(_, let msg):
        Issue.record("Unexpected failure: \(msg)")
    }
}

@Test("Parse tree root is the original start symbol")
func testRootSymbolIsOriginalStart() throws {
    let grammarString = """
    <S> ::= "x" | <S> "x"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    let tree = try parser.syntaxTree(for: "x x")
    #expect(tree.root?.name == "S")
}

// MARK: - 5. Ambiguous Grammars

@Test("Ambiguous S ::= S S | 'a' detects ambiguity flag")
func testAmbiguousSSAmbiguityFlag() throws {
    let grammarString = """
    <S> ::= <S> <S> | "a"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    let result = try parser.parse("a a a")
    #expect(result.hasAmbiguity)
}

@Test("Ambiguous S ::= S S | 'a' produces exactly 2 trees for 'a a a'")
func testAmbiguousSSTreeCount() throws {
    let grammarString = """
    <S> ::= <S> <S> | "a"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    let trees = try parser.allSyntaxTrees(for: "a a a")
    // (S S) S  or  S (S S)
    #expect(trees.count == 2)
}

@Test("Ambiguous operator grammar produces 2 trees for 'id + id * id'")
func testAmbiguousOperatorPrecedence() throws {
    let grammarString = """
    <E> ::= <E> "+" <E> | <E> "*" <E> | "id"
    """
    let grammar = try Grammar(bnf: grammarString, start: "E")
    let parser = CYKParser(grammar: grammar)

    let result = try parser.parse("id + id * id")
    #expect(result.hasAmbiguity)

    let trees = try parser.allSyntaxTrees(for: "id + id * id")
    // Two groupings: (id+id)*id  and  id+(id*id)
    #expect(trees.count == 2)
}

@Test("Unambiguous grammar does NOT report hasAmbiguity")
func testUnambiguousGrammarNoAmbiguityFlag() throws {
    let grammarString = """
    <E> ::= <T> | <E> "+" <T>
    <T> ::= "id"
    """
    let grammar = try Grammar(bnf: grammarString, start: "E")
    let parser = CYKParser(grammar: grammar)

    let result = try parser.parse("id + id + id")
    #expect(!result.hasAmbiguity)
}

// MARK: - 6. Parse Tree Structure

@Test("mapLeafs converts Range<String.Index> to token strings correctly")
func testMapLeafsStringConversion() throws {
    let grammarString = """
    <S> ::= "hello" "world"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    let input = "hello world"
    let tree = try parser.syntaxTree(for: input)
    let stringTree = tree.mapLeafs { String(input[$0]) }
    let leafs = stringTree.leafs
    #expect(leafs.contains("hello"))
    #expect(leafs.contains("world"))
}

@Test("children property returns non-empty list for compound expressions")
func testTreeChildrenProperty() throws {
    let grammarString = """
    <E> ::= <T> | <E> "+" <T>
    <T> ::= "id"
    """
    let grammar = try Grammar(bnf: grammarString, start: "E")
    let parser = CYKParser(grammar: grammar)

    let tree = try parser.syntaxTree(for: "id + id")
    #expect(tree.children != nil)
    #expect(tree.children?.isEmpty == false)
}

@Test("leafs property returns tokens in left-to-right order")
func testLeafsProperty() throws {
    let grammarString = """
    <S> ::= "a" "b" "c"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    let input = "a b c"
    let tree = try parser.syntaxTree(for: input)
    let leafStrings = tree.mapLeafs { String(input[$0]) }.leafs
    #expect(leafStrings == ["a", "b", "c"])
}

// MARK: - 7. BSR Set Contents

@Test("BSR set is non-empty for valid single-rule input")
func testBSRSetNonEmpty() throws {
    let grammarString = """
    <S> ::= "a" "b"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    let result = try parser.parse("a b")
    switch result {
    case .success(let bsr, _):
        #expect(bsr.count > 0)
    case .failure(_, let msg):
        Issue.record("Unexpected failure: \(msg)")
    }
}

@Test("BSR entry for terminal 'a' has start index 0")
func testBSRSpanIndices() throws {
    let grammarString = """
    <S> ::= "a" "b"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    let result = try parser.parse("a b")
    switch result {
    case .success(let bsr, _):
        // Find any terminal BSR entry whose span starts at position 0.
        // The CNF converter wraps each terminal t into a helper non-terminal
        // T_<description>, so we match by rule kind and start index rather
        // than by an internal name that depends on Terminal.description.
        let aEntry = bsr.first { entry in
            if case .terminal = entry.rule { return entry.i == 0 }
            return false
        }
        #expect(aEntry?.i == 0)
    case .failure(_, let msg):
        Issue.record("Unexpected failure: \(msg)")
    }
}

// MARK: - 8. SPPF Graph Structure

@Test("SPPF contains symbol nodes for valid parse")
func testSPPFContainsSymbolNodes() throws {
    let grammarString = """
    <S> ::= "a"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    let result = try parser.parse("a")
    switch result {
    case .success(_, let sppf):
        #expect(!sppf.getAllNodes().isEmpty)
        let hasSymbol = sppf.getAllNodes().contains { !$0.isPacked }
        #expect(hasSymbol)
    case .failure(_, let msg):
        Issue.record("Unexpected failure: \(msg)")
    }
}

@Test("SPPF has multiple packed nodes for ambiguous input")
func testSPPFPackedNodeCountForAmbiguity() throws {
    let grammarString = """
    <S> ::= <S> <S> | "a"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    let result = try parser.parse("a a a")
    switch result {
    case .success(_, let sppf):
        let packedCount = sppf.getAllNodes().filter { $0.isPacked }.count
        #expect(packedCount > 1)
    case .failure(_, let msg):
        Issue.record("Unexpected failure: \(msg)")
    }
}

@Test("SPPF graphviz output is valid DOT")
func testSPPFGraphvizOutput() throws {
    let grammarString = """
    <E> ::= <E> "+" <E> | "id"
    """
    let grammar = try Grammar(bnf: grammarString, start: "E")
    let parser = CYKParser(grammar: grammar)

    let result = try parser.parse("id + id")
    switch result {
    case .success(_, let sppf):
        let dot = sppf.graphviz
        #expect(dot.hasPrefix("digraph SPPF {"))
        #expect(dot.hasSuffix("}"))
        #expect(dot.contains("shape=box"))
        #expect(dot.contains("shape=ellipse"))
    case .failure(_, let msg):
        Issue.record("Unexpected failure: \(msg)")
    }
}

// MARK: - 9. CNF Artifact Removal (TreeTransformer)

@Test("Transformed tree root is original start symbol, not CNF_Start")
func testTransformedTreeHasOriginalStartSymbol() throws {
    let grammarString = """
    <Expr> ::= "num" | <Expr> "+" "num"
    """
    let grammar = try Grammar(bnf: grammarString, start: "Expr")
    let parser = CYKParser(grammar: grammar)

    let tree = try parser.syntaxTree(for: "num + num")
    #expect(tree.root?.name == "Expr")
    #expect(tree.root?.name != "CNF_Start")
}

@Test("Transformed tree contains no BIN_ internal nodes")
func testTransformedTreeHasNoBINNodes() throws {
    let grammarString = """
    <S> ::= "a" "b" "c" "d"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    let tree = try parser.syntaxTree(for: "a b c d")
    let binNodes = tree.allNodes(where: { $0.name.hasPrefix("BIN") })
    #expect(binNodes.isEmpty)
}

@Test("Transformed tree contains no T_ terminal wrapper nodes")
func testTransformedTreeHasNoTWrapperNodes() throws {
    let grammarString = """
    <E> ::= <E> "+" <E> | "id"
    """
    let grammar = try Grammar(bnf: grammarString, start: "E")
    let parser = CYKParser(grammar: grammar)

    let tree = try parser.syntaxTree(for: "id + id")
    let tNodes = tree.allNodes(where: { $0.name.hasPrefix("T_") })
    #expect(tNodes.isEmpty)
}

// MARK: - 10. Long-Rule Binarization and Flattening

@Test("4-symbol rule A->B C D E produces 4 flat children after transformation")
func testLongRuleFlattenedChildren() throws {
    let grammarString = """
    <S> ::= "a" "b" "c" "d"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    let tree = try parser.syntaxTree(for: "a b c d")
    let children = tree.children ?? []
    #expect(children.count == 4)
}

// MARK: - 11. Unit Rule Elimination

@Test("Unit rule chain S->A->B->'x' is correctly resolved")
func testUnitRuleElimination() throws {
    let grammarString = """
    <S> ::= <A>
    <A> ::= <B>
    <B> ::= "x"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    #expect(parser.recognizes("x"))
    #expect(!parser.recognizes("y"))

    let tree = try parser.syntaxTree(for: "x")
    #expect(tree.root?.name == "S")
}

// MARK: - 12. Multiple Alternative Rules

@Test("Grammar with multiple terminal alternatives parses all valid options")
func testMultipleAlternatives() throws {
    let grammarString = """
    <S> ::= "cat" | "dog" | "fish"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    #expect(parser.recognizes("cat"))
    #expect(parser.recognizes("dog"))
    #expect(parser.recognizes("fish"))
    #expect(!parser.recognizes("bird"))
}

// MARK: - 13. Recursive Grammars

@Test("Right-recursive grammar parses strings of length 1 to 6")
func testDeepRightRecursion() throws {
    let grammarString = """
    <S> ::= "a" | "a" <S>
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    for count in 1...6 {
        let input = Array(repeating: "a", count: count).joined(separator: " ")
        #expect(parser.recognizes(input), "Should recognize \(count) 'a' tokens")
    }
}

@Test("Left-recursive grammar parses id + id + id")
func testLeftRecursion() throws {
    let grammarString = """
    <E> ::= "id" | <E> "+" "id"
    """
    let grammar = try Grammar(bnf: grammarString, start: "E")
    let parser = CYKParser(grammar: grammar)

    #expect(parser.recognizes("id"))
    #expect(parser.recognizes("id + id"))
    #expect(parser.recognizes("id + id + id"))
    #expect(!parser.recognizes("id + id +"))
}

// MARK: - 14. GeneralizedParser Protocol Conformance

@Test("CYKParser conforms to GeneralizedParser and returns ParseResult")
func testGeneralizedParserConformance() throws {
    let grammarString = """
    <S> ::= "a"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let genParser: any GeneralizedParser = CYKParser(grammar: grammar)

    let result = try genParser.parse("a")
    switch result {
    case .success(let bsr, _):
        #expect(bsr.count > 0)
    case .failure(_, let msg):
        Issue.record("Unexpected failure: \(msg)")
    }
}

// MARK: - 15. hasAmbiguity Property

@Test("hasAmbiguity is false for simple unambiguous grammar")
func testHasAmbiguityFalseForUnambiguous() throws {
    let grammarString = """
    <S> ::= "a" "b"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    let result = try parser.parse("a b")
    #expect(!result.hasAmbiguity)
}

@Test("hasAmbiguity is true for classic ambiguous grammar on 4 tokens")
func testHasAmbiguityTrueForFourTokens() throws {
    let grammarString = """
    <S> ::= <S> <S> | "a"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    let result = try parser.parse("a a a a")
    #expect(result.hasAmbiguity)
}

// MARK: - 16. Catalan Number Tree Count

@Test("S::=SS grammar produces 5 trees for 4 tokens (Catalan number C(3)=5)")
func testCatalanTreeCountFourTokens() throws {
    let grammarString = """
    <S> ::= <S> <S> | "a"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    let trees = try parser.allSyntaxTrees(for: "a a a a")
    #expect(trees.count == 5)
}

// MARK: - 17. SyntaxTree Transformations

@Test("mapNodes transforms all inner node labels to lowercase")
func testMapNodesTransformsLabels() throws {
    let grammarString = """
    <E> ::= <T> | <E> "+" <T>
    <T> ::= "id"
    """
    let grammar = try Grammar(bnf: grammarString, start: "E")
    let parser = CYKParser(grammar: grammar)

    let input = "id + id"
    let tree = try parser.syntaxTree(for: input)
    let mappedTree = tree.mapNodes { nt in nt.name.lowercased() }
    #expect(mappedTree.root == "e")
}

@Test("allNodes(where:) returns all E-labeled subtrees")
func testAllNodesWhereReturnsMatches() throws {
    let grammarString = """
    <E> ::= <T> | <E> "+" <T>
    <T> ::= "id"
    """
    let grammar = try Grammar(bnf: grammarString, start: "E")
    let parser = CYKParser(grammar: grammar)

    let tree = try parser.syntaxTree(for: "id + id + id")
    let eNodes = tree.allNodes(where: { $0.name == "E" })
    #expect(eNodes.count >= 3)
}

@Test("filter() prunes subtrees whose root fails a predicate")
func testFilterRemovesSubtrees() throws {
    let grammarString = """
    <E> ::= <T> | <E> "+" <T>
    <T> ::= "id"
    """
    let grammar = try Grammar(bnf: grammarString, start: "E")
    let parser = CYKParser(grammar: grammar)

    let tree = try parser.syntaxTree(for: "id + id")
    let filtered = tree.filter { $0.name == "E" }
    #expect(filtered != nil)
}

@Test("flattened() hoists children of matching inner nodes")
func testFlattenHoistsChildren() throws {
    let grammarString = """
    <E> ::= <T> | <E> "+" <T>
    <T> ::= "id"
    """
    let grammar = try Grammar(bnf: grammarString, start: "E")
    let parser = CYKParser(grammar: grammar)
    
    let tree = try parser.syntaxTree(for: "id + id")
    let flattened = tree.flattened(where: { $0.name == "T" } )
    #expect(!flattened.isEmpty)
}

// MARK: - 18. Tree Equality

@Test("Two parses of identical inputs produce equal parse trees")
func testTreeEqualityForSameInput() throws {
    let grammarString = """
    <E> ::= <T> | <E> "+" <T>
    <T> ::= "id"
    """
    let grammar = try Grammar(bnf: grammarString, start: "E")
    let parser = CYKParser(grammar: grammar)

    let tree1 = try parser.syntaxTree(for: "id + id")
    let tree2 = try parser.syntaxTree(for: "id + id")
    #expect(tree1 == tree2)
}

@Test("Trees from structurally different inputs are not equal")
func testTreeInequalityForDifferentInputs() throws {
    let grammarString = """
    <E> ::= <T> | <E> "+" <T>
    <T> ::= "id"
    """
    let grammar = try Grammar(bnf: grammarString, start: "E")
    let parser = CYKParser(grammar: grammar)

    let tree1 = try parser.syntaxTree(for: "id")
    let tree2 = try parser.syntaxTree(for: "id + id")
    #expect(tree1 != tree2)
}

// MARK: - 19. Graphviz Export — Syntax Tree

@Test("Syntax tree graphviz output is a valid DOT digraph")
func testSyntaxTreeGraphvizFormat() throws {
    let grammarString = """
    <E> ::= <T> | <E> "+" <T>
    <T> ::= "id"
    """
    let grammar = try Grammar(bnf: grammarString, start: "E")
    let parser = CYKParser(grammar: grammar)

    let tree = try parser.syntaxTree(for: "id + id")
    let dot = tree.mapLeafs { _ in "leaf" }.graphviz
    #expect(dot.hasPrefix("digraph {"))
    #expect(dot.contains("->"))
}

// MARK: - 20. Edge Cases

@Test("Single token input produces a valid single-node parse tree")
func testSingleTokenInput() throws {
    let grammarString = """
    <S> ::= "hello"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    let tree = try parser.syntaxTree(for: "hello")
    #expect(tree.root?.name == "S")
    #expect(tree.children?.count ?? 0 >= 1)
}

@Test("Grammar with only one rule and two tokens")
func testTwoTokenMinimalGrammar() throws {
    let grammarString = """
    <S> ::= "a" "b"
    """
    let grammar = try Grammar(bnf: grammarString, start: "S")
    let parser = CYKParser(grammar: grammar)

    #expect(parser.recognizes("a b"))
    #expect(!parser.recognizes("b a"))
    #expect(!parser.recognizes("a"))
    #expect(!parser.recognizes("b"))
}
