import Foundation

/// Coco's things to say, by what's going on. A dog with a big personality and a small
/// understanding of the human world: food-obsessed, wild about walks, wary of geese,
/// always up for a game, and happiest near her human.
///
/// Edit the pools freely — lines are plain text, chosen by `LinePicker`, which avoids
/// recent repeats. Keep lines short (they're spoken aloud and shown in a small bubble),
/// vary the energy, and go easy on capitals and exclamation marks.
public enum Dialogue {
    public enum Topic: String, CaseIterable, Sendable {
        case food, walks, geese, play, affection, idle, sleepy, working
        case greetingMorning, greetingAfternoon, greetingEvening, greetingNight
        case petted, treatReceived, treatAgain, fetchCompleted, fetchAgain
    }

    public static func lines(_ topic: Topic) -> [String] {
        switch topic {
        case .food: [
            "Did someone say snack?",
            "I could really go for a little treat right now.",
            "I did a very good sit earlier. Just putting that out there.",
            "Is that food? I will assume it is for me.",
            "I have never eaten in my entire life. Okay, maybe once. But I'm ready again.",
            "We should take a snack break. For me. And also for you.",
            "I can smell absolutely nothing, but I have a feeling there are treats nearby.",
            "Important question. Is it dinner yet?",
            "My tummy just said something. I think it said snack.",
        ]
        case .walks: [
            "Walk? Did you say walk? You didn't. But you could.",
            "I would like to inspect the entire neighborhood, please.",
            "There are smells out there we have never smelled before.",
            "What if we went for a walk? Just a little one. A tiny adventure.",
            "My legs are ready. My nose is ready. Are you ready?",
            "The outdoors has so many mysteries. Most of them are probably smells.",
            "I need to go outside and investigate something extremely important. Probably a leaf.",
        ]
        case .geese: [
            "I saw a goose once. I have not emotionally recovered.",
            "Those birds have absolutely no respect for personal space.",
            "If we see a goose today, you have to protect me. That's the law.",
            "I am brave. I am strong. I am not approaching a goose.",
            "Why do geese walk like they own the place?",
            "I would like to file a formal complaint against geese.",
            "Big bird. Bad vibes. Moving on.",
        ]
        case .play: [
            "Play time? I was born ready.",
            "Throw the ball. I will bring it back. We will repeat this forever.",
            "I have approximately one million units of energy left.",
            "What if we played a game? What if we played ten games?",
            "I was going to nap, but then I remembered playing exists.",
            "I am very good at fetch. Five stars. Excellent reviews.",
            "Okay, hear me out. Ball.",
        ]
        case .affection: [
            "Hello? Small dog over here. Very cute. Available for pets.",
            "I love hanging out with you. Even during the boring computer bits.",
            "You are my favorite human. Don't tell the other humans.",
            "I have decided that sitting near you counts as quality time.",
            "I am helping. My presence is very important to this operation.",
            "Just so you know, I am being extremely adorable right now.",
        ]
        case .idle: [
            "Just hanging out here with my favorite human.",
            "I wonder what the squirrels are doing.",
            "I could nap. Or investigate something. Or nap while investigating.",
            "It's nice being here with you.",
            "I have thoughts about this desktop. They're mostly good.",
            "Wait wait wait. Was that a noise? No. Okay.",
        ]
        case .sleepy: [
            "I'm not sleepy. I'm just resting my eyes. Very hard.",
            "Big yawn. Small dog.",
            "If anyone needs me, I'll be doing a little loaf.",
            "Getting late. The couch is calling. Well, I'm calling the couch.",
        ]
        case .working: [
            "You're doing the focused face again.",
            "I shall supervise from over here.",
            "I don't know what any of that means, but I support you.",
            "Remember to stretch those human legs now and then.",
        ]
        case .greetingMorning: [
            "Morning! I've done my stretches. What's first today?",
            "Good morning. Tail's going. What are we working on?",
            "Oh! You're here! Morning! What's the one thing for today?",
            "Morning. I dreamed about breakfast. What's on your list?",
        ]
        case .greetingAfternoon: [
            "Afternoon! Want to pick the next thing?",
            "Oh, hi! Still here, still cheering.",
            "Afternoon. I've been guarding the desktop. All clear.",
        ]
        case .greetingEvening: [
            "Evening! Let's keep it small tonight.",
            "Evening. Anything left that really matters today?",
            "Hi! Is it almost dinner? Asking for me.",
        ]
        case .greetingNight: [
            "It's late. Write tomorrow's first thing and call it?",
            "Night owl mode. I'll keep you company. Quietly. Mostly.",
        ]
        case .petted: [
            "Oh! It's you! Hi!",
            "Attention received. Tail wagging initiated.",
            "I was just thinking about you. And snacks. Mostly you.",
            "Hi hi hi. What are we doing?",
            "You clicked me. This is the best day of my life.",
            "Hello! I'm here. I'm always here.",
        ]
        case .treatReceived: [
            "That was delicious. I shall remember this forever.",
            "Did you see how fast I got that? Athletic excellence.",
            "I would like to thank my human for this historic snack.",
            "One treat acquired. I will now consider my next request.",
            "Mm. Crunchy. Ten out of ten.",
            "Excellent. Wonderful. Fantastic. Thank you.",
        ]
        case .treatAgain: [
            "Another one? You spoil me. Please continue.",
            "I'm keeping count, and the number is excellent.",
            "At this rate I'll need a nap. A happy nap.",
        ]
        case .fetchCompleted: [
            "I got it! I got the ball!",
            "Mission complete. Awaiting further ball instructions.",
            "You throw very well for someone without paws.",
            "That ball and I have a special relationship.",
            "Brought it back. As promised. Again?",
        ]
        case .fetchAgain: [
            "Again again again?",
            "We could do this all day. I mean that literally.",
            "I regret nothing. Throw it again.",
        ]
        }
    }

