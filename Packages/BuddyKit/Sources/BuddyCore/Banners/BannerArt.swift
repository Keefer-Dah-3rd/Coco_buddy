import Foundation

/// The six illustrated banners, ported line for line from the Figma Make file's
/// `src/IllustratedScene.tsx` (Illustrated Task Card Concepts, round 04). Every path, colour,
/// stroke and layer order is the Make file's own; the light (`BannerTimeOfDay`) and weather
/// (`BannerWeather`) change the scene exactly as they do there. The one change is progress:
/// the prototype counted five tasks, this uses `BannerProgress` so any number works.
///
/// Don't edit the art here by eye. Change it in Figma, export it again
/// (`scripts/banners/export_make_states.sh`) and keep `BannerArtPortTests` passing.
public enum BannerArt {
    public static let ink = "#1d1f20"
    public static let accent = "#ff741b"

    /// [sky, horizon, grass, deep] for each light — the Make file's `moments`.
    static func moment(_ time: BannerTimeOfDay) -> (sky: String, horizon: String, grass: String, deep: String) {
        switch time {
        case .morning: ("#eef5d9", "#ffde9c", "#b7d482", "#62805a")
        case .daytime: ("#dcecf3", "#f8edce", "#9ac978", "#507358")
        case .evening: ("#c5b9dd", "#ffb68c", "#98936e", "#635c64")
        case .night: ("#242b50", "#626487", "#637c79", "#354f5a")
        }
    }

    /// Ids of the shared definitions (the Make file prefixes them with React's `useId`).
    public enum Def {
        public static let sky = "sky"
        public static let dots = "dots"
        public static let clip = "clip"
        public static let carriageWindow = "carriage-window"
        public static let harbourWater = "harbour-water"
        public static let lighthouseBody = "lighthouse-body"
        public static let awningRoof = "awning-roof"
    }

    static func url(_ id: String) -> String { "url(#\(id))" }

    /// The ambient-motion classes the art uses (the Make file's CSS animations).
    public enum Motion: String, CaseIterable, Sendable {
        case cloud = "vector-cloud"
        case star = "vector-star"
        case rainfall = "vector-rainfall"
        case snowfall = "vector-snowfall"
        case gust = "vector-gust"
        case sway = "vector-sway"
        case ferryBob = "ferry-bob"
        case linen = "hanging-linen"
        case scenery = "carriage-scenery"
        case steam = "tea-steam"
        /// Progress-driven, not ambient: these move when tasks are done.
        case ferryJourney = "ferry-journey"
        case thumb = "vector-thumb"
    }

    // MARK: - The frame

    public static func document(_ state: BannerState) -> SceneDocument {
        let s = Scene(state)
        return SceneDocument(defs: s.defs, art: s.art, rail: s.rail)
    }

    /// Everything a frame's art depends on, named as in the Make source.
    struct Scene {
        let concept: BannerID
        let time: BannerTimeOfDay
        let weather: BannerWeather
        let progress: BannerProgress

        let night: Bool
        let snow: Bool
        let rain: Bool
        let muted: Bool
        let sky: String, horizon: String, grass: String, deep: String
        let ground: String
        let ink = BannerArt.ink
        let accent = BannerArt.accent
        let harbourWater = "M0 56C55 58 105 58 160 56S265 54 320 56V108H0Z"
        let awningRoof = "M50 9H263L273 25H40Z"
        /// `q-8.32… 6 -16.64… 0`, fourteen times: the awning's scalloped edge.
        let awningScallops = Array(repeating: "q\(svgNumber(-233.0 / 28)) 6 \(svgNumber(-233.0 / 14)) 0", count: 14)
            .joined(separator: " ")
        /// The thumb's x: the start of the rail plus the done share of its 280 units.
        let x: Double

