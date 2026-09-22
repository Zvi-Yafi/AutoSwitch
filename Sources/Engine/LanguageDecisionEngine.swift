import Foundation

class LanguageDecisionEngine {
    static let shared = LanguageDecisionEngine()
    private let englishAbbreviations: Set<String> = [
        "afaik", "afk", "asl", "atm", "b4", "bc", "bbl", "bbs", "bday", "bf",
        "brb", "btw", "cya", "dm", "fomo", "fwiw", "gg", "gl", "gm", "gn",
        "gr8", "gtg", "hbd", "hmu", "idc", "idk", "ig", "iirc", "imo", "imho",
        "irl", "jk", "lfg", "lmao", "lmk", "lol", "mb", "nbd", "nvm", "omg",
        "pls", "plz", "rn", "rofl", "smh", "tbh", "thx", "tnx", "ttyl", "ty",
        "tysm", "wdym", "wth", "wtf", "xoxo", "yk", "yolo", "yw"
    ]
    private let hebrewCommonWords: Set<String> = [
        "אני", "את", "אתה", "הוא", "היא", "אנחנו", "אתם", "אתן", "הם", "הן",
        "של", "על", "אל", "עם", "לא", "כן", "גם", "רק", "כל", "כמה",
        "מה", "מי", "איך", "למה", "איפה", "מתי", "איזה", "כמו", "אבל", "או",
        "זה", "זו", "זאת", "אלה", "אלו", "שם", "פה", "כאן", "שלי", "שלך",
        "יש", "אין", "היה", "יהיה", "עוד", "פעם", "יום", "שנה", "עכשיו"
    ]
    private let edgeAffixCharacters: Set<Character> = [
        ",", ";", ".", "!", "?", "(", ")", "[", "]", "{", "}",
        "\"", "\u{2026}", "\u{201C}", "\u{201D}", "\u{201E}", "\u{00AB}", "\u{00BB}",
        "'", "\u{05F3}", "\u{2018}", "\u{2019}", "`", "\u{00B4}"
    ]
    private let blockedTechnicalCharacters: Set<Character> = ["-", "_", "/", "\\", "@", ":"]
    private static let apostropheVariants: Set<Character> = [
        "'", "\u{05F3}", "\u{2018}", "\u{2019}", "`", "\u{00B4}"
    ]
    private static let canonicalApostrophe: Character = "'"
    private static let morphologicalPrefixes: [String: [String]] = [
        "he": ["\u{05D1}", "\u{05D4}", "\u{05D5}", "\u{05DB}", "\u{05DC}", "\u{05DE}", "\u{05E9}"],
        "ar": ["\u{0627}\u{0644}"]
    ]
    private static let forbiddenNonFinalCodePoints: [String: Set<UnicodeScalar>] = [
        "Hebr": [
            UnicodeScalar(0x05DA)!,
            UnicodeScalar(0x05DD)!,
            UnicodeScalar(0x05DF)!,
            UnicodeScalar(0x05E3)!,
            UnicodeScalar(0x05E5)!
        ],
        "Grek": [
            UnicodeScalar(0x03C2)!
        ]
    ]

    private init() {}
    
