//
//  PendingMemoImportRequest.swift
//  JBCHBibleResearch
//
//  `.onOpenURL`로 받은 개인묵상 파일(`SharedMemoPayload`)을 담아 두는 신호 전용 싱글턴. `.onOpenURL`은 특정
//  화면의 `ModelContext`가 보장되지 않는 시점에 호출될 수 있어, 최상단 화면(`ContentView`)이 이를 관찰해
//  미리보기 시트를 띄운다. `AppOnboardingReplayRequest`(`Views/Onboarding/AppOnboardingOverlay.swift`)와
//  같은 구조지만, 값 없는 카운터가 아니라 받은 내용을 함께 넘겨야 해서 페이로드를 옵셔널로 들고 있는다.
//

import Foundation
import Observation
import SwiftData
import BibleResearchModels

@MainActor
@Observable
final class PendingMemoImportRequest {
    static let shared = PendingMemoImportRequest()

    private(set) var pending: PendingMemoImport?
    /// 받은 파일이 이 앱이 만든 `.jbchmemo` 형식이 아니거나(예: 손상된
    /// 파일, 형식이 다른 파일을 잘못 연 경우) JSON 파싱에 실패했을 때만
    /// 채워진다 — `ContentView`가 이 경우 미리보기 시트 대신 알림을
    /// 띄운다.
    private(set) var lastImportError: String?

    private init() {}

    /// `JBCHBibleResearchApp`의 `.onOpenURL`이 호출한다. 파일을 열어보고
    /// 성공하면 `pending`을, 실패하면 `lastImportError`를 채운다 — 실패
    /// 사유를 그냥 삼키지 않는다.
    func handleOpenedFile(at url: URL) {
        // AirDrop/"다음으로 열기"로 받은 파일은 이미 앱 샌드박스 안으로 복사돼 오지만, 보안 스코프 URL로
        // 직접 넘어오는 경우에도 안전하도록 시작/종료를 감싼다 — 스코프가 필요 없는 URL이면 `false`를
        // 돌려줄 뿐 부작용이 없다(Apple 문서).
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try Data(contentsOf: url)
            let payload = try SharedMemoFile.decode(data)
            lastImportError = nil
            pending = PendingMemoImport(payload: payload)
        } catch {
            print("[PendingMemoImportRequest] 받은 묵상 파일 열기 실패: \(error)")
            pending = nil
            lastImportError = "받은 파일을 열 수 없습니다. 이 앱에서 공유한 개인 묵상 파일(.\(SharedMemoFile.fileExtension))이 맞는지 확인해 주세요."
        }
    }

    /// 미리보기 시트가 "추가"/"취소"로 닫힌 뒤 호출 — 다음에 같은 파일을
    /// 다시 열었을 때도 새 요청으로 인식되도록 비운다.
    func consume() {
        pending = nil
    }

    /// 열기 실패 알림을 확인한 뒤 호출.
    func consumeError() {
        lastImportError = nil
    }

    /// 실제로 받는 기기의 개인 묵상 목록에 추가한다. 태그는 `MemoDetailView`가 쓰는
    /// `TagDeduplication.findOrCreateTag` 경로를 재사용해, 같은 이름의 태그가 있으면 합류하고 없으면 새로 만든다.
    static func importIntoLibrary(_ payload: SharedMemoPayload, context: ModelContext) throws {
        // 폴더는 "폴더 없음"으로 받는다 — `folder`를 넘기지 않아 `UserMemo.init`의 기본값 `nil`을 쓴다.
        let memo = UserMemo(
            bookId: payload.bookId,
            chapter: payload.chapter,
            verse: payload.verse,
            rangeStart: payload.rangeStart,
            rangeEnd: payload.rangeEnd,
            annotationTranslationCode: payload.annotationTranslationCode,
            anchorText: payload.anchorText,
            contentHtml: payload.contentText,
            contentText: payload.contentText
        )
        context.insert(memo)

        // 태그 정보도 함께 받는다.
        for tagName in payload.tagNames {
            let tag = try TagDeduplication.findOrCreateTag(named: tagName, context: context)
            let join = MemoTag(memo: memo, tag: tag)
            context.insert(join)
        }

        try context.save()
        BibleReferenceIndexingService.reindexMemo(memo, context: context)
    }
}

/// `.sheet(item:)`은 `Identifiable`을 요구하는데 `SharedMemoPayload`
/// 자체엔(파일 비교 등 다른 용도에서 식별자가 필요 없어) 굳이 넣지 않고,
/// 화면 표시용으로만 감싸는 얇은 래퍼.
struct PendingMemoImport: Identifiable {
    let id = UUID()
    let payload: SharedMemoPayload
}
