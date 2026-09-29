import UIKit

// swiftlint:disable file_length

// Disclaimer: This is fully based on Vercel prototype.
//             It is intentionally left as is for easier animation copy and replace if it is to change.
//             Only some variable names were changed to comply with linting rules.

// iOS - Confetti (progressive) with Golden / Golden 2 finales + Halo.
// Custom particle system: 180 deterministic particles laid out by a seeded
// RNG. Each attestation signal fires a CONTIGUOUS PREFIX of that layout
// (start..end). Reaching 100% applies the chosen FinaleStyle to the new
// particles AND triggers the radial Halo overlay.
//
// Calibrated for ~10 plays per 2.5 min (multi-round games):
//   Golden 2 lifetime ~= 2.3 s, halo 2.0 s - clears even on clustered rounds.

let fullParticleCount = 180

struct BurstParticle {
    let velocityX: CGFloat
    let velocityY: CGFloat
    var color: UIColor
    var size: CGFloat
    let xRel: CGFloat // 0..1, spawn x across top edge
    let rotation: CGFloat
    let rotSpeed: CGFloat // rad/frame
}

// Mulberry32 - same seed = same layout on every device.
final class SeededRNG {
    private var state: UInt32
    init(_ seed: UInt32 = 42) { state = seed }
    func next() -> Double {
        state &+= 0x6D2B_79F5
        var value = state
        value = (value ^ (value >> 15)) &* (value | 1)
        value ^= value &+ ((value ^ (value >> 7)) &* (value | 61))
        return Double(value ^ (value >> 14)) / 4_294_967_296.0
    }
}

func makeBurstLayout() -> [BurstParticle] {
    let confettiColors: [UIColor] = .confettiPalette
    let rng = SeededRNG()
    return (0 ..< fullParticleCount).map { _ in
        let angle = rng.next() * .pi // downward hemisphere
        let speed = 12.0 * (0.85 + rng.next() * 0.30)
        return BurstParticle(
            velocityX: CGFloat(cos(angle) * speed),
            velocityY: CGFloat(sin(angle) * speed),
            color: confettiColors[Int(rng.next() * Double(confettiColors.count))],
            size: CGFloat((5 + rng.next() * 4) * 1.2),
            xRel: CGFloat(0.15 + rng.next() * 0.70),
            rotation: CGFloat(rng.next() * .pi * 2),
            rotSpeed: CGFloat((rng.next() - 0.5) * 0.3)
        )
    }
}

// MARK: - Finale styles

struct FinaleStyle {
    let palette: [UIColor]
    let sizeMul: CGFloat
    let velMul: CGFloat
    let lifeMul: CGFloat
    let glow: CGFloat
    let gravityMul: CGFloat
    let rotSpeedMul: CGFloat
    // Gravity curve - gravity = baseG x lerp(startMul, endMul, t^power).
    // Defaults (1, 1, 1) give constant gravity (Golden's behaviour).
    let gravityStartMul: CGFloat
    let gravityEndMul: CGFloat
    let gravityPower: CGFloat
    // Hero / bokeh variant - heroEvery == 0 disables it.
    let heroEvery: Int
    let heroSizeMul: CGFloat
    let heroGlow: CGFloat
    let bokehSizeMul: CGFloat
    let bokehAlpha: CGFloat
    let bokehVelMul: CGFloat
}

// Golden - the original, uniform-gold finale.
let finaleGolden = FinaleStyle(
    palette: .goldPalette,
    sizeMul: 1.3,
    velMul: 1.0,
    lifeMul: 1.2,
    glow: 6,
    gravityMul: 1.0,
    rotSpeedMul: 1.0,
    gravityStartMul: 1.0,
    gravityEndMul: 1.0,
    gravityPower: 1.0,
    heroEvery: 0,
    heroSizeMul: 1,
    heroGlow: 0,
    bokehSizeMul: 1,
    bokehAlpha: 1,
    bokehVelMul: 1
)

// Golden 2 - Cinematic timing + Hero/bokeh depth + gravity curve.
//   * velMul 1.05, lifeMul 1.15  - punchier launch, tighter total runtime
//   * gravityMul 1.05            - heavier base gravity
//   * gravityStartMul 0.45, gravityEndMul 4.0, gravityPower 2.0
//     -> gentle drift at top, sharp acceleration in last ~30 % of life
//   * rotSpeedMul 0.4            - 60 % slower spin
//   * heroEvery 3                - every 3rd particle is a "hero"
//   * bokeh particles small, translucent, drifting behind the heroes
let finaleGolden2 = FinaleStyle(
    palette: .goldPalette,
    sizeMul: 1.3,
    velMul: 1.05,
    lifeMul: 1.15,
    glow: 8,
    gravityMul: 1.05,
    rotSpeedMul: 0.4,
    gravityStartMul: 0.45,
    gravityEndMul: 4.0,
    gravityPower: 2.0,
    heroEvery: 3,
    heroSizeMul: 0.98,
    heroGlow: 12,
    bokehSizeMul: 0.45,
    bokehAlpha: 0.55,
    bokehVelMul: 0.7
)

// MARK: - Live particle (active in flight)

