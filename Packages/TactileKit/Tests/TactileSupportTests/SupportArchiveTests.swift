import Foundation
import TactileDevices
import TactileSupport
import TactileUpdates
import XCTest

/// The report's zip: made with `ditto` in a temporary folder that is removed afterwards, within
/// tactilemac.com's limits (2 MiB zipped, 8 MiB unpacked, 32 entries, the files at its root and
/// nothing else), trimming the raw reports and then the log until it fits.
final class SupportArchiveTests: XCTestCase {

    /// A folder for one test, removed when it ends.
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("TactileSupportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    private func contents(_ folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path)
    }

    /// Writes a zip as large as the files it was given (no compression at all), and remembers what
    /// it was given.
    private final class FakeZipper: SupportZipping, @unchecked Sendable {
        var sizes: [Int] = []
        var names: [[String]] = []
        var fixedSize: Int?
        var fails = false

        func zip(folder: URL, to zip: URL) async -> Bool {
            if fails { return false }
            let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
            var total = 0
            var found: [String] = []
            while let url = walker?.nextObject() as? URL {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                total += values?.fileSize ?? 0
                found.append(String(url.resolvingSymlinksInPath().path.dropFirst(folder.resolvingSymlinksInPath().path.count + 1)))
            }
            sizes.append(total)
            names.append(found.sorted())
            return FileManager.default.createFile(atPath: zip.path, contents: Data(count: fixedSize ?? total))
        }
    }

    /// The ILITEK's input with raw reports of `bytes` bytes each, 200 in each step.
    private func bulky(_ bytes: Int) throws -> SupportReportInput {
        var input = try Fixture.ilitekInput(logLines: (0..<300).map { "line \($0) about device-3" })
        input.steps = input.steps.map { step in
            var step = step
            step.reports = (0..<200).map { n in
                SupportRawReport(interface: 4_294_970_001, role: .touch, bytes: [UInt8](repeating: UInt8(n % 256), count: bytes),
                                 time: step.startedAt + Double(n) * 0.01)
            }
            step.reportsSeen = 200
            return step
        }
        return input
    }

    // MARK: - The size limits

    func testAReportThatFitsIsZippedWhole() async throws {
        let folder = try makeFolder()
        let zipper = FakeZipper()
        let input = try Fixture.ilitekInput(logLines: ["one"])
        let archive = try await SupportArchiver.make(input, zipper: zipper, temporary: folder).get()
        XCTAssertEqual(archive.reportsPerStep, 200)
        XCTAssertNil(archive.logLines)
        XCTAssertEqual(archive.files, SupportReport.files(input))
        XCTAssertEqual(zipper.names.first, archive.files.map(\.name).sorted(), "every file, at the folder's root")
        XCTAssertEqual(archive.data.count, zipper.sizes.first)
        XCTAssertEqual(try contents(folder), [], "the temporary folder is removed")
    }

    func testRawReportsAreTrimmedUntilTheZipFits() async throws {
        let folder = try makeFolder()
        let zipper = FakeZipper()
        // 600 reports of 2,000 bytes are 2.4 MB of hex: over 2 MiB unzipped by this zipper, under it at 100 a step.
        let archive = try await SupportArchiver.make(try bulky(2000), zipper: zipper, temporary: folder).get()
        XCTAssertEqual(archive.reportsPerStep, 100)
        XCTAssertLessThanOrEqual(archive.data.count, SupportArchiver.maxZipBytes)
        XCTAssertEqual(zipper.sizes.count, 2, "tried whole, then trimmed once")
        XCTAssertGreaterThan(zipper.sizes[0], SupportArchiver.maxZipBytes)
        let steps = try XCTUnwrap(try Fixture.json(archive.files.first { $0.name == "touches.json" })["steps"] as? [[String: Any]])
        XCTAssertEqual(steps.map { $0["reports_kept"] as? Int }, [100, 100, 100], "the list shows what is sent")
        XCTAssertEqual(try contents(folder), [])
    }

    func testFilesThatWouldUnpackTooLargeAreTrimmedBeforeZipping() async throws {
        let folder = try makeFolder()
        let zipper = FakeZipper()
        zipper.fixedSize = 1000
        // 600 reports of 8,000 bytes are 9.6 MB of hex: over 8 MiB, so they are never zipped whole.
        let archive = try await SupportArchiver.make(try bulky(8000), zipper: zipper, temporary: folder).get()
        XCTAssertEqual(archive.reportsPerStep, 100)
        XCTAssertEqual(zipper.sizes.count, 1, "the first try was too large to zip at all")
        XCTAssertLessThanOrEqual(archive.files.reduce(0) { $0 + $1.size }, SupportArchiver.maxUnpackedBytes)
    }