        init(_ state: BannerState) {
            concept = state.banner
            time = state.time
            weather = state.weather
            progress = state.progress
            night = time == .night
            snow = weather == .snowy
            rain = weather == .rainy
            muted = rain || weather == .cloudy
            (sky, horizon, grass, deep) = BannerArt.moment(time)
            ground = snow ? "#f2f4ed" : muted ? deep : grass
            x = 20 + progress.along(280)
        }

        var common: [(String, String)] {
            [("stroke", ink), ("stroke-width", "1.25"), ("stroke-linecap", "round"), ("stroke-linejoin", "round")]
        }

        func withCommon(_ extra: SceneAttributes = [:], @SceneBuilder _ content: () -> [SceneNode]) -> SceneNode {
            var node = G(extra, content)
            for (key, value) in common { node.attributes[key] = value }
            return node
        }

        func clotheslineY(_ position: Double) -> Double {
            let t = (position - 30) / 259
            return 15 + 44 * t * (1 - t)
        }

        func plant(_ px: Double, _ py: Double, _ tall: Double, _ reached: Bool) -> SceneNode {
            G(["transform": "translate(\(svgNumber(px)) \(svgNumber(py)))",
               "class": weather == .windy ? Motion.sway.rawValue : ""]) {
                Path("M0 0Q-3 -\(svgNumber(tall / 2)) 0 -\(svgNumber(tall))", ["fill": "none"])
                Path("M-1 -\(svgNumber(tall * 0.4))Q-18 -\(svgNumber(tall * 0.75)) -13 -\(svgNumber(tall * 0.95))Q2 -\(svgNumber(tall * 0.85)) -1 -\(svgNumber(tall * 0.4))",
                     ["fill": reached ? "#51e302" : ground])
                Path("M-1 -\(svgNumber(tall * 0.65))Q16 -\(svgNumber(tall * 1.1)) 13 -\(svgNumber(tall * 1.25))Q0 -\(svgNumber(tall * 1.2)) -1 -\(svgNumber(tall * 0.65))",
                     ["fill": reached ? "#c9df82" : deep])
            }
        }

        // MARK: Definitions

        var defs: [SceneNode] {
            [
                SceneNode(.linearGradient, ["id": Def.sky, "x2": "0", "y2": "1"], children: [
                    SceneNode(.stop, ["stop-color": muted ? (night ? "#252e41" : "#becdce") : sky]),
                    SceneNode(.stop, ["offset": "1", "stop-color": muted ? (night ? "#525e6b" : "#dce2da") : horizon]),
                ]),
                SceneNode(.pattern, ["id": Def.dots, "width": "5", "height": "5", "patternUnits": "userSpaceOnUse"], children: [
                    Circle(["cx": "1", "cy": "1", "r": ".45", "fill": ink, "opacity": ".12"]),
                ]),
                SceneNode(.clipPath, ["id": Def.clip], children: [Rect(["y": "-44", "width": "320", "height": "152"])]),
                SceneNode(.clipPath, ["id": Def.carriageWindow], children: [
                    Rect(["x": "25", "y": "2", "width": "269", "height": "65", "rx": "15"]),
                ]),
                SceneNode(.clipPath, ["id": Def.harbourWater], children: [Path(harbourWater)]),
                SceneNode(.clipPath, ["id": Def.lighthouseBody], children: [Path("m0 41 5-34h13l5 34Z")]),
                SceneNode(.clipPath, ["id": Def.awningRoof], children: [Path(awningRoof)]),
            ]
        }

        // MARK: Art

