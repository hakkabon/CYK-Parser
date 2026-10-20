import Foundation
import Grammar
import Parser

/// Engine-owned executable microbenchmarks for the CYK implementation.
public enum CYKParserMicrobenchmarks {
    public static let ownerVersion = "0.2.1"
    public static let inputScale = 16

    private static let grammarSource = """
    <S> ::= 'id' <S> | 'end'
    """
    private static var input: String {
        (Array(repeating: "id", count: inputScale) + ["end"]).joined(separator: " ")
    }

    public static func suite(
        buildConfiguration: ParserEngineMicrobenchmarkSuite.BuildConfiguration,
        warmupIterations: Int = 2,
        measurementIterations: Int = 10
    ) -> ParserEngineMicrobenchmarkSuite {
        .init(
            owner: .init(repository: "CYK-Parser", version: ownerVersion),
            engineID: "cyk", id: "cyk-core-v1", title: "CYK core workloads",
            buildConfiguration: buildConfiguration,
            warmupIterations: warmupIterations,
            measurementIterations: measurementIterations,
            cases: [.init(
                id: "right-recursive-forest", title: "Build a normalized right-recursive forest",
                operation: .forestConstruction,
                boundary: "Tokenize and run CYK with a pre-built, Grammar-normalized CYKParser, including SPPF construction.",
                workloadFingerprint: ParserEngineMicrobenchmarkCodec.evidenceFingerprint([
                    grammarSource, input, "prebuilt-normalized-parser", "cyk-sppf"
                ]),
                scale: inputScale
            )]
        )
    }

    public static func run(
        buildConfiguration: ParserEngineMicrobenchmarkSuite.BuildConfiguration,
        warmupIterations: Int = 2,
        measurementIterations: Int = 10,
        environment: ParserEngineMicrobenchmarkEnvironment = .current
    ) throws -> ParserEngineMicrobenchmarkReport {
        let parser = CYKParser(grammar: try Grammar(bnf: grammarSource, start: "S"))
        return try ParserEngineMicrobenchmarkRunner.run(
            suite(
                buildConfiguration: buildConfiguration,
                warmupIterations: warmupIterations,
                measurementIterations: measurementIterations
            ),
            environment: environment
        ) { _ in
            let result = try parser.parse(input)
            let nodes = result.sppfGraph?.getAllNodes().count ?? 0
            return .init(
                evidenceFingerprint: ParserEngineMicrobenchmarkCodec.evidenceFingerprint([
                    String(result.isSuccessful), String(result.bsr.count), String(nodes)
                ]),
                counters: [
                    "accepted": result.isSuccessful ? 1 : 0,
                    "bsrCount": result.bsr.count, "forestNodeCount": nodes
                ]
            )
        }
    }
}
