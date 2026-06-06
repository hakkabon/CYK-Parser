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
    #expect(tree == .empty)
    
    let trees = try parser.allSyntaxTrees(for: "")
    #expect(trees.count == 1)
    #expect(trees[0] == .empty)
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
