import SwiftUI

//
//  NameListEditorView.swift
//  PersonSeedEditor
//
//  [2026-09-16 신설] 이름 목록 하나를 추가/삭제/수정하는 재사용 컴포넌트 —
//  가족관계 9종(할아버지~손녀)과 "관련 구절"(verses) 편집에 공통으로 쓴다.
//  값 자체는 `[String]`으로만 다루고, 가족관계 쪽 `StringOrArray` 변환은
//  호출부(`PersonEditorView`)가 담당한다 — 이 컴포넌트는 "문자열 목록
//  편집기"라는 단일 책임만 진다.
struct NameListEditorView: View {
    let title: String
    @Binding var items: [String]
    /// 관련 구절처럼 "책 장:절" 형식 힌트가 필요할 때만 채운다.
    var placeholder: String = "이름"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    TextField(placeholder, text: Binding(
                        get: { items.indices.contains(index) ? items[index] : "" },
                        set: { newValue in
                            guard items.indices.contains(index) else { return }
                            items[index] = newValue
                        }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Button(role: .destructive) {
                        guard items.indices.contains(index) else { return }
                        items.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }
            Button {
                items.append("")
            } label: {
                Label("\(title) 추가", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .font(.callout)
        }
    }
}
