//
//  OCRReviewView.swift
//  JBCHBibleResearch
//
//  S7(OCR 검수) 화면. "원본 이미지 좌측, 추출 텍스트 우측에 나란히 배치, 텍스트
//  직접 수정 가능" + `[저장] [재시도] [폐기]` 버튼(screens.md 3장 S5/S6/S7 절 원문
//  그대로).
//
//  ⚠️ [레이아웃] 좁은 화면(아이폰)에서는 좌우 배치가 비현실적이라 세로 배치로
//  전환한다 — 원문서에 이 화면의 ASCII 목업이 없어(프로즈 설명만 있음) 상하 폭에
//  따른 적응형 레이아웃은 이번 구현에서 임의로 정한 것이다.
//
//  [2026-08-07 수정] 14.3 "검수 화면 진입(대기열 방식 — '저장 후 다음'으로 순차
//  처리)"을 반영해 큐 안에서 열릴 수 있게 됐다(OCRReviewQueueView.swift 참고).
//  `onAdvance`가 있으면(큐 안) 저장/폐기 후 그 클로저를 호출해 다음 문서로
//  넘어가고, 없으면(단독으로 열린 경우 — 이 화면 자체는 재사용 가능한 컴포넌트로
//  남겨 둔다) 기존처럼 dismiss()로 닫는다.
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

struct OCRReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let document: SourceDocument
    var onAdvance: (() -> Void)?
    /// 큐 안에서 열렸을 때 "2 / 5"처럼 진행 상황을 보여주기 위한 (현재 순번, 전체
    /// 개수). 단독으로 열린 경우(onAdvance == nil)엔 보통 nil.
    var queuePosition: (index: Int, count: Int)?

    @State private var viewModel: OCRReviewViewModel?
    @State private var loadedImage: PlatformImage?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(navigationTitleText)
        .onAppear(perform: setUpIfNeeded)
        .onChange(of: viewModel?.didSave) { _, didSave in
            guard didSave == true else { return }
            if let onAdvance {
                onAdvance()
            } else {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: OCRReviewViewModel) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                imagePane
                textPane(viewModel: viewModel)
            }
            .padding()

            VStack(alignment: .leading, spacing: 16) {
                imagePane
                textPane(viewModel: viewModel)
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            actionBar(viewModel: viewModel)
        }
        .alert("오류", isPresented: Binding(
            get: { viewModel.lastErrorDescription != nil },
            set: { if !$0 { viewModel.lastErrorDescription = nil } }
        )) {
            Button("확인") { viewModel.lastErrorDescription = nil }
        } message: {
            Text(viewModel.lastErrorDescription ?? "")
        }
    }

    // MARK: - 좌측: 원본 이미지

    @ViewBuilder
    private var imagePane: some View {
        Group {
            if let loadedImage {
                #if os(macOS)
                Image(nsImage: loadedImage)
                    .resizable()
                #else
                Image(uiImage: loadedImage)
                    .resizable()
                #endif
            } else {
                ContentUnavailableMessage("이미지를 불러올 수 없습니다.")
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(minWidth: 200, idealWidth: 360, maxWidth: 480)
    }

    // MARK: - 우측: 추출 텍스트(직접 수정 가능)

    private func textPane(viewModel: OCRReviewViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let confidence = viewModel.ocrResult?.confidence {
                Text("인식 신뢰도: \(Int(confidence * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: Binding(
                get: { viewModel.editedText },
                set: { viewModel.editedText = $0 }
            ))
            .font(.body)
            .frame(minHeight: 200)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - [저장] [재시도] [폐기]

    private func actionBar(viewModel: OCRReviewViewModel) -> some View {
        HStack {
            if viewModel.isRetrying {
                ProgressView().controlSize(.small)
                Text("OCR 다시 실행 중…").font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                Button("폐기", role: .destructive) { viewModel.discard() }
                Button("재시도") { Task { await viewModel.retry() } }
                Spacer()
                // 큐 안에서 마지막이 아닌 문서를 검수 중이면 "저장 후 다음"으로
                // 라벨을 바꿔, 저장하면 이 화면에 계속 머무는 게 아니라 다음
                // 문서로 넘어간다는 걸 미리 알려준다.
                Button(saveButtonTitle) { viewModel.save() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.bar)
    }

    // MARK: - 큐 진행 상황 표시

    private var navigationTitleText: String {
        guard let queuePosition else { return "OCR 검수" }
        return "OCR 검수 (\(queuePosition.index + 1) / \(queuePosition.count))"
    }

    private var saveButtonTitle: String {
        guard let queuePosition, queuePosition.index + 1 < queuePosition.count else { return "저장" }
        return "저장 후 다음"
    }

    // MARK: - 로드

    private func setUpIfNeeded() {
        guard viewModel == nil else { return }
        let vm = OCRReviewViewModel(document: document, modelContext: modelContext)
        vm.onAppear()
        viewModel = vm
        loadImage()
    }

    private func loadImage() {
        // [2026-08-18 수정, 기기 간 이식 fix] 북마크 직접 해석 대신 공용 헬퍼.
        guard let url = try? DocumentUploadService.resolveOriginalFileURL(for: document, context: modelContext) else { return }
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }
        loadedImage = PlatformImage(contentsOfFile: url.path)
    }
}

// MARK: - 플랫폼 공통 이미지 타입 별칭

#if os(macOS)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif

private struct ContentUnavailableMessage: View {
    let message: String
    init(_ message: String) { self.message = message }

    var body: some View {
        VStack {
            Spacer()
            Image(systemName: "photo")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