    func evaluate(snapshot: CorrectionSnapshot) -> LanguageDecision {
        let original = snapshot.originalWord
        let parsedToken = parseToken(original: original)
        appLog("DIAG: TokenNormalize raw='\(original)' variants=\(parsedToken.debugSummary) blocked=\(parsedToken.blockedReason ?? "none")", level: .debug)

        if parsedToken.lookupForms.contains(where: { OverrideController.shared.isIgnoredWord($0) }) {
            appLog("DIAG: Reject ignored token raw='\(original)' forms=\(parsedToken.lookupForms)", level: .debug)
            return .rejected
        }
        
        if let blockedReason = parsedToken.blockedReason {
            appLog("DIAG: Reject blocked token raw='\(original)' reason=\(blockedReason)", level: .debug)
            return .rejected
        }

        let evaluationVariants = parsedToken.variants.filter { $0.token.count >= 2 && $0.token.count <= 20 }
        guard !evaluationVariants.isEmpty else {
            appLog("DIAG: Reject token raw='\(original)' reason=length", level: .debug)
            return .rejected
        }

        let settings = SettingsStore.shared.getSettings()
        let sourceInputSourceID = snapshot.sourceInputSourceID ?? InputSourceController.shared.getCurrentLayoutID()
        let installedInputSources = InputSourceController.shared.listInstalledInputSources()
        let sourceInputSource = installedInputSources.first(where: { $0.id == sourceInputSourceID })
        let targetInputSources = eligibleTargetInputSources(
            from: installedInputSources,
            settings: settings,
            sourceInputSourceID: sourceInputSourceID
        )
        guard !targetInputSources.isEmpty else {
            return .rejected
        }

        let originalLooksValid = originalIsKnownWord(parsedToken.lookupForms, installedInputSources: targetInputSources)
        var uniqueCandidates: [String: EvaluatedCandidate] = [:]
        for mappingTarget in targetInputSources {
            for variant in evaluationVariants {
                guard let mappedWord = mappedWord(
                    for: variant,
                    snapshot: snapshot,
                    sourceInputSourceID: sourceInputSourceID,
                    targetInputSourceID: mappingTarget.id
                ),
                      mappedWord != variant.token,
                      !containsBlockingPattern(mappedWord),
                      !containsDisallowedMappedSymbols(mappedWord),
                      mappedWord.contains(where: \.isLetter) else {
                    continue
                }
                guard let candidate = buildCandidate(
                    original: variant.token,
                    variant: variant,
                    mappedWord: mappedWord,
                    localeTarget: mappingTarget,
                    settings: settings,
                    originalLooksValid: originalLooksValid
                ) else {
                    continue
                }
                let key = "\(candidate.candidate.target.inputSourceID)\u{1F}\(candidate.candidate.word)"
                if let existing = uniqueCandidates[key] {
                    if isPreferred(candidate, over: existing) {
                        uniqueCandidates[key] = candidate
                    }
                } else {
                    uniqueCandidates[key] = candidate
                }
            }
        }

        let sortedCandidates = collapseIdenticalReplacementCandidates(
            Array(uniqueCandidates.values),
            installedInputSources: installedInputSources
        ).sorted(by: isPreferred)
        guard let bestEvaluatedCandidate = sortedCandidates.first else {
            if let switchOnly = evaluateSwitchOnlyFallback(
                parsedToken: parsedToken,
                sourceInputSource: sourceInputSource,
                targetInputSources: targetInputSources
            ) {
                return switchOnly
            }
            appLog("DIAG: Reject token raw='\(original)' reason=no_candidate", level: .debug)
            return .rejected
        }
        let bestCandidate = bestEvaluatedCandidate.candidate
        let targetEvidence = bestEvaluatedCandidate.targetEvidence
        let sourceEvidence = sourceWordEvidence(
            [bestEvaluatedCandidate.variant.token],
            sourceInputSource: sourceInputSource,
            sourceInputSourceID: sourceInputSourceID
        )
        appLog("DIAG: SourceEvidence raw='\(original)' token='\(bestEvaluatedCandidate.variant.token)' evidence=\(sourceEvidence)", level: .debug)
        let sourceLooksValid = sourceEvidence != .none

        let scoreThreshold = settings.ambiguousConfidenceThreshold
        guard bestCandidate.score >= scoreThreshold else {
            appLog("DIAG: Reject token raw='\(original)' reason=below_threshold score=\(bestCandidate.score)", level: .debug)
            return .rejected
        }

        let secondBestScore = sortedCandidates
            .dropFirst()
            .first(where: {
                $0.variant.strippedCharacterCount <= bestEvaluatedCandidate.variant.strippedCharacterCount
                    && $0.candidate.word != bestCandidate.word
            })?
            .candidate.score ?? 0
        if sourceLooksValid && !allowsOverride(from: sourceInputSource, to: bestCandidate, original: bestEvaluatedCandidate.variant.token) {
            if shouldDeferAmbiguous(candidate: bestCandidate, secondBestScore: secondBestScore, settings: settings) {
                appLog("DIAG: EvidencePolicy ambiguous_defer raw='\(original)' candidate='\(bestCandidate.word)' source=\(sourceEvidence) target=\(targetEvidence)", level: .debug)
                return .ambiguous(candidate: bestCandidate)
            } else {
                appLog("DIAG: EvidencePolicy reject_source_valid raw='\(original)' candidate='\(bestCandidate.word)' source=\(sourceEvidence) target=\(targetEvidence)", level: .debug)
                return .rejected
            }
        }

        if bestCandidate.score - secondBestScore < 0.15 {
            appLog("DIAG: Ambiguous low_delta raw='\(original)' candidate='\(bestCandidate.word)' delta=\(bestCandidate.score - secondBestScore)", level: .debug)
            return .ambiguous(candidate: bestCandidate)
        }

        appLog("DIAG: Accept token raw='\(original)' candidate='\(bestCandidate.word)' score=\(bestCandidate.score)", level: .debug)
        return .accepted(candidate: bestCandidate)
    }

