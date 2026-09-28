import SwiftUI
import BibleResearchModels

//
//  RelationDetailView.swift
//  JBCHBibleResearch
//
//  [2026-09-16 신설] 통합검색의 "관계 정보" 카드 항목 하나의 상세 콘텐츠 —
//  `PersonDetailView`/`ThemeDetailView`와 같은 배경(사용자 피드백 "통합검색
//  페이지 자체가 인물/주제/관계 카드로 전환돼야 한다") + AskUserQuestion으로
//  확인한 범위 확장("AI토글의 모든 카드 유형") 결과 새로 생겼다.
//
//  기존(Phase 5, 2026-08-20)엔 관계 행을 탭해도 이동하지 않고 그 좌표들이
//  "성경구절" 섹션에 한꺼번에 나열됐다(`QueryIntentHandler.RelationDisplayItem`
//  주석, `SearchViewModel.performAIQuerySearch` 참고) — 사용자가 "클릭했을때
//  구절 이동 하지말고, 아래 성경구절로 표시될 수 있도록" 요청한 결과였다.
//  이번 요청으로 그 결정이 인물/주제와 같은 방식으로 대체된다: "성경구절"
//  섹션 자체가 이제 카드가 뜬 상태에서는 보이지 않으므로(`SearchView.
//  intentCardIsInlineDisplay` 참고), 관계 문장이 가리키는 좌표는 이 화면
//  안의 "관련 성경구절" 절 칩(`BibleVerseChipRow`, 인물/주제와 동일 컴포넌트)
//  이 대신 담당한다.
//
//  `RelationDisplayItem`엔 인물처럼 개요/생애/사건 같은 서술 컬럼이 없다 —
//  관계 문장(`PersonRelationLabeling.sentence`) 자체가 이미 이 항목의 전부다.
//  그래서 이 화면은 `ThemeDetailView`보다도 더 단순하다(문장 + 원문 + 성경구절
//  뿐) — 있지도 않은 정보를 채우려 하지 않는다(추측성 콘텐츠 금지).
//
//  ⚠️ [미검증] 이 세션엔 Xcode가 없어 컴파일 확인을 못 했다 — 이 프로젝트의
//  다른 신규 Swift 파일들과 같은 caveat.
//
struct RelationDetailView: View {
    let item: RelationDisplayItem
    private var settings: UserSettingsStore { .shared }

    var body: some View {
        Group {
            Section {
                header
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section("원문") {
                Text(item.relation.rawSentence).font(.body)
            }

            if !item.verseRefs.isEmpty {
                Section("관련 성경구절") {
                    BibleVerseChipRow(refs: item.verseRefs)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16))
                }
            }
        }
    }

    private var header: some View {
        Text(PersonRelationLabeling.sentence(for: item.relation))
            .font(.custom(SpecialPurposeFonts.titleSerif, size: 22, relativeTo: .title2))
            .fontWeight(.bold)
            .foregroundStyle(settings.bibleTextColor ?? .primary)
            .padding(.vertical, 6)
    }
}