        var art: SceneNode {
            G {
                Rect(["y": "-44", "width": "320", "height": "152", "fill": url(Def.sky)])
                withCommon {
                    if night {
                        G(["fill": "#fff2c6"]) {
                            Path("M270 11a12 12 0 1 0 13 17 12 12 0 0 1-13-17Z")
                            for (i, p) in [35, 101, 188, 242, 303].enumerated() {
                                Path("M\(p) \(12 + (i % 3) * 9)v4m-2-2h4",
                                     ["stroke": "#f3edcf", "stroke-width": ".8", "class": Motion.star.rawValue])
                            }
                        }
                    } else {
                        Circle(["cx": time == .evening ? "273" : "260", "cy": time == .evening ? "46" : "23",
                                "r": "13", "fill": "#ffcf71"])
                    }
                    if muted || snow {
                        G(["fill": night ? "#737e92" : "#f5f4e9", "class": Motion.cloud.rawValue]) {
                            Path("M202 28c-6-1-6-9 1-10 0-10 15-12 19-3 9-3 16 4 12 10 6 0 7 7 0 7h-29Z")
                            Path("M48 19c-2-8 9-12 14-6 1-7 15-8 17 2 9-1 12 10 2 11H50c-7 0-9-6-2-7Z")
                        }
                    }
                    switch concept {
                    case .tidalPool: tidalPool
                    case .windowNook: windowNook
                    case .slowFerry: slowFerry
                    case .cornerBookshop: cornerBookshop
                    case .laundryInTheSky: laundryInTheSky
                    case .quietCarriage: quietCarriage
                    }
                    Rect(["width": "320", "height": "108", "fill": url(Def.dots), "stroke": "none"])
                    G(["clip-path": concept == .quietCarriage ? url(Def.carriageWindow) : nil]) {
                        if snow {
                            Path("M0 75q10-4 19 0t20 0m161 1q12-5 24-1m50-4q18-5 46 0",
                                 ["stroke": "#fffdf5", "stroke-width": "5"])
                        }
                        if rain || snow {
                            G(["class": rain ? Motion.rainfall.rawValue : Motion.snowfall.rawValue,
                               "stroke": night ? "#e6f0ee" : "#5f8090"]) {
                                for i in 0..<12 {
                                    if rain {
                                        Path("m\(i * 29 - 6) \((i % 3) * 17) -3 8", ["stroke-width": ".8"])
                                    } else {
                                        Circle(["cx": "\(i * 29 - 6)", "cy": "\((i % 3) * 17)", "r": "1.6",
                                                "fill": "#fff", "stroke-width": ".5"])
                                    }
                                }
                            }
                        }
                        if weather == .windy {
                            G(["class": Motion.gust.rawValue, "fill": "none",
                               "stroke": night ? "#d5d9de" : "#71867c", "stroke-width": ".8"]) {
                                Path("M9 31h36q9 0 7-5m178 17h30q10 0 7-6M79 14h23")
                                Path("m230 27 6-3 2 4-6 3Z", ["fill": "#ffb17a"])
                            }
                        }
                    }
                }
            }
        }

        // MARK: 03 / A Little Tidal Pool  (Make key: atmospheric)

        @SceneBuilder var tidalPool: [SceneNode] {
            Path("M0 57Q38 52 80 58T160 57T240 58T320 56V108H0Z", ["fill": night ? "#6c8790" : "#b2d6ca"])
            Path("M0 73Q40 59 87 72T180 75T270 71T320 74", ["fill": "none", "stroke": night ? "#d6e2d4" : "#eff6e1"])
            Path("M0 88Q46 71 108 87T230 85T320 91V108H0Z", ["fill": snow ? "#ecf2eb" : "#e7d5a8"])
            Path("M177 70q18-8 31 3l10 8-20 5-29-6Z", ["fill": "#a6b5a2"])
            Path("M175 72q10-9 21-3", ["fill": "none"])
            Path("M45 67v-9l13 4-13 5 7 4h-15Z", ["fill": "#fff8dd"])
            Path("M87 44h19m-9-4v8m147 12h17m-8-4v8", ["stroke": night ? "#b8c9c9" : "#f6fbec", "stroke-width": ".7"])
            G(["transform": "translate(235 77)"]) {
                Path("m0 0 4-5 4 5 6-2-2 6 4 4-7 1-3 6-3-6-7-1 4-4-2-6Z", ["fill": "#ff9e78"])
            }
            if rain {
                G(["fill": "none", "stroke": "#eff5ec"]) {
                    Ellipse(["cx": "87", "cy": "75", "rx": "8", "ry": "2"])
                    Ellipse(["cx": "275", "cy": "69", "rx": "5", "ry": "1.5"])
                }
            }
        }

