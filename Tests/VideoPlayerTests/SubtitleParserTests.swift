import XCTest
@testable import VideoPlayer

final class SubtitleParserTests: XCTestCase {
    func testParsesSRTVTTAndASS() throws {
        let trackID = UUID()
        let srt = """
        1
        00:00:01,250 --> 00:00:03,500
        First line
        """
        let vtt = """
        WEBVTT

        cue-1
        00:00:04.000 --> 00:00:06.000 align:center
        Second line
        """
        let ass = """
        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:07.00,0:00:09.25,Default,,0,0,0,,Third\\Nline
        """

        let srtCue = try XCTUnwrap(SubtitleParser.parse(srt, fileExtension: "srt", trackID: trackID).first)
        let vttCue = try XCTUnwrap(SubtitleParser.parse(vtt, fileExtension: "vtt", trackID: trackID).first)
        let assCue = try XCTUnwrap(SubtitleParser.parse(ass, fileExtension: "ass", trackID: trackID).first)

        XCTAssertEqual(srtCue.startTime, 1.25)
        XCTAssertEqual(srtCue.text, "First line")
        XCTAssertEqual(vttCue.endTime, 6)
        XCTAssertEqual(vttCue.text, "Second line")
        XCTAssertEqual(assCue.endTime, 9.25)
        XCTAssertEqual(assCue.text, "Third\nline")
    }

    func testStripsHTMLTagsFromSRT() throws {
        let srt = """
        1
        00:00:01,000 --> 00:00:02,000
        <i>Hello</i>
        """
        let cue = try XCTUnwrap(SubtitleParser.parse(srt, fileExtension: "srt", trackID: UUID()).first)
        XCTAssertEqual(cue.text, "Hello")
    }

    func testParsesVTTShortTimestampsWithoutHours() throws {
        let vtt = """
        WEBVTT

        00:04.000 --> 00:06.500
        Short form
        """
        let cue = try XCTUnwrap(SubtitleParser.parse(vtt, fileExtension: "vtt", trackID: UUID()).first)
        XCTAssertEqual(cue.startTime, 4)
        XCTAssertEqual(cue.endTime, 6.5)
        XCTAssertEqual(cue.text, "Short form")
    }

    func testParsesWindows1251EncodedSRT() throws {
        let srt = "1\n00:00:01,000 --> 00:00:02,000\nПривет, мир\n"
        let data = try XCTUnwrap(srt.data(using: .windowsCP1251))
        let decoded = try XCTUnwrap(SubtitleTextDecoder.decode(data))
        let cue = try XCTUnwrap(SubtitleParser.parse(decoded, fileExtension: "srt", trackID: UUID()).first)
        XCTAssertEqual(cue.text, "Привет, мир")
    }

    func testSubtitleStyleNormalizationClampsValues() {
        let style = SubtitleStyle(
            fontSize: 500,
            textColor: .white,
            outlineWidth: 99,
            backgroundOpacity: 2,
            verticalOffset: -50
        )
        let normalized = style.normalized()
        XCTAssertEqual(normalized.fontSize, 52)
        XCTAssertEqual(normalized.outlineWidth, 4)
        XCTAssertEqual(normalized.backgroundOpacity, 0.9)
        XCTAssertEqual(normalized.verticalOffset, 20)
    }

    func testWritesSRTWithMillisecondTimestamps() {
        let trackID = UUID()
        let contents = SubtitleFileWriter.srtContents(for: [
            SubtitleCue(
                startTime: 1.25,
                endTime: 3.875,
                text: "Hello\nworld",
                trackID: trackID
            )
        ])

        XCTAssertEqual(
            contents,
            "1\n00:00:01,250 --> 00:00:03,875\nHello\nworld\n"
        )
    }

    func testFormatsHourLongTimecodesWithoutTruncation() {
        XCTAssertEqual(
            PlaybackTimeFormat.string(from: 3_619, includingHours: true),
            "1:00:19"
        )
    }

    func testFindsSidecarSubtitlesNextToTheVideo() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueSidecar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("Movie.mkv")
        try Data().write(to: video)
        let srt = folder.appendingPathComponent("Movie.en.srt")
        try Data().write(to: srt)
        try Data().write(to: folder.appendingPathComponent("Other.srt"))

        XCTAssertEqual(SidecarSubtitleLocator.urls(beside: video).map(\.lastPathComponent), ["Movie.en.srt"])
    }
}
