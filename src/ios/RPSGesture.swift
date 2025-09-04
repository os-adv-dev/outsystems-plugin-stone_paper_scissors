//
//  RPSGesture.swift
//  PedraPapelTesoura
//  By André Grillo
//

import UIKit
import AVFoundation
import MediaPipeTasksVision
//import MorphingLabel

// MARK: - Gesture Types
enum RPSGesture: String, CaseIterable {
    case rock = "Rock"
    case paper = "Paper"
    case scissors = "Scissors"
    case unknown = "Unknown"

    var color: UIColor {
        switch self {
        case .rock:     return .systemRed
        case .paper:    return .systemGreen
        case .scissors: return .systemBlue
        case .unknown:  return .systemGray
        }
    }
}

// MARK: - Detection Result
struct HandDetection {
    let gesture: RPSGesture
    let boundingBox: CGRect   // screen-layer coords (not needed for drawing, but ok for logs)
    let landmarks: [NormalizedLandmark]
    let handedness: String
    let confidence: Float
}

// ===== Angle helpers (mirror/rotation-proof) =====
private func angleDeg(_ a: NormalizedLandmark,
                      _ b: NormalizedLandmark,
                      _ c: NormalizedLandmark) -> CGFloat {
    let ab = CGPoint(x: CGFloat(a.x - b.x), y: CGFloat(a.y - b.y))
    let cb = CGPoint(x: CGFloat(c.x - b.x), y: CGFloat(c.y - b.y))
    let dot = ab.x * cb.x + ab.y * cb.y
    let mag = hypot(ab.x, ab.y) * hypot(cb.x, cb.y)
    guard mag > 0 else { return 0 }
    let cosv = max(min(dot / mag, 1), -1)
    return acos(cosv) * 180 / .pi
}

private func isFingerExtended(mcp: Int, pip: Int, dip: Int,
                              landmarks l: [NormalizedLandmark],
                              straightThreshold: CGFloat = 160) -> Bool {
    angleDeg(l[mcp], l[pip], l[dip]) >= straightThreshold
}

private func isThumbExtended(mcp: Int, ip: Int, tip: Int,
                             landmarks l: [NormalizedLandmark],
                             straightThreshold: CGFloat = 160) -> Bool {
    angleDeg(l[mcp], l[ip], l[tip]) >= straightThreshold
}

// MARK: - Main VC
class RPSDetectionViewController: UIViewController {

    // MARK: - IBOutlets
    @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var handImage: UIImageView!
    @IBOutlet weak var player1Label: UILabel!
    @IBOutlet weak var player2Label: UILabel!
    //@IBOutlet weak var winnerLabel: UILabel!
    @IBOutlet weak var winnerLabel: UILabel!
    @IBOutlet weak var instructionsLabel: UILabel!

    // MARK: - Camera
    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var videoOutput: AVCaptureVideoDataOutput!
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private var lastFrameSize: CGSize = .zero
    private var isMirrored: Bool = false
    private var videoOrientation: AVCaptureVideoOrientation = .portrait

    // MARK: - MediaPipe
    private var handLandmarker: HandLandmarker!
    private let backgroundQueue = DispatchQueue(label: "hand.detection")

    // MARK: - Drawing
    private var lastDetections: [HandDetection] = []
    private var detectionOverlayView: UIView!
    // Background view for player labels (persist between UI updates)
    private var playersBgView: UIView?

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        UIApplication.shared.isIdleTimerDisabled = true
        setupUI()
        setupMediaPipe()
        setupCamera()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startCameraSession()
        updateConnectionsForCurrentInterfaceOrientation()
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopCameraSession()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = previewView.bounds
        detectionOverlayView.frame = previewView.bounds
    }

    // MARK: - Setup
    private func setupUI() {
        // 1. Create players' background view if needed
        if self.playersBgView == nil {
            let bgView = UIView()
            bgView.backgroundColor = UIColor.black.withAlphaComponent(0.3)
            bgView.translatesAutoresizingMaskIntoConstraints = false
            self.playersBgView = bgView
            self.playersBgView?.isHidden = true
            self.player1Label.isHidden = true
            self.player2Label.isHidden = true

            if let superview = self.player1Label.superview {
                superview.insertSubview(bgView, belowSubview: self.player1Label)
            }

            NSLayoutConstraint.activate([
                bgView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                bgView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                bgView.topAnchor.constraint(equalTo: self.player1Label.topAnchor, constant: -20),
                bgView.bottomAnchor.constraint(equalTo: self.player2Label.bottomAnchor, constant: 6)
            ])
        } else if self.playersBgView?.superview == nil {
            // If view exists but was removed (shouldn't happen), re-add.
            if let bgView = self.playersBgView, let superview = self.player1Label.superview {
                superview.insertSubview(bgView, belowSubview: self.player1Label)
            }
        }
        
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.6)
        shadow.shadowOffset = CGSize(width: 1, height: 1)
        shadow.shadowBlurRadius = 2

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "MarkerFelt-Bold", size: 26) ?? UIFont.systemFont(ofSize: 26),
            .foregroundColor: UIColor.white,           // Cor do preenchimento do texto
