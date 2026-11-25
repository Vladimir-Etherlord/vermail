import AirmailImport
import Foundation

@main
struct AirmailImportTool {
    static func main() async {
        let code = await AirmailImportCommand.run(CommandLine.arguments)
        guard code == 0 else {
            exit(code)
        }
    }
}
