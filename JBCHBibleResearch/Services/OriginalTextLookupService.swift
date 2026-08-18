//
//  OriginalTextLookupService.swift
//  JBCHBibleResearch
//
//  [2026-08-09 신설] "원문 정보" 기능 — 앱 번들의 Resources/OriginalText.sqlite를
//  찾아 여는 부분만 앱 레이어 책임으로 둔다(TranslationBootstrap.resolvedBundledDatabaseURL
//  과 같은 이유 — 패키지는 파일시스템 위치를 몰라도 되게). 실제 조회는
//  BibleResearchModels.OriginalTextStore가 담당.
//
//  ⚠️ [출처/라이선스] OriginalText.sqlite는 STEPBible-Data(github.com/STEPBible/STEPBible-Data,
//  CC BY 4.0)의 TAHOT(히브리어 구약)·TAGNT(그리스어 신약) 텍스트를 변환한 것이다.
//  [2026-08-13 해소] 앱 내 크레딧 고지 — 환경설정 "정보" 탭(SettingsView.swift,
//  AboutSettingsTab)의 "오픈소스 라이선스 고지" 섹션에 STEPBible-Data(TAHOT/TAGNT,
//  CC BY 4.0) 문구와 저장소 링크를 추가해 반영했다.
//

import Foundation
import BibleResearchModels

enum OriginalTextLookupError: Error, LocalizedError {
    case bundledDatabaseNotFound

    var errorDescription: String? {
        switch self {
        case .bundledDatabaseNotFound:
            return "앱 번들에서 OriginalText.sqlite를 찾을 수 없습니다. Xcode 타겟의 Copy Bundle Resources에 Resources/OriginalText.sqlite가 포함돼 있는지 확인하세요."
        }
    }
}

/// 단일 `OriginalTextStore` 커넥션을 앱 전역에서 재사용한다(매번 새로 열지 않음 —
/// `BibleReferenceStore`가 절/장 조회마다 파일을 여는 것과 달리, 이 데이터는 앱
/// 실행 내내 읽기 전용으로 반복 조회되므로 커넥션을 유지하는 편이 낫다).
@MainActor
final class OriginalTextLookupService {
    static let shared = OriginalTextLookupService()

    private var store: OriginalTextStore?
    private var openError: Error?

    private init() {}

    private func resolvedStore() -> OriginalTextStore? {
        if let store { return store }
        if openError != nil { return nil }
        do {
            guard let url = Bundle.main.url(forResource: "OriginalText", withExtension: "sqlite") else {
                throw OriginalTextLookupError.bundledDatabaseNotFound
            }
            let opened = try OriginalTextStore(filePath: url.path)
            store = opened
            return opened
        } catch {
            openError = error
            print("[OriginalTextLookupService] OriginalText.sqlite 열기 실패: \(error)")
            return nil
        }
    }

    /// 절 하나의 원어 단어 목록. 번들 DB를 못 열었거나 그 절이 파싱 대상에서
    /// 빠졌으면(원본 변환 스크립트가 모든 절을 커버하지 못함, README 참고) 빈
    /// 배열을 돌려준다 — 호출부(OriginalTextInfoView)가 "원문 정보 없음" 상태로
    /// 처리한다.
    func words(bookId: Int, chapter: Int, verse: Int) -> [OriginalWordInfo] {
        guard let store = resolvedStore() else { return [] }
        do {
            return try store.words(bookId: bookId, chapter: chapter, verse: verse)
        } catch {
            print("[OriginalTextLookupService] 조회 실패: \(error)")
            return []
        }
    }
}
