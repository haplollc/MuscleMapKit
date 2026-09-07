//
//  ExerciseMuscleMap.swift
//  Cinder
//
//  Deterministic exercise → muscle activation mapping. Primary movers score
//  1.0, secondaries 0.5; per-workout intensity = Σ(sets × score) per muscle,
//  normalized to the hardest-worked muscle. The on-device LLM is only consulted
//  for names this table can't resolve (see MuscleActivationAI) — the common 95%
//  never pays inference cost and never mislabels a bench press.
//

import Foundation

public enum ExerciseMuscleMap {

    /// Primary (1.0) / secondary (0.5) activation for one exercise, or nil if
    /// the name can't be resolved deterministically.
    public static func activation(for exerciseName: String) -> [MuscleGroup: Double]? {
        let name = normalize(exerciseName)
        if let exact = exactTable[name] { return exact }
        // Plurals ("Bicep Curls", "Face Pulls") → singular exact entries.
        let singular = name
            .components(separatedBy: " ")
            .map { word -> String in
                guard word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") else { return word }
                return String(word.dropLast())
            }
            .joined(separator: " ")
        if let exact = exactTable[singular] { return exact }
        for rule in keywordRules where rule.matches(name) {
            return rule.activation
        }
        return nil
    }

    /// Aggregate a whole workout into per-muscle intensity 0…1.
    /// `resolved` supplies activations for names the table couldn't (AI results);
    /// unresolved exercises are skipped and reported via `unresolved`.
    public static func workoutIntensities(
        exercises: [(name: String, sets: Int)],
        resolved: [String: [MuscleGroup: Double]] = [:]
    ) -> (intensities: [MuscleGroup: Double], unresolved: [String]) {
        var volume: [MuscleGroup: Double] = [:]
        var unresolved: [String] = []

        for exercise in exercises {
            let act = activation(for: exercise.name)
                ?? resolved[normalize(exercise.name)]
            guard let act else {
                unresolved.append(exercise.name)
                continue
            }
            for (muscle, score) in act {
                volume[muscle, default: 0] += Double(exercise.sets) * score
            }
        }

        guard let peak = volume.values.max(), peak > 0 else { return ([:], unresolved) }
        return (volume.mapValues { $0 / peak }, unresolved)
    }

