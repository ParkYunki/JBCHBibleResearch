//
//  OutlineSeedImporter.swift
//  JBCHBibleResearch
//
//  번들된 `Resources/OutlineSeed.json`의 기본 개요를 신규 사용자 DB로 복사해 넣는 1회성 가져오기(복사된 뒤에는
//  사용자가 수정 가능). 파일이 없으면 조용히 건너뛴다(에러 아님).
//
//  ## OutlineSeed.json 형식
//  ```json
//  [
//    { "book": "창세기", "chapter": null, "text": "책 전체 개요 텍스트" },
//    { "book": "창세기", "chapter": 1, "text": "1장 개요 텍스트" }
//  ]
//  ```
//  - `book`: 정경 순 66권 한글 이름 그대로(`books.json`의 `nameKo`) — 예: "창세기", "시편", "요한복음".
//    오타가 있으면 그 항목만 건너뛰고 콘솔에 로그를 남긴다(다른 항목엔 영향 없음).
//  - `chapter`: 생략하거나 `null`이면 "책 개요"(`BookOutline`), 숫자를 넣으면 그 장 개요(`ChapterSummary`).
//  - `text`: 순수 텍스트(줄바꿈은 `\n`) 또는 `OutlineSeedExporter`가 내보낸 RTF 문자열(`{\rtf1`로 시작).
//    `RichTextCodec.decode`가 접두사로 판별하므로 두 형식이 같은 배열에 섞여 있어도 된다.
//
//  작성 워크플로: DEBUG 빌드에서 `OutlineBookBulkEditView`의 리치 에디터로 서식을 넣어 작성 → 설정 > 개발자 탭의
//  "내보내기"(`OutlineSeedExporter`) → 결과를 `Resources/OutlineSeed.json`에 덮어쓴다. 서식이 필요 없는 짧은
//  항목은 텍스트 편집기로 직접 써도 된다.
//
//  ⚠️ JSON 파일을 처음 만든 뒤 Xcode Copy Bundle Resources에 한 번 등록해야 한다(다른 번들 리소스와 동일).
//  같은 경로를 유지하는 한 내용을 고쳐도 재등록은 필요 없다.
//
//  ⚠️ `importIfNeeded`는 기기당 한 번만 실행된다(`UserSettingsStore.hasImportedOutlineSeed` 플래그).
//  JSON을 고친 뒤 다시 테스트하려면 앱을 지우고 재설치해 플래그를 초기화해야 한다.
//

import Foundation
import SwiftData
import BibleResearchModels

@MainActor
enum OutlineSeedImporter {
    /// 항목마다 `ModelContext.fetch`/`insert`를 동기 호출하고 반복 횟수가 콘텐츠 분량(장 수)에 비례한다.
    /// `await` 없이 `@MainActor`에서 끝까지 돌면 최초 실행 때 UI 이벤트(온보딩 "다음" 탭 등)가 처리되지 못해
    /// 한동안 멈춘 것처럼 보이므로, `yieldInterval`개마다 `await Task.yield()`로 메인 런루프에 제어를 돌려준다.
    private static let yieldInterval = 20

    static func importIfNeeded(into context: ModelContext) async {
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

            for (index, raw) in rawEntries.enumerated() {
                // 메인 스레드를 계속 붙들지 않도록 일정 개수마다 실행을 양보한다(`yieldInterval` 참고).
                if index > 0 && index % yieldInterval == 0 {
                    await Task.yield()
                }
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
