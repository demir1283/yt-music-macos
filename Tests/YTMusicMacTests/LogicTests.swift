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

/// Volume leveling: every song is brought to 6 dB below YouTube's reference; songs
/// already below it stay, and a song without a measurement counts as the reference.
final class LevelingTests: XCTestCase {
    @MainActor
    func testSongsAboveTheTargetAreTurnedDownToIt() {
        XCTAssertEqual(YTMusic.gain(for: 6), 0.251, accuracy: 0.001)    // −12 dB
        XCTAssertEqual(YTMusic.gain(for: 0), 0.501, accuracy: 0.001)    // −6 dB
        XCTAssertEqual(YTMusic.gain(for: -3), 0.708, accuracy: 0.001)   // −3 dB
    }

    @MainActor
    func testSongsAtOrBelowTheTargetStay() {
        XCTAssertEqual(YTMusic.gain(for: -6), 1)
        XCTAssertEqual(YTMusic.gain(for: -9), 1)
    }

    @MainActor
    func testUnmeasuredSongsCountAsTheReference() {
        XCTAssertEqual(YTMusic.gain(for: nil), 0.501, accuracy: 0.001)
    }
}

/// "Your listening": what counts, for which period, and who comes first.
final class ListeningSummaryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func play(_ v: String, _ title: String, _ artists: [(String, String)], heard: Int, daysAgo: Double) -> ListeningLog.Play {
        ListeningLog.Play(t: Int(now.timeIntervalSince1970 - daysAgo * 86_400), v: v, ti: title,
                          ar: artists.map(\.0), ai: artists.map(\.1), ty: "MUSIC_VIDEO_TYPE_ATV",
                          len: 200, heard: heard, at: heard, end: "done", src: "list")
    }

    private var plays: [ListeningLog.Play] {
        [
            play("a", "Song A", [("Artist 1", "UC1")], heard: 200, daysAgo: 1),
            play("a", "Song A", [("Artist 1", "UC1")], heard: 200, daysAgo: 2),
            play("b", "Song B", [("Artist 1", "UC1"), ("Artist 2", "UC2")], heard: 100, daysAgo: 3),
            play("c", "Skipped", [("Artist 3", "UC3")], heard: 10, daysAgo: 1),     // under 30 s
            play("d", "Old", [("Artist 4", "UC4")], heard: 150, daysAgo: 40),       // before the last 30 days
        ]
    }

    func testLastThirtyDays() {
        let s = ListeningSummary(plays: plays, period: .month, now: now, calendar: utc)
        XCTAssertEqual(s.plays, 3)
        XCTAssertEqual(s.seconds, 500)
        XCTAssertEqual(s.songCount, 2)
        XCTAssertEqual(s.artistCount, 2)
        XCTAssertEqual(s.topArtists.first?.name, "Artist 1")
        XCTAssertEqual(s.topArtists.first?.seconds, 500)
        XCTAssertEqual(s.topArtists.last?.name, "Artist 2")      // a joint song counts for both
        XCTAssertEqual(s.topSongs.first?.id, "a")
        XCTAssertEqual(s.topSongs.first?.plays, 2)
    }

    func testAllTimeKeepsOlderPlays() {
        let s = ListeningSummary(plays: plays, period: .all, now: now, calendar: utc)
        XCTAssertEqual(s.plays, 4)
        XCTAssertEqual(s.seconds, 650)
    }

    func testNothingHeard() {
        XCTAssertTrue(ListeningSummary(plays: [], period: .week, now: now, calendar: utc).isEmpty)
    }
}

/// Crossfade: where songs may overlap, and the curve they overlap with.
final class CrossfadeTests: XCTestCase {
    private func entry(_ id: String, _ duration: String, album: String? = nil) -> QueueEntry {
        QueueEntry(index: 0, title: id, subtitle: "", duration: duration, thumbnail: nil, selected: false,
                   videoId: id, album: album.map { AlbumRef(name: $0, id: $0) })
    }

    @MainActor
    func testOrdinarySongsMayOverlap() {
        XCTAssertTrue(YTMusic.mayCrossfade(from: entry("a", "3:45"), to: entry("b", "4:10"),
                                           repeatOne: false, sleepAtEnd: false))
        XCTAssertTrue(YTMusic.mayCrossfade(from: entry("a", "3:45", album: "X"), to: entry("b", "4:10", album: "Y"),
                                           repeatOne: false, sleepAtEnd: false))
    }