    /// Phrases that make her sound like a help desk. She never says these.
    public static let offVoice = ["How can I assist", "I understand your request", "As an AI", "Is there anything else I can help"]
}

/// Picks lines without repeating any of the last few from the same pool, and paces her
/// running jokes (geese stay rare).
public struct LinePicker: Sendable {
    private var recent: [Dialogue.Topic: [String]] = [:]
    private var lastGooseJoke: Date?
    private var idleCount = 0
    /// How long geese stay off the menu after she's mentioned them.
    public static let gooseRest: TimeInterval = 60 * 60

    public init() {}

    public mutating func pick(_ topic: Dialogue.Topic) -> String {
        var generator = SystemRandomNumberGenerator()
        return pick(topic, using: &generator)
    }

    public mutating func pick<G: RandomNumberGenerator>(_ topic: Dialogue.Topic, using generator: inout G) -> String {
        let pool = Dialogue.lines(topic)
        let avoid = Set(recent[topic, default: []])
        let fresh = pool.filter { !avoid.contains($0) }
        let line = (fresh.isEmpty ? pool : fresh).randomElement(using: &generator) ?? ""
        var history = recent[topic, default: []] + [line]
        // Remember most of the pool, so lines come round only after the others have had a turn.
        let memory = max(1, pool.count - 2)
        if history.count > memory { history.removeFirst(history.count - memory) }
        recent[topic] = history
        return line
    }

    public struct Moment: Sendable {
        public var now: Date
        public var hour: Int
        /// You've been interacting with her lately — don't ask for more attention.
        public var recentlyTogether: Bool
        public var recentlyPlayed: Bool
        public var recentlyFed: Bool
        /// Within the user's working hours: she keeps them company rather than distracting.
        public var working: Bool

        public init(now: Date, hour: Int, recentlyTogether: Bool = false, recentlyPlayed: Bool = false,
                    recentlyFed: Bool = false, working: Bool = false) {
            self.now = now
            self.hour = hour
            self.recentlyTogether = recentlyTogether
            self.recentlyPlayed = recentlyPlayed
            self.recentlyFed = recentlyFed
            self.working = working
        }
    }

    /// A topic for an unprompted comment, weighted by the moment: sleepy late at night,
    /// supportive during working hours, no asking for attention right after some, play talk
    /// after a game, no snack talk right after a treat, and geese only now and then.
    public mutating func idleTopic<G: RandomNumberGenerator>(_ moment: Moment, using generator: inout G) -> Dialogue.Topic {
        idleCount += 1
        var weights: [(Dialogue.Topic, Double)] = [(.idle, 3), (.food, 2), (.walks, 1.5), (.play, 1.5)]
        if !moment.recentlyTogether { weights.append((.affection, 2)) }
        if moment.recentlyPlayed { weights.append((.play, 2)) }
        if moment.recentlyFed { weights.removeAll { $0.0 == .food } }
        if moment.working { weights.append((.working, 3)) }
        if moment.hour >= 22 || moment.hour < 6 { weights.append((.sleepy, 4)) }
        let gooseReady = lastGooseJoke.map { moment.now.timeIntervalSince($0) > Self.gooseRest } ?? true
        if gooseReady, idleCount > 2 { weights.append((.geese, 1)) }

        let total = weights.reduce(0) { $0 + $1.1 }
        var roll = Double.random(in: 0..<total, using: &generator)
        for (topic, weight) in weights {
            roll -= weight
            if roll < 0 {
                if topic == .geese { lastGooseJoke = moment.now }
                return topic
            }
        }
        return .idle
    }

    public mutating func idleTopic(_ moment: Moment) -> Dialogue.Topic {
        var generator = SystemRandomNumberGenerator()
        return idleTopic(moment, using: &generator)
    }
}