        // MARK: 04 / Coco’s Window Nook  (Make key: coco)

        @SceneBuilder var windowNook: [SceneNode] {
            Path("M0 0h39v108H0Zm257 0h63v108h-63Z", ["fill": "#eee9d9"])
            Path("M42 0v76h211V0M146 0v75", ["fill": "none", "stroke-width": "3"])
            Path("M46 63Q87 39 144 60T253 55v21H46Z", ["fill": ground])
            Path("M33 76h231v7H33Z", ["fill": "#f0cf9a"])
            Path("M0 83h320v25H0Z", ["fill": night ? "#b5aa9b" : "#efdebd"])
            G(["transform": "translate(58 58)"]) {
                plant(0, 15, 20, progress.reached(1))
                Path("m-10 13 3 14H7l3-14Z", ["fill": "#d99e7d"])
            }
            Path("M104 88q3-15 32-15h28q30 0 33 15l-7 10h-79Z", ["fill": "#b7b3d9"])
            Ellipse(["cx": "150", "cy": "87", "rx": "35", "ry": "7", "fill": night ? "#e5dbbb" : "#fff1d7"])
            Path("m136 85 7-3 8 3 9-3 7 4", ["stroke": "#b5ac9d", "fill": "none"])
            // The tennis ball rolls along the ledge as the day fills (prototype: 5 units a task).
            Circle(["cx": svgNumber(211 + progress.along(25)), "cy": "91", "r": "6", "fill": "#51e302"])
            Path("M\(svgNumber(208 + progress.along(25))) 86q7 5 2 10", ["stroke": "#fcffe6", "fill": "none"])
            Path("M12 27q11 10 8 33M307 27q-11 10-8 33", ["fill": "none", "stroke": "#b8b29d"])
            Path("M217 70h20l-2-6h-16Z", ["fill": "#ff9d66"])
        }

        // MARK: 06 / The Slow Ferry  (Make key: ferry)

        @SceneBuilder var slowFerry: [SceneNode] {
            Path("M0 54Q26 48 47 51L64 40H98L116 52Q166 53 205 48Q239 43 272 50L320 48V64H0Z", ["fill": ground])
            Path(harbourWater, ["fill": night ? "#456777" : rain ? "#82a3a6" : "#b3d9cf"])
            G(["transform": "translate(219 8)"]) {
                Path("m0 41 5-34h13l5 34Z", ["fill": snow ? "#fff" : "#f4ebd0", "stroke": "none"])
                G(["clip-path": url(Def.lighthouseBody)]) {
                    Path("M0 22h23v7H0Z", ["fill": "#e39778"])
                }
                Path("m0 41 5-34h13l5 34Z", ["fill": "none"])
                Path("M3 8h17V1H3Zm-2-7 11-8 11 8Z", ["fill": accent])
                Path("M8 2h7v6H8Z", ["fill": night ? "#ffe5a0" : "#d2e2da"])
                if night {
                    Path("M20 3 83-13v35L20 7Z", ["fill": "#fff2c0", "opacity": ".16", "stroke": "none"])
                }
            }
            Path("M0 83h34v25H0Z", ["fill": "#c7ab89"])
            for p in [10, 29] {
                G {
                    Path("M\(p) 86V64h6v22Z", ["fill": "#f8ecce"])
                    Path("M\(p) 72h6v5h-6Z", ["fill": accent])
                }
            }
            // The ferry crosses the bay as the day fills (prototype: 32 units a task).
            G(["class": Motion.ferryJourney.rawValue,
               "style": "transform:translateX(\(svgNumber(35 + progress.along(160)))px)"]) {
                Path("M-8 79q13 4 27 0m-33 6q9 2 18 0", ["fill": "none", "stroke": night ? "#adc9cb" : "#f5fae7"])
                G(["class": Motion.ferryBob.rawValue]) {
                    Path("M0 64h69l-10 12H12Z", ["fill": accent])
                    Path("M13 64V46h39v18Z", ["fill": "#faf1d7"])
                    Path("M10 46h47v-5H10Zm23-5V31h8v10Z", ["fill": "#688c89"])
                    for p in [19, 31, 43] {
                        Rect(["x": "\(p)", "y": "50", "width": "7", "height": "7", "rx": "1",
                              "fill": night ? "#ffdc91" : "#a8ccd1"])
                    }
                    Circle(["cx": "16", "cy": "68", "r": "3", "fill": "#f6eddb"])
                    Circle(["cx": "53", "cy": "68", "r": "3", "fill": "#f6eddb"])
                }
            }
            Path("M259 84q9 2 18 0M138 88q11 2 22 0M256 64q10 2 20 0M63 91q9 2 18 0",
                 ["stroke": night ? "#9dbdc1" : "#edf6e0", "stroke-width": ".8",
                  "clip-path": url(Def.harbourWater), "fill": "none"])
        }

