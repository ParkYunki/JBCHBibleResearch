import Foundation
import SwiftData

// Strong 번호별 한글 뜻풀이 캐시. STEPBible 영어 뜻풀이를 Apple Translation으로 번역한 결과를 저장해 재번역을 피한다.
// 캐시 키는 Strong 번호(`strongCode`, 예: "G2316") — 같은 번호는 어느 절에 나오든 같은 뜻풀이를 쓰므로 절이 아니라 번호 단위로 캐싱한다.
// `sourceEnglishGloss`는 번역 시점의 영어 원문 스냅샷으로, 원문 데이터가 바뀌면 비교해 재번역 여부를 판단한다.
@Model
public final class StrongGlossTranslation {
    public var strongCode: String = ""
    public var sourceEnglishGloss: String = ""
    public var koreanGloss: String = ""
    public var updatedAt: Date = Date.now

    public init(
        strongCode: String,
        sourceEnglishGloss: String,
        koreanGloss: String,
        updatedAt: Date = .now
    ) {
        self.strongCode = strongCode
        self.sourceEnglishGloss = sourceEnglishGloss
        self.koreanGloss = koreanGloss
        self.updatedAt = updatedAt
    }
}