    public static func normalize(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Exact table (normalized names)

    private static let exactTable: [String: [MuscleGroup: Double]] = [
        "bench press": [.chest: 1, .triceps: 0.5, .frontDelts: 0.5],
        "incline bench press": [.chest: 1, .frontDelts: 0.5, .triceps: 0.5],
        "decline bench press": [.chest: 1, .triceps: 0.5],
        "dumbbell bench press": [.chest: 1, .triceps: 0.5, .frontDelts: 0.5],
        "incline db press": [.chest: 1, .frontDelts: 0.5, .triceps: 0.5],
        "incline dumbbell press": [.chest: 1, .frontDelts: 0.5, .triceps: 0.5],
        "push up": [.chest: 1, .triceps: 0.5, .frontDelts: 0.5, .abs: 0.5],
        "chest fly": [.chest: 1, .frontDelts: 0.5],
        "cable fly": [.chest: 1, .frontDelts: 0.5],
        "pec deck": [.chest: 1],
        "dip": [.chest: 1, .triceps: 1, .frontDelts: 0.5],

        "overhead press": [.frontDelts: 1, .sideDelts: 1, .triceps: 0.5, .traps: 0.5],
        "shoulder press": [.frontDelts: 1, .sideDelts: 1, .triceps: 0.5],
        "military press": [.frontDelts: 1, .sideDelts: 1, .triceps: 0.5, .abs: 0.5],
        "arnold press": [.frontDelts: 1, .sideDelts: 1, .triceps: 0.5],
        "lateral raise": [.sideDelts: 1],
        "front raise": [.frontDelts: 1],
        "rear delt fly": [.rearDelts: 1, .upperBack: 0.5],
        "face pull": [.rearDelts: 1, .upperBack: 0.5, .traps: 0.5],
        "upright row": [.sideDelts: 1, .traps: 1, .biceps: 0.5],
        "shrug": [.traps: 1],

        "deadlift": [.lowerBack: 1, .glutes: 1, .hamstrings: 1, .traps: 0.5, .forearms: 0.5, .quads: 0.5, .lats: 0.5],
        "romanian deadlift": [.hamstrings: 1, .glutes: 1, .lowerBack: 0.5],
        "sumo deadlift": [.glutes: 1, .quads: 1, .hamstrings: 0.5, .lowerBack: 0.5],
        "rack pull": [.lowerBack: 1, .traps: 1, .glutes: 0.5, .forearms: 0.5],
        "good morning": [.hamstrings: 1, .lowerBack: 1, .glutes: 0.5],
        "back extension": [.lowerBack: 1, .glutes: 0.5, .hamstrings: 0.5],
        "hip thrust": [.glutes: 1, .hamstrings: 0.5],
        "glute bridge": [.glutes: 1, .hamstrings: 0.5],

        "squat": [.quads: 1, .glutes: 1, .hamstrings: 0.5, .lowerBack: 0.5, .abs: 0.5],
        "back squat": [.quads: 1, .glutes: 1, .hamstrings: 0.5, .lowerBack: 0.5],
        "front squat": [.quads: 1, .glutes: 0.5, .abs: 0.5, .upperBack: 0.5],
        "goblet squat": [.quads: 1, .glutes: 0.5, .abs: 0.5],
        "hack squat": [.quads: 1, .glutes: 0.5],
        "leg press": [.quads: 1, .glutes: 0.5, .hamstrings: 0.5],
        "lunge": [.quads: 1, .glutes: 1, .hamstrings: 0.5],
        "bulgarian split squat": [.quads: 1, .glutes: 1, .hamstrings: 0.5],
        "step up": [.quads: 1, .glutes: 1],
        "leg extension": [.quads: 1],
        "leg curl": [.hamstrings: 1],
        "calf raise": [.calves: 1],
        "seated calf raise": [.calves: 1],

        "pull up": [.lats: 1, .biceps: 0.5, .upperBack: 0.5, .forearms: 0.5],
        "chin up": [.lats: 1, .biceps: 1, .upperBack: 0.5],
        "lat pulldown": [.lats: 1, .biceps: 0.5, .upperBack: 0.5],
        "barbell row": [.lats: 1, .upperBack: 1, .biceps: 0.5, .rearDelts: 0.5, .lowerBack: 0.5],
        "bent over row": [.lats: 1, .upperBack: 1, .biceps: 0.5, .rearDelts: 0.5, .lowerBack: 0.5],
        "dumbbell row": [.lats: 1, .upperBack: 0.5, .biceps: 0.5],
        "cable row": [.lats: 1, .upperBack: 1, .biceps: 0.5],
        "seated cable row": [.lats: 1, .upperBack: 1, .biceps: 0.5],
        "t bar row": [.lats: 1, .upperBack: 1, .biceps: 0.5],
        "pendlay row": [.lats: 1, .upperBack: 1, .lowerBack: 0.5],
        "pullover": [.lats: 1, .chest: 0.5, .triceps: 0.5],

        "bicep curl": [.biceps: 1, .forearms: 0.5],
        "barbell curl": [.biceps: 1, .forearms: 0.5],
        "dumbbell curl": [.biceps: 1, .forearms: 0.5],
        "hammer curl": [.biceps: 1, .forearms: 1],
        "preacher curl": [.biceps: 1],
        "concentration curl": [.biceps: 1],
        "cable curl": [.biceps: 1, .forearms: 0.5],
        "wrist curl": [.forearms: 1],
        "reverse curl": [.forearms: 1, .biceps: 0.5],
        "farmer carry": [.forearms: 1, .traps: 1, .abs: 0.5],

        "tricep extension": [.triceps: 1],
        "overhead tricep extension": [.triceps: 1],
        "skull crusher": [.triceps: 1],
        "tricep pushdown": [.triceps: 1],
        "cable pushdown": [.triceps: 1],
        "close grip bench press": [.triceps: 1, .chest: 0.5, .frontDelts: 0.5],
        "kickback": [.triceps: 1],

        "crunch": [.abs: 1],
        "sit up": [.abs: 1],
        "plank": [.abs: 1, .obliques: 0.5, .lowerBack: 0.5],
        "side plank": [.obliques: 1, .abs: 0.5],
        "russian twist": [.obliques: 1, .abs: 0.5],
        "leg raise": [.abs: 1],
        "hanging leg raise": [.abs: 1, .obliques: 0.5, .forearms: 0.5],
        "ab wheel": [.abs: 1, .obliques: 0.5, .lats: 0.5],
        "cable woodchop": [.obliques: 1, .abs: 0.5],
        "dead bug": [.abs: 1],
        "mountain climber": [.abs: 1, .obliques: 0.5, .quads: 0.5],

        "clean": [.glutes: 1, .hamstrings: 1, .traps: 1, .quads: 0.5, .lowerBack: 0.5],
        "power clean": [.glutes: 1, .hamstrings: 1, .traps: 1, .quads: 0.5, .lowerBack: 0.5],
        "snatch": [.glutes: 1, .hamstrings: 1, .traps: 1, .sideDelts: 0.5, .lowerBack: 0.5],
        "kettlebell swing": [.glutes: 1, .hamstrings: 1, .lowerBack: 0.5, .abs: 0.5],
        "thruster": [.quads: 1, .glutes: 1, .frontDelts: 1, .triceps: 0.5],
        "burpee": [.chest: 0.5, .quads: 0.5, .abs: 0.5, .triceps: 0.5],
    ]

    // MARK: - Keyword fallback rules (checked in order)

    private struct Rule {
        let all: [String]          // every keyword must appear as a word
        let activation: [MuscleGroup: Double]

        /// Keywords match whole words, not substrings: "machine" must not
        /// trigger the chin-up rule and "cable" must not trigger the ab rule.
        /// A word matches a keyword when it is the keyword, a plural of it,
        /// or (for keywords of four or more letters) starts with it, which
        /// keeps "triceps", "hamstrings" and "pullups" resolving. Multi-word
        /// rules also accept their keywords run together as one word.
        func matches(_ name: String) -> Bool {
            let words = name.split(separator: " ").map(String.init)
            if all.allSatisfy({ keyword in words.contains { Rule.word($0, matches: keyword) } }) {
                return true
            }
            return all.count > 1 && words.contains { Rule.word($0, matches: all.joined()) }
        }

        static func word(_ word: String, matches keyword: String) -> Bool {
            if word == keyword || word == keyword + "s" || word == keyword + "es" { return true }
            if keyword.hasSuffix("y"), word == keyword.dropLast() + "ies" { return true }
            if keyword.hasSuffix("f"), word == keyword.dropLast() + "ves" { return true }
            return keyword.count >= 4 && word.hasPrefix(keyword)
        }
    }

    private static let keywordRules: [Rule] = [
        // Specific compounds first — generic single words last.
        Rule(all: ["romanian"], activation: [.hamstrings: 1, .glutes: 1, .lowerBack: 0.5]),
        Rule(all: ["incline", "press"], activation: [.chest: 1, .frontDelts: 0.5, .triceps: 0.5]),
        Rule(all: ["bench"], activation: [.chest: 1, .triceps: 0.5, .frontDelts: 0.5]),
        Rule(all: ["chest", "press"], activation: [.chest: 1, .triceps: 0.5]),
        Rule(all: ["shoulder", "press"], activation: [.frontDelts: 1, .sideDelts: 1, .triceps: 0.5]),
        Rule(all: ["overhead", "press"], activation: [.frontDelts: 1, .sideDelts: 1, .triceps: 0.5]),
        Rule(all: ["lateral"], activation: [.sideDelts: 1]),
        Rule(all: ["rear", "delt"], activation: [.rearDelts: 1, .upperBack: 0.5]),
        Rule(all: ["reverse", "fly"], activation: [.rearDelts: 1, .upperBack: 0.5]),
        Rule(all: ["fly"], activation: [.chest: 1, .frontDelts: 0.5]),
        Rule(all: ["shrug"], activation: [.traps: 1]),
        Rule(all: ["pulldown"], activation: [.lats: 1, .biceps: 0.5]),
        Rule(all: ["pull", "up"], activation: [.lats: 1, .biceps: 0.5, .upperBack: 0.5]),
        Rule(all: ["chin"], activation: [.lats: 1, .biceps: 1]),
        Rule(all: ["row"], activation: [.lats: 1, .upperBack: 1, .biceps: 0.5]),
        Rule(all: ["deadlift"], activation: [.lowerBack: 1, .glutes: 1, .hamstrings: 1, .traps: 0.5]),
        Rule(all: ["hip", "thrust"], activation: [.glutes: 1, .hamstrings: 0.5]),
        Rule(all: ["glute"], activation: [.glutes: 1]),
        Rule(all: ["squat"], activation: [.quads: 1, .glutes: 1, .hamstrings: 0.5]),
        Rule(all: ["lunge"], activation: [.quads: 1, .glutes: 1, .hamstrings: 0.5]),
        Rule(all: ["leg", "press"], activation: [.quads: 1, .glutes: 0.5, .hamstrings: 0.5]),
        Rule(all: ["leg", "extension"], activation: [.quads: 1]),
        Rule(all: ["leg", "curl"], activation: [.hamstrings: 1]),
        Rule(all: ["hamstring"], activation: [.hamstrings: 1]),
        Rule(all: ["calf"], activation: [.calves: 1]),
        Rule(all: ["wrist"], activation: [.forearms: 1]),
        Rule(all: ["hammer", "curl"], activation: [.biceps: 1, .forearms: 1]),
        Rule(all: ["curl"], activation: [.biceps: 1, .forearms: 0.5]),
        Rule(all: ["tricep"], activation: [.triceps: 1]),
        Rule(all: ["skull"], activation: [.triceps: 1]),
        Rule(all: ["pushdown"], activation: [.triceps: 1]),
        Rule(all: ["back", "extension"], activation: [.lowerBack: 1, .glutes: 0.5, .hamstrings: 0.5]),
        Rule(all: ["hyperextension"], activation: [.lowerBack: 1, .glutes: 0.5, .hamstrings: 0.5]),
        Rule(all: ["leg", "raise"], activation: [.abs: 1]),
        Rule(all: ["extension"], activation: [.triceps: 1]),   // after leg/back extension rules
        Rule(all: ["dip"], activation: [.chest: 1, .triceps: 1]),
        Rule(all: ["push", "up"], activation: [.chest: 1, .triceps: 0.5, .abs: 0.5]),
        Rule(all: ["press"], activation: [.chest: 1, .triceps: 0.5, .frontDelts: 0.5]),
        Rule(all: ["crunch"], activation: [.abs: 1]),
        Rule(all: ["plank"], activation: [.abs: 1, .obliques: 0.5]),
        Rule(all: ["oblique"], activation: [.obliques: 1]),
        Rule(all: ["twist"], activation: [.obliques: 1, .abs: 0.5]),
        Rule(all: ["ab"], activation: [.abs: 1]),
        Rule(all: ["core"], activation: [.abs: 1, .obliques: 0.5]),
        Rule(all: ["swing"], activation: [.glutes: 1, .hamstrings: 1, .lowerBack: 0.5]),
        Rule(all: ["carry"], activation: [.forearms: 1, .traps: 1, .abs: 0.5]),
        Rule(all: ["raise"], activation: [.frontDelts: 1]),
    ]
}
