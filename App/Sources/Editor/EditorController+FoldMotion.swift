import AppKit
import Theme

/// 꺾쇠가 도는 동안에만 그 행의 열림 정도를 보관한다(0은 닫힘, 1은 열림).
nonisolated final class FoldDrawing {
    var openness: [Int: Double] = [:]
}

struct FoldTransition {
    let from: Double
    let to: Double
    var start: TimeInterval
    let duration: TimeInterval

    func value(at now: TimeInterval, curve: BezierCurve) -> Double {
        guard duration > 0 else { return to }
        return from + (to - from) * curve.progress(at: (now - start) / duration)
    }
}

extension EditorController {
    /// 줄 명령에 넘길 접힘. 기본값으로 닫힌 빈 토글은 커서 줄에서만 판단하면 된다.
    func foldsAtCaret(_ caret: NSRange) -> Set<Int> {
        let row = document.blockLines(at: document.lineIndex(at: caret.location)).lowerBound
        return foldState.isClosed(row, in: document) ? folded.union([row]) : folded
    }

    func performFoldCommand(_ action: EditorAction, at caret: NSRange, moveCaret: Bool) {
        let current = foldsAtCaret(caret)
        let next: Set<Int>
        if action == .fold {
            guard let change = FoldState.fold(document, selection: caret, folded: current) else { return }
            if moveCaret { setSelection(change.selection) }
            next = change.folded
        } else {
            guard let change = FoldState.unfold(document, selection: caret, folded: current) else { return }
            next = change
        }
        changeUserFolds(foldState.toggling(current.symmetricDifference(next), in: document))
    }

    func changeUserFolds(_ next: FoldState, applying edit: TextEdit? = nil) {
        guard next != foldState else {
            if let edit { apply(edit) }
            return
        }
        let changed = folded.symmetricDifference(next.closed)
            .union(foldState.openedEmpty.symmetricDifference(next.openedEmpty))
        isChangingUserFold = true
        defer { isChangingUserFold = false }
        startFoldMotion(rows: changed, to: next)
        if let edit {
            // 선택한 투두의 완료와 토글의 접힘을 같은 편집으로 되돌릴 수 있게 한다.
            apply(edit)
        } else {
            applyFolds(next)
            notifyFoldChangeIfNeeded()
        }
        guard foldState == next else { stopFoldMotion(); return }
        // 동기 배치와 저장이 끝난 뒤부터 꺾쇠의 시간을 센다.
        let start = foldClock()
        for row in changed { foldTransitions[row]?.start = start }
    }

    private func startFoldMotion(rows: Set<Int>, to next: FoldState) {
        guard foldAnimationsEnabled(), theme.motion.chevronRotation > 0 else {
            stopFoldMotion()
            return
        }
        let now = foldClock()
        for row in rows {
            let target: Double = next.isClosed(row, in: document) ? 0 : 1
            let from = foldDrawing.openness[row] ?? (1 - target)
            foldTransitions[row] = FoldTransition(from: from, to: target, start: now,
                                                  duration: theme.motion.chevronRotation * abs(target - from))
            foldDrawing.openness[row] = from
        }
        guard foldTask == nil, !foldTransitions.isEmpty else { return }
        let fps = max(1, textView.window?.screen?.maximumFramesPerSecond ?? 60)
        foldTask = Task { [weak self] in
            while !Task.isCancelled, self?.advanceFoldMotion() == true {
                try? await Task.sleep(for: .seconds(1 / Double(fps)))
            }
        }
    }

    @discardableResult func advanceFoldMotion() -> Bool {
        let interval = EditorTrace.begin("advanceFoldMotion")
        defer { EditorTrace.end("advanceFoldMotion", interval) }
        let now = foldClock()
        for (row, transition) in foldTransitions {
            if !foldAnimationsEnabled() || now >= transition.start + transition.duration {
                foldTransitions.removeValue(forKey: row)
                foldDrawing.openness.removeValue(forKey: row)
            } else {
                foldDrawing.openness[row] = transition.value(at: now, curve: theme.motion.curve)
            }
        }
        textView.setNeedsDisplay(textView.visibleRect)
        if foldTransitions.isEmpty {
            foldTask = nil
            return false
        }
        return true
    }

    func stopFoldMotion() {
        foldTask?.cancel()
        foldTask = nil
        foldDrawing.openness.removeAll()
        foldTransitions.removeAll()
    }
}
