//
//  OutlineSeedImporter.swift
//  JBCHBibleResearch
//
//  [2026-08-13 신설, 2026-08-14 재설계, 2026-08-14 2차 재설계, 2026-08-14 3차 정정]
//  사용자 요청 — "기본 개요 정보를 제공하고 싶음. 내가 개요를 입력한 내용을
//  앱의 기본 DB에 넣되, 배포할 때는 앱의 기본 DB의 내용이 사용자 DB로 복사해서
//  수정 가능하게 하도록 ... 리치 에디터 페이지를 만들어주되, 배포할 때는
//  해당기능을 빼야 함."
//
//  ⚠️ [2026-08-14 3차 정정, 중요] 2차 재설계 때 "사람이 텍스트 편집기로
//  OutlineSeed.json을 직접 고친다"는 워크플로를 기본값처럼 설명했는데, 이는
//  원래 요청("리치 에디터 스타일을 먹이면서 작성하고 싶다")과 어긋난 잘못된
//  판단이었다 — 사용자가 정확히 지적해 바로잡았다. **실제 권장 워크플로는
//  다음과 같다** (`OutlineSeedExporter.swift` 상단 주석 참고):
//  1. 개발자(박윤기)는 DEBUG 빌드에서 평소처럼 사이드바 "개요" 메뉴로 들어가
//     `OutlineBookBulkEditView`의 리치 에디터로 서식을 넣어 작성한다(새 화면
//     아님 — 이미 있는 프로덕션 화면을 그대로 쓴다).
//  2. 설정 > 개발자 탭의 "내보내기" 버튼이 그 결과(RTF 포함)를 아래 JSON
//     포맷으로 뽑아낸다.
//  3. 뽑아낸 파일을 `Resources/OutlineSeed.json`에 덮어쓰고 Xcode Copy Bundle
//     Resources에 등록한다(최초 1회만 필요).
//  아래 "직접 텍스트 편집기로 고치는 방법"은 서식이 필요 없는 짧은 항목을 급히
//  채워 넣고 싶을 때 쓸 수 있는 **보조 수단**으로만 남겨 둔다 — 서식이 필요한
//  항목은 반드시 위 리치 에디터 워크플로를 쓸 것.
//
//  ## (보조 수단) 텍스트 편집기로 직접 쓰거나 고치는 방법
//  이 프로젝트의 `Resources/OutlineSeed.json` 파일을 아무 텍스트 편집기(메모장,
//  VS Code, Xcode 등)로 열어 아래 형식의 JSON 배열을 직접 쓰거나 고치면 된다.
//  ```json
//  [
//    { "book": "창세기", "chapter": null, "text": "책 전체 개요 텍스트" },
//    { "book": "창세기", "chapter": 1, "text": "1장 개요 텍스트" }
//  ]
//  ```
//  - `book`: 정경 순 66권 한글 이름 그대로(`books.json`의 `nameKo`) — 예:
//    "창세기", "시편", "요한복음". 오타가 있으면 그 항목만 건너뛰고 콘솔에
//    로그를 남긴다(다른 항목엔 영향 없음).
//  - `chapter`: 생략하거나 `null`이면 "책 개요"(`BookOutline`), 숫자를 넣으면
//    그 장 개요(`ChapterSummary`).
//  - `text`: 순수 텍스트를 직접 써도 되고(줄바꿈은 `\n`으로 이스케이프),
//    `OutlineSeedExporter`가 내보낸 RTF 문자열(`{\rtf1`로 시작)을 그대로 붙여
//    넣어도 된다 — `RichTextCodec.decode`가 접두사로 자동 판별해 서식 있는
//    항목과 순수 텍스트 항목이 같은 배열 안에 섞여 있어도 각각 올바르게
//    처리된다.
//
//  ⚠️ [남은 수동 단계, 정확히 한 가지] 이 JSON 파일을 처음 만든 뒤에는 Xcode
//  프로젝트의 Copy Bundle Resources에 등록해야 한다 — 이 앱의 다른 모든 번들
//  리소스(BibleDB.sqlite, OriginalText.sqlite, books.json)도 똑같이 거쳐야
//  했던, Xcode 프로젝트라면 예외 없이 필요한 절차다. 파일 내용을 그 뒤에
//  아무리 고쳐도(같은 파일 경로를 유지하는 한) 이 등록을 다시 할 필요는 없다.
//
//  ⚠️ [테스트 시 주의] 아래 `importIfNeeded`는 기기(또는 개발 중이면 시뮬레이터/
//  Mac)당 딱 한 번만 실행된다(`UserSettingsStore.hasImportedOutlineSeed`
//  플래그). JSON 내용을 고친 뒤 다시 테스트하려면 앱을 지우고 재설치해야
//  플래그가 초기화된다 — 일반적인 iOS/macOS 개발 테스트 방식과 동일하다.
//
//  이 파일이 없으면(아직 콘텐츠를 만들지 않았으면) 조용히 건너뛴다 — 에러로
//  취급하지 않는다.
//

