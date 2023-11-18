import SpriteKit
import AVFoundation

enum ForceBomb {
    case never
    case always
    case random
}

enum SequenceType: CaseIterable {
    case oneNoBomb
    case one
    case twoWithOneBomb
    case two
    case three
    case four
    case chain
    case fastChain
}

class GameScene: SKScene {
    var scoreLabel: SKLabelNode!
    var activeSliceBG: SKShapeNode!
    var activeSliceFG: SKShapeNode!
    var bombSoundEffect: AVAudioPlayer?
    
    var activeSlicePoints = [CGPoint]()
    var activeEnemies = [SKSpriteNode]()
    var livesImages = [SKSpriteNode]()
    var sequence = [SequenceType]()
    
    var isGameOver = false
    var isSwooshSoundOn = false
    var nextSequenceQueued = true
    
    var popupTime = 0.9
    var chainDelay: Double = 3
    var sequencePosition = 0
    var lives = 3
    var score = 0 {
        didSet {
            scoreLabel.text = "Score: \(score)"
        }
    }
    
    let fusePosition = CGPoint(x: 76, y: 64)
    let circleOfRadius: CGFloat = 64
    let angularVelocityRange: ClosedRange<CGFloat> = -3...3
    let xPositionRange = 64...960
    let outerXVelocityRange = 8...15
    let innerXVelocityRange = 3...5
    let YVelocityRange = 24...32
    let velocityMultiplier = 40
    let fastEnemyConstant = 5
    