    private func mappedWord(
        for variant: ParsedTokenVariant,
        snapshot: CorrectionSnapshot,
        sourceInputSourceID: String,
        targetInputSourceID: String
    ) -> String? {
        guard !snapshot.keystrokes.isEmpty,
              let sourceRender = LayoutMapper.shared.render(
                keystrokes: snapshot.keystrokes,
                layoutID: sourceInputSourceID
              ),
              sourceRender.consumedAllKeystrokes,
              !sourceRender.hasPendingDeadKey,
              sourceRender.text == snapshot.originalWord,
              sourceRender.characterKeyRanges.count == snapshot.originalWord.count else {
            return LayoutMapper.shared.map(
                text: variant.token,
                from: sourceInputSourceID,
                to: targetInputSourceID
            )
        }

        let characterStart = variant.leadingAffix.count
        let characterEnd = characterStart + variant.token.count
        guard characterStart >= 0,
              characterEnd <= sourceRender.characterKeyRanges.count,
              characterStart < characterEnd else {
            return nil
        }

        let selectedRanges = sourceRender.characterKeyRanges[characterStart..<characterEnd]
        guard let firstRange = selectedRanges.first,
              let lastRange = selectedRanges.last else {
            return nil
        }
        let keyStart = firstRange.lowerBound
        let keyEnd = lastRange.upperBound
        guard keyStart >= 0,
              keyEnd <= snapshot.keystrokes.count,
              keyStart < keyEnd else {
            return nil
        }

        let targetKeystrokes = Array(snapshot.keystrokes[keyStart..<keyEnd])
        guard let targetRender = LayoutMapper.shared.render(
            keystrokes: targetKeystrokes,
            layoutID: targetInputSourceID
        ),
              targetRender.consumedAllKeystrokes,
              !targetRender.hasPendingDeadKey else {
            return nil
        }
        return targetRender.text
    }
    
    func effectivePeriodMergeForSnapshot(originalWord: String, boundary: Character, sourceLayoutID: String) -> (originalWord: String, boundaryCharacter: String) {
        guard boundary == "." else {
            return (originalWord, String(boundary))
        }
        guard !originalWord.contains(".") else {
            return (originalWord, String(boundary))
        }
        let installedSources = InputSourceController.shared.listInstalledInputSources()
        let sourceSource = installedSources.first(where: { $0.id == sourceLayoutID })
        guard sourceSource?.isASCIICapable == true else {
            return (originalWord, String(boundary))
        }
        let merged = originalWord + "."
        let targetSources = installedSources.filter { $0.id != sourceLayoutID && $0.isSelectable && $0.supportTier != .unsupported }
        for target in targetSources {
            guard let mappedMerged = LayoutMapper.shared.map(text: merged, from: sourceLayoutID, to: target.id),
                  let mappedWithout = LayoutMapper.shared.map(text: originalWord, from: sourceLayoutID, to: target.id),
                  let locale = DictionaryManager.shared.bestSupportedLocale(for: target) else {
                continue
            }
            let mergedOk = wordLooksValid(mappedMerged, locale: locale, inputSource: target)
            let withoutOk = wordLooksValid(mappedWithout, locale: locale, inputSource: target)
            if mergedOk && !withoutOk {
                return (merged, "")
            }
        }
        return (originalWord, String(boundary))
    }

    private func containsDisallowedMappedSymbols(_ word: String) -> Bool {
        return word.contains { character in
            if character.isLetter {
                return false
            }
            return !Self.apostropheVariants.contains(character)
        }
    }

