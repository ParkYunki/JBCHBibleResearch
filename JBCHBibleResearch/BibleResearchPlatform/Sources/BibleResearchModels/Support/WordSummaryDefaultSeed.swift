import Foundation

/// [2026-09-03 신설] 사용자 요청 — "'말씀 요약' 클릭 시 선택한 말씀 구절이
/// 기본 텍스트로 입력되는 부분을 뺄 것" + "말씀 요약 클릭했다가 아무 입력을
/// 하지 않고 닫기 버튼을 누르면 등록되지 않게 할 것." 성경 조회 화면에서
/// "말씀 요약" 버튼(`BibleReadingView.openWordSummaryEditor()`)을 누르면 지금도
/// 첫 줄에 "YYYY.MM.dd 말씀"이 기본으로 채워진다(사용자 확인 — "날짜 줄은
/// 남김, 성경 구절만 제거") — 그런데 이 문구가 남아 있는 한 본문이 "완전히
/// 비어있지" 않으므로, `WordSummaryEditorView.handleDisappear()`의 기존
/// "진짜 텍스트가 한 글자도 없어야만 자동 정리" 규칙(그 파일 상단 주석 참고)이
/// 그대로는 이 기본 문구만 남은 상태를 "비어있다"고 판단하지 못한다.
///
/// 그래서 "본문을 만들 때 이 기본 문구를 만드는 자리"와 "닫을 때 그 문구뿐인지
/// 확인하는 자리"가 정확히 같은 문자열을 계산해야 한다 — 이 타입 하나로
/// 그 계산을 한곳에 모아 양쪽(`BibleReadingView.swift`/`WordSummaryEditorView.swift`)
/// 이 같이 쓴다. `createdAt`(레코드 생성 시각, 한 번 정해지면 바뀌지 않는
/// 영구 저장 값)을 기준으로 다시 계산하는 방식이라, 예전에 `.contextual`이
/// 겪었던 버그(`WordSummaryEditorView.swift` 상단 2026-08-12 3차 수정 주석 참고 —
/// 화면이 다시 그려질 때 view의 `@State` 스냅샷이 "그 시점까지 사용자가 이미
/// 입력해 둔 내용"으로 잘못 다시 캡처되던 문제)와는 근본적으로 다르다 — 여기엔
/// view 생명주기에 따라 달라지는 `@State` 스냅샷이 전혀 없고, 모델 자신의
/// 고정된 `createdAt` 값만 본다.
public enum WordSummaryDefaultSeed {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()

    /// "말씀 요약" 편집기를 처음 열 때 채워주는 기본 문구.
    public static func text(for date: Date) -> String {
        "\(dateFormatter.string(from: date)) 말씀"
    }
}