    override func didMove(to view: SKView) {
        let background = SKSpriteNode(imageNamed: "sliceBackground")
        background.position = CGPoint(x: 512, y: 384)
        background.blendMode = .replace
        background.zPosition = -1
        addChild(background)
        
        physicsWorld.gravity = CGVector(dx: 0, dy: -6)
        physicsWorld.speed = 0.85
        
        createScore()
        createLives()
        createSlices()
        
        sequence = [.oneNoBomb, .oneNoBomb, .twoWithOneBomb, .twoWithOneBomb, .three, .one, .chain]
        
        for _ in 0...1000 {
            if let nextSequence = SequenceType.allCases.randomElement() {
                sequence.append(nextSequence)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.tossEnemies()
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        
        let location = touch.location(in: self)
        activeSlicePoints.removeAll(keepingCapacity: true)
        activeSlicePoints.append(location)
        redrawActiveSlice()
        
        activeSliceBG.removeAllActions()
        activeSliceBG.alpha = 1
        
        activeSliceFG.removeAllActions()
        activeSliceFG.alpha = 1
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        guard !isGameOver else { return }
        
        let location = touch.location(in: self)
        activeSlicePoints.append(location)
        redrawActiveSlice()
        
        if !isSwooshSoundOn {
            playSwooshSound()
        }
        
        let nodesAtPoint = nodes(at: location)
        for case let node as SKSpriteNode in nodesAtPoint {
            if node.name == "enemy" || node.name == "enemyFast" {
                if let emitter = SKEmitterNode(fileNamed: "sliceHitEnemy") {
                    emitter.position = node.position
                    addChild(emitter)
                }
                
                if node.name == "enemyFast" {
                    score += 2
                }
                node.name = ""
                node.physicsBody?.isDynamic = false
                
                let scaleOut = SKAction.scale(to: 0.001, duration: 0.2)
                let fadeOut = SKAction.fadeOut(withDuration: 0.2)
                let group = SKAction.group([scaleOut, fadeOut])
                let remove = SKAction.removeFromParent()
                let seq = SKAction.sequence([group, remove])
                node.run(seq)
                
                score += 1
                
                if let index = activeEnemies.firstIndex(of: node) {
                    activeEnemies.remove(at: index)
                }
                
                run(SKAction.playSoundFileNamed("whack.caf", waitForCompletion: false))
            } else if node.name == "bomb" {
                guard let bombContainer = node.parent as? SKSpriteNode else { continue }
                
                if let emitter = SKEmitterNode(fileNamed: "sliceHitBomb") {
                    emitter.position = bombContainer.position
                    addChild(emitter)
                }
                
                node.name = ""
                bombContainer.physicsBody?.isDynamic = false
                
                let scaleOut = SKAction.scale(to: 0.001, duration: 0.2)
                let fadeOut = SKAction.fadeOut(withDuration: 0.2)
                let group = SKAction.group([scaleOut, fadeOut])
                let remove = SKAction.removeFromParent()
                let seq = SKAction.sequence([group, remove])
                bombContainer.run(seq)
                
                if let index = activeEnemies.firstIndex(of: bombContainer) {
                    activeEnemies.remove(at: index)
                }
                
                run(SKAction.playSoundFileNamed("explosion.caf", waitForCompletion: false))
                
                endGame(byBomb: true)
            }
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeSliceBG.run(SKAction.fadeOut(withDuration: 0.25))
        activeSliceFG.run(SKAction.fadeOut(withDuration: 0.25))
    }
    
    func createScore() {
        scoreLabel = SKLabelNode(fontNamed: "Chalkduster")
        scoreLabel.position = CGPoint(x: 8, y: 8)
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.fontSize = 48
        addChild(scoreLabel)
        score = 0
    }
    
    func createLives() {
        for i in 0..<3 {
            let sprite = SKSpriteNode(imageNamed: "sliceLife")
            sprite.position = CGPoint(x: CGFloat(834 + (i * 70)), y: 720)
            addChild(sprite)
            livesImages.append(sprite)
        }
    }
    
    func createSlices() {
        activeSliceBG = SKShapeNode()
        activeSliceBG.zPosition = 2
        activeSliceBG.strokeColor = UIColor(red: 1, green: 0.9, blue: 0, alpha: 1)
        activeSliceBG.lineWidth = 9
        addChild(activeSliceBG)
        
        activeSliceFG = SKShapeNode()
        activeSliceFG.zPosition = 3
        activeSliceFG.strokeColor = .white
        activeSliceFG.lineWidth = 5
        addChild(activeSliceFG)
    }
    
    func createEnemy(forceBomb: ForceBomb = .random) {
        let enemy: SKSpriteNode
        var randomXVelocity: Int
        var enemyType = Int.random(in: 0...6)
        
        if forceBomb == .never {
            enemyType = 1
        } else if forceBomb == .always {
            enemyType = 0
        }
        
        if enemyType == 0 {
            enemy = SKSpriteNode()
            enemy.zPosition = 1
            enemy.name = "bombContainer"
            
            let bombImage = SKSpriteNode(imageNamed: "sliceBomb")
            bombImage.name = "bomb"
            enemy.addChild(bombImage)
            
            if bombSoundEffect != nil {
                bombSoundEffect?.stop()
                bombSoundEffect = nil
            }
            
            if let path = Bundle.main.url(forResource: "sliceBombFuse", withExtension: "caf") {
                if let sound = try? AVAudioPlayer(contentsOf: path) {
                    bombSoundEffect = sound
                    sound.play()
                }
            }
            
            if let emitter = SKEmitterNode(fileNamed: "sliceFuse") {
                emitter.position = fusePosition
                enemy.addChild(emitter)
            }
        } else if enemyType == 6 {
            enemy = SKSpriteNode(imageNamed: "penguinEvil")
            run(SKAction.playSoundFileNamed("launch.caf", waitForCompletion: false))
            enemy.name = "enemyFast"
        } else {
            enemy = SKSpriteNode(imageNamed: "penguin")
            run(SKAction.playSoundFileNamed("launch.caf", waitForCompletion: false))
            enemy.name = "enemy"
        }
        
        let randomPosition = CGPoint(x: Int.random(in: xPositionRange), y: -128)
        let randomAngularVelocity = CGFloat.random(in: angularVelocityRange)
        var randomYVelocity = Int.random(in: YVelocityRange)
        if randomPosition.x < 256 {
            randomXVelocity = Int.random(in: outerXVelocityRange)
        } else if randomPosition.x < 512 {
            randomXVelocity = Int.random(in: innerXVelocityRange)
        } else if randomPosition.x < 768 {
            randomXVelocity = -Int.random(in: innerXVelocityRange)
        } else {
            randomXVelocity = -Int.random(in: outerXVelocityRange)
        }
        
        if enemy.name == "enemyFast" {
            if randomXVelocity < 0 {
                randomXVelocity -= fastEnemyConstant
            }
            if randomXVelocity > 0 {
                randomXVelocity += fastEnemyConstant
            }
            randomYVelocity += fastEnemyConstant
        }
        
        enemy.position = randomPosition
        enemy.physicsBody = SKPhysicsBody(circleOfRadius: circleOfRadius)
        enemy.physicsBody?.collisionBitMask = 0
        enemy.physicsBody?.angularVelocity = randomAngularVelocity
        enemy.physicsBody?.velocity = CGVector(dx: randomXVelocity * velocityMultiplier, dy: randomYVelocity * velocityMultiplier)
        
        addChild(enemy)
        activeEnemies.append(enemy)
    }
    
    func tossEnemies() {
        guard !isGameOver else { return }
        
        popupTime *= 0.991
        chainDelay *= 0.99
        physicsWorld.speed *= 1.02
        
        let sequenceType = sequence[sequencePosition]
        
        switch sequenceType {
        case .oneNoBomb:
            createEnemy(forceBomb: .never)
        case .one:
            createEnemy()
        case .twoWithOneBomb:
            createEnemy(forceBomb: .never)
            createEnemy(forceBomb: .always)
        case .two:
            for _ in 1...2 {
                createEnemy()
            }
        case .three:
            for _ in 1...3 {
                createEnemy()
            }
        case .four:
            for _ in 1...4 {
                createEnemy()
            }
        case .chain:
            createEnemy()
            DispatchQueue.main.asyncAfter(deadline: .now() + (chainDelay / 5)) { [weak self] in
                self?.createEnemy()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (chainDelay / 5 * 2)) { [weak self] in
                self?.createEnemy()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (chainDelay / 5 * 3)) { [weak self] in
                self?.createEnemy()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (chainDelay / 5 * 4)) { [weak self] in
                self?.createEnemy()
            }
        case .fastChain:
            createEnemy()
            DispatchQueue.main.asyncAfter(deadline: .now() + (chainDelay / 10)) { [weak self] in
                self?.createEnemy()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (chainDelay / 10 * 2)) { [weak self] in
                self?.createEnemy()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (chainDelay / 10 * 3)) { [weak self] in
                self?.createEnemy()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (chainDelay / 10 * 4)) { [weak self] in
                self?.createEnemy()
            }
        }
            sequencePosition += 1
            nextSequenceQueued = false
    }
    
    func redrawActiveSlice() {
        if activeSlicePoints.count < 2 {
            activeSliceBG.path = nil
            activeSliceFG.path = nil
            return
        }
        
        if activeSlicePoints.count > 12 {
            activeSlicePoints.removeFirst(activeSlicePoints.count - 12)
        }
        
        let path = UIBezierPath()
        path.move(to: activeSlicePoints[0])
        for i in 1..<activeSlicePoints.count {
            path.addLine(to: activeSlicePoints[i])
        }
        
        activeSliceBG.path = path.cgPath
        activeSliceFG.path = path.cgPath
    }
    
    func playSwooshSound() {
        isSwooshSoundOn = true
        
        let randomNum = Int.random(in: 1...3)
        let soundName = "swoosh\(randomNum).caf"
        let swooshSound = SKAction.playSoundFileNamed(soundName, waitForCompletion: true)
        
        run(swooshSound) { [weak self] in
            self?.isSwooshSoundOn = false
        }
    }
    
    func endGame(byBomb: Bool) {
        guard !isGameOver else { return }
        
        isGameOver = true
        physicsWorld.speed = 0
        isUserInteractionEnabled = false
        
        bombSoundEffect?.stop()
        bombSoundEffect = nil
        
        if byBomb {
            for image in livesImages {
                image.texture = SKTexture(imageNamed: "sliceLifeGone")
            }
        }
        
        let gameOverPic = SKSpriteNode(imageNamed: "gameOver")
        gameOverPic.position = CGPoint(x: 512, y: 400)
        gameOverPic.zPosition = 2
        
        let finalScoreLabel = SKLabelNode(fontNamed: "Chalkduster")
        finalScoreLabel.text = "Final Score: \(score)"
        finalScoreLabel.fontSize = 80
        finalScoreLabel.position = CGPoint(x: 512, y: 280)
        finalScoreLabel.zPosition = 2
        
        addChild(gameOverPic)
        addChild(finalScoreLabel)
        run(SKAction.playSoundFileNamed("gameOverSound", waitForCompletion: false))
    }
    
    func subtractLife() {
        var life: SKSpriteNode
        
        lives -= 1
        run(SKAction.playSoundFileNamed("wrong.caf", waitForCompletion: false))
        
        if lives == 2 {
            life = livesImages[0]
        } else if lives == 1 {
            life = livesImages[1]
        } else {
            life = livesImages[2]
            endGame(byBomb: false)
        }
        
        life.texture = SKTexture(imageNamed: "sliceLifeGone")
        life.xScale = 1.3
        life.yScale = 1.3
        life.run(SKAction.scale(to: 1, duration: 0.1))
    }
    
    override func update(_ currentTime: TimeInterval) {
        var bombCount = 0
        
        for node in activeEnemies {
            if node.name == "bombContainer" {
                bombCount += 1
                break
            }
        }
        
        if activeEnemies.count > 0 {
            for (index, node) in activeEnemies.enumerated().reversed() {
                if node.position.y < -140 {
                    node.removeAllActions()
                    
                    if node.name == "enemy" || node.name == "enemyFast"{
                        node.name = ""
                        subtractLife()
                        node.removeFromParent()
                        activeEnemies.remove(at: index)
                    } else if node.name == "bombContainer" {
                        node.name = ""
                        node.removeFromParent()
                        activeEnemies.remove(at: index)
                    }
                }
            }
        } else {
            if !nextSequenceQueued {
                DispatchQueue.main.asyncAfter(deadline: .now() + popupTime) { [weak self] in
                    self?.tossEnemies()
                }
                nextSequenceQueued = true
            }
        }
        
        if bombCount == 0 {
            bombSoundEffect?.stop()
            bombSoundEffect = nil
        }
    }
}