    private func containsBlockingPattern(_ word: String) -> Bool {
        let hasNonLatinLetter = word.unicodeScalars.contains { scalar in
            CharacterSet.letters.contains(scalar) && scalar.value > 0x024F
        }
        if !hasNonLatinLetter, word.contains(where: { blockedTechnicalCharacters.contains($0) }) {
            return true
        }
        let hasLetters = word.contains { $0.isLetter }
        let hasNumbers = word.contains { $0.isNumber }
        if hasLetters && hasNumbers {
            return true
        }
        let pattern = "[a-z][A-Z]"
        if let _ = word.range(of: pattern, options: .regularExpression) {
            return true
        }
        return false
    }

    private func isKnownAbbreviation(_ word: String) -> Bool {
        let normalized = word.lowercased()
        return englishAbbreviations.contains(normalized)
    }

    private func containsApostropheVariant(_ word: String) -> Bool {
        return word.contains { Self.apostropheVariants.contains($0) }
    }

    private func eligibleTargetInputSources(
        from installedInputSources: [InstalledInputSource],
        settings: AppSettings,
        sourceInputSourceID: String
    ) -> [InstalledInputSource] {
        var targets = installedInputSources.filter {
            $0.id != sourceInputSourceID && $0.isSelectable && $0.supportTier != .unsupported
        }
        if !settings.enabledTargetInputSourceIDs.isEmpty {
            let enabledIDs = Set(settings.enabledTargetInputSourceIDs)
            targets = targets.filter { enabledIDs.contains($0.id) }
        } else if !settings.enableBestEffortTargets {
            targets = targets.filter { $0.supportTier == .fullSupport }
        }
        if settings.correctionPreferenceMode == .preferSpecificTarget,
           let preferredTargetInputSourceID = settings.preferredTargetInputSourceID,
           let preferredTarget = installedInputSources.first(where: { $0.id == preferredTargetInputSourceID }),
           preferredTarget.id != sourceInputSourceID,
           preferredTarget.supportTier != .unsupported,
           !targets.contains(where: { $0.id == preferredTarget.id }) {
            targets.append(preferredTarget)
        }
        return targets
    }

    private func buildCandidate(
        original: String,
        variant: ParsedTokenVariant,
        mappedWord: String,
        localeTarget: InstalledInputSource,
        settings: AppSettings,
        originalLooksValid: Bool
    ) -> EvaluatedCandidate? {
        let locale = DictionaryManager.shared.bestSupportedLocale(for: localeTarget)
        let score: Double
        let targetEvidence: ValidityEvidence

        if let locale {
            let evidence = validityEvidence(for: mappedWord, locale: locale, inputSource: localeTarget)
            guard evidence != .none else {
                return nil
            }
            targetEvidence = evidence
            score = scoreFullSupportCandidate(
                original: original,
                mappedWord: mappedWord,
                locale: locale,
                targetInputSource: localeTarget,
                settings: settings,
                originalLooksValid: originalLooksValid
            )
        } else {
            guard settings.enableBestEffortTargets,
                  localeTarget.supportTier == .bestEffort,
                  qualifiesForBestEffort(mappedWord, targetInputSource: localeTarget, original: original) else {
                return nil
            }
            targetEvidence = .weakStructural
            score = scoreBestEffortCandidate(
                original: original,
                mappedWord: mappedWord,
                targetInputSource: localeTarget,
                settings: settings,
                originalLooksValid: originalLooksValid
            )
        }

        let target = CorrectionTarget(
            inputSourceID: localeTarget.id,
            languageCode: localeTarget.languageCode,
            supportTier: localeTarget.supportTier
        )
        let replacementWord = variant.leadingAffix + mappedWord + variant.trailingAffix
        let adjustedScore = max(0, score - (Double(variant.strippedCharacterCount) * 0.08))
        let candidate = CorrectionCandidate(word: replacementWord, target: target, score: adjustedScore)
        return EvaluatedCandidate(candidate: candidate, variant: variant, targetEvidence: targetEvidence)
    }

    private func passesScriptStructuralRules(_ word: String, inputSource: InstalledInputSource) -> Bool {
        guard let scriptCode = inputSource.scriptCode,
              let forbidden = Self.forbiddenNonFinalCodePoints[scriptCode] else {
            return true
        }
        let category = scriptCategory(for: inputSource)
        let letterScalars = word.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard letterScalars.count >= 2 else {
            return true
        }
        let scriptLetters = letterScalars.filter { category.contains($0) }
        guard scriptLetters.count >= 2 else {
            return true
        }
        for scalar in scriptLetters.dropLast() {
            if forbidden.contains(scalar) {
                return false
            }
        }
        return true
    }