        // MARK: 07 / The Corner Bookshop  (Make key: bookshop)

        @SceneBuilder var cornerBookshop: [SceneNode] {
            Path("M0 82h320v26H0Z", ["fill": rain ? "#9faeaa" : snow ? "#e8eeeb" : "#d3c7ad"])
            Path("M48 82V9h217v73Z", ["fill": night ? "#a3afa5" : "#ece4ce"])
            Path("M50 9H263L273 25V31\(awningScallops)V25Z", ["fill": "#f6eddb", "stroke": "none"])
            G(["clip-path": url(Def.awningRoof)]) {
                for i in stride(from: 0, through: 12, by: 2) {
                    let i = Double(i)
                    Path("M\(svgNumber(50 + (i * 213) / 14)) 9H\(svgNumber(50 + ((i + 1) * 213) / 14))L\(svgNumber(40 + ((i + 1) * 233) / 14)) 25H\(svgNumber(40 + (i * 233) / 14))Z",
                         ["fill": "#bc7b64", "stroke": "none"])
                }
                for i in 1...13 {
                    let i = Double(i)
                    Path("M\(svgNumber(50 + (i * 213) / 14)) 9L\(svgNumber(40 + (i * 233) / 14)) 25",
                         ["fill": "none", "stroke-width": ".7"])
                }
            }
            Path("M50 9H263L273 25V31\(awningScallops)V25Z", ["fill": "none"])
            Path("M40 25H273", ["fill": "none"])
            // Five arched windows; each warms up as a fifth of the day gets done.
            for i in 0..<5 {
                G(["transform": "translate(\(61 + i * 37) 37)"]) {
                    Path("M0 42V12a14 14 0 0 1 28 0v30Z",
                         ["fill": progress.reached(i) ? "#ffdc9f" : night ? "#3d4b60" : "#bdcfc2"])
                    Path("M0 27h28", ["stroke-width": ".8"])
                    for b in 0..<3 {
                        Path("m\(5 + b * 7) 37v-7h4v7Z", ["fill": ["#d89574", "#889b82", "#d4bd8b"][b], "stroke-width": ".7"])
                    }
                    Path("M14-2v28", ["stroke-width": ".7"])
                }
            }
            Path("M47 80h219v5H47Z", ["fill": "#b98d6b"])
            Path("M282 82V58h20v24Zm-3-24 13-8 13 8Z", ["fill": "#f9edd1"])
            Path("M286 65h13m-13 5h10m-10 5h12", ["stroke-width": ".7"])
            Path("M21 81V61m-9 4q10 12 9-11 13 10 3 18", ["fill": ground])
            Path("m11 76 3 10h14l3-10Z", ["fill": "#cc9477"])
            if rain {
                Ellipse(["cx": "283", "cy": "89", "rx": "17", "ry": "2", "fill": "#b8ced0", "stroke-width": ".7"])
            }
        }

