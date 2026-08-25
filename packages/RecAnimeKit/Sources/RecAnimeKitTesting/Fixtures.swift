import Foundation

/// Golden API responses exported by the Go test-suite (services/api/testdata/golden).
/// Regenerate with `UPDATE_GOLDEN=1 pnpm api:test:it` and copy with `pnpm fixtures:sync`.
public enum Fixtures {
    public static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    public enum FixtureError: Error {
        case missing(String)
    }
}