    private func validityEvidence(for word: String, locale: String, inputSource: InstalledInputSource) -> ValidityEvidence {
        guard passesScriptStructuralRules(word, inputSource: inputSource) else {
            appLog("DIAG: ValidityCheck word='\(word)' locale='\(locale)' result=structural_fail", level: .debug)
            return .none
        }
        if scriptCategory(for: inputSource) == .hebrew && hebrewCommonWords.contains(word) {
            appLog("DIAG: ValidityCheck word='\(word)' locale='\(locale)' result=hebrew_common_word", level: .debug)
            return .dictionary
        }
        let isDictionaryWord = DictionaryManager.shared.isWord(word, in: locale)
        appLog("DIAG: ValidityCheck word='\(word)' locale='\(locale)' isDictionaryWord=\(isDictionaryWord)", level: .debug)
        if isDictionaryWord {
            return .dictionary
        }
        let localePrefix = localeLanguagePrefix(locale)
        if let prefixes = Self.morphologicalPrefixes[localePrefix], word.count > 2 {
            for prefix in prefixes where word.hasPrefix(prefix) {
                let stripped = String(word.dropFirst(prefix.count))
                if !stripped.isEmpty,
                   passesScriptStructuralRules(stripped, inputSource: inputSource),
                   DictionaryManager.shared.isWord(stripped, in: locale) {
                    return .dictionaryAfterMorphology
                }
            }
        }
        if containsApostropheVariant(word) {
            let normalized = normalizeApostrophes(word)
            if normalized != word,
               passesScriptStructuralRules(normalized, inputSource: inputSource),
               DictionaryManager.shared.isWord(normalized, in: locale) {
                return .dictionaryAfterNormalization
            }
        }
        if word.count == 2 {
            let category = scriptCategory(for: inputSource)
            if category != .unknown && category != .latin {
                let letters = word.unicodeScalars.filter { CharacterSet.letters.contains($0) }
                if letters.count == 2 && letters.allSatisfy({ category.contains($0) }) {
                    return .weakStructural
                }
            }
        }
        return .none
    }

    private func wordLooksValid(_ word: String, locale: String, inputSource: InstalledInputSource) -> Bool {
        return validityEvidence(for: word, locale: locale, inputSource: inputSource) != .none
    }

    private func scoreFullSupportCandidate(
        original: String,
        mappedWord: String,
        locale: String,
        targetInputSource: InstalledInputSource,
        settings: AppSettings,
        originalLooksValid: Bool
    ) -> Double {
        var score = 0.8
        if matchesExpectedScript(mappedWord, targetInputSource: targetInputSource) {
            score += 0.12
        }
        if settings.correctionPreferenceMode == .preferSpecificTarget,
           settings.preferredTargetInputSourceID == targetInputSource.id {
            score += 0.1
        }
        if containsApostropheVariant(original) {
            score += 0.03
        }
        if isKnownAbbreviation(original),
           OverrideController.shared.isAbbreviationPriorityEnabled(for: original) {
            score += 0.04
        }
        if originalLooksValid {
            score -= 0.08
        }
        if mappedWord.count == original.count {
            score += 0.03
        }
        return min(score, 1.0)
    }

    private func scoreBestEffortCandidate(
        original: String,
        mappedWord: String,
        targetInputSource: InstalledInputSource,
        settings: AppSettings,
        originalLooksValid: Bool
    ) -> Double {
        var score = 0.66
        if settings.correctionPreferenceMode == .preferSpecificTarget,
           settings.preferredTargetInputSourceID == targetInputSource.id {
            score += 0.05
        }
        if mappedWord.count == original.count {
            score += 0.02
        }
        if originalLooksValid {
            score -= 0.08
        }
        return min(score, 0.78)
    }

    private func originalEvidence(_ lookupForms: [String], installedInputSources: [InstalledInputSource]) -> ValidityEvidence {
        var best: ValidityEvidence = .none
        for original in lookupForms {
            for inputSource in installedInputSources {
                guard let locale = DictionaryManager.shared.bestSupportedLocale(for: inputSource) else {
                    continue
                }
                let evidence = validityEvidence(for: original, locale: locale, inputSource: inputSource)
                if evidence > best {
                    best = evidence
                }
                if best == .dictionary {
                    return best
                }
            }
        }
        return best
    }

