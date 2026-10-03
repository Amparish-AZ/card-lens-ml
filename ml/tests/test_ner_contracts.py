import pytest

from cardlens_ml.contracts import ContractError
from cardlens_ml.ner_contracts import NerCardAnnotation


def _card(tag: str = "B-NAME") -> dict[str, object]:
    return {
        "schema_version": 2,
        "card_id": "card-1",
        "physical_card_group": "physical-1",
        "image": "images/card-1.jpg",
        "source": "test",
        "split": "train",
        "verified": True,
        "tokens": [
            {
                "ocr_text": "Avery",
                "truth_text": "Avery",
                "tag": tag,
                "box": [0.1, 0.1, 0.2, 0.1],
                "confidence": 0.9,
                "line_index": 0,
            }
        ],
    }


def test_ner_contract_accepts_verified_bio_annotation() -> None:
    card = NerCardAnnotation.from_mapping(_card())
    assert card.tokens[0].tag == "B-NAME"
    assert card.verified


def test_ner_contract_rejects_unknown_entity() -> None:
    with pytest.raises(ContractError, match="unsupported BIO"):
        NerCardAnnotation.from_mapping(_card("B-DEPARTMENT"))
