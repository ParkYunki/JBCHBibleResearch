import Foundation
import SwiftData

// 번들 번역본은 정적 자산(동기화 제외), 사용자 추가 번역본은 CloudKit 파일 동기화 대상이다.

@Model
public final class TranslationRegistry {
    public var id: UUID = UUID()
    public var code: String = ""
    public var displayName: String = ""
    public var isBundled: Bool = false
    public var isUserAdded: Bool = false
    public var licenseType: String?
    public var addedAt: Date = Date.now

    /// 설정에서 활성화한 번역본인지 여부. 꺼지면 검색과 성경 조회 표시 후보(`TranslationPickerPopover` 포함)에서 제외된다.
    /// 기본값 `true` — 이 필드가 생기기 전에 추가된 번역본도 라이트웨이트 마이그레이션 후 모두 활성 상태로 유지된다.
    public var isEnabled: Bool = true

    /// `isBundled == true`: 앱 번들 내 정적 경로.
    /// `isUserAdded == true`: 로컬에 materialize된 캐시 파일 경로 — 기기별로 다시
    /// 생성되므로 이 필드 자체는 동기화 대상이 아니다.
    public var sqliteFileReference: String = ""

    /// `isUserAdded == true`일 때만 사용. `.externalStorage`로 표시해 SwiftData가
    /// 대용량 바이너리를 CloudKit CKAsset으로 자동 처리하게 한다.
    /// ⚠️ 동기화된 Data를 SQLite로 바로 열 수 없다 — 동기화 완료 시점에 로컬 앱지원 디렉터리에
    /// 실제 `.sqlite` 파일로 써낸 뒤(`sqliteFileReference` 갱신) 열어야 한다.
    @Attribute(.externalStorage)
    public var sqliteData: Data?

    /// 사용자 추가 번역본은 파일 안에 책 이름이 없는 경우가 대부분이라(book_id 정수만 있음), 어느 언어의
    /// 책 이름표(앱 레이어 `BookNameTable`)로 표시할지 가리키는 식별자. `nil`이면(번들 번역본은 항상 nil)
    /// 한글 기본 이름(`BooksProvider`)으로 표시한다. `BookNameTable` 자체는 앱 타겟에 있으므로
    /// 여기서는 문자열 식별자만 보관한다.
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
        addedAt: Date = .now,
        isEnabled: Bool = true
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
        self.isEnabled = isEnabled
    }
}