    private func originalIsKnownWord(_ lookupForms: [String], installedInputSources: [InstalledInputSource]) -> Bool {
        return originalEvidence(lookupForms, installedInputSources: installedInputSources) != .none
    }

    private func sourceWordEvidence(
        _ lookupForms: [String],
        sourceInputSource: InstalledInputSource?,
        sourceInputSourceID: String
    ) -> ValidityEvidence {
        guard let resolvedSource = sourceInputSource ?? resolveInputSource(for: sourceInputSourceID) else {
            return .none
        }
        guard let locale = DictionaryManager.shared.bestSupportedLocale(for: resolvedSource) else {
            return .none
        }
        var best: ValidityEvidence = .none
        for original in lookupForms {
            let stripped = splitEdgeAffixes(for: original).coreWord
            let formToCheck = stripped.isEmpty ? original : stripped
            let evidence = validityEvidence(for: formToCheck, locale: locale, inputSource: resolvedSource)
            if evidence > best {
                best = evidence
            }
            if best == .dictionary {
                return best
            }
        }
        return best
    }

    private func sourceWordLooksValid(
        _ lookupForms: [String],
        sourceInputSource: InstalledInputSource?,
        sourceInputSourceID: String
    ) -> Bool {
        return sourceWordEvidence(
            lookupForms,
            sourceInputSource: sourceInputSource,
            sourceInputSourceID: sourceInputSourceID
        ) != .none
    }

    private func allowsOverride(from sourceInputSource: InstalledInputSource?, to candidate: CorrectionCandidate, original: String) -> Bool {
        guard sourceInputSource != nil else {
            return false
        }
        return isKnownAbbreviation(original)
            && OverrideController.shared.isAbbreviationPriorityEnabled(for: original)
    }

    private func shouldDeferAmbiguous(candidate: CorrectionCandidate, secondBestScore: Double, settings: AppSettings) -> Bool {
        guard settings.enableAmbiguousCorrection else {
            return false
        }
        guard candidate.target.supportTier == .fullSupport else {
            return false
        }
        let minimumDeferredScore = max(settings.ambiguousConfidenceThreshold, 0.8)
        guard candidate.score >= minimumDeferredScore else {
            return false
        }
        return candidate.score - secondBestScore >= 0.15
    }

    private func resolveInputSource(for inputSourceID: String) -> InstalledInputSource? {
        InputSourceController.shared.listInstalledInputSources().first(where: { $0.id == inputSourceID })
    }

    private func qualifiesForBestEffort(_ mappedWord: String, targetInputSource: InstalledInputSource, original: String) -> Bool {
        guard matchesExpectedScript(mappedWord, targetInputSource: targetInputSource) else {
            return false
        }
        guard !originalIsMostlyInTargetScript(original, targetInputSource: targetInputSource) else {
            return false
        }
        let letterCount = mappedWord.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let changedCount = zip(original, mappedWord).filter { $0 != $1 }.count
        guard letterCount > 0, changedCount > 0 else {
            return false
        }
        return Double(changedCount) / Double(mappedWord.count) >= 0.6
    }

    private func originalIsMostlyInTargetScript(_ word: String, targetInputSource: InstalledInputSource) -> Bool {
        let targetCategory = scriptCategory(for: targetInputSource)
        guard targetCategory != .unknown else {
            return false
        }
        let letters = word.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else {
            return false
        }
        let matching = letters.filter { targetCategory.contains($0) }.count
        return Double(matching) / Double(letters.count) >= 0.8
    }

    private func matchesExpectedScript(_ word: String, targetInputSource: InstalledInputSource) -> Bool {
        let category = scriptCategory(for: targetInputSource)
        let letters = word.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else {
            return false
        }
        if category == .unknown {
            return targetInputSource.isASCIICapable ? letters.allSatisfy(\.isASCII) : letters.contains(where: { !$0.isASCII })
        }
        let matchingCount = letters.filter { category.contains($0) }.count
        return Double(matchingCount) / Double(letters.count) >= 0.8
    }

