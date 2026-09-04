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
}
