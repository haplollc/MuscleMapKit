import XCTest
@testable import MuscleMapKit

/// The mesh and the exercise table are the two things a consumer inherits
/// wholesale, so both are pinned here: a silently missing resource or a
/// renamed muscle would fail at runtime, in 3D, with no error.
final class MuscleMapKitTests: XCTestCase {

    // MARK: - Model

    func testSeventeenMuscleGroupsAreStable() {
        // The baked mesh stores a muscle id per vertex as an index into this
        // exact order. Reordering or inserting a case silently repaints the body.
        XCTAssertEqual(MuscleGroup.allCases.count, 17)
        XCTAssertEqual(MuscleGroup.allCases.map(\.rawValue), [
            "chest", "frontDelts", "sideDelts", "rearDelts", "biceps", "triceps",
            "forearms", "traps", "lats", "upperBack", "lowerBack", "abs",
            "obliques", "glutes", "quads", "hamstrings", "calves",
        ])
    }

    func testEveryGroupHasAReadableName() {
        for group in MuscleGroup.allCases {
            XCTAssertFalse(group.displayName.isEmpty, "\(group.rawValue) has no display name")
        }
    }

    // MARK: - Resource

    func testBakedBodyMeshShipsInThePackageBundle() {
        // Bundle.module, not Bundle.main — the mesh lives in the package, and
        // getting this wrong only shows up as an invisible body at runtime.
        let url = Bundle.module.url(forResource: "body", withExtension: "mesh")
        XCTAssertNotNil(url, "body.mesh missing from the package bundle")
        if let url, let data = try? Data(contentsOf: url) {
            XCTAssertGreaterThan(data.count, 1_000_000, "body.mesh looks truncated")
            XCTAssertEqual(String(bytes: data.prefix(4), encoding: .ascii), "CMB1",
                           "unexpected mesh header — the baker's format changed")
        }
    }

    // MARK: - Mapping

    func testCommonLiftsResolveToMuscles() {
        for lift in ["Bench Press", "Squat", "Deadlift", "Pull Up", "Bicep Curl"] {
            let activation = ExerciseMuscleMap.activation(for: lift)
            XCTAssertNotNil(activation, "\(lift) should be in the table")
            XCTAssertFalse(activation?.isEmpty ?? true, "\(lift) resolved to nothing")
        }
    }

    func testLookupIgnoresCasingAndSpacing() {
        let canonical = ExerciseMuscleMap.activation(for: "Bench Press")
        XCTAssertEqual(ExerciseMuscleMap.activation(for: "bench press"), canonical)
        XCTAssertEqual(ExerciseMuscleMap.activation(for: "  BENCH   PRESS  "), canonical)
    }

    func testUnknownExerciseIsReportedRatherThanGuessed() {
        XCTAssertNil(ExerciseMuscleMap.activation(for: "Zercher Good Morning Jump"))
        let result = ExerciseMuscleMap.workoutIntensities(
            exercises: [("Bench Press", 4), ("Zercher Good Morning Jump", 3)])
        XCTAssertTrue(result.unresolved.contains("Zercher Good Morning Jump"))
        XCTAssertFalse(result.intensities.isEmpty, "the known lift should still count")
    }

    func testKeywordsMatchWholeWordsNotSubstrings() {
        // "machine" contains "chin" and "cable" contains "ab"; neither is a
        // chin-up or an ab exercise. Wrong muscles are worse than no muscles.
        XCTAssertEqual(ExerciseMuscleMap.activation(for: "Leg Press Machine")?[.quads], 1)
        XCTAssertNil(ExerciseMuscleMap.activation(for: "Leg Press Machine")?[.lats])
        XCTAssertNil(ExerciseMuscleMap.activation(for: "Cable Crossover"))
        XCTAssertNil(ExerciseMuscleMap.activation(for: "Hip Abduction"))
        XCTAssertEqual(ExerciseMuscleMap.activation(for: "Chins")?[.biceps], 1)
        XCTAssertEqual(ExerciseMuscleMap.activation(for: "Ab Rollout")?[.abs], 1)
    }

    func testKeywordsStillMatchPluralsCompoundsAndStems() {
        XCTAssertEqual(ExerciseMuscleMap.activation(for: "Pullups")?[.lats], 1)
        XCTAssertEqual(ExerciseMuscleMap.activation(for: "Pushups")?[.chest], 1)
        XCTAssertEqual(ExerciseMuscleMap.activation(for: "Weighted Dips")?[.triceps], 1)
        XCTAssertEqual(ExerciseMuscleMap.activation(for: "Cable Flies")?[.chest], 1)
        XCTAssertEqual(ExerciseMuscleMap.activation(for: "Standing Calves")?[.calves], 1)
        XCTAssertEqual(ExerciseMuscleMap.activation(for: "Rope Triceps Pushdowns")?[.triceps], 1)
        XCTAssertEqual(ExerciseMuscleMap.activation(for: "Suitcase Carries")?[.forearms], 1)
        XCTAssertEqual(ExerciseMuscleMap.activation(for: "Nordic Hamstrings")?[.hamstrings], 1)
    }

    func testIntensitiesAreNormalisedToUnitRange() {
        let result = ExerciseMuscleMap.workoutIntensities(
            exercises: [("Bench Press", 10), ("Squat", 2)])
        for (group, value) in result.intensities {
            XCTAssertGreaterThan(value, 0, "\(group.rawValue) should carry work")
            XCTAssertLessThanOrEqual(value, 1.0, "\(group.rawValue) exceeds 1.0")
        }
    }

    func testMoreVolumeMeansMoreIntensity() {
        // The body shades by how much a muscle actually did, so volume has to
        // move the number monotonically or the visual is meaningless.
        let light = ExerciseMuscleMap.workoutIntensities(exercises: [("Bench Press", 1), ("Squat", 10)])
        let heavy = ExerciseMuscleMap.workoutIntensities(exercises: [("Bench Press", 8), ("Squat", 10)])
        let l = light.intensities[.chest] ?? 0
        let h = heavy.intensities[.chest] ?? 0
        XCTAssertGreaterThan(h, l, "more chest volume should shade the chest harder")
    }
}
