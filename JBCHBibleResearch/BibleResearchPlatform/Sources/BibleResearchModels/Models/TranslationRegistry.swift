import Foundation
import SwiftData

// 근거: bible-research-platform-screens.md 6.7 — 번들 번역본은 정적 자산(동기화 제외,
// schema.md 0장), 사용자 추가 번역본은 CloudKit 파일 동기화 대상으로 변경 확정.

@Model
public final class TranslationRegistry {
    public var id: UUID = UUID()
    public var code: String = ""
    public var displayName: String = ""
    public var isBundled: Bool = false
    public var isUserAdded: Bool = false
    public var licenseType: String?
    public var addedAt: Date = Date.now

    /// `isBundled == true`: 앱 번들 내 정적 경로.
    /// `isUserAdded == true`: 로컬에 materialize된 캐시 파일 경로 — 기기별로 다시
    /// 생성되므로 이 필드 자체는 동기화 대상이 아니다(6.7).
    public var sqliteFileReference: String = ""

    /// `isUserAdded == true`일 때만 사용. `.externalStorage`로 표시해 SwiftData가
    /// 대용량 바이너리를 CloudKit CKAsset으로 자동 처리하게 한다(6.7 — CKRecord/CKAsset을
    /// 직접 다루는 코드 불필요). ⚠️ 놓치기 쉬운 구현 포인트(6.7): 동기화된 Data를
    /// SQLite로 바로 열 수 없다 — 동기화 완료 시점에 로컬 앱지원 디렉터리에 실제
    /// `.sqlite` 파일로 한 번 써낸 뒤(`sqliteFileReference` 갱신) 열어야 한다.
    @Attribute(.externalStorage)
    public var sqliteData: Data?

    /// 2026-08-06 추가 — 근거: 사용자가 이전에 만들어 쓰던 앱(BibleSeminarPresentationForIOS)의
    /// `TranslationInfo.bookNameTableID`를 그대로 가져온 필드. 사용자 추가 번역본은
    /// 파일 안에 책 이름이 안 들어있는 경우가 대부분이라(book_id 정수만 있음), 어느
    /// 언어의 책 이름표(앱 레이어의 `BookNameTable`, `Services/BookNameTable.swift`
    /// 참고)를 써서 표시할지 가리키는 식별자다. `nil`이면(번들 번역본은 항상 nil)
    /// 한글 기본 이름(`BooksProvider`)으로 표시한다 — 원본 주석의 정책 그대로.
    ///
    /// ⚠️ `BookNameTable` 자체는 이 패키지가 아니라 앱 타겟에 있다(순수 표시용
    /// 데이터라 CloudKit 동기화 대상 모델로 만들 필요가 없다고 판단) — 여기서는
    /// 문자열 식별자만 보관하고, 실제 이름표 조회/해석은 앱 레이어의 책임이다.
    public var bookNameTableID: String?

    public init(
        id: UUID = UUID(),
        code: String,
        displayName: String,
        isBundled: Bool,
        isUserAdded: Bool,
        licenseType: String? = nil,
        sqliteFileReference: String = "",
        sqliteData: Data? = nil,
        bookNameTableID: String? = nil,
        addedAt: Date = .now
    ) {
        self.id = id
        self.code = code
        self.displayName = displayName
        self.isBundled = isBundled
        self.isUserAdded = isUserAdded
        self.licenseType = licenseType
        self.sqliteFileReference = sqliteFileReference
        self.sqliteData = sqliteData
        self.bookNameTableID = bookNameTableID
        self.addedAt = addedAt
    }
}
