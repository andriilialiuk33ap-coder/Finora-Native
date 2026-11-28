import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct DataFile: FileDocument {
  static var readableContentTypes: [UTType] { [.json, .commaSeparatedText, .pdf, UTType(filenameExtension: "xlsx") ?? .data, UTType(filenameExtension: "ics") ?? .data] }
  var data: Data
  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}