        // MARK: 08 / Laundry in the Sky  (Make key: rooftop)

        @SceneBuilder var laundryInTheSky: [SceneNode] {
            Path("M0 74V48h24v-9h24v35m16 0V30h27v44m112 0V44h22v-8h30v38m16 0V24h27v50",
                 ["fill": night ? "#566378" : "#c5c7be", "stroke-width": ".7"])
            Path("M0 82h320v26H0Z", ["fill": snow ? "#f0f3e9" : rain ? "#9d9f96" : "#d6bba1"])
            Path("M0 75h320v8H0Z", ["fill": "#b5b29f"])
            Path("M29 77V5m261 72V5M30 15q129.5 22 259 0", ["fill": "none"])
            // Five pegs on the line; a piece of laundry goes up for each fifth of the day done.
            for i in 0..<5 {
                let left = Double(49 + i * 43)
                let top = clotheslineY(left)
                let rightOffset = clotheslineY(left + 23) - top
                G(["transform": "translate(\(svgNumber(left)) \(svgNumber(top)))"]) {
                    Path("M0-5v9M23 \(svgNumber(rightOffset - 5))v9", ["stroke": "#9a7055", "stroke-width": "3"])
                    if progress.reached(i) {
                        G(["class": weather == .windy ? Motion.linen.rawValue : ""]) {
                            if i % 2 == 0 {
                                Path("m-2 0 7-3 7 3 7-3 7 3 6 12-7 3-2-4 1 26H0l1-26-3 4-7-3Z",
                                     ["fill": ["#f9edcf", "#c4d4c1", "#dfa58a", "#b7bdd4", "#f4da9c"][i]])
                            } else {
                                Path("M-2-2q14 4 29 0l-1 38q-14-5-26 0Z", ["fill": i == 1 ? "#a6bab2" : "#b8afd0"])
                            }
                            Path("M5 5v23m14-22v20", ["stroke-width": ".6", "opacity": ".4", "fill": "none"])
                        }
                    } else {
                        Path("M0 2h23", ["stroke-dasharray": "2 3", "opacity": ".35"])
                    }
                }
            }
            Path("M22 87h30v-9H22Zm5-9h23v-5H27Z", ["fill": "#e9dfc2"])
            Path("m266 80 4 10h21l4-10Z", ["fill": "#ce9675"])
            Path("M280 80V60m0 12q-18-3-14-12 12 1 14 12m0-4q15-19 19-9-6 11-19 9", ["fill": ground])
            Path("M93 87h33m90 0h17", ["stroke": "#b49b82", "stroke-width": ".7"])
        }

        // MARK: 09 / The Quiet Carriage  (Make key: train)

