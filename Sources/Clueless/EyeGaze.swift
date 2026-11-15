import Foundation
import Vision

/// Where the eyes point, estimated from Apple Vision face landmarks (not a language model).
/// Since T48 the look-away trigger uses it too (Presence.swift), unless "Count eye direction as looking
/// away" is off or CLUELESS_EYES=0. The camera window's tracking view shows the numbers.
/// The estimate is rough: it compares each pupil with the outline of its eye, so it says "the eyes are
/// turned left / right / up / down within the eye", not what point on the screen is being looked at.
struct EyeGaze {
    /// Eye outlines and pupils in Vision picture coordinates (0 to 1, origin at the bottom left).
    /// "Left" and "right" are the person's own left and right, as Vision names them.
    var leftEye: [CGPoint] = []
    var rightEye: [CGPoint] = []
    var leftPupil: CGPoint?
    var rightPupil: CGPoint?
    /// Pupil position inside the eye, mean of both eyes. -1 = at the edge towards the left of the
    /// picture, 0 = centred, +1 = at the edge towards the right of the picture.
    var horizontal: Double?
    /// -1 = bottom of the eye opening, 0 = centred, +1 = top. Noisy: the eyelids follow the pupil.
    var vertical: Double?
    /// Eye height divided by eye width, mean of both eyes. Small means closed.
    var openness: Double?

    // Starting values, never tuned: guesses. The camera window's tracking view shows the live numbers;
    // CLUELESS_EYE_H and CLUELESS_EYE_V override the two limits without a rebuild.
    static let defaultHorizontalLimit = 0.35
    static let defaultVerticalLimit = 0.60
    static let horizontalLimit = EyeGaze.limit("CLUELESS_EYE_H", EyeGaze.defaultHorizontalLimit)
    static let verticalLimit = EyeGaze.limit("CLUELESS_EYE_V", EyeGaze.defaultVerticalLimit)
    static let closedBelow = 0.15

    private static func limit(_ name: String, _ fallback: Double) -> Double {
        guard let raw = ProcessInfo.processInfo.environment[name], let value = Double(raw), value > 0 else {
            return fallback
        }
        return value
    }

    enum Verdict: Equatable { case onScreen, sideways, upOrDown, closed, unknown }

    /// True only when the eyes are open and turned away from the screen. Closed eyes (a blink) and
    /// eyes that were not found are NOT "looking away": the head-only rule decides those frames (T48).
    var lookingAway: Bool { verdict == .sideways || verdict == .upOrDown }

    var verdict: Verdict {
        guard let openness else { return .unknown }
        if openness < EyeGaze.closedBelow { return .closed }
        guard let horizontal else { return .unknown }
        if abs(horizontal) > EyeGaze.horizontalLimit { return .sideways }
        if let vertical, abs(vertical) > EyeGaze.verticalLimit { return .upOrDown }
        return .onScreen
    }

    /// Runs Vision's landmark detection on one face that was already found. Returns nil when Vision
    /// gives no landmarks. Costs one more Vision request per analysed frame (about 3 a second).
    static func measure(face: VNFaceObservation, in pixels: CVPixelBuffer) -> EyeGaze? {
        let request = VNDetectFaceLandmarksRequest()
        request.inputFaceObservations = [face]
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil,
              let found = request.results?.first, let landmarks = found.landmarks else { return nil }
        let box = found.boundingBox
        // Landmark points are relative to the face box; move them into picture coordinates.
        func inPicture(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            (region?.normalizedPoints ?? []).map {
                CGPoint(x: box.minX + $0.x * box.width, y: box.minY + $0.y * box.height)
            }
        }
        var gaze = EyeGaze()
        gaze.leftEye = inPicture(landmarks.leftEye)
        gaze.rightEye = inPicture(landmarks.rightEye)
        gaze.leftPupil = inPicture(landmarks.leftPupil).first
        gaze.rightPupil = inPicture(landmarks.rightPupil).first

        // Measure in pixels: the picture is not square, so 0-to-1 units differ between x and y.
        let width = Double(CVPixelBufferGetWidth(pixels)), height = Double(CVPixelBufferGetHeight(pixels))
        var horizontals: [Double] = [], verticals: [Double] = [], opennesses: [Double] = []
        for (outline, pupil) in [(gaze.leftEye, gaze.leftPupil), (gaze.rightEye, gaze.rightPupil)] {
            guard outline.count >= 4, let pupil else { continue }
            let xs = outline.map { Double($0.x) * width }, ys = outline.map { Double($0.y) * height }
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(),
                  maxX - minX > 1 else { continue }
            let eyeWidth = maxX - minX, eyeHeight = maxY - minY
            opennesses.append(eyeHeight / eyeWidth)
            horizontals.append((Double(pupil.x) * width - (minX + maxX) / 2) / (eyeWidth / 2))
            if eyeHeight > 0.5 {
                verticals.append((Double(pupil.y) * height - (minY + maxY) / 2) / (eyeHeight / 2))
            }
        }
        func mean(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        gaze.horizontal = mean(horizontals)
        gaze.vertical = mean(verticals)
        gaze.openness = mean(opennesses)
        return gaze
    }
}
