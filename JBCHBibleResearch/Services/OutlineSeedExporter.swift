//
//  OutlineSeedExporter.swift
//  JBCHBibleResearch
//
//  [2026-08-14 신설] 사용자 지적 — "왜 개요 시딩을 마음대로 json 파일 방식으로
//  바꿨지? 나는 리치 에디터 스타일을 먹이면서 개요를 작성하기를 원하는데, 그래서
//  내가 임시 별도페이지를 만들어달라고 하지 않았나?" — 이전 라운드에서
//  `OutlineSeedImporter`를 "사람이 평문 JSON을 직접 텍스트 편집기로 고치는" 방식으로
//  바꾼 게 잘못된 판단이었음을 인정하고 되돌린다.
//
//  ⚠️ [핵심 통찰, 이번에 바로잡은 것] "개요"(`BookOutline`/`ChapterSummary`) 화면은
//  이미 `OutlineBookBulkEditView`가 `RichTextEditor` + `EditorDefaultStyle`(글꼴/
//  글자색/배경색/줄간격)로 완전한 서식 편집을 지원하는 **실제 프로덕션 화면**이다
//  — 이 화면은 건드릴 필요가 전혀 없었다. 사용자가 원한 건 "리치 에디터 스타일이
//  살아있는 별도의 임시(배포시 제외) 페이지"였는데, 그건 새 에디터를 또 만들라는
//  뜻이 아니라 정확히 이 화면을 **개발자 자신의 기기에서 그대로 써서** 기본값
//  콘텐츠를 작성하고, 그 결과(서식 포함)를 배포용 시드 파일로 뽑아낼 방법이
//  필요하다는 뜻이었다. 그래서:
//  1. 개발자(박윤기)는 DEBUG 빌드에서 평소와 똑같이 사이드바 "개요" 메뉴로 들어가
//     `OutlineBookBulkEditView`에서 리치 에디터로 원하는 만큼 서식을 넣어 작성한다
//     (이 부분은 이미 다 있었다 — 아무것도 새로 안 만들어도 된다).
//  2. 그렇게 자신의 로컬 DB에 쌓인 `BookOutline`/`ChapterSummary`(내용은
//     `RichTextCodec`가 만드는 진짜 RTF 문자열, 서식 그대로)를, 이 파일의
//     `exportSeedJSON(context:)`가 `Resources/OutlineSeed.json`과 같은 JSON 배열
//     포맷으로 내보낸다 — `text` 필드에 RTF 문자열을 그대로 담는다(JSON 문자열은
//     원래 임의의 유니코드 텍스트를 담을 수 있어 `{`/`}`/`\` 같은 RTF 제어 문자도
//     `JSONSerialization`이 알아서 안전하게 이스케이프한다 — 별도 base64 인코딩 불필요).
//  3. 내보낸 JSON을 (설정 > 개발자 탭의) 저장 대화상자로 원하는 위치에 저장한 뒤,
//     `Resources/OutlineSeed.json`에 덮어쓰고 Xcode Copy Bundle Resources에
//     등록하면(최초 1회만 필요, 파일 상단 `OutlineSeedImporter.swift` 주석 참고)
//     끝난다.
//  4. `OutlineSeedImporter`는 그대로 두어도 된다 — `RichTextCodec.decode`가
//     `{\rtf1`로 시작하면 RTF로, 아니면 평문으로 자동 판별하는 규칙을 이미 갖고
//     있어서, 이 내보내기가 만드는 RTF 콘텐츠도 사람이 직접 손으로 쓴 평문 항목도
//     같은 JSON 배열 안에 섞여 있어도 각자 올바르게 처리된다(예: 서식이 꼭
//     필요없는 짧은 장은 사람이 평문으로 직접 채워도 무방하다).
//
//  ⚠️ [DEBUG 전용, 명확히 플래그] 이 파일 전체가 개발자 도구다 — 배포 빌드에는
//  포함되지 않도록 `#if DEBUG`로 감싼다(설정 > 개발자 탭도 동일). `OutlineSeedImporter`
//  (시드 파일을 읽어 신규 사용자 DB에 채워 넣는 쪽)는 배포 빌드에도 반드시 있어야
//  하므로 별도 파일로 남겨 뒀다 — 대칭이 아니라 의도적인 비대칭이다.
//

#if DEBUG
import Foundation
import SwiftData
import BibleResearchModels

@MainActor
enum OutlineSeedExporter {
    struct Summary {
        let bookCount: Int
        let chapterCount: Int
    }

    /// 지금 이 기기(개발자 자신의 DB)에 쌓인 책 개요/장 개요 중 내용이 있는
    /// 것만 모아 `OutlineSeed.json`과 같은 배열 포맷으로 내보낸다. `text` 필드는
    /// `contentHtml`(실제로는 RTF, `RichTextEditor.swift` 상단 주석 참고)을
    /// 그대로 옮긴다 — 리치 에디터로 넣은 서식(글꼴/색/굵게 등)이 그대로 보존된다.
    static func exportSeedJSON(context: ModelContext) throws -> (data: Data, summary: Summary) {
        let outlines = try context.fetch(FetchDescriptor<BookOutline>())
            .filter { !$0.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let summaries = try context.fetch(FetchDescriptor<ChapterSummary>())
            .filter { !$0.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        var entries: [[String: Any]] = []

        for outline in outlines.sorted(by: { $0.bookId < $1.bookId }) {
            guard let book = BooksProvider.shared.book(id: outline.bookId) else { continue }
            entries.append(["book": book.nameKo, "chapter": NSNull(), "text": outline.contentHtml])
        }
        for summary in summaries.sorted(by: { $0.bookId != $1.bookId ? $0.bookId < $1.bookId : $0.chapter < $1.chapter }) {
            guard let book = BooksProvider.shared.book(id: summary.bookId) else { continue }
            entries.append(["book": book.nameKo, "chapter": summary.chapter, "text": summary.contentHtml])
        }

        let data = try JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted, .sortedKeys])
        return (data, Summary(bookCount: outlines.count, chapterCount: summaries.count))
    }
}
#endif
