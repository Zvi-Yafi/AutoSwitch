import Foundation

class AutoSwitchStateMachine {
    static let shared = AutoSwitchStateMachine()

    private let stateQueue = DispatchQueue(label: "com.autoswitch.state", qos: .userInteractive)
    private var _currentState: SystemState = .idle
    private var _currentGeneration: Int = 0

    var currentState: SystemState {
        stateQueue.sync { _currentState }
    }

    var currentGeneration: Int {
        stateQueue.sync { _currentGeneration }
    }

    private let evaluationQueue = DispatchQueue(label: "com.autoswitch.evaluation", qos: .userInitiated)
    private var pendingDisable = false
    private var pendingAmbiguousCorrection: PendingAmbiguousCorrection?

    private init() {}

    func appActivated(isAuthorized: Bool) {
        stateQueue.async(flags: .barrier) {
            self._currentGeneration += 1
            self.pendingAmbiguousCorrection = nil
            WordBufferManager.shared.clearLastInjectedLayout()
            if isAuthorized {
                self._transition(to: .idle)
            } else {
                self._transition(to: .disabled)
            }
        }
    }

    func secureFieldDetected() {
        stateQueue.async(flags: .barrier) {
            self._currentGeneration += 1
            self.pendingAmbiguousCorrection = nil
            if self._currentState == .injecting {
                self.pendingDisable = true
            } else {
                self._transition(to: .disabled)
            }
        }
    }
    
    func secureFieldCleared(isAuthorized: Bool) {
        stateQueue.async(flags: .barrier) {
            guard self._currentState == .disabled else {
                return
            }
            if isAuthorized {
                self._transition(to: .idle)
            }
        }
    }

    func handleNavigationEvent() {
        stateQueue.async(flags: .barrier) {
            self._currentGeneration += 1
            self.pendingAmbiguousCorrection = nil
            WordBufferManager.shared.clearLastInjectedLayout()
            self._transition(to: .idle)
        }
    }

    func handleKeystroke(keyCode: UInt16, modifierFlags: UInt32) {
        stateQueue.async(flags: .barrier) {
            guard self._currentState == .idle || self._currentState == .buffering else {
                appLog("DIAG: handleKeystroke ignored — state=\(self._currentState)", level: .debug)
                return
            }
            if self._currentState == .idle { self._transition(to: .buffering) }
            WordBufferManager.shared.appendKeystroke(keyCode: keyCode, modifierFlags: modifierFlags)
        }
    }

    func handleBackspace() {
        stateQueue.async(flags: .barrier) {
            guard self._currentState == .buffering else { return }
            WordBufferManager.shared.removeLast()
            if WordBufferManager.shared.isEmpty {
                self._transition(to: .idle)
            }
        }
    }

