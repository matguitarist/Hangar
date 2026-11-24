import Foundation

/// A frame rate limit for a Windows game (S-038). DXVK reads DXVK_FRAME_RATE; D3DMetal, DXMT and
/// Wine's own Direct3D have no limit Hangar can set, so the cap applies to DXVK games only.
public enum FrameCap {
    /// The choices: nil is no limit, 0 the display's own rate.
    public static let choices: [Int?] = [nil, 30, 40, 60, 0]

    /// The variables a launch adds for a cap, or none when the game doesn't run with DXVK.
    public static func environment(cap: Int?, backend: GraphicsBackend?, displayRate: Int) -> [String: String] {
        guard let cap, backend == .dxvk else { return [:] }
        let rate = cap == 0 ? displayRate : cap
        return rate > 0 ? ["DXVK_FRAME_RATE": String(rate)] : [:]
    }
}
