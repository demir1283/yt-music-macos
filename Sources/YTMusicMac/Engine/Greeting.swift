import SwiftUI
import Observation

/// The line over the home page's tiles. At launch it greets by the time of day ("Günaydın",
/// "İyi akşamlar"); then every ten minutes it changes to a short line from the world of
/// music, chosen at random (never the same twice in a row, never a night line in the
/// morning). The home page shows the change with a soft cross-fade.
@MainActor
@Observable
final class Greeting {
    static let shared = Greeting()

    private(set) var text = Greeting.timeOfDay()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var last: Int?

    static let interval: UInt64 = 10 * 60 * 1_000_000_000

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.interval)
                guard !Task.isCancelled else { return }
                self?.next()
            }
        }
    }

    private func next() {
        let hour = Calendar.current.component(.hour, from: Date())
        let fitting = Self.lines.indices.filter { $0 != last && Self.lines[$0].fits(hour) }
        guard let i = fitting.randomElement() else { return }
        last = i
        withAnimation(.smooth(duration: 0.9)) { text = Self.lines[i].text }
    }

    nonisolated static func timeOfDay(_ date: Date = Date()) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return M.t("Günaydın", "Good morning")
        case 12..<18: return M.t("İyi günler", "Good afternoon")
        case 18..<23: return M.t("İyi akşamlar", "Good evening")
        default: return M.t("İyi geceler", "Good night")
        }
    }

    struct Line {
        let tr: String
        let en: String
        let emoji: String
        var when: Part = .any

        enum Part { case any, morning, day, night }

        var text: String { "\(M.t(tr, en)) \(emoji)" }

        func fits(_ hour: Int) -> Bool {
            switch when {
            case .any: return true
            case .morning: return (5..<12).contains(hour)
            case .day: return (7..<19).contains(hour)
            case .night: return hour >= 20 || hour < 5
            }
        }
    }

    nonisolated static let lines: [Line] = [
        Line(tr: "Kulaklıklar hazır, gün senin", en: "Headphones on, the day is yours", emoji: "🎧"),
        Line(tr: "Bugün hangi şarkı seni anlatıyor?", en: "Which song tells your story today?", emoji: "🎶"),
        Line(tr: "Bir şarkı, bin his", en: "One song, a thousand feelings", emoji: "✨"),
        Line(tr: "Sesi aç, dünyayı kıs", en: "Turn it up, turn the world down", emoji: "🔊"),
        Line(tr: "Her güne bir intro yakışır", en: "Every day deserves an intro", emoji: "🌅", when: .morning),
        Line(tr: "Ayakların ritmi tuttu bile", en: "Your feet already caught the beat", emoji: "💃"),
        Line(tr: "Bugün biraz piyano iyi gelir", en: "A little piano would do you good today", emoji: "🎹"),
        Line(tr: "Kalbin de bir davul, dinle", en: "Your heart is a drum too, listen", emoji: "🥁"),
        Line(tr: "Biraz gitar, biraz huzur", en: "A little guitar, a little peace", emoji: "🎸"),
        Line(tr: "Gece yarısı şarkıları başkadır", en: "Midnight songs hit different", emoji: "🌙", when: .night),
        Line(tr: "Kahve ve iyi bir çalma listesi", en: "Coffee and a good playlist", emoji: "☕", when: .morning),
        Line(tr: "Bas düştü, mod yükseldi", en: "The bass dropped, the mood went up", emoji: "🚀"),
        Line(tr: "Renkli bir gün için renkli şarkılar", en: "Colourful songs for a colourful day", emoji: "🌈", when: .day),
        Line(tr: "Kimse duymuyor, söyle gitsin", en: "No one's listening, sing along", emoji: "🎤"),
        Line(tr: "Disko topu senin için dönüyor", en: "The disco ball spins for you", emoji: "🪩"),
        Line(tr: "Dalga dalga melodiler", en: "Melodies, wave after wave", emoji: "🌊"),
        Line(tr: "Notalar seni bekliyor", en: "The notes are waiting for you", emoji: "🎼"),
        Line(tr: "Bir kez daha, bu sefer daha yüksek", en: "One more time, louder this time", emoji: "🔁"),
        Line(tr: "Sakin bir şarkı, derin bir nefes", en: "A calm song, a deep breath", emoji: "🌿"),
        Line(tr: "Bugün çalma listesi yanıyor", en: "Today the playlist is on fire", emoji: "🔥"),
        Line(tr: "Caz zamanı mı dersin?", en: "Jazz o'clock, maybe?", emoji: "🎷"),
        Line(tr: "Yağmura en çok şarkılar yakışır", en: "Nothing suits the rain like songs", emoji: "🌧️"),
        Line(tr: "Güneş var, ritim var", en: "Sun's out, beat's on", emoji: "☀️", when: .day),
        Line(tr: "Rahatla, gerisini müzik halleder", en: "Relax, the music will handle the rest", emoji: "🛋️"),
        Line(tr: "Tempoyu sen belirle", en: "You set the tempo", emoji: "🏃"),
        Line(tr: "Keşfedilmeyi bekleyen şarkılar var", en: "Songs are waiting to be discovered", emoji: "💫"),
        Line(tr: "Bugünün miksini sen yap", en: "Mix today your way", emoji: "🎛️"),
        Line(tr: "Hayat bir şarkıysa nakarat sensin", en: "If life's a song, you're the chorus", emoji: "🎵"),
        Line(tr: "Sevdiğin şarkı bir tık uzakta", en: "Your favourite song is one click away", emoji: "🧡"),
        Line(tr: "Yıldızlar da dinliyor", en: "The stars are listening too", emoji: "🌌", when: .night),
        Line(tr: "Yol şarkıları hazır", en: "Road songs ready", emoji: "🚗"),
        Line(tr: "Bugünün frekansı: iyi hisler", en: "Today's frequency: good vibes", emoji: "📻"),
        Line(tr: "Biraz yaylı, bolca duygu", en: "A few strings, a lot of feeling", emoji: "🎻"),
        Line(tr: "Sessizliğe güzel bir şarkı ekle", en: "Add a good song to the silence", emoji: "😌"),
        Line(tr: "Her şarkı küçük bir kutlama", en: "Every song is a small celebration", emoji: "🎉"),
        Line(tr: "Nefes al, ritmi bul", en: "Breathe in, find the rhythm", emoji: "🧘"),
        Line(tr: "Bugün iyi şeyler çalacak", en: "Good things will play today", emoji: "🌻"),
        Line(tr: "Kimse bakmıyor, dans et", en: "No one's watching, dance", emoji: "🕺"),
        Line(tr: "Ses seviyesi: mutluluk", en: "Volume level: happiness", emoji: "🎚️"),
        Line(tr: "Şehir uyurken şarkılar uyanık", en: "The city sleeps, the songs stay awake", emoji: "🌃", when: .night),
        Line(tr: "Hafif bir melodi, hafif bir gün", en: "A light melody, a light day", emoji: "🍃"),
        Line(tr: "Sıradaki şarkı sürpriz olsun", en: "Let the next song be a surprise", emoji: "🔮"),
        Line(tr: "Müzik her zaman iyi bir fikir", en: "Music is always a good idea", emoji: "💜"),
        Line(tr: "Sahne senin", en: "The stage is yours", emoji: "🎙️"),
        Line(tr: "Bir şarkı dile, çalsın", en: "Wish for a song, let it play", emoji: "🌠"),
        Line(tr: "Kafa tatili için birkaç şarkı", en: "A few songs for a mind vacation", emoji: "🏝️"),
        Line(tr: "Plağı çevir, yeni bir yüz başlasın", en: "Flip the record, start a new side", emoji: "💿"),
        Line(tr: "Bugün biraz neşe üfleyelim", en: "Let's blow a little joy today", emoji: "🎺"),
        Line(tr: "Tam şarkı saati", en: "It's song o'clock", emoji: "⏰"),
        Line(tr: "Gece uzun, liste uzun", en: "Long night, long playlist", emoji: "🌙", when: .night),
        Line(tr: "Dünyayı sessize al", en: "Put the world on mute", emoji: "🎧"),
        Line(tr: "Yumuşak notalar, yumuşak anlar", en: "Soft notes, soft moments", emoji: "🌸"),
        Line(tr: "Enerji mi düştü? Bası yükselt", en: "Low energy? Raise the bass", emoji: "⚡"),
        Line(tr: "Bugün hangi türe yolculuk?", en: "Which genre are we travelling to today?", emoji: "🗺️"),
        Line(tr: "İyi şarkılar iyi insanlara", en: "Good songs for good people", emoji: "🫶"),
        Line(tr: "Her ruh hâlinin bir şarkısı var", en: "Every mood has its song", emoji: "🎶"),
        Line(tr: "Bulutlar dağılsın, şarkı başlasın", en: "Clouds away, music on", emoji: "🌤️", when: .day),
        Line(tr: "Ritim sende", en: "You've got the rhythm", emoji: "🎵"),
        Line(tr: "Eksik parça bir şarkı olabilir", en: "The missing piece might be a song", emoji: "🧩"),
        Line(tr: "Derin bas, derin huzur", en: "Deep bass, deep calm", emoji: "🌊"),
        Line(tr: "Final değil, sadece bir ara nağme", en: "Not the finale, just an interlude", emoji: "🎆"),
        Line(tr: "Çay demlenirken bir şarkı", en: "A song while the tea brews", emoji: "🍵"),
        Line(tr: "Hafif tempo, keyifli yol", en: "Easy tempo, easy ride", emoji: "🚲"),
        Line(tr: "Döngüde en sevdiğin şarkı", en: "Your favourite song on loop", emoji: "🎡"),
        Line(tr: "Bugün kalbine iyi gelecek bir şey çal", en: "Play something kind to your heart today", emoji: "🌺"),
        Line(tr: "Biraz akustik, biraz samimi", en: "A bit acoustic, a bit close", emoji: "🪕"),
        Line(tr: "Bir şarkılık mola ver", en: "Take a one-song break", emoji: "🎧"),
        Line(tr: "İlham bir melodi uzağında", en: "Inspiration is one melody away", emoji: "💡"),
        Line(tr: "Ay ışığında lo-fi", en: "Lo-fi in the moonlight", emoji: "🌙", when: .night),
        Line(tr: "Tam zamanında bir drop", en: "A drop right on time", emoji: "🔊"),
        Line(tr: "Sessizlik bile müziğin parçası", en: "Even silence is part of the music", emoji: "🎼"),
        Line(tr: "Sabah enerjisi yüklendi", en: "Morning energy loaded", emoji: "🌞", when: .morning),
        Line(tr: "Hafif şarkılar, hafif kalpler", en: "Light songs, light hearts", emoji: "🎈"),
        Line(tr: "Yolculuğunun müziği hazır", en: "Your journey's soundtrack is ready", emoji: "🛤️"),
        Line(tr: "Nakarata az kaldı", en: "The chorus is almost here", emoji: "🎤"),
        Line(tr: "Bir şarkıya dal, kaybol", en: "Dive into a song, get lost", emoji: "🌀"),
        Line(tr: "Bugün sana iyi şarkılar", en: "Wishing you good songs today", emoji: "💛"),
        Line(tr: "Kalp atışın kaç BPM?", en: "What's your heart's BPM?", emoji: "🎶"),
        Line(tr: "Gece moduna geçildi", en: "Night mode: on", emoji: "🌒", when: .night),
        Line(tr: "Siyah beyaz tuşlarda renkli bir gün", en: "A colourful day on black and white keys", emoji: "🎹"),
        Line(tr: "Yeni bir favorin seni bekliyor olabilir", en: "A new favourite might be waiting", emoji: "🌟"),
        Line(tr: "Yaz akşamı şarkıları, her mevsim", en: "Summer-evening songs, any season", emoji: "🏖️"),
        Line(tr: "Kulaklarına güzel bir şey dinlet", en: "Treat your ears to something good", emoji: "🎧"),
        Line(tr: "Bir melodi, bin anı", en: "One melody, a thousand memories", emoji: "🎵"),
        Line(tr: "Isınma bitti, sıra asıl parçada", en: "Warm-up's done, here comes the track", emoji: "🔥"),
        Line(tr: "Yeni bir şarkı, yeni bir başlangıç", en: "A new song, a new start", emoji: "🌱"),
        Line(tr: "Ses dalgası seni çağırıyor", en: "The soundwave is calling", emoji: "🎶"),
        Line(tr: "Rotayı müzik çizsin", en: "Let the music set the course", emoji: "🧭"),
        Line(tr: "Uyku sonra, şimdi bir şarkı daha", en: "Sleep later, one more song now", emoji: "🌙", when: .night),
        Line(tr: "Şarkılar seni bekledi", en: "The songs waited for you", emoji: "✨"),
        Line(tr: "Bugün biraz uzay ambient'i?", en: "A bit of space ambient today?", emoji: "🪐"),
        Line(tr: "Mod düğmesi: yukarı", en: "Mood knob: up", emoji: "🎛️"),
        Line(tr: "Her şey yolunda, ritim de", en: "All is well, and so is the beat", emoji: "🎵"),
        Line(tr: "Bu şarkı sana iyi gelecek", en: "This song is going to do you good", emoji: "❤️‍🔥"),
        Line(tr: "Ufukta güzel bir melodi var", en: "There's a lovely melody on the horizon", emoji: "🌄"),
        Line(tr: "Hoş geldin, müzik seni özledi", en: "Welcome back, the music missed you", emoji: "🎧"),
        Line(tr: "Çalma listen partiye hazır", en: "Your playlist is party-ready", emoji: "🎉"),
        Line(tr: "Akışta kal", en: "Stay in the flow", emoji: "🌊"),
        Line(tr: "Biraz nostalji, biraz yeni", en: "A little nostalgia, a little new", emoji: "🎶"),
        Line(tr: "Günün en güzel şarkısı henüz çalmadı", en: "The best song of the day hasn't played yet", emoji: "💫"),
    ]
}
