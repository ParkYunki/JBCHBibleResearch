#!/usr/bin/env python3
"""
convert_multilingual_e5_small.py

[2026-08-19 신설] 사용자 요청 — 성경 의미검색 임베딩 모델을 애플 내장
NLContextualEmbedding 대신 intfloat/multilingual-e5-small(오픈소스, 한국어 지원
명시)로 교체. 이 스크립트는 이 세션(리눅스 샌드박스, huggingface.co 접속 차단,
torch 설치도 시간/용량 초과로 실패)이 아니라 **사용자의 맥에서 직접** 실행해야
한다 — 인터넷이 열려 있고 디스크 여유가 있는 일반 환경이 필요하다.

⚠️⚠️ [실행 검증 안 됨] 이 스크립트 자체는 이 세션에서 한 번도 실행해보지
못했다 — torch/coremltools 설치가 이 샌드박스에서 네트워크/시간 제약으로
실패했고, huggingface.co 접속도 막혀 있어 모델을 받을 수조차 없었다. 아래
코드는 Hugging Face 공식 사용법(모델 카드)과 coremltools의 표준 BERT류 변환
패턴을 그대로 따른 것이지만, 실행 중 에러가 나면 그 에러 메시지를 그대로
알려주면 바로 고칠 수 있다.

실행 방법(맥 터미널):
    cd ~/아무-작업폴더
    python3 -m venv .venv && source .venv/bin/activate
    pip install torch transformers coremltools
    python3 convert_multilingual_e5_small.py

완료되면 이 폴더에 다음이 생긴다:
    - MultilingualE5Small.mlpackage   (Xcode 프로젝트에 그대로 드래그해 추가)
    - MultilingualE5SmallTokenizer/   (tokenizer_config.json, tokenizer.json 등 —
      이 폴더 전체를 "폴더 참조"로 Xcode에 추가. swift-transformers의
      `AutoTokenizer.from(modelFolder:)`가 바로 이 두 파일을 읽는다.)
"""

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
import coremltools as ct
from transformers import AutoTokenizer, AutoModel

MODEL_NAME = "intfloat/multilingual-e5-small"
# 개역한글 절 하나(가장 긴 편인 에스더 8:9 등)도 넉넉히 담을 수 있는 길이로
# 잡았다 — 정확한 최대 토큰 수는 실측하지 않았으니, 변환 후 유난히 긴 절에서
# 잘림이 의심되면 이 값을 늘리고 다시 변환하면 된다.
MAX_LENGTH = 128
OUTPUT_MODEL_NAME = "MultilingualE5Small.mlpackage"
OUTPUT_TOKENIZER_DIR = "MultilingualE5SmallTokenizer"


class MeanPoolingE5Embedder(nn.Module):
    """
    intfloat/multilingual-e5-small 모델 카드가 명시한 공식 사용법(마스킹된
    평균 풀링 + L2 정규화)을 그대로 forward에 포함시킨다 — Swift 쪽에서는
    이 한 번의 모델 호출만으로 곧바로 정규화된 임베딩 벡터를 받게 하기 위함
    (풀링/정규화 수식을 Swift로 다시 구현해 두 구현이 어긋날 위험을 없앤다).
    """

    def __init__(self, base_model: nn.Module):
        super().__init__()
        self.base_model = base_model

    def forward(self, input_ids: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
        # CoreML은 int32로 넘어오는 게 자연스럽지만 임베딩 조회(nn.Embedding)는
        # int64 인덱스를 요구한다 — 여기서 명시적으로 올려 캐스팅한다.
        input_ids = input_ids.long()
        attention_mask_float = attention_mask.float()

        # [수정] `AutoModel.from_pretrained(..., torchscript=True)`로 불러온
        # 모델은 트레이싱 호환을 위해 출력이 `BaseModelOutput`(속성으로 접근,
        # `.last_hidden_state`) 대신 평범한 튜플로 나온다 — 실제 실행 결과
        # `AttributeError: 'tuple' object has no attribute 'last_hidden_state'`
        # 로 확인됨. 튜플의 첫 번째 요소가 last_hidden_state다(HF 문서 표준
        # 순서: last_hidden_state, [pooler_output], [hidden_states], ...).
        outputs = self.base_model(input_ids=input_ids, attention_mask=attention_mask.long())
        last_hidden = outputs[0]  # [batch, seq, hidden]

        mask = attention_mask_float.unsqueeze(-1).expand(last_hidden.size())
        summed = torch.sum(last_hidden * mask, dim=1)
        counts = torch.clamp(mask.sum(dim=1), min=1e-9)
        pooled = summed / counts

        normalized = F.normalize(pooled, p=2, dim=1)
        return normalized


def main() -> None:
    print(f"[1/5] 토크나이저/모델 다운로드 중: {MODEL_NAME}")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
    base_model = AutoModel.from_pretrained(MODEL_NAME, torchscript=True)
    base_model.eval()

    wrapper = MeanPoolingE5Embedder(base_model)
    wrapper.eval()

    print("[2/5] TorchScript 트레이싱 중")
    dummy_input_ids = torch.ones((1, MAX_LENGTH), dtype=torch.int64)
    dummy_attention_mask = torch.ones((1, MAX_LENGTH), dtype=torch.int64)
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, (dummy_input_ids, dummy_attention_mask))

    print("[3/5] Core ML 변환 중 (몇 분 걸릴 수 있음)")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, MAX_LENGTH)),
            ct.TensorType(name="attention_mask", shape=(1, MAX_LENGTH)),
        ],
        outputs=[ct.TensorType(name="embedding")],
        minimum_deployment_target=ct.target.iOS17,
        compute_units=ct.ComputeUnit.ALL,
        convert_to="mlprogram",
    )
    mlmodel.short_description = "intfloat/multilingual-e5-small — 문장 임베딩(평균 풀링 + L2 정규화 포함)"
    mlmodel.input_description["input_ids"] = "토큰 ID 시퀀스 (길이 128, 패딩은 <pad> 토큰 ID)"
    mlmodel.input_description["attention_mask"] = "실제 토큰=1, 패딩=0"
    mlmodel.output_description["embedding"] = "384차원 L2 정규화된 문장 임베딩"

    print(f"[4/5] 저장 중: {OUTPUT_MODEL_NAME}")
    mlmodel.save(OUTPUT_MODEL_NAME)

    print(f"[5/5] 토크나이저 파일 저장 중: {OUTPUT_TOKENIZER_DIR}/")
    tokenizer.save_pretrained(OUTPUT_TOKENIZER_DIR)

    print("완료. 다음 두 가지를 Xcode 프로젝트에 추가하세요:")
    print(f"  1) {OUTPUT_MODEL_NAME} (그대로 드래그 — 빌드 시 자동으로 .mlmodelc로 컴파일됨)")
    print(f"  2) {OUTPUT_TOKENIZER_DIR}/ 폴더 전체 ('폴더 참조'로 추가 — 개별 파일 추가 금지, 폴더 구조가 유지돼야 함)")


if __name__ == "__main__":
    main()