    private func scriptCategory(for inputSource: InstalledInputSource) -> ScriptCategory {
        switch inputSource.scriptCode {
        case "Hebr":
            return .hebrew
        case "Cyrl":
            return .cyrillic
        case "Grek":
            return .greek
        case "Arab":
            return .arabic
        case "Deva":
            return .devanagari
        case "Latn":
            return .latin
        default:
            return .unknown
        }
    }

    private func normalizeApostrophes(_ word: String) -> String {
        var result = word
        for variant in Self.apostropheVariants where variant != Self.canonicalApostrophe {
            result = result.replacingOccurrences(of: String(variant), with: String(Self.canonicalApostrophe))
        }
        return result
    }

    private func localeLanguagePrefix(_ locale: String) -> String {
        let normalized = locale.replacingOccurrences(of: "-", with: "_").lowercased()
        return normalized.split(separator: "_").first.map(String.init) ?? normalized
    }

    private func parseToken(original: String) -> ParsedToken {
        let edgeSplit = splitEdgeAffixes(for: original)
        var variants: [ParsedTokenVariant] = []
        var seen: Set<String> = []

        func appendVariant(token: String, leadingAffix: String, trailingAffix: String) {
            guard !token.isEmpty else {
                return
            }
            let key = "\(leadingAffix)|\(token)|\(trailingAffix)"
            guard !seen.contains(key) else {
                return
            }
            seen.insert(key)
            variants.append(
                ParsedTokenVariant(
                    token: token,
                    leadingAffix: leadingAffix,
                    trailingAffix: trailingAffix
                )
            )
        }

        appendVariant(token: original, leadingAffix: "", trailingAffix: "")
        if !edgeSplit.leadingAffix.isEmpty {
            appendVariant(token: String(original.dropFirst(edgeSplit.leadingAffix.count)), leadingAffix: edgeSplit.leadingAffix, trailingAffix: "")
        }
        if !edgeSplit.trailingAffix.isEmpty {
            appendVariant(token: String(original.dropLast(edgeSplit.trailingAffix.count)), leadingAffix: "", trailingAffix: edgeSplit.trailingAffix)
        }
        if !edgeSplit.leadingAffix.isEmpty || !edgeSplit.trailingAffix.isEmpty {
            appendVariant(token: edgeSplit.coreWord, leadingAffix: edgeSplit.leadingAffix, trailingAffix: edgeSplit.trailingAffix)
        }

        var lookupForms: [String] = []
        var seenLookupForms: Set<String> = []
        for variant in variants where variant.token.contains(where: \.isLetter) {
            if !seenLookupForms.contains(variant.token) {
                seenLookupForms.insert(variant.token)
                lookupForms.append(variant.token)
            }
        }

        let primaryLookupWord = edgeSplit.coreWord.isEmpty ? original : edgeSplit.coreWord
        let blockedReason: String?
        if primaryLookupWord.isEmpty {
            blockedReason = "empty_core"
        } else if !primaryLookupWord.contains(where: \.isLetter) {
            blockedReason = "no_letters"
        } else if containsBlockingPattern(primaryLookupWord) {
            blockedReason = "technical_pattern"
        } else {
            blockedReason = nil
        }

        return ParsedToken(
            raw: original,
            variants: variants,
            lookupForms: lookupForms,
            primaryLookupWord: primaryLookupWord,
            blockedReason: blockedReason
        )
    }

    private func splitEdgeAffixes(for original: String) -> (leadingAffix: String, coreWord: String, trailingAffix: String) {
        var start = original.startIndex
        var end = original.endIndex

        while start < end, edgeAffixCharacters.contains(original[start]) {
            start = original.index(after: start)
        }

        while end > start {
            let previous = original.index(before: end)
            if edgeAffixCharacters.contains(original[previous]) {
                end = previous
            } else {
                break
            }
        }

        return (
            leadingAffix: String(original[..<start]),
            coreWord: String(original[start..<end]),
            trailingAffix: String(original[end...])
        )
    }