//            .strokeColor: UIColor.white,                   // Cor da borda (stroke)
//            .strokeWidth: -2.0,                            // Espessura da borda (-2.0 mantém o preenchimento)
            .shadow: shadow
        ]
        
        let attributesPlayers: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "RockWell-Bold", size: 24) ?? UIFont.systemFont(ofSize: 24),
            .foregroundColor: UIColor.white,           // Cor do preenchimento do texto
            .strokeColor: UIColor.black,                   // Cor da borda (stroke)
            .strokeWidth: -2.0,                            // Espessura da borda (-2.0 mantém o preenchimento)
            .shadow: shadow
        ]

        let instructionText = "Show your hands to play Rock, Paper, and Scissors!"
        instructionsLabel.attributedText = NSAttributedString(string: instructionText, attributes: attributes)
        
        self.handImage.alpha = 1
        self.handImage.isHidden = false
        
        // Create the highlight view (rectangle)
        let instructionsBgHighlight = UIView()
        instructionsBgHighlight.alpha = 1
        instructionsBgHighlight.isHidden = false
        instructionsBgHighlight.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        instructionsBgHighlight.translatesAutoresizingMaskIntoConstraints = false

        // Add bgHighlight and instructionsLabel to same superview
        // Ensure bgHighlight is behind the label
        instructionsLabel.superview?.addSubview(instructionsBgHighlight)
        instructionsLabel.superview?.bringSubviewToFront(instructionsLabel) // force it in front

        // Set constraints relative to the label
        NSLayoutConstraint.activate([
            instructionsBgHighlight.leadingAnchor.constraint(equalTo: instructionsLabel.leadingAnchor, constant: -12),
            instructionsBgHighlight.trailingAnchor.constraint(equalTo: instructionsLabel.trailingAnchor, constant: 12),
            instructionsBgHighlight.topAnchor.constraint(equalTo: instructionsLabel.topAnchor, constant: -4),
            instructionsBgHighlight.bottomAnchor.constraint(equalTo: instructionsLabel.bottomAnchor, constant: 4)
        ])
        
        player1Label.attributedText = NSAttributedString(string: "Player 1: --", attributes: attributesPlayers)
        player2Label.attributedText = NSAttributedString(string: "Player 2: --", attributes: attributesPlayers)
        
        // Winner label configuration for improved stroke and text truncation
        winnerLabel.numberOfLines = 1
        winnerLabel.lineBreakMode = .byClipping
        winnerLabel.adjustsFontSizeToFitWidth = true
        winnerLabel.minimumScaleFactor = 0.5
        winnerLabel.textAlignment = .center
        winnerLabel.clipsToBounds = false
        winnerLabel.layer.masksToBounds = false
        winnerLabel.attributedText = NSAttributedString(string: "", attributes: [
            .font: UIFont(name: "Rockwell", size: 30) ?? UIFont.systemFont(ofSize: 30),
            .foregroundColor: UIColor.systemRed,
            .strokeColor: UIColor.white,
            .strokeWidth: -2.0,
            .kern: 1.0
        ])

        detectionOverlayView = UIView()
        detectionOverlayView.backgroundColor = .clear
        previewView.addSubview(detectionOverlayView)

