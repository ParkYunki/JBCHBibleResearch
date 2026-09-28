import SwiftUI

//
//  PersonEditorView.swift
//  PersonSeedEditor
//
//  [2026-09-16 신설] 인물 한 명의 모든 필드를 편집하는 화면. `@State private
//  var working`(로컬 사본)에서만 수정하고, "저장"을 눌러야 비로소
//  `PersonSeedStore.save(_:isNew:)`(→ apply_person_edit.py)를 거쳐 실제
//  PersonSeed.json에 반영된다 — 그 전까지는 다른 인물로 이동하거나 앱을
//  닫아도 원본이 바뀌지 않는다.
struct PersonEditorView: View {
    @EnvironmentObject var store: PersonSeedStore
    /// nil이면 "새 인물 추가" 모드.
    let originalIdx: String?
    @State private var working: PersonSeedEntry
    @State private var showDeleteConfirm = false
    let onSaved: (PersonSeedEntry) -> Void
    let onDeleted: () -> Void

    init(entry: PersonSeedEntry, isNew: Bool, onSaved: @escaping (PersonSeedEntry) -> Void, onDeleted: @escaping () -> Void) {
        self.originalIdx = isNew ? nil : entry.idx
        var seed = entry
        // 관계 블록이 비어 있으면(원본 파일에선 안 나타나지만, "새 인물
        // 추가"로 만든 빈 항목까지 항상 안전하게) 편집 UI가 기대하는
        // 길이 1로 맞춰 둔다.
        if seed.description.relations.isEmpty {
            seed.description.relations = [PersonSeedRelationBlock.blank]
        }
        _working = State(initialValue: seed)
        self.onSaved = onSaved
        self.onDeleted = onDeleted
    }

    private var isNew: Bool { originalIdx == nil }

    /// `description.관계[0]`에 안전하게 접근하는 바인딩 — 위 init에서 항상
    /// 길이 1 이상을 보장하므로 인덱스 0 접근은 안전하다.
    private var relationBinding: Binding<PersonSeedRelationBlock> {
        Binding(
            get: { working.description.relations.first ?? .blank },
            set: { newValue in
                if working.description.relations.isEmpty {
                    working.description.relations = [newValue]
                } else {
                    working.description.relations[0] = newValue
                }
            }
        )
    }

    private func stringOrArrayBinding(_ keyPath: WritableKeyPath<PersonSeedRelationBlock, StringOrArray>) -> Binding<[String]> {
        Binding(
            get: { relationBinding.wrappedValue[keyPath: keyPath].values },
            set: { newValues in
                var block = relationBinding.wrappedValue
                block[keyPath: keyPath] = StringOrArray.fromValues(newValues)
                relationBinding.wrappedValue = block
            }
        )
    }

    var body: some View {
        Form {
            Section("idx") {
                Text(working.idx)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Section("기본 정보") {
                TextField("이름 (word)", text: $working.word)
                NameListEditorView(title: "별칭", items: $working.word2, placeholder: "별칭")
                TextField("분류 (kind)", text: $working.kind)
                TextField("kind2", text: $working.kind2)
                TextField("호칭/직함 (call)", text: $working.call)
                TextField("이름의 뜻 (meaning)", text: $working.meaning)
            }

            Section("서술") {
                LabeledTextEditor(label: "개요 (introduce)", text: $working.introduce)
                LabeledTextEditor(label: "주요 생애 (lifetime)", text: $working.lifetime)
                LabeledTextEditor(label: "업적과 사건 (event)", text: $working.event)
                LabeledTextEditor(label: "성품과 특징 (character)", text: $working.character)
            }

            Section("인물 정보") {
                TextField("출신", text: $working.description.origin)
                TextField("민족", text: $working.description.nation)
                TextField("지파", text: $working.description.tribe)
                TextField("성별", text: $working.description.gender)
                NameListEditorView(title: "직업/직위", items: $working.description.occupations, placeholder: "직업/직위")
            }

            Section("가족관계") {
                NameListEditorView(title: "할아버지", items: stringOrArrayBinding(\.grandfather), placeholder: "할아버지")
                NameListEditorView(title: "할머니", items: stringOrArrayBinding(\.grandmother), placeholder: "할머니")
                NameListEditorView(title: "아버지", items: stringOrArrayBinding(\.father), placeholder: "아버지")
                NameListEditorView(title: "어머니", items: stringOrArrayBinding(\.mother), placeholder: "어머니")
                NameListEditorView(title: "배우자", items: stringOrArrayBinding(\.spouse), placeholder: "배우자")
                NameListEditorView(title: "아들", items: stringOrArrayBinding(\.sons), placeholder: "아들")
                NameListEditorView(title: "딸", items: stringOrArrayBinding(\.daughters), placeholder: "딸")
                NameListEditorView(title: "손자", items: stringOrArrayBinding(\.grandsons), placeholder: "손자")
                NameListEditorView(title: "손녀", items: stringOrArrayBinding(\.granddaughters), placeholder: "손녀")
            }

            Section("기타관계 (제자·동역자·친구 등 — \"이름(라벨)\" 형식)") {
                OtherRelationsEditorView(items: Binding(
                    get: { relationBinding.wrappedValue.otherRelations },
                    set: { newValue in
                        var block = relationBinding.wrappedValue
                        block.otherRelations = newValue
                        relationBinding.wrappedValue = block
                    }
                ))
            }

            Section("관련 구절") {
                NameListEditorView(title: "구절", items: $working.verses, placeholder: "예: 창 1:1")
            }

            Section("메모/비고") {
                LabeledTextEditor(label: "비고 (remark)", text: $working.remark)
                LabeledTextEditor(label: "메모 (memo)", text: $working.memo, minHeight: 160)
            }

            if !isNew {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("이 인물 삭제", systemImage: "trash")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(working.word.isEmpty ? "(이름 없음)" : working.word)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await store.save(working, isNew: isNew)
                        if store.lastError == nil {
                            onSaved(working)
                        }
                    }
                } label: {
                    if store.isBusy {
                        ProgressView()
                    } else {
                        Label("저장", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(store.isBusy || working.word.isEmpty)
                .help(working.word.isEmpty ? "이름(word)은 비워 둘 수 없습니다." : "PersonSeed.json에 저장합니다.")
            }
        }
        .alert("정말 삭제할까요?", isPresented: $showDeleteConfirm) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                Task {
                    await store.delete(working)
                    if store.lastError == nil {
                        onDeleted()
                    }
                }
            }
        } message: {
            Text("\"\(working.word)\"(idx=\(working.idx))을(를) PersonSeed.json에서 완전히 삭제합니다. 되돌릴 수 없습니다.")
        }
    }
}

/// 여러 줄 서술 필드(개요/생애/사건/메모 등) 공용 라벨+에디터.
private struct LabeledTextEditor: View {
    let label: String
    @Binding var text: String
    var minHeight: CGFloat = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .frame(minHeight: minHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25))
                )
        }
    }
}
