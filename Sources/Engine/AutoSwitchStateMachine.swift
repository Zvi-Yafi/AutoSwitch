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
            guard self._currentState == .idle || self._currentState == .buffering || self._currentState == .evaluating else {
                return
            }
            // A deletion invalidates the previous word and any evaluation of
            // the text before the edit, even when the current buffer is empty.
            self._currentGeneration += 1
            self.pendingAmbiguousCorrection = nil
            if self._currentState == .evaluating {
                self._transition(to: .idle)
                return
            }
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

                let decision = LanguageDecisionEngine.shared.evaluate(snapshot: snapshot)
                self.stateQueue.async(flags: .barrier) {
                    // Apply every result on the same queue as edits. A result
                    // captured before a deletion must not restore pending text
                    // or clear the buffer of the word typed after it.
                    guard capturedGeneration == self._currentGeneration,
                          self._currentState == .evaluating else {
                        appLog("State moved on before evaluation could apply")
                        return
                    }

                    switch decision {
                    case .accepted(let candidate):
                        let correctedWord = candidate.word
                        let pending = self.consumePendingAmbiguousIfCompatible(
                            target: candidate.target,
                            appBundleId: snapshot.activeAppBundleId,
                            generation: capturedGeneration
                        )
                        let fullCorrectedWord = (pending.map { $0.correctedWord + $0.delimiter } ?? "") + correctedWord
                        let fullOriginalWord = (pending.map { $0.originalWord + $0.delimiter } ?? "") + snapshot.originalWord

                        appLog("Correction Approved: \(snapshot.originalWord) -> \(correctedWord)", level: .debug)
                        DispatchQueue.main.async {
                            guard self.beginInjection(generation: capturedGeneration) else {
                                return
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
                            LayoutMapper.shared.warmCache(for: candidate.target.inputSourceID)
                            WordBufferManager.shared.setLastInjectedLayout(candidate.target.inputSourceID)

                            TextInjector.shared.inject(
                                originalWord: fullOriginalWord,
                                correctedWord: fullCorrectedWord,
                                delimiter: snapshot.boundaryCharacter,
                                layoutToSwitch: candidate.target.inputSourceID
                            ) { applied in
                                DispatchQueue.main.async {
                                    if applied {
                                        CorrectionHistory.shared.push(item)
                                    } else {
                                        WordBufferManager.shared.clearLastInjectedLayout()
                                    }
                                    self.injectionCompleted()
                                }
                            }
                        }
                    case .ambiguous(let candidate):
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
                    case .switchOnly(let targetInputSourceID, _):
                        appLog("Correction SwitchOnly: '\(snapshot.originalWord)' layout -> \(targetInputSourceID)", level: .debug)
                        DispatchQueue.main.async {
                            guard self.beginInjection(generation: capturedGeneration) else {
                                return
                            }
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
                        self.clearPendingAmbiguousCorrection()
                        self._transition(to: .idle)
                    }
                }
            }
        }
    }

    private func beginInjection(generation: Int) -> Bool {
        stateQueue.sync {
            // Recheck after waiting for the main queue, and claim the state
            // atomically with respect to deletions and other invalidations.
            guard generation == self._currentGeneration,
                  self._currentState == .evaluating else { return false }
            self._transition(to: .injecting)
            return true
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
                originalWord: item.correctedWord,
                correctedWord: item.originalWord,
                delimiter: item.delimiter,
                layoutToSwitch: item.previousLayout
            ) { applied in
                DispatchQueue.main.async {
                    if !applied {
                        WordBufferManager.shared.clearLastInjectedLayout()
                    }
                    self.injectionCompleted()
                }
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
