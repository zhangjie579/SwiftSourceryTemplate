// The Swift Programming Language
// https://docs.swift.org/swift-book

// generate.swift
import Foundation
import PathKit
import SourceryFramework
import SourceryRuntime
import SourcerySwift
import SourceryUtils

class KCParser {
    var serialParse: Bool = false

    var cacheDisabled: Bool = false

    var cacheBasePath: Path?

    typealias ParserWrapper = (path: Path, parse: () throws -> FileParserResult?)

    typealias ParsingResult = (
        parserResult: FileParserResult?,
        types: Types,
        functions: [SourceryMethod],
        inlineRanges: [(file: String, ranges: [String: NSRange], indentations: [String: String])])

    func parse(from: [Path], exclude: [Path] = [], forceParse: [String] = [], parseDocumentation: Bool, modules: [String]?, requiresFileParserCopy: Bool) throws -> ParsingResult {
        if let modules = modules {
            precondition(from.count == modules.count, "There should be module for each file to parse")
        }

        let startScan = currentTimestamp()
        Log.info("Scanning sources...")

        var inlineRanges = [(file: String, ranges: [String: NSRange], indentations: [String: String])]()
        var allResults = [(changed: Bool, result: FileParserResult)]()

        let excludeSet = Set(exclude
            .map { $0.isDirectory ? try? $0.recursiveChildren() : [$0] }
            .compactMap { $0 }.flatMap { $0 })

        try from.enumerated().forEach { index, from in
            let fileList = from.isDirectory ? try from.recursiveChildren() : [from]
            let parserGenerator: [ParserWrapper] = fileList
                .filter { $0.isSwiftSourceFile }
                .filter {
                    !excludeSet.contains($0)
                }
                .map { path in
                    (path: path, parse: {
                        let module = modules?[index]

                        if path.exists {
                            let content = try path.read(.utf8)
                            let status = Verifier.canParse(content: content, path: path, generationMarker: "// Generated using Sourcery", forceParse: forceParse)
                            switch status {
                            case .containsConflictMarkers:
                                throw NSError()
                            case .isCodeGenerated:
                                return nil
                            case .approved:
                                return try makeParser(for: content, forceParse: forceParse, parseDocumentation: parseDocumentation, path: path, module: module).parse()
                            }
                        } else {
                            return nil
                        }
                    })
                }

            var lastError: Swift.Error?

            let transform: (ParserWrapper) -> (changed: Bool, result: FileParserResult)? = { parser in
                do {
                    return try self.loadOrParse(parser: parser, cachesPath: self.cachesDir(sourcePath: from))
                } catch {
                    lastError = error
                    Log.error("Unable to parse \(parser.path), error \(error)")
                    return nil
                }
            }

            let results: [(changed: Bool, result: FileParserResult)]
            if serialParse {
                results = parserGenerator.compactMap(transform)
            } else {
                results = parserGenerator.parallelCompactMap(transform: transform)
            }

            if let error = lastError {
                throw error
            }

            if !results.isEmpty {
                allResults.append(contentsOf: results)
            }
        }

        Log.benchmark("\tloadOrParse: \(currentTimestamp() - startScan)")
        let reduceStart = currentTimestamp()

        var allTypealiases = [Typealias]()
        var allTypes = [Type]()
        var allFunctions = [SourceryMethod]()

        for pair in allResults {
            let next = pair.result
            allTypealiases += next.typealiases
            allTypes += next.types
            allFunctions += next.functions

            // swiftlint:disable:next force_unwrapping
            inlineRanges.append((next.path!, next.inlineRanges, next.inlineIndentations))
        }

        let parserResult = FileParserResult(path: nil, module: nil, types: allTypes, functions: allFunctions, typealiases: allTypealiases)

        var parserResultCopy: FileParserResult?
        if requiresFileParserCopy {
            let data = try NSKeyedArchiver.archivedData(withRootObject: parserResult, requiringSecureCoding: false)
            parserResultCopy = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? FileParserResult
        }

        let uniqueTypeStart = currentTimestamp()

        // ! All files have been scanned, time to join extensions with base class
        let (types, functions, typealiases) = Composer.uniqueTypesAndFunctions(parserResult, serial: serialParse)

        let filesThatHadToBeParsed = allResults
            .filter { $0.changed }
            .compactMap { $0.result.path }

        Log.benchmark("\treduce: \(uniqueTypeStart - reduceStart)\n\tcomposer: \(currentTimestamp() - uniqueTypeStart)\n\ttotal: \(currentTimestamp() - startScan)")
        Log.info("Found \(types.count) types in \(allResults.count) files, \(filesThatHadToBeParsed.count) changed from last run.")

        if !filesThatHadToBeParsed.isEmpty, filesThatHadToBeParsed.count < 50 || Log.level == .verbose {
            let files = filesThatHadToBeParsed
                .joined(separator: "\n")
            Log.info("Files changed:\n\(files)")
        }

        return (parserResultCopy, Types(types: types, typealiases: typealiases), functions, inlineRanges)
    }

    private func loadOrParse(parser: ParserWrapper, cachesPath: @autoclosure () -> Path?) throws -> (changed: Bool, result: FileParserResult)? {
        guard let cachesPath = cachesPath() else {
            return try parser.parse().map { (changed: true, result: $0) }
        }

        let path = parser.path
        let artifactsPath = cachesPath + "\(path.string.sha256()?.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "\(path.string.hash)").srf"

        guard
            artifactsPath.exists,
            let modifiedDate = path.modifiedDate,
            let unarchived = load(artifacts: artifactsPath.string, modifiedDate: modifiedDate, path: path)
        else {
            guard let result = try parser.parse() else {
                return nil
            }

            do {
                let data = try NSKeyedArchiver.archivedData(withRootObject: result, requiringSecureCoding: false)
                try artifactsPath.write(data)
            } catch {
                fatalError("Unable to save artifacts for \(path) under \(artifactsPath), error: \(error)")
            }

            return (changed: true, result: result)
        }

        return (changed: false, result: unarchived)
    }

    private func load(artifacts: String, modifiedDate: Date, path: Path) -> FileParserResult? {
        var unarchivedResult: FileParserResult?

        // this deprecation can't be removed atm, new API is 10x slower
        if let unarchived = NSKeyedUnarchiver.unarchiveObject(withFile: artifacts) as? FileParserResult {
            if unarchived.modifiedDate == modifiedDate {
                unarchivedResult = unarchived
            }
        }

        return unarchivedResult
    }

    fileprivate func cachesDir(sourcePath: Path, createIfMissing: Bool = true) -> Path? {
        return cacheDisabled
            ? nil
            : Path.cachesDir(sourcePath: sourcePath, basePath: cacheBasePath, createIfMissing: createIfMissing)
    }
}


let parser = KCParser()

let parserResult = try? parser.parse(from: [Path("~/Downloads/tmp/User1.swift")], parseDocumentation: true, modules: nil, requiresFileParserCopy: true)

if let types = parserResult?.types {
    let value = classAndStructTypes(types: types)
    
    for type in value {
        let ivars = typeVariables(type: type)
    }
}