    @MainActor
    func testNoOverlapWhereTheSongsShouldStayApart() {
        let a = entry("a", "3:45"), b = entry("b", "4:10")
        XCTAssertFalse(YTMusic.mayCrossfade(from: a, to: b, repeatOne: true, sleepAtEnd: false))
        XCTAssertFalse(YTMusic.mayCrossfade(from: a, to: b, repeatOne: false, sleepAtEnd: true))
        // Into or out of a long set.
        XCTAssertFalse(YTMusic.mayCrossfade(from: entry("a", "1:02:00"), to: b, repeatOne: false, sleepAtEnd: false))
        XCTAssertFalse(YTMusic.mayCrossfade(from: a, to: entry("b", "45:00"), repeatOne: false, sleepAtEnd: false))
        // Very short songs.
        XCTAssertFalse(YTMusic.mayCrossfade(from: entry("a", "0:20"), to: b, repeatOne: false, sleepAtEnd: false))
        // Consecutive songs of one album.
        XCTAssertFalse(YTMusic.mayCrossfade(from: entry("a", "3:45", album: "X"), to: entry("b", "4:10", album: "X"),
                                            repeatOne: false, sleepAtEnd: false))
    }

    @MainActor
    func testTheButtonStepsThroughTheLengthsThenTurnsOff() {
        XCTAssertEqual(CrossfadeButton.step(after: 0), 3)
        XCTAssertEqual(CrossfadeButton.step(after: 3), 6)
        XCTAssertEqual(CrossfadeButton.step(after: 9), 12)
        XCTAssertEqual(CrossfadeButton.step(after: 12), 0)
        XCTAssertEqual(CrossfadeButton.step(after: 5), 3)   // an unknown value starts over
    }

    func testCurveKeepsThePowerEven() {
        for t in stride(from: Float(0), through: 1, by: 0.125) {
            let c = AudioPlayer.crossfadeCurve(t)
            XCTAssertEqual(c.incoming * c.incoming + c.outgoing * c.outgoing, 1, accuracy: 0.0001)
        }
        XCTAssertEqual(AudioPlayer.crossfadeCurve(0).incoming, 0, accuracy: 0.0001)
        XCTAssertEqual(AudioPlayer.crossfadeCurve(0).outgoing, 1, accuracy: 0.0001)
        XCTAssertEqual(AudioPlayer.crossfadeCurve(1).incoming, 1, accuracy: 0.0001)
        XCTAssertEqual(AudioPlayer.crossfadeCurve(1).outgoing, 0, accuracy: 0.0001)
    }
}

/// Which build of YouTube's player script the stream solver reads.
final class PlayerVariantTests: XCTestCase {
    func testTheTVBuildIsTriedFirst() {
        XCTAssertEqual(SigSolver.variants.first, "tv")
        XCTAssertEqual(SigSolver.variants, ["tv", "main"])
    }

    func testVariantAddresses() {
        XCTAssertEqual(SigSolver.variantURL(id: "b485e332", variant: "tv")?.absoluteString,
                       "https://www.youtube.com/s/player/b485e332/tv-player-ias.vflset/tv-player-ias.js")
        XCTAssertEqual(SigSolver.variantURL(id: "b485e332", variant: "main")?.absoluteString,
                       "https://www.youtube.com/s/player/b485e332/player_ias.vflset/en_US/base.js")
    }

    func testAnyPlayerAddressGivesItsVersion() {
        let url = SigSolver.canonicalPlayerURL("/s/player/b485e332/player_ias.vflset/tr_TR/base.js")
        XCTAssertEqual(url.map { SigSolver.playerID($0) }, "b485e332")
    }
}

/// The disk image of a release, for apps installed from it.
final class ReleaseAssetTests: XCTestCase {
    func testTheDiskImageIsFoundByItsName() {
        let release: [String: Any] = ["assets": [
            ["name": "notes.txt", "browser_download_url": "https://example.invalid/notes.txt"],
            ["name": "YT-Music.dmg", "browser_download_url": "https://github.com/o/r/releases/download/v3.2.0/YT-Music.dmg"],
        ]]
        XCTAssertEqual(Updater.dmgAsset(in: release)?.lastPathComponent, "YT-Music.dmg")
    }

    func testAReleaseWithoutOneHasNone() {
        XCTAssertNil(Updater.dmgAsset(in: ["assets": [] as [[String: Any]]]))
        XCTAssertNil(Updater.dmgAsset(in: [:]))
    }
}