    private func evaluateSwitchOnlyFallback(
        parsedToken: ParsedToken,
        sourceInputSource: InstalledInputSource?,
        targetInputSources: [InstalledInputSource]
    ) -> LanguageDecision? {
        guard let source = sourceInputSource,
              let sourceLocale = DictionaryManager.shared.bestSupportedLocale(for: source),
              let coreWord = parsedToken.lookupForms.first,
              coreWord.count >= 3 else { return nil }
        guard !wordLooksValid(coreWord, locale: sourceLocale, inputSource: source) else { return nil }
        let sourceScript = scriptCategory(for: source)
        var matches: [InstalledInputSource] = []
        for target in targetInputSources {
            guard scriptCategory(for: target) == sourceScript,
                  let locale = DictionaryManager.shared.bestSupportedLocale(for: target),
                  wordLooksValid(coreWord, locale: locale, inputSource: target) else { continue }
            matches.append(target)
        }
        guard matches.count == 1, let target = matches.first else { return nil }
        appLog("DIAG: SwitchOnly raw='\(coreWord)' -> target=\(target.id)", level: .debug)
        return .switchOnly(targetInputSourceID: target.id, targetLanguageCode: target.languageCode)
    }

    private func collapseIdenticalReplacementCandidates(
        _ candidates: [EvaluatedCandidate],
        installedInputSources: [InstalledInputSource]
    ) -> [EvaluatedCandidate] {
        let targetOrder = Dictionary(uniqueKeysWithValues: installedInputSources.enumerated().map { ($1.id, $0) })
        var bestByReplacementWord: [String: EvaluatedCandidate] = [:]
        for candidate in candidates {
            let replacementWord = candidate.candidate.word
            guard let existing = bestByReplacementWord[replacementWord] else {
                bestByReplacementWord[replacementWord] = candidate
                continue
            }
            let existingRank = targetOrder[existing.candidate.target.inputSourceID] ?? Int.max
            let candidateRank = targetOrder[candidate.candidate.target.inputSourceID] ?? Int.max
            if candidateRank < existingRank || (candidateRank == existingRank && isPreferred(candidate, over: existing)) {
                bestByReplacementWord[replacementWord] = candidate
            }
        }
        return Array(bestByReplacementWord.values)
    }

    private func isPreferred(_ lhs: EvaluatedCandidate, over rhs: EvaluatedCandidate) -> Bool {
        if lhs.candidate.score != rhs.candidate.score {
            return lhs.candidate.score > rhs.candidate.score
        }
        if lhs.variant.strippedCharacterCount != rhs.variant.strippedCharacterCount {
            return lhs.variant.strippedCharacterCount < rhs.variant.strippedCharacterCount
        }
        if lhs.variant.token.count != rhs.variant.token.count {
            return lhs.variant.token.count > rhs.variant.token.count
        }
        return lhs.candidate.word < rhs.candidate.word
    }
}

private struct ParsedToken {
    let raw: String
    let variants: [ParsedTokenVariant]
    let lookupForms: [String]
    let primaryLookupWord: String
    let blockedReason: String?

    var debugSummary: String {
        variants.map { "\($0.leadingAffix){\($0.token)}\($0.trailingAffix)" }.joined(separator: ",")
    }
}

private struct ParsedTokenVariant {
    let token: String
    let leadingAffix: String
    let trailingAffix: String

    var strippedCharacterCount: Int {
        leadingAffix.count + trailingAffix.count
    }
}

private struct EvaluatedCandidate {
    let candidate: CorrectionCandidate
    let variant: ParsedTokenVariant
    let targetEvidence: ValidityEvidence
}

enum ValidityEvidence: Int, Comparable {
    case none = 0
    case weakStructural = 1
    case dictionaryAfterNormalization = 2
    case dictionaryAfterMorphology = 3
    case dictionary = 4

    static func < (lhs: ValidityEvidence, rhs: ValidityEvidence) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

private enum ScriptCategory {
    case latin
    case hebrew
    case cyrillic
    case greek
    case arabic
    case devanagari
    case unknown

    func contains(_ scalar: UnicodeScalar) -> Bool {
        switch self {
        case .latin:
            return scalar.value <= 0x024F
        case .hebrew:
            return (0x0590...0x05FF).contains(scalar.value)
        case .cyrillic:
            return (0x0400...0x052F).contains(scalar.value)
        case .greek:
            return (0x0370...0x03FF).contains(scalar.value)
        case .arabic:
            return (0x0600...0x06FF).contains(scalar.value)
        case .devanagari:
            return (0x0900...0x097F).contains(scalar.value)
        case .unknown:
            return false
        }
    }
}
