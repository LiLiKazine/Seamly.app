import Darwin
import Foundation
import StitchHarness

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    let data = try await HarnessDispatcher().run(arguments)
    FileHandle.standardOutput.write(data)
} catch {
    FileHandle.standardError.write(HarnessDispatcher.errorData(for: error, arguments: arguments))
    exit(1)
}
