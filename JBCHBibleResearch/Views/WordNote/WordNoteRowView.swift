//
//  WordNoteRowView.swift
//  JBCHBibleResearch
//
//  [2026-08-13 신설] `WordNoteHomeView`(개인 묵상+말씀 요약 통합 목록)의 행 하나.
//  기존 `MemoRowView`/`WordSummaryHomeView.WordSummaryRowView`(둘 다 이제 삭제됨)와
//  같은 원칙(미리보기 첫 줄 + 성경 좌표 + 인덱스 갱신 배지)에, 사용자 요청대로
//  "리스트 항목 앞에 카테고리를 표시"하는 배지를 앞에 붙였다.
//
//  [2026-09-12 수정] 사용자가 검토한 "말씀 노트 레이아웃 개선안"(HTML 목업,
//  아이폰/아이패드/맥 시뮬레이션 — 자세한 반영 근거는 `WordNoteHomeView.swift`
//  상단 새 주석 참고) 3항·7항을 그대로 반영 — ① 행의 정보 위계를 "노트
//  종류·날짜 → 제목 → 성경 구절 → 본문 미리보기" 순으로 재배열했다(기존엔
//  카테고리 배지+제목이 한 줄, 좌표+날짜가 그 아래 한 줄뿐이었다 — 본문
//  미리보기 자체가 아예 없었음). ② 그 목업이 "연구문서 서가" 목업에서 가져와
//  통일한 spine(책등) 왼쪽 색선 — `categoryBadge`와 완전히 같은 색을 행 왼쪽에
//  세로 막대로 한 번 더 표시해, 목록을 빠르게 훑을 때도 종류 구분이 되게 한다.
//  `previewTitle`/`previewSnippet`/`coordinateLabel`/`dateLabel`(원래 이 파일
//  private 계산 프로퍼티였던 것)과 카테고리→색 매핑은, 상세 패널의 "최근 노트"
//  카드(`WordNoteHomeView.swift`의 `WordNoteRecentEmptyState`)도 정확히 같은
//  값을 보여줘야 해서 각각 `WordNoteItem.xxx`/`WordNoteCategory.spineColor`로
//  옮겼다 — 이 파일은 이제 그 공용 프로퍼티를 그대로 읽기만 한다.
//

import SwiftUI
import BibleResearchModels

struct WordNoteRowView: View {
    let item: WordNoteItem
    /// [2026-09-09 추가] 사용자 요청 — "테마를 적용하면 배경색과 글자색을
    /// 전체적으로 적용할 수 있는가(... 말씀노트 화면 배경색...)." 이 행의
    /// 제목/좌표 텍스트는 지금까지 시스템 기본색(`.primary`/`.secondary`)을
    /// 썼다 — `WordNoteHomeView`가 이제 리스트 배경을 테마색으로 바꿀 수
    /// 있으므로(그 파일 상단 주석 참고), 이 행 텍스트도 같은 색을 읽어야
    /// 한다. `TranslationColumnView`와 같은 읽기 전용 접근 패턴.
    private var settings: UserSettingsStore { .shared }

    var body: some View {
        // [2026-09-12 수정] 아래 각 줄 순서 — "노트 종류·날짜 → 제목 → 성경
        // 구절 → 본문 미리보기"(목업 3항). 인덱스 갱신 배지는 "노트 상태"에
        // 가까워 기존처럼 맨 첫 줄(카테고리 배지 옆)에 남겨 뒀다 — 위치만
        // 옮겼을 뿐 표시 조건(`item.pendingIndexRefresh`)은 그대로다.
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                categoryBadge
                if item.pendingIndexRefresh {
                    indexRefreshBadge
                }
                Spacer(minLength: 6)
                if let dateLabel = item.dateLabel {
                    Text(dateLabel)
                        .font(.caption)
                        .foregroundStyle(settings.bibleTextColor?.opacity(0.7) ?? .secondary)
                }
            }
            Text(item.previewTitle)
                .font(.headline)
                // [2026-09-09 추가] 위 `settings` 주석 참고 — 카테고리/
                // 인덱스 갱신 배지(위)는 의미색(파랑·초록·주황)이라
                // 테마와 무관하게 그대로 두지만, 이 제목 텍스트는 리스트
                // 배경과 같은 테마 계열이어야 대비가 유지된다.
                .foregroundStyle(settings.bibleTextColor ?? .primary)
                .lineLimit(1)
            Text(item.coordinateLabel)
                .font(.caption.weight(.semibold))
                // [2026-09-12 추가] 목업의 "성경 구절" 줄이 accent 계열로
                // 강조돼 있던 것을 그대로 옮긴다 — 이미 같은 행의 배지·
                // spine에 쓰는 `categoryColor`를 재사용해 새 색을 만들지
                // 않았다.
                .foregroundStyle(categoryColor)
            if let previewSnippet = item.previewSnippet {
                Text(previewSnippet)
                    .font(.caption)
                    // [2026-09-09 수정] `TranslationColumnView` 아이콘들이
                    // 이미 쓰는 `settings.bibleTextColor ?? .secondary`
                    // 폴백 관례를 그대로 따랐다.
                    .foregroundStyle(settings.bibleTextColor?.opacity(0.75) ?? .secondary)
                    .lineLimit(2)
            }
            if item.pendingIndexRefresh {
                Text("이 항목을 열었다가 닫으면 관련 구절 인덱스가 다시 생성됩니다.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
        // [2026-09-12 추가] "연구문서 서가" 목업과 통일한 spine(책등) 왼쪽
        // 색선 — 왼쪽에 3pt 여백을 더 두고, 그 여백 안에 `categoryColor`
        // 막대를 그린다(패딩을 먼저 적용해야 오버레이가 여백까지 포함한
        // 바깥 경계에 맞춰 그려진다).
        .padding(.leading, 11)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(categoryColor)
                .frame(width: 3)
        }
    }

    /// 사용자 요청 — "리스트에서 리스트 항목 앞에 카테고리를 표시할 것."
    private var categoryBadge: some View {
        Text(item.category.rawValue)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(categoryColor.opacity(0.15))
            .foregroundStyle(categoryColor)
            .clipShape(Capsule())
    }

    /// [2026-09-12 수정] 매핑 자체(가죽 표지=개인 묵상/서재 금박=말씀 요약)는
    /// 바뀌지 않았다 — `WordNoteCategory.spineColor`(`WordNoteHomeView.swift`)로
    /// 옮겨 "최근 노트" 카드와 정확히 같은 색을 쓰게 한 것뿐이다.
    private var categoryColor: Color { item.category.spineColor }

    /// `MemoRowView.indexRefreshBadge`/`WordSummaryRowView.indexRefreshBadge`와
    /// 같은 시각 언어(연구문서 상태 배지 — 대기/추출중=주황).
    private var indexRefreshBadge: some View {
        Text("인덱스 갱신 필요")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15))
            .foregroundStyle(Color.orange)
            .clipShape(Capsule())
    }
}
