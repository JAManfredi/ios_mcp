//
//  XcodebuildPhaseParserTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Testing
@testable import Tools

@Suite("XcodebuildPhaseParser")
struct XcodebuildPhaseParserTests {

    @Test("Parses CompileSwift line")
    func parseCompileSwift() async {
        let parser = XcodebuildPhaseParser()
        let result = await parser.parse(line: "CompileSwift normal arm64 /path/to/File.swift")
        #expect(result == "Compiling")
    }

    @Test("Parses CompileC line")
    func parseCompileC() async {
        let parser = XcodebuildPhaseParser()
        let result = await parser.parse(line: "CompileC /path/to/File.m normal arm64")
        #expect(result == "Compiling")
    }

    @Test("Parses Ld line")
    func parseLd() async {
        let parser = XcodebuildPhaseParser()
        let result = await parser.parse(line: "Ld /path/to/output normal arm64")
        #expect(result == "Linking")
    }

    @Test("Parses CodeSign line")
    func parseCodeSign() async {
        let parser = XcodebuildPhaseParser()
        let result = await parser.parse(line: "CodeSign /path/to/App.app")
        #expect(result == "Code signing")
    }

    @Test("Parses CopySwiftLibs line")
    func parseCopySwiftLibs() async {
        let parser = XcodebuildPhaseParser()
        let result = await parser.parse(line: "CopySwiftLibs /path/to/App.app")
        #expect(result == "Copying Swift libraries")
    }

    @Test("Parses ProcessInfoPlistFile line")
    func parseProcessInfoPlist() async {
        let parser = XcodebuildPhaseParser()
        let result = await parser.parse(line: "ProcessInfoPlistFile /path/to/Info.plist")
        #expect(result == "Processing plists")
    }

    @Test("Parses CompileAssetCatalog line")
    func parseCompileAssetCatalog() async {
        let parser = XcodebuildPhaseParser()
        let result = await parser.parse(line: "CompileAssetCatalog /path/to/Assets.xcassets")
        #expect(result == "Compiling assets")
    }

    @Test("Parses CompileStoryboard line")
    func parseCompileStoryboard() async {
        let parser = XcodebuildPhaseParser()
        let result = await parser.parse(line: "CompileStoryboard /path/to/Main.storyboard")
        #expect(result == "Compiling storyboards")
    }

    @Test("Parses MergeSwiftModule line")
    func parseMergeSwiftModule() async {
        let parser = XcodebuildPhaseParser()
        let result = await parser.parse(line: "MergeSwiftModule normal arm64")
        #expect(result == "Merging Swift module")
    }

    @Test("Parses GenerateDSYMFile line")
    func parseGenerateDSYM() async {
        let parser = XcodebuildPhaseParser()
        let result = await parser.parse(line: "GenerateDSYMFile /path/to/App.dSYM")
        #expect(result == "Generating dSYM")
    }

    @Test("Parses PhaseScriptExecution line")
    func parsePhaseScriptExecution() async {
        let parser = XcodebuildPhaseParser()
        let result = await parser.parse(line: "PhaseScriptExecution Run\\ Script /path/to/script.sh")
        #expect(result == "Running build script")
    }

    @Test("Parses TEST_SUITE line")
    func parseTestSuite() async {
        let parser = XcodebuildPhaseParser()
        let result = await parser.parse(line: "Test Suite 'MyTests' started at 2025-01-01 00:00:00.000.")
        #expect(result == "Running tests")
    }

    @Test("Returns nil for non-phase lines")
    func nonPhaseLines() async {
        let parser = XcodebuildPhaseParser()
        #expect(await parser.parse(line: "Build settings from command line:") == nil)
        #expect(await parser.parse(line: "    PRODUCT_NAME = MyApp") == nil)
        #expect(await parser.parse(line: "") == nil)
        #expect(await parser.parse(line: "** BUILD SUCCEEDED **") == nil)
    }

    @Test("Deduplicates consecutive identical phases")
    func deduplicatesPhases() async {
        let parser = XcodebuildPhaseParser()
        let first = await parser.parse(line: "CompileSwift normal arm64 /path/File1.swift")
        let second = await parser.parse(line: "CompileSwift normal arm64 /path/File2.swift")
        let third = await parser.parse(line: "Ld /path/output normal arm64")

        #expect(first == "Compiling")
        #expect(second == nil)
        #expect(third == "Linking")
    }

    @Test("Reports same phase again after intervening different phase")
    func reportsPhaseAfterDifferent() async {
        let parser = XcodebuildPhaseParser()
        #expect(await parser.parse(line: "CompileSwift normal arm64 /a.swift") == "Compiling")
        #expect(await parser.parse(line: "Ld /output normal arm64") == "Linking")
        #expect(await parser.parse(line: "CompileSwift normal arm64 /b.swift") == "Compiling")
    }

    @Test("Handles leading whitespace in lines")
    func leadingWhitespace() async {
        let parser = XcodebuildPhaseParser()
        let result = await parser.parse(line: "    CompileSwift normal arm64 /path/to/File.swift")
        #expect(result == "Compiling")
    }

    @Test("Parses Linking line")
    func parseLinking() async {
        let parser = XcodebuildPhaseParser()
        let result = await parser.parse(line: "Linking MyApp (arm64)")
        #expect(result == "Linking")
    }

    @Test("Parses CompileSwiftSources line")
    func parseCompileSwiftSources() async {
        let parser = XcodebuildPhaseParser()
        let result = await parser.parse(line: "CompileSwiftSources normal arm64 com.apple.xcode.tools.swift.compiler")
        #expect(result == "Compiling")
    }
}