    func testTheLogIsTrimmedLastAndThenItGivesUp() async throws {
        let folder = try makeFolder()
        let zipper = FakeZipper()
        zipper.fixedSize = SupportArchiver.maxZipBytes + 1
        let result = await SupportArchiver.make(try bulky(10), zipper: zipper, temporary: folder)
        XCTAssertEqual(result, .failure(.tooLarge))
        XCTAssertEqual(zipper.sizes.count, SupportArchiver.trims.count, "every trim was tried")
        XCTAssertEqual(SupportArchiver.trims.last?.reportsPerStep, 0)
        XCTAssertEqual(SupportArchiver.trims.last?.logLines, 0)
        XCTAssertEqual(try contents(folder), [])
    }

    func testAZipperThatFailsSaysSo() async throws {
        let folder = try makeFolder()
        let zipper = FakeZipper()
        zipper.fails = true
        let result = await SupportArchiver.make(try Fixture.ilitekInput(), zipper: zipper, temporary: folder)
        XCTAssertEqual(result, .failure(.couldNotZip))
        XCTAssertEqual(try contents(folder), [])
    }

    // MARK: - ditto, for real, in a temporary folder

    func testDittoPutsTheFilesAtTheZipsRootAndNothingElse() async throws {
        let folder = try makeFolder()
        let input = try Fixture.ilitekInput(logLines: ["one", "two"])
        let archive = try await SupportArchiver.make(input, zipper: DittoZipper(), temporary: folder).get()
        XCTAssertEqual(try contents(folder), [], "the temporary folder is removed")
        XCTAssertLessThanOrEqual(archive.data.count, SupportArchiver.maxZipBytes)

        let entries = try ZipDirectory.entries(archive.data)
        let names = entries.map(\.name).filter { $0 != "descriptors/" }
        XCTAssertEqual(Set(names), Set(archive.files.map(\.name)))
        XCTAssertEqual(names.count, archive.files.count, "each file once")
        XCTAssertLessThanOrEqual(entries.count, 32)
        XCTAssertTrue(entries.allSatisfy { [0, 8].contains($0.method) }, "stored or deflated only")
        XCTAssertTrue(entries.allSatisfy { $0.flags & 1 == 0 }, "nothing encrypted")
        XCTAssertFalse(entries.contains { $0.name.contains("._") || $0.name.hasPrefix("__MACOSX") || $0.name.hasSuffix(".DS_Store") })
        XCTAssertFalse(archive.data.range(of: Data([0x50, 0x4B, 0x06, 0x06])) != nil, "no ZIP64")

        // What ditto unpacks is byte for byte what the list showed.
        let unpacked = folder.appendingPathComponent("unpacked", isDirectory: true)
        let zip = folder.appendingPathComponent("report.zip")
        try archive.data.write(to: zip)
        let unpackedOK = await DittoUnpacker().unpack(zip, into: unpacked)
        XCTAssertTrue(unpackedOK)
        for file in archive.files {
            XCTAssertEqual(try Data(contentsOf: unpacked.appendingPathComponent(file.name)), file.data, file.name)
        }
    }
}

/// The names, compression methods and flags in a zip's central directory: enough to check a zip
/// against what tactilemac.com takes, without unpacking it.
enum ZipDirectory {
    struct Entry {
        var name: String
        var method: Int
        var flags: Int
    }

    struct Malformed: Error {}

    static func entries(_ data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        guard bytes.count >= 22,
              let end = stride(from: bytes.count - 22, through: 0, by: -1).first(where: {
                  bytes[$0] == 0x50 && bytes[$0 + 1] == 0x4B && bytes[$0 + 2] == 0x05 && bytes[$0 + 3] == 0x06
              })
        else { throw Malformed() }
        let count = u16(end + 10)
        var at = u32(end + 16)
        var entries: [Entry] = []
        for _ in 0..<count {
            guard at + 46 <= bytes.count, u32(at) == 0x0201_4B50 else { throw Malformed() }
            let nameLength = u16(at + 28), extra = u16(at + 30), comment = u16(at + 32)
            guard at + 46 + nameLength <= bytes.count else { throw Malformed() }
            let name = String(decoding: bytes[(at + 46)..<(at + 46 + nameLength)], as: UTF8.self)
            entries.append(Entry(name: name, method: u16(at + 10), flags: u16(at + 8)))
            at += 46 + nameLength + extra + comment
        }
        return entries
    }
}