    func handleBoundary(_ char: Character, activeAppId: String?) {
        stateQueue.async(flags: .barrier) {
            let currentWord = WordBufferManager.shared.currentWord
            guard self._currentState == .buffering, !currentWord.isEmpty else {
                self._transition(to: .idle)
                return
            }
            if !self.hasLetters(currentWord) {
                self.pendingAmbiguousCorrection = nil
                self._transition(to: .idle)
                return
            }
            
            if OverrideController.shared.consumeSkipNextCorrection() {
                self.pendingAmbiguousCorrection = nil
                self._transition(to: .idle)
                return
            }

            let rawSnapshot = WordBufferManager.shared.getSnapshot(boundary: char, appBundleId: activeAppId, generation: self._currentGeneration)
            let periodMerge = LanguageDecisionEngine.shared.effectivePeriodMergeForSnapshot(
                originalWord: rawSnapshot.originalWord,
                boundary: char,
                sourceLayoutID: rawSnapshot.sourceInputSourceID ?? ""
            )
            let snapshot: CorrectionSnapshot
            if periodMerge.originalWord != rawSnapshot.originalWord {
                appLog("PeriodMerge: '\(rawSnapshot.originalWord)' + '.' → '\(periodMerge.originalWord)'", level: .debug)
                snapshot = CorrectionSnapshot(
                    originalWord: periodMerge.originalWord,
                    boundaryCharacter: periodMerge.boundaryCharacter,
                    activeAppBundleId: rawSnapshot.activeAppBundleId,
                    generationAtCapture: rawSnapshot.generationAtCapture,
                    sourceInputSourceID: rawSnapshot.sourceInputSourceID,
                    keystrokes: rawSnapshot.keystrokes
                )
            } else {
                snapshot = rawSnapshot
            }
            self._transition(to: .evaluating)
            let capturedGeneration = self._currentGeneration

            self.evaluationQueue.async { [weak self] in
                guard let self = self else { return }

                if snapshot.generationAtCapture != self.currentGeneration {
                    appLog("Generation mismatch, dropping.")
                    return
                }

                switch LanguageDecisionEngine.shared.evaluate(snapshot: snapshot) {
                case .accepted(let candidate):
                    let correctedWord = candidate.word
                    appLog("Correction Approved: \(snapshot.originalWord) -> \(correctedWord)", level: .debug)
                    DispatchQueue.main.async {
                        guard snapshot.generationAtCapture == self.currentGeneration,
                              self.currentState == .evaluating else {
                            appLog("State moved on before correction could apply")
                            self.stateQueue.async(flags: .barrier) { self._transition(to: .idle) }
                            return
                        }

                        self.stateQueue.async(flags: .barrier) { self._transition(to: .injecting) }

                        var fullCorrectedWord = correctedWord
                        var originalLengthToDelete = snapshot.originalWord.count + snapshot.boundaryCharacter.count

                        if let pending = self.consumePendingAmbiguousIfCompatible(target: candidate.target, appBundleId: snapshot.activeAppBundleId, generation: capturedGeneration) {
                            fullCorrectedWord = pending.correctedWord + pending.delimiter + correctedWord
                            originalLengthToDelete += pending.originalWord.count + pending.delimiter.count
                        } else {
                            self.clearPendingAmbiguousCorrection()
                        }

                        let item = CorrectionHistoryItem(
                            originalWord: snapshot.originalWord,
                            correctedWord: correctedWord,
                            delimiter: snapshot.boundaryCharacter,
                            previousLayout: InputSourceController.shared.getCurrentLayoutID(),
                            targetInputSourceID: candidate.target.inputSourceID,
                            appBundleId: snapshot.activeAppBundleId,
                            timestamp: Date(),
                            generation: capturedGeneration
                        )
                        CorrectionHistory.shared.push(item)

                        LayoutMapper.shared.warmCache(for: candidate.target.inputSourceID)
                        WordBufferManager.shared.setLastInjectedLayout(candidate.target.inputSourceID)

                        TextInjector.shared.inject(
                            originalLength: originalLengthToDelete,
                            correctedWord: fullCorrectedWord,
                            delimiter: snapshot.boundaryCharacter,
                            layoutToSwitch: candidate.target.inputSourceID
                        ) {
                            DispatchQueue.main.async { self.injectionCompleted() }
                        }
                    }
                case .ambiguous(let candidate):
                    self.stateQueue.async(flags: .barrier) {
                        if SettingsStore.shared.getSettings().enableAmbiguousCorrection {
                            appLog("Correction Ambiguous: \(snapshot.originalWord) -> \(candidate.word)", level: .debug)
                            self.pendingAmbiguousCorrection = PendingAmbiguousCorrection(
                                originalWord: snapshot.originalWord,
                                correctedWord: candidate.word,
                                delimiter: snapshot.boundaryCharacter,
                                target: candidate.target,
                                appBundleId: snapshot.activeAppBundleId,
                                generation: capturedGeneration
                            )
                        } else {
                            self.pendingAmbiguousCorrection = nil
                        }
                        self._transition(to: .idle)
                    }
                case .switchOnly(let targetInputSourceID, _):
                    appLog("Correction SwitchOnly: '\(snapshot.originalWord)' layout -> \(targetInputSourceID)", level: .debug)
                    DispatchQueue.main.async {
                        guard snapshot.generationAtCapture == self.currentGeneration,
                              self.currentState == .evaluating else {
                            self.stateQueue.async(flags: .barrier) { self._transition(to: .idle) }
                            return
                        }
                        self.stateQueue.async(flags: .barrier) { self._transition(to: .injecting) }
                        let previousLayout = InputSourceController.shared.getCurrentLayoutID()
                        let item = CorrectionHistoryItem(
                            originalWord: snapshot.originalWord,
                            correctedWord: snapshot.originalWord,
                            delimiter: snapshot.boundaryCharacter,
                            previousLayout: previousLayout,
                            targetInputSourceID: targetInputSourceID,
                            appBundleId: snapshot.activeAppBundleId,
                            timestamp: Date(),
                            generation: capturedGeneration
                        )
                        CorrectionHistory.shared.push(item)
                        WordBufferManager.shared.setLastInjectedLayout(targetInputSourceID)
                        _ = InputSourceController.shared.switchLayout(to: targetInputSourceID)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            self.injectionCompleted()
                        }
                    }
                case .rejected:
                    appLog("Correction Rejected for: \(snapshot.originalWord)", level: .debug)
                    DispatchQueue.main.async {
                        if self.currentState == .evaluating {
                            self.stateQueue.async(flags: .barrier) {
                                self.clearPendingAmbiguousCorrection()
                                self._transition(to: .idle)
                            }
                        }
                    }
                }
            }
        }
    }

    private func injectionCompleted() {
        stateQueue.async(flags: .barrier) {
            if self.pendingDisable {
                self.pendingDisable = false
                self._transition(to: .disabled)
            } else {
                self._transition(to: .idle)
            }
        }
    }

    func requestUndoRecentCorrection() -> Bool {
        let undoWindowSeconds = SettingsStore.shared.getSettings().undoWindowSeconds
        let historyItem = CorrectionHistory.shared.popLast(within: undoWindowSeconds)
        guard let item = historyItem else {
            return false
        }
        stateQueue.async(flags: .barrier) {
            if self._currentState == .injecting {
                return
            }
            self.pendingAmbiguousCorrection = nil
            self._transition(to: .injecting)
            if item.originalWord == item.correctedWord {
                DispatchQueue.main.async {
                    _ = InputSourceController.shared.switchLayout(to: item.previousLayout)
                    self.stateQueue.async(flags: .barrier) { self._transition(to: .idle) }
                }
                return
            }
            WordBufferManager.shared.setLastInjectedLayout(item.previousLayout)
            TextInjector.shared.inject(
                originalLength: item.correctedWord.count + item.delimiter.count,
                correctedWord: item.originalWord,
                delimiter: item.delimiter,
                layoutToSwitch: item.previousLayout
            ) {
                DispatchQueue.main.async { self.injectionCompleted() }
            }
        }
        return true
    }

    private func _transition(to newState: SystemState) {
        appLog("StateMachine: Transitioning \(_currentState) -> \(newState)")
        _currentState = newState
        if newState == .idle || newState == .disabled {
            WordBufferManager.shared.clear()
        }
    }

    private func clearPendingAmbiguousCorrection() {
        pendingAmbiguousCorrection = nil
    }

    private func consumePendingAmbiguousIfCompatible(target: CorrectionTarget, appBundleId: String?, generation: Int) -> PendingAmbiguousCorrection? {
        guard let pending = pendingAmbiguousCorrection else {
            return nil
        }
        let isCompatibleTarget = pending.target == target
        let isCompatibleApp = pending.appBundleId == appBundleId
        let isCompatibleGeneration = pending.generation == generation
        if isCompatibleTarget && isCompatibleApp && isCompatibleGeneration {
            pendingAmbiguousCorrection = nil
            return pending
        }
        pendingAmbiguousCorrection = nil
        return nil
    }


    private func hasLetters(_ word: String) -> Bool {
        for scalar in word.unicodeScalars {
            if CharacterSet.letters.contains(scalar) {
                return true
            }
        }
        return false
    }

    #if DEBUG
    func _setPendingAmbiguousForTesting(_ pending: PendingAmbiguousCorrection?) {
        stateQueue.sync(flags: .barrier) {
            self.pendingAmbiguousCorrection = pending
            self._currentState = .idle
        }
    }

    var _pendingAmbiguousForTesting: PendingAmbiguousCorrection? {
        stateQueue.sync { self.pendingAmbiguousCorrection }
    }
    #endif
}
