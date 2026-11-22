import XCTest
@testable import YTMusicMac

/// Which version is newer (the update check).
final class VersionTests: XCTestCase {
    @MainActor
    func testNewerVersions() {
        XCTAssertTrue(Updater.isNewer("2.7.1", than: "2.7.0"))
        XCTAssertTrue(Updater.isNewer("2.10.0", than: "2.9.9"))
        XCTAssertTrue(Updater.isNewer("3.0", than: "2.99.99"))
    }

    @MainActor
    func testSameOrOlderVersions() {
        XCTAssertFalse(Updater.isNewer("2.7", than: "2.7.0"))
        XCTAssertFalse(Updater.isNewer("2.6.9", than: "2.7.0"))
        XCTAssertFalse(Updater.isNewer("2.7.0", than: "2.7.0"))
    }
}

/// Telling the same song apart from other versions (radio cleanup, playlist and liked
/// indicators).
final class SongMatchingTests: XCTestCase {
    func testDecorationsAreDropped() {
        XCTAssertEqual(QueueCurator.stripDecorations("Innerbloom (Official Video)"), "Innerbloom")
        XCTAssertEqual(QueueCurator.stripDecorations("Song [Lyric Video]"), "Song")
        XCTAssertEqual(QueueCurator.stripDecorations("Song feat. Someone"), "Song")
    }

    func testVersionsAreKept() {
        XCTAssertEqual(QueueCurator.stripDecorations("Song (Extended Mix)"), "Song (Extended Mix)")
        XCTAssertEqual(QueueCurator.stripDecorations("Song (Live)"), "Song (Live)")
    }

    func testNormalize() {
        XCTAssertEqual(QueueCurator.normalize("Charlotte de Witte"), "charlotte de witte")
        XCTAssertEqual(QueueCurator.normalize("RÜFÜS DU SOL"), "rufus du sol")
        XCTAssertEqual(QueueCurator.normalize("  A-ha!  "), "a ha")
    }

    func testSongAndVideoShareAKey() {
        let video = IndexedPlaylist.key(title: "Innerbloom (Official Video)", artist: "RÜFÜS DU SOL, Hans Zimmer")
        let song = IndexedPlaylist.key(title: "Innerbloom", artist: "RÜFÜS DU SOL")
        XCTAssertNotNil(video)
        XCTAssertEqual(video, song)
    }

    func testDifferentSongsDiffer() {
        XCTAssertNotEqual(IndexedPlaylist.key(title: "Innerbloom", artist: "RÜFÜS DU SOL"),
                          IndexedPlaylist.key(title: "Underwater", artist: "RÜFÜS DU SOL"))
        XCTAssertNil(IndexedPlaylist.key(title: "X", artist: "Someone"))
    }
}

/// Reading an audio file's index ("sidx" box) into the pieces the playlist lists.
final class AudioIndexTests: XCTestCase {
    /// A version-0 sidx box: timescale 1000, the given pieces of 10 s each.
    private func sidx(sizes: [Int], firstOffset: Int = 0) -> Data {
        func u32(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
        let boxSize = 32 + sizes.count * 12
        var b: [UInt8] = []
        b += u32(boxSize) + Array("sidx".utf8)
        b += [0, 0, 0, 0]                    // version 0, flags
        b += u32(1)                          // reference id
        b += u32(1000)                       // timescale
        b += u32(0)                          // earliest presentation time
        b += u32(firstOffset)
        b += [0, 0]                          // reserved
        b += [UInt8(sizes.count >> 8), UInt8(sizes.count & 0xFF)]
        for size in sizes {
            b += u32(size)                   // reference type 0 + size
            b += u32(10_000)                 // 10 s
            b += u32(0x9000_0000)            // starts with a SAP
        }
        return Data(b)
    }

    func testPiecesFollowTheIndex() throws {
        let pieces = try XCTUnwrap(DashToHLS.pieces(sidx: sidx(sizes: [100, 200, 300, 400]), at: 1000))
        XCTAssertEqual(pieces.map(\.offset), [1080, 1180, 1380, 1680])
        XCTAssertEqual(pieces.map(\.size), [100, 200, 300, 400])
        XCTAssertEqual(pieces.map(\.seconds), [10, 10, 10, 10])
    }

    func testFirstPieceAloneThenJoinedParts() throws {
        let pieces = try XCTUnwrap(DashToHLS.pieces(sidx: sidx(sizes: [100, 200, 300, 400]), at: 1000))
        let parts = DashToHLS.joined(pieces)
        XCTAssertEqual(parts.map(\.offset), [1080, 1180])
        XCTAssertEqual(parts.map(\.size), [100, 900])
        XCTAssertEqual(parts.map(\.seconds), [10, 30])
    }

    func testNotAnIndex() {
        var bad = sidx(sizes: [100])
        bad[4] = 0x6D   // "midx"
        XCTAssertNil(DashToHLS.pieces(sidx: bad, at: 0))
        XCTAssertNil(DashToHLS.pieces(sidx: Data([0, 1, 2]), at: 0))
    }
}