struct LiveParticle {
    var xPosition, yPosition: CGFloat
    var velocityX: CGFloat
    var velocityY: CGFloat
    var color: UIColor
    var size: CGFloat
    var rot: CGFloat
    var rotSpeed: CGFloat
    var glow: CGFloat
    var alphaCap: CGFloat
    let gStart, gEnd, gPow: CGFloat // gravity curve
    var ticksLeft: Int
    let lifeStart: Int
}

extension [UIColor] {
    // Shared gold palette.
    static var goldPalette: [UIColor] {
        [
            .goldFFD700,
            .goldF2C700,
            .goldFFA500,
            .goldFFE56B,
            .goldDAA520,
            .goldFFB347
        ]
    }

    // Multi-hue confetti palette.
    static var confettiPalette: [UIColor] {
        [
            .confettiFFE04A,
            .confettiFF6EA5,
            .confetti6BE087,
            .confetti6BD1FF,
            .confettiC48CFF,
            .confettiFF993D
        ]
    }
}

// MARK: - Renderer

final class ProgressiveBurstView: UIView {
    private let layout = makeBurstLayout()
    var completion: Int = 0 // 0..100, monotonic
    private var active: [LiveParticle] = []
    private var displayLink: CADisplayLink?
    var onDidBecomeIdle: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
    }

    /// Fire a signal at `level` percent. Pass `finale` on the wave that
    /// completes the burst (i.e. when prev + level >= 100).
    func fire(level: Int, finale: FinaleStyle? = nil) {
        let prev = completion
        let next = max(prev, min(level, 100)) // monotonic mode
        completion = next
        let start = prev * fullParticleCount / 100
        let end = next * fullParticleCount / 100
        let baseGravity: CGFloat = 0.20 // base gravity (px/frame^2)

        guard start < end else {
            return
        }

        for index in start ..< end {
            let particle = layout[index]
            var size = particle.size
            var velocityX = particle.velocityX
            var velocityY = particle.velocityY
            var color = particle.color
            var glow: CGFloat = 0
            var alphaCap: CGFloat = 1
            var lifeTicks = 120
            var rotSpeed = particle.rotSpeed
            var gStart = baseGravity, gEnd = baseGravity, gPow: CGFloat = 1

            if let finaleStyle = finale {
                // Base finale overrides.
                color = finaleStyle.palette[index % finaleStyle.palette.count]
                size *= finaleStyle.sizeMul
                velocityX *= finaleStyle.velMul
                velocityY *= finaleStyle.velMul
                lifeTicks = Int(120 * finaleStyle.lifeMul)
                glow = finaleStyle.glow
                rotSpeed *= finaleStyle.rotSpeedMul
                let finaleGravity = baseGravity * finaleStyle.gravityMul
                gStart = finaleGravity * finaleStyle.gravityStartMul
                gEnd = finaleGravity * finaleStyle.gravityEndMul
                gPow = finaleStyle.gravityPower

                // Hero / bokeh variant.
                if finaleStyle.heroEvery > 0 {
                    if index % finaleStyle.heroEvery == 0 {
                        size *= finaleStyle.heroSizeMul
                        glow = finaleStyle.heroGlow
                    } else {
                        size *= finaleStyle.bokehSizeMul
                        velocityX *= finaleStyle.bokehVelMul
                        velocityY *= finaleStyle.bokehVelMul
                        alphaCap = finaleStyle.bokehAlpha
                    }
                }
            }

            active.append(LiveParticle(
                xPosition: bounds.width * particle.xRel,
                yPosition: -size,
                velocityX: velocityX,
                velocityY: velocityY,
                color: color,
                size: size,
                rot: particle.rotation,
                rotSpeed: rotSpeed,
                glow: glow,
                alphaCap: alphaCap,
                gStart: gStart,
                gEnd: gEnd,
                gPow: gPow,
                ticksLeft: lifeTicks,
                lifeStart: lifeTicks
            ))
        }

        startDisplayLinkIfNeeded()
        setNeedsDisplay()
    }

    func resetSession() {
        completion = 0
        active.removeAll()
        displayLink?.invalidate()
        displayLink = nil
        setNeedsDisplay()
    }

    /// Per-frame physics step (call from a CADisplayLink at 60 fps).
    func step() {
        let decay: CGFloat = 0.9
        active = active.compactMap { particle in
            guard particle.ticksLeft > 0 else { return nil }
            var particle = particle
            // Gravity curve: lerp gStart -> gEnd by t^gPow.
            let progress = CGFloat(particle.lifeStart - particle.ticksLeft) / CGFloat(particle.lifeStart)
            let gravity = particle.gStart + (particle.gEnd - particle.gStart) *
                CGFloat(pow(Double(progress), Double(particle.gPow)))
            particle.xPosition += particle.velocityX
            particle.yPosition += particle.velocityY
            particle.velocityX *= decay
            particle.velocityY *= decay
            particle.velocityY += gravity
            particle.rot += particle.rotSpeed
            particle.ticksLeft -= 1
            return particle
        }
    }

    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        for particle in active {
            draw(particle, in: context)
        }
    }

    // Render `active` per frame: alpha = min(ticksLeft / 30, 1) * alphaCap;
    // colour = color; rotate by `rot`; shape = circle/rect (mixed); glow via
    // shadow blur = p.glow + shadowColor = p.color (additive look).
    private func draw(_ particle: LiveParticle, in context: CGContext) {
        let alpha = min(CGFloat(particle.ticksLeft) / 30, 1) * particle.alphaCap
        guard alpha > 0 else {
            return
        }

        context.saveGState()
        context.setAlpha(alpha)
        context.translateBy(x: particle.xPosition, y: particle.yPosition)
        context.rotate(by: particle.rot)

        if particle.glow > 0 {
            context.setShadow(
                offset: .zero,
                blur: particle.glow,
                color: particle.color.withAlphaComponent(alpha).cgColor
            )
        }

        particle.color.setFill()

        if particle.rotSpeed >= 0 {
            let rect = CGRect(
                x: -particle.size / 2,
                y: -particle.size / 2,
                width: particle.size,
                height: particle.size
            )
            context.fillEllipse(in: rect)
        } else {
            let rect = CGRect(
                x: -particle.size / 2,
                y: -particle.size / 5,
                width: particle.size,
                height: particle.size * 0.4
            )
            context.fill(rect)
        }

        context.restoreGState()
    }

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil else {
            return
        }

        let link = CADisplayLink(target: self, selector: #selector(handleDisplayLink))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func handleDisplayLink() {
        step()
        setNeedsDisplay()

        if active.isEmpty {
            displayLink?.invalidate()
            displayLink = nil
            onDidBecomeIdle?()
        }
    }
}

