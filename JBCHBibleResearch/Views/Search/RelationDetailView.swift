import SwiftUI
import BibleResearchModels

//
//  RelationDetailView.swift
//  JBCHBibleResearch
//
//  통합검색의 "관계 정보" 카드 항목 하나의 상세 콘텐츠.
//  `PersonDetailView`/`ThemeDetailView`와 같은 방식으로, 관계 문장 + 원문 +
//  관련 성경구절 칩(`BibleVerseChipRow`)만 보여준다. 카드가 뜬 상태에서는
//  "성경구절" 섹션이 숨겨지므로(`SearchView.intentCardIsInlineDisplay`)
//  관계 문장이 가리키는 좌표는 이 화면의 칩이 대신 담당한다.
//
//  `RelationDisplayItem`엔 개요/생애/사건 같은 서술 컬럼이 없으므로
//  있는 정보(관계 문장, 원문, 구절)만 표시한다.
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
                Text(PersonRelationLabeling.displayRawSentence(item.relation.rawSentence)).font(.body)
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