//        previewView.layer.cornerRadius = 12
        previewView.layer.masksToBounds = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            UIView.animate(withDuration: 1.0, animations: {
                self.instructionsLabel.alpha = 0
                instructionsBgHighlight.alpha = 0
                self.handImage.alpha = 0
            }, completion: { _ in
                self.instructionsLabel.isHidden = true
                self.handImage.isHidden = true
                instructionsBgHighlight.isHidden = true
//                self.handImage.alpha = 0
                self.handImage.isHidden = true
                
                self.playersBgView?.isHidden = false
                self.player1Label.isHidden = false
                self.player2Label.isHidden = false
            })
        }
    }

    private func setupMediaPipe() {
        guard let modelPath = Bundle.main.path(forResource: "hand_landmarker", ofType: "task") else {
            fatalError("❌ Missing hand_landmarker.task in bundle.")
        }
        do {
            let opts = HandLandmarkerOptions()
            opts.baseOptions.modelAssetPath = modelPath
            opts.runningMode = .liveStream
            opts.numHands = 2
            opts.minHandDetectionConfidence = 0.7
            opts.minHandPresenceConfidence = 0.7
            opts.minTrackingConfidence = 0.5
            opts.handLandmarkerLiveStreamDelegate = self
            handLandmarker = try HandLandmarker(options: opts)
        } catch {
            fatalError("❌ Failed to create HandLandmarker: \(error)")
        }
    }

    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device)
        else {
            print("❌ Failed to get front camera")
            return
        }
        if captureSession.canAddInput(input) { captureSession.addInput(input) }

        videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        if captureSession.canAddOutput(videoOutput) { captureSession.addOutput(videoOutput) }

        // Preview layer
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewView.layer.insertSublayer(previewLayer, at: 0)

        // Align connections with current UI orientation
        updateConnectionsForCurrentInterfaceOrientation()
    }

    private func currentVideoOrientation() -> AVCaptureVideoOrientation {
        if let io = view.window?.windowScene?.interfaceOrientation {
            switch io {
            case .portrait: return .portrait
            case .portraitUpsideDown: return .portraitUpsideDown
            case .landscapeLeft: return .landscapeLeft
            case .landscapeRight: return .landscapeRight
            default: break
            }
        }
        return .portrait
    }

    private func updateConnectionsForCurrentInterfaceOrientation() {
        let vo = currentVideoOrientation()

        // Preview layer: set orientation + mirror for selfie feel
        if let layerConn = previewLayer?.connection {
            layerConn.videoOrientation = vo
            layerConn.automaticallyAdjustsVideoMirroring = false
            layerConn.isVideoMirrored = true     // mirror ONLY the preview
        }

        // Video output: do NOT mirror; MediaPipe wants real (unmirrored) frames
        if let outConn = videoOutput?.connection(with: .video) {
            outConn.videoOrientation = vo
            outConn.automaticallyAdjustsVideoMirroring = false
            outConn.isVideoMirrored = false
        }
    }

    private func startCameraSession() { sessionQueue.async { [weak self] in self?.captureSession.startRunning() } }
    private func stopCameraSession()  { sessionQueue.async { [weak self] in self?.captureSession.stopRunning() } }

    // MARK: - Gesture classification (rotation-invariant via angles)
    private func classifyGesture(from lm: [NormalizedLandmark]) -> RPSGesture {
        guard lm.count >= 21 else { return .unknown }
        let thumb   = isThumbExtended(mcp: 2,  ip: 3,  tip: 4,  landmarks: lm)
        let index   = isFingerExtended(mcp: 5,  pip: 6,  dip: 7,  landmarks: lm)
        let middle  = isFingerExtended(mcp: 9,  pip:10,  dip:11, landmarks: lm)
        let ring    = isFingerExtended(mcp:13,  pip:14,  dip:15, landmarks: lm)
        let pinky   = isFingerExtended(mcp:17,  pip:18,  dip:19, landmarks: lm)

        if index && middle && !ring && !pinky { return .scissors }
        let straight = [thumb, index, middle, ring, pinky].filter { $0 }.count
        if straight >= 4 { return .paper }
        if straight <= 1 { return .rock }
        return .unknown
    }

    // ---- Orientation-aware denormalization ----
    private func denorm(_ p: CGPoint, to imageSize: CGSize, orientation: AVCaptureVideoOrientation) -> CGPoint {
        let w = imageSize.width, h = imageSize.height
        switch orientation {
        case .portrait:
            // x right, y down (no swap)
            return CGPoint(x: p.x * w, y: p.y * h)

        case .landscapeRight:
            // Device held with the Lightning port on the LEFT (common selfie landscape)
            // Match your observed mapping: right→down, up→left
            // x' comes from original y, y' comes from original x (no inversion)
            return CGPoint(x: p.y * w, y: p.x * h)

        case .landscapeLeft:
            // Opposite landscape; mirror the above across both axes
            // (If this feels wrong on your device, swap with the variant below in the comment.)
            return CGPoint(x: (1 - p.y) * w, y: (1 - p.x) * h)

            // If your device behaves like landscapeRight instead, use this instead:
            // return CGPoint(x: p.y * w, y: p.x * h)

        case .portraitUpsideDown:
            return CGPoint(x: (1 - p.x) * w, y: (1 - p.y) * h)

        @unknown default:
            return CGPoint(x: p.x * w, y: p.y * h)
        }
    }

    private func getBoundingBox(from landmarks: [NormalizedLandmark],
                                imageSize: CGSize) -> CGRect {
        // Convert each normalized landmark to pixel coords for the current orientation
        let pts: [CGPoint] = landmarks.map {
            denorm(CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)),
                   to: imageSize,
                   orientation: videoOrientation)
        }
        guard
            let minX = pts.map({ $0.x }).min(),
            let maxX = pts.map({ $0.x }).max(),
            let minY = pts.map({ $0.y }).min(),
            let maxY = pts.map({ $0.y }).max()
        else { return .zero }

        let pad: CGFloat = 18
        return CGRect(x: max(0, minX - pad),
                      y: max(0, minY - pad),
                      width: min(imageSize.width,  (maxX - minX) + 2*pad),
                      height: min(imageSize.height, (maxY - minY) + 2*pad))
    }

    // MARK: - Game logic & UI
    private func determineWinner(_ g1: RPSGesture, _ g2: RPSGesture) -> String? {
        if g1 == g2 { return "It's a Tie!" }
        switch (g1, g2) {
        case (.rock, .scissors), (.paper, .rock), (.scissors, .paper): return "Player 1 Wins!"
        case (.scissors, .rock), (.rock, .paper), (.paper, .scissors): return "Player 2 Wins!"
        default: return nil
        }
    }

    private func updateUI(with detections: [HandDetection]) {
        // Sort detections left-to-right before assigning players
        let sortedDetections = detections.sorted { a, b in
            let ra = a.boundingBox.isEmpty ? self.layerRect(for: a.landmarks) : a.boundingBox
            let rb = b.boundingBox.isEmpty ? self.layerRect(for: b.landmarks) : b.boundingBox
            return ra.minX < rb.minX
        }
        
        DispatchQueue.main.async {
            // Winner label attributes for stroke and spacing
            let attributesWinner: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Rockwell-Bold", size: 30) ?? UIFont.systemFont(ofSize: 30),
                .foregroundColor: UIColor.white,
                .strokeColor: UIColor.black,
                .strokeWidth: -2.0,
                .kern: 1.0
            ]
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.6)
            shadow.shadowOffset = CGSize(width: 1, height: 1)
            shadow.shadowBlurRadius = 2
            let attributesPlayers: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "RockWell-Bold", size: 24) ?? UIFont.systemFont(ofSize: 24),
                .foregroundColor: UIColor.white,
                .strokeColor: UIColor.black,
                .strokeWidth: -2.0,
                .shadow: shadow
            ]

            self.clearOverlays()
            self.drawDetections(detections)

            if sortedDetections.count >= 2 {
                let p1 = sortedDetections[0], p2 = sortedDetections[1]
                self.player1Label.attributedText = NSAttributedString(string: "Player 1: \(p1.gesture.rawValue)", attributes: attributesPlayers)
                self.player2Label.attributedText = NSAttributedString(string: "Player 2: \(p2.gesture.rawValue)", attributes: attributesPlayers)
                if let win = self.determineWinner(p1.gesture, p2.gesture) {
//                    self.winnerLabel.morphingEffect = .fall
                    self.winnerLabel.attributedText = NSAttributedString(string: win, attributes: attributesWinner)
                } else {
                    self.winnerLabel.attributedText = NSAttributedString(string: "", attributes: attributesWinner)
                }
            } else if sortedDetections.count == 1 {
                self.player1Label.attributedText = NSAttributedString(string: "Player 1: \(sortedDetections[0].gesture.rawValue)", attributes: attributesPlayers)
                self.player2Label.attributedText = NSAttributedString(string: "Player 2: Waiting...", attributes: attributesPlayers)
                self.winnerLabel.attributedText = NSAttributedString(string: "", attributes: attributesWinner)
            } else {
                self.player1Label.attributedText = NSAttributedString(string: "Player 1: --", attributes: attributesPlayers)
                self.player2Label.attributedText = NSAttributedString(string: "Player 2: --", attributes: attributesPlayers)
                self.winnerLabel.attributedText = NSAttributedString(string: "", attributes: attributesWinner)
            }
        }
    }

    private func clearOverlays() { detectionOverlayView.subviews.forEach { $0.removeFromSuperview() } }

    private func drawDetections(_ detections: [HandDetection]) {
        guard previewLayer != nil else { return }

        // left→right on screen
        let sorted = detections.sorted { a, b in
            let ra = a.boundingBox.isEmpty ? layerRect(for: a.landmarks) : a.boundingBox
            let rb = b.boundingBox.isEmpty ? layerRect(for: b.landmarks) : b.boundingBox
            return ra.minX < rb.minX
        }

        for (idx, det) in sorted.enumerated() {
            let rectOnLayer = det.boundingBox.isEmpty ? layerRect(for: det.landmarks) : det.boundingBox
            guard rectOnLayer.width > 0, rectOnLayer.height > 0 else { continue }

            // Box
            let box = UIView(frame: rectOnLayer)
            box.backgroundColor = .clear
            box.layer.borderColor = det.gesture.color.cgColor
            box.layer.borderWidth = 3
            box.layer.cornerRadius = 8
            detectionOverlayView.addSubview(box)

            // Label
            let pct = Int(round(Double(det.confidence) * 100))
            let label = UILabel()
            label.text = "P\(idx+1): \(det.handedness) \(det.gesture.rawValue) (\(pct)%)"
            label.textColor = .white
            label.backgroundColor = det.gesture.color.withAlphaComponent(0.85)
            label.font = .boldSystemFont(ofSize: 14)
            label.textAlignment = .center
            label.layer.cornerRadius = 4
            label.layer.masksToBounds = true
            label.sizeToFit()
            label.frame.size.width += 16
            label.frame.size.height += 6

            var labelFrame = label.frame
            labelFrame.origin.x = rectOnLayer.midX - labelFrame.width / 2
            labelFrame.origin.y = max(0, rectOnLayer.minY - labelFrame.height - 4)
            label.frame = labelFrame

            detectionOverlayView.addSubview(label)
        }
    }

    /// Map rect in **image pixels** to preview coords (handles `.resizeAspectFill` and mirroring).
    private func convertImageRectToPreview(_ r: CGRect,
                                           imageSize: CGSize,
                                           previewBounds: CGRect,
                                           mirrored: Bool) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = max(previewBounds.width / imageSize.width,
                        previewBounds.height / imageSize.height)

        let scaledW = imageSize.width * scale
        let scaledH = imageSize.height * scale

        let dx = (previewBounds.width  - scaledW) / 2.0
        let dy = (previewBounds.height - scaledH) / 2.0

        var x = r.origin.x * scale + dx
        let y = r.origin.y * scale + dy
        let w = r.size.width  * scale
        let h = r.size.height * scale

        if mirrored {
            x = previewBounds.width - (x + w)
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    // Rotation handling
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.updateConnectionsForCurrentInterfaceOrientation()
            self.previewLayer?.frame = self.previewView.bounds
            self.detectionOverlayView.frame = self.previewView.bounds
        })
    }

    // MARK: - Actions
    @IBAction func resetGame(_ sender: UIButton) {
        lastDetections.removeAll()
        clearOverlays()
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.6)
        shadow.shadowOffset = CGSize(width: 1, height: 1)
        shadow.shadowBlurRadius = 2
        let attributesPlayers: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "RockWell-Bold", size: 24) ?? UIFont.systemFont(ofSize: 24),
            .foregroundColor: UIColor.white,
            .strokeColor: UIColor.black,
            .strokeWidth: -2.0,
            .shadow: shadow
        ]
        player1Label.attributedText = NSAttributedString(string: "Player 1: --", attributes: attributesPlayers)
        player2Label.attributedText = NSAttributedString(string: "Player 2: --", attributes: attributesPlayers)
        let attributesWinner: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Rockwell", size: 30) ?? UIFont.systemFont(ofSize: 30),
            .foregroundColor: UIColor.systemRed,
            .strokeColor: UIColor.white,
            .strokeWidth: -2.0,
            .kern: 1.0
        ]
        winnerLabel.attributedText = NSAttributedString(string: "", attributes: attributesWinner)
    }
    
    /// Build a tight bounding box on the *preview layer* by converting each landmark
    /// from normalized capture space into layer points. This handles orientation,
    /// aspectFill, and mirroring for us.
    private func layerRect(for landmarks: [NormalizedLandmark]) -> CGRect {
        guard let pl = previewLayer else { return .zero }

        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for lm in landmarks {
            // MediaPipe gives normalized (0..1) with origin at top-left of the image.
            // Convert directly to layer coordinates:
            let layerPt = pl.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: CGFloat(lm.x),
                                                                                 y: CGFloat(lm.y)))
            minX = min(minX, layerPt.x)
            minY = min(minY, layerPt.y)
            maxX = max(maxX, layerPt.x)
            maxY = max(maxY, layerPt.y)
        }

        if !minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite { return .zero }

        // Pad the box a bit in *screen points*
        let pad: CGFloat = 10
        var r = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        r = r.insetBy(dx: -pad, dy: -pad)
        return r
    }
    @IBAction func switchCamera(_ sender: UIButton) { /* optional later */ }
}