// MARK: - Halo overlay (CAGradientLayer.type = .radial, iOS 14+)

final class HaloOverlay: CAGradientLayer {
    override init() {
        super.init()
        type = .radial
        startPoint = CGPoint(x: 0.5, y: 0.5)
        endPoint = CGPoint(x: 1.0, y: 1.0)
        // 6-stop warm halo: pale gold -> gold -> amber -> orange -> red-orange -> fade.
        colors = [
            UIColor(red: 1.00, green: 1.00, blue: 0.82, alpha: 0.98).cgColor, // 0xFFFFD2
            UIColor(red: 1.00, green: 0.84, blue: 0.35, alpha: 0.92).cgColor, // 0xFFD75A
            UIColor(red: 1.00, green: 0.67, blue: 0.24, alpha: 0.78).cgColor, // 0xFFAA3C
            UIColor(red: 1.00, green: 0.43, blue: 0.20, alpha: 0.55).cgColor, // 0xFF6E32
            UIColor(red: 0.86, green: 0.22, blue: 0.16, alpha: 0.25).cgColor, // 0xDC3728
            UIColor.clear.cgColor
        ]
        locations = [0, 0.18, 0.36, 0.54, 0.72, 0.88].map(NSNumber.init(value:))
        compositingFilter = "screenBlendMode"
        opacity = 0
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    /// Plays the halo: scale 1 -> 2.15 with alpha 0 -> 1 -> 0 over 2.0 s.
    /// 2 s pairs cleanly with Golden 2's ~2.3 s particle lifetime.
    func play() {
        removeAllAnimations()

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0; scale.toValue = 2.15
        scale.duration = 2.0

        let alpha = CAKeyframeAnimation(keyPath: "opacity")
        alpha.values = [0, 1, 0]
        alpha.keyTimes = [0, 0.2, 1]
        alpha.duration = 2.0

        scale.fillMode = .forwards; scale.isRemovedOnCompletion = false
        alpha.fillMode = .forwards; alpha.isRemovedOnCompletion = false
        add(scale, forKey: "halo-scale"); add(alpha, forKey: "halo-alpha")
    }

    func reset() {
        removeAllAnimations()
        transform = CATransform3DIdentity
        opacity = 0
    }
}

// MARK: - Composed UIKit view

final class GestureAcceptanceConfettiView: UIView {
    private let burst = ProgressiveBurstView()
    var onFinale: (() -> Void)?

    /// Pick finaleGolden or finaleGolden2 from the lab UI selector.
    let finale: FinaleStyle = finaleGolden2

    override init(frame: CGRect) {
        super.init(frame: frame)

        isUserInteractionEnabled = false
        backgroundColor = .clear
        clipsToBounds = true
        isHidden = true

        addSubview(burst)

        burst.onDidBecomeIdle = { [weak self] in
            self?.isHidden = true
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        burst.frame = bounds
    }

    /// Call when an attestation signal arrives at `level` percent.
    func onSignal(level: Int) {
        isHidden = false

        let willComplete = burst.completion < 100 && level >= 100
        burst.fire(level: level, finale: willComplete ? finale : nil)
        if willComplete {
            onFinale?()
        }
    }

    func bind(
        tier: GameVideoViewLayout.GestureAcceptanceTier
    ) {
        switch tier {
        case .none:
            resetSession()
        case let .level(level):
            onSignal(level: level)
        }
    }

    func prepareForReuse() {
        resetSession()
    }

    private func resetSession() {
        burst.resetSession()
        isHidden = true
    }
}
