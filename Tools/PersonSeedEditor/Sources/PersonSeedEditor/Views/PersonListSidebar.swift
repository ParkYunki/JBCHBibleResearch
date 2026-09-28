import SwiftUI

//
//  PersonListSidebar.swift
//  PersonSeedEditor
//
struct PersonListSidebar: View {
    @EnvironmentObject var store: PersonSeedStore
    @Binding var selection: String?
    @State private var query = ""
    let onAddNew: () -> Void

    private var filtered: [PersonSeedEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.persons }
        return store.persons.filter {
            $0.word.contains(trimmed) || $0.idx.contains(trimmed) || $0.word2.contains { $0.contains(trimmed) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("이름/별칭/idx 검색", text: $query)
                    .textFieldStyle(.roundedBorder)
                Button {
                    onAddNew()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .help("새 인물 추가")
            }
            .padding(8)

            Divider()

            List(filtered, selection: $selection) { person in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(person.word.isEmpty ? "(이름 없음)" : person.word)
                            .font(.body.weight(.medium))
                        Spacer()
                        Text("idx=\(person.idx)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !person.call.isEmpty {
                        Text(person.call)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .tag(person.idx)
            }
            .listStyle(.sidebar)

            Divider()
            Text("\(filtered.count) / \(store.persons.count)명")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(6)
        }
    }
}
