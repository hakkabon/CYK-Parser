import Parser
import Testing
@testable import CYK_Parser

@Test("CYK owns a reproducible executable microbenchmark")
func cykMicrobenchmark() throws {
    let report = try CYKParserMicrobenchmarks.run(
        buildConfiguration: .release, warmupIterations: 0, measurementIterations: 3,
        environment: .init(
            operatingSystem: "test", architecture: "test",
            processorCount: 1, physicalMemoryBytes: 1
        )
    )
    #expect(report.suite.owner.repository == "CYK-Parser")
    #expect(report.suite.engineID == "cyk")
    #expect(report.results.first?.counters["accepted"] == 1)
    #expect((report.results.first?.counters["forestNodeCount"] ?? 0) > 0)
}