        @SceneBuilder var quietCarriage: [SceneNode] {
            Rect(["y": "-44", "width": "320", "height": "152", "fill": night ? "#485663" : "#e5dbc6", "stroke": "none"])
            G(["clip-path": url(Def.carriageWindow)]) {
                Rect(["x": "25", "y": "2", "width": "269", "height": "65", "fill": url(Def.sky), "stroke": "none"])
                if night {
                    Path("M270 11a10 10 0 1 0 10 14 10 10 0 0 1-10-14Z", ["fill": "#fff2c6"])
                } else {
                    Circle(["cx": "263", "cy": time == .evening ? "34" : "19", "r": "10", "fill": "#ffcf71"])
                }
                Path("M20 42q53-26 99-4t84 1 99-8v44H20Z", ["fill": ground])
                Path("M20 56q67-15 122-1t160-5v25H20Z", ["fill": snow ? "#e9eee5" : deep])
                G(["class": Motion.scenery.rawValue, "fill": night ? "#a1aa9a" : "#e5d7b4"]) {
                    Path("m47 48 10-8 10 8v11H47Zm2 0h16m153-7 10-8 10 8v16h-20Z")
                    Path("M56 49v6m171-12v7", ["stroke": "#fff0bf"])
                }
            }
            Rect(["x": "25", "y": "2", "width": "269", "height": "65", "rx": "15", "fill": "none"])
            Path("M26 66h268v7H26ZM111 3v63m95-63v63", ["fill": "#b49a79", "stroke-width": "2"])
            Path("M0 79q20-16 56 0v29H0Zm260 0q30-16 60 0v29h-60Z", ["fill": night ? "#697988" : "#9aaba1"])
            Path("M8 83h37m227 0h40", ["stroke": "#d9d9c2", "stroke-width": ".7"])
            Path("M79 80h160l9 6H70Zm24 6-3 22m114-22 3 22", ["fill": "#d6b78f"])
            Path("M171 76h31m-27-1-2-15h22l-2 15Zm20-14q15-3 10 8l-11 2", ["fill": "#f9efd8"])
            Path("M180 55q-5-4 0-8m7 8q-4-4 0-8", ["fill": "none", "stroke": night ? "#fff0d0" : "#8e9e90",
                                                    "class": Motion.steam.rawValue])
            Rect(["x": "108", "y": "74", "width": "40", "height": "7", "rx": "1", "fill": "#f5e3b3"])
            // Five ticket punches; one goes orange for each fifth of the day done.
            for i in 0..<5 {
                Circle(["cx": "\(113 + i * 7)", "cy": "77.5", "r": "1.4",
                        "fill": progress.reached(i) ? accent : "#d9ccb0", "stroke-width": ".5"])
            }
        }

        // MARK: The progress rail

        /// The foreground rail, drawn over everything: track, done fill, one tick per task, and the
        /// scene's own thumb (buoy, bookmark, clothespin, ticket, tennis ball).
        var rail: SceneNode {
            withCommon(["transform": "translate(0 0)"]) {
                Rect(["x": "20", "y": "96", "width": "280", "height": "5", "rx": "2.5", "fill": "#f6f1de"])
                Rect(["x": "20", "y": "96", "width": svgNumber(max(0, progress.along(280))), "height": "5", "rx": "2.5",
                      "fill": accent, "stroke": "none"])
                for i in stride(from: 1, through: progress.tickCount, by: 1) {
                    Path("M\(svgNumber(20 + Double(i) * 280 / Double(progress.total))) 97v3",
                         ["stroke": i < progress.done ? "#ffe5ba" : ink, "stroke-width": ".7"])
                }
                G(["class": Motion.thumb.rawValue, "style": "transform:translateX(\(svgNumber(x))px)"]) {
                    thumb
                }
            }
        }

        var thumb: SceneNode {
            switch concept {
            case .cornerBookshop:
                return Path("M-5 91H5v15l-5-3-5 3Z", ["fill": "#e6a17b"])
            case .laundryInTheSky:
                return G {
                    Rect(["x": "-4", "y": "90", "width": "8", "height": "16", "rx": "2", "fill": "#ddbd8e"])
                    Path("M0 94v7")
                }
            case .slowFerry:
                return G {
                    Path("M-5 102v-7a5 5 0 0 1 10 0v7Z", ["fill": accent])
                    Path("M-5 98H5", ["stroke": "#fff5dc", "stroke-width": "2"])
                    Path("M-7 103H7")
                }
            case .quietCarriage:
                return G {
                    Rect(["x": "-7", "y": "91", "width": "14", "height": "14", "rx": "3", "fill": "#ffcf71"])
                    Path("M-2 95v6m4-6v6", ["stroke-width": ".8"])
                }
            case .tidalPool, .windowNook:
                let coco = concept == .windowNook
                return G {
                    Circle(["cy": "98.5", "r": "7", "fill": coco ? "#51e302" : "#fff9e9"])
                    if coco {
                        Path("M-3 92q6 6 0 13", ["fill": "none", "stroke": "#fff"])
                    } else {
                        Circle(["cy": "98.5", "r": "2", "fill": accent, "stroke": "none"])
                    }
                }
            }
        }
    }
}