// MARK: - Capture Output
extension RPSDetectionViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrameSize = CGSize(width: CVPixelBufferGetWidth(pb),
                               height: CVPixelBufferGetHeight(pb))
        
//        if #available(iOS 13.0, *), previewLayer?.connection != nil {
//            print("📸 frame \(Int(lastFrameSize.width))x\(Int(lastFrameSize.height))  orient=\(videoOrientation.rawValue)  mirrored=\(isMirrored)")
//        }

        guard let mpImage = try? MPImage(sampleBuffer: sampleBuffer) else { return }

        let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let ms = Int(CMTimeGetSeconds(ts) * 1000)

        backgroundQueue.async { [weak self] in
            do { try self?.handLandmarker.detectAsync(image: mpImage, timestampInMilliseconds: ms) }
            catch { print("❌ Hand detection error:", error) }
        }
    }
}

// MARK: - MediaPipe Delegate
extension RPSDetectionViewController: HandLandmarkerLiveStreamDelegate {
    func handLandmarker(_ handLandmarker: HandLandmarker,
                        didFinishDetection result: HandLandmarkerResult?,
                        timestampInMilliseconds: Int,
                        error: Error?) {

        guard let result = result else {
            if let error { print("❌ HandLandmarker error:", error) }
            return
        }

        var out: [HandDetection] = []
        let landmarks = result.landmarks
        let handedness = result.handedness

        // Build detections
        for i in 0..<landmarks.count {
            let lms = landmarks[i]
            let info = handedness.count > i ? handedness[i] : []
            let handLabel = info.first?.categoryName ?? "Unknown"
            let score     = info.first?.score ?? 0.0

            let gesture = classifyGesture(from: lms)

            // 👉 compute *screen* rect once (uses previewLayer mapping)
            //    Do this on main to be safe with layer access.
            var screenRect: CGRect = .zero
            DispatchQueue.main.sync {
                screenRect = self.layerRect(for: lms)
            }

            let pct = Int(round(Double(score) * 100))
            print("👉 Hand \(i): \(handLabel)  \(gesture.rawValue)  hand=\(pct)%  box=\(Int(screenRect.origin.x)),\(Int(screenRect.origin.y)),\(Int(screenRect.width)),\(Int(screenRect.height))")

            out.append(HandDetection(gesture: gesture,
                                     boundingBox: screenRect,
                                     landmarks: lms,
                                     handedness: handLabel,
                                     confidence: score))
        }

        // Draw/update
        lastDetections = out
        updateUI(with: out)
    }
}

extension RPSDetectionViewController {
    static func instantiateFromStoryboard() -> RPSDetectionViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
        guard let vc = storyboard.instantiateViewController(withIdentifier: "RPSDetectionViewController") as? RPSDetectionViewController else {
            fatalError("❌ Could not instantiate RPSDetectionViewController from storyboard.")
        }
        return vc
    }
}
