"""Tests de la variante upload PDF de l'ingestion des documents de recherche.

Couvre l'endpoint POST /tenants/{tenant_id}/research/documents/upload :
extraction de texte, dédup partagée avec la variante JSON, et les rejets
explicites (non-PDF, PDF quasi vide, PDF corrompu).
"""
import os

import pytest
from sqlalchemy import func, select

from app.models import DestinationResearchDocument

# Texte ASCII pur (Helvetica/Type1 n'a pas d'accentuation fiable à l'extraction)
# et > 50 caractères pour passer le garde-fou « PDF scanné sans OCR ».
NATIVE_TEXT = (
    "Guide touristique de la Casbah d Alger : sites classes par l UNESCO, "
    "musees et monuments a ne pas manquer."
)


def _make_pdf_bytes(text: str) -> bytes:
    """Génère un PDF 1.4 minimal d'une page avec une couche texte native.

    Suffisant pour que ``pypdf.PdfReader.extract_text()`` récupère ``text``
    (police Type1 Helvetica). ``text=""`` produit une page blanche.
    """
    content = f"BT /F1 12 Tf 72 720 Td ({text}) Tj ET".encode("ascii")
    stream_obj = (
        b"<< /Length "
        + str(len(content)).encode("ascii")
        + b" >>\nstream\n"
        + content
        + b"\nendstream"
    )
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        (
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
            b"/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>"
        ),
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        stream_obj,
    ]

    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for index, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % index
        out += body
        out += b"\nendobj\n"

    xref_offset = len(out)
    out += b"xref\n0 %d\n" % (len(objects) + 1)
    out += b"0000000000 65535 f \n"
    for offset in offsets:
        out += b"%010d 00000 n \n" % offset
    out += (
        b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n"
        % (len(objects) + 1, xref_offset)
    )
    return bytes(out)


def _upload_url(tenant_id) -> str:
    return f"/api/v1/tenants/{tenant_id}/research/documents/upload"


@pytest.mark.asyncio
async def test_upload_pdf_with_native_text_creates_document(
    client, admin_headers, test_tenant, db_session
):
    response = await client.post(
        _upload_url(test_tenant.id),
        headers=admin_headers,
        data={"source_type": "guide", "language": "fr"},
        files={"file": ("guide.pdf", _make_pdf_bytes(NATIVE_TEXT), "application/pdf")},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["tenant_id"] == str(test_tenant.id)
    assert data["source_type"] == "guide"
    assert data["status"] == "raw"
    assert len(data["content_hash"]) == 64  # sha256 hex

    # La réponse n'expose pas raw_text : on vérifie l'extraction en DB.
    result = await db_session.execute(
        select(DestinationResearchDocument).where(
            DestinationResearchDocument.tenant_id == test_tenant.id
        )
    )
    doc = result.scalar_one()
    assert "Casbah" in doc.raw_text
    assert "UNESCO" in doc.raw_text


@pytest.mark.asyncio
async def test_upload_same_pdf_twice_is_deduplicated(
    client, admin_headers, test_tenant, db_session
):
    pdf_bytes = _make_pdf_bytes(NATIVE_TEXT)
    first = await client.post(
        _upload_url(test_tenant.id),
        headers=admin_headers,
        data={"source_type": "guide"},
        files={"file": ("guide.pdf", pdf_bytes, "application/pdf")},
    )
    second = await client.post(
        _upload_url(test_tenant.id),
        headers=admin_headers,
        data={"source_type": "guide"},
        files={"file": ("guide.pdf", pdf_bytes, "application/pdf")},
    )
    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["id"] == second.json()["id"], (
        "redéposer le même PDF doit renvoyer le document existant, "
        "pas en créer un doublon"
    )
    assert first.json()["content_hash"] == second.json()["content_hash"]

    count = await db_session.execute(
        select(func.count())
        .select_from(DestinationResearchDocument)
        .where(DestinationResearchDocument.tenant_id == test_tenant.id)
    )
    assert count.scalar_one() == 1, "le même PDF déposé deux fois ne crée qu'une ligne"


@pytest.mark.asyncio
async def test_upload_rejects_non_pdf_content_type(client, admin_headers, test_tenant):
    response = await client.post(
        _upload_url(test_tenant.id),
        headers=admin_headers,
        data={"source_type": "guide"},
        files={"file": ("guide.txt", b"ce n'est pas un pdf", "text/plain")},
    )
    assert response.status_code == 400
    assert "PDF" in response.json()["detail"]


@pytest.mark.asyncio
async def test_upload_rejects_pdf_with_too_little_text(
    client, admin_headers, test_tenant
):
    # Une page quasi vide (un seul caractère) : assimilable à un scan sans OCR.
    response = await client.post(
        _upload_url(test_tenant.id),
        headers=admin_headers,
        data={"source_type": "guide"},
        files={"file": ("scan.pdf", _make_pdf_bytes("A"), "application/pdf")},
    )
    assert response.status_code == 422
    assert "PDF scanné sans OCR" in response.json()["detail"]


@pytest.mark.asyncio
async def test_upload_rejects_corrupted_pdf(client, admin_headers, test_tenant):
    garbage = os.urandom(512)  # jamais de marqueur %%EOF → pypdf lève une erreur
    response = await client.post(
        _upload_url(test_tenant.id),
        headers=admin_headers,
        data={"source_type": "guide"},
        files={"file": ("corrupt.pdf", garbage, "application/pdf")},
    )
    assert response.status_code == 422
    assert response.json()["detail"] == "PDF illisible ou corrompu"


@pytest.mark.asyncio
async def test_upload_rejects_unknown_source_type(client, admin_headers, test_tenant):
    # La variante Form bypass le schéma ResearchDocumentIngest : la validation
    # doit rester équivalente à la variante JSON (422, pas un 500 de response_model).
    response = await client.post(
        _upload_url(test_tenant.id),
        headers=admin_headers,
        data={"source_type": "reseau_social"},
        files={"file": ("guide.pdf", _make_pdf_bytes(NATIVE_TEXT), "application/pdf")},
    )
    assert response.status_code == 422
    assert "source_type invalide" in response.json()["detail"]


@pytest.mark.asyncio
async def test_upload_is_tenant_isolated(client, other_admin_headers, test_tenant):
    # Isolation des routes /{tenant_id}/... : un admin d'un autre tenant reçoit 404.
    response = await client.post(
        _upload_url(test_tenant.id),
        headers=other_admin_headers,
        data={"source_type": "guide"},
        files={"file": ("guide.pdf", _make_pdf_bytes(NATIVE_TEXT), "application/pdf")},
    )
    assert response.status_code == 404