import Foundation
import SwiftData
import BibleResearchModels

@MainActor
enum OutlineSeedImporter {
    static func importIfNeeded(into context: ModelContext) {
        guard !UserSettingsStore.shared.hasImportedOutlineSeed else { return }
        defer { UserSettingsStore.shared.hasImportedOutlineSeed = true }

        guard let url = Bundle.main.url(forResource: "OutlineSeed", withExtension: "json") else {
            // 아직 번들에 시드 파일이 없다 — 정상 상황이므로 에러로 취급하지 않는다.
            return
        }

        do {
            let data = try Data(contentsOf: url)
            guard let rawEntries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                print("[OutlineSeedImporter] OutlineSeed.json이 배열(JSON array) 형식이 아닙니다.")
                return
            }

            var filledBookCount = 0
            var filledChapterCount = 0
            var skippedCount = 0

            for raw in rawEntries {
                guard let bookName = raw["book"] as? String, let text = raw["text"] as? String else {
                    print("[OutlineSeedImporter] 형식이 맞지 않아 건너뜁니다(book/text 필요): \(raw)")
                    skippedCount += 1
                    continue
                }
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedText.isEmpty else { continue }

                guard let book = resolveBook(named: bookName) else {
                    print("[OutlineSeedImporter] \"\(bookName)\" 책 이름을 찾지 못해 건너뜁니다 — books.json의 정확한 한글 이름(nameKo)과 맞는지 확인하세요.")
                    skippedCount += 1
                    continue
                }

                // JSON에 "chapter"가 없거나 null이면 raw["chapter"]는 nil이거나
                // NSNull이다 — 둘 다 `as? Int`가 nil을 돌려주므로 별도 처리 없이
                // "책 개요"로 해석된다.
                let chapter = raw["chapter"] as? Int

                do {
                    if let chapter {
                        let target = try ChapterSummaryDeduplication.findOrCreateChapterSummary(
                            bookId: book.bookId, chapter: chapter, context: context
                        )
                        guard target.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                        target.contentHtml = text
                        target.contentText = text
                        target.updatedAt = .now
                        filledChapterCount += 1
                    } else {
                        let target = try BookOutlineDeduplication.findOrCreateBookOutline(bookId: book.bookId, context: context)
                        guard target.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                        target.contentHtml = text
                        target.contentText = text
                        target.updatedAt = .now
                        filledBookCount += 1
                    }
                } catch {
                    print("[OutlineSeedImporter] \(bookName) 항목 적용 실패: \(error)")
                    skippedCount += 1
                }
            }

            try context.save()
            print("[OutlineSeedImporter] 기본 개요 가져오기 완료 — 책 \(filledBookCount)권 / 장 \(filledChapterCount)개 적용, \(skippedCount)개 건너뜀.")
        } catch {
            print("[OutlineSeedImporter] OutlineSeed.json 읽기 실패: \(error)")
        }
    }

    /// `book` 문자열을 `Book`으로 해석한다 — 정확한 한글 이름(`nameKo`) 우선,
    /// 없으면 약칭(`abbreviation`) 목록에서 찾는다. 공백은 앞뒤로 트리밍한다.
    private static func resolveBook(named name: String) -> Book? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = BooksProvider.shared.books.first(where: { $0.nameKo == trimmed }) {
            return exact
        }
        return BooksProvider.shared.books.first { $0.abbreviation.contains(trimmed) }
    }
}
