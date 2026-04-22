import base64
import io
import os
import re
import zipfile
from typing import Any, Dict, List

import logging


def _dependency_error(exc: Exception) -> RuntimeError:
    return RuntimeError(
        "错误: 缺少必要的库。请先运行 `pip install -r requirements.txt`。\n"
        "如需隔离环境，执行 `python3 -m venv .venv && .venv/bin/pip install -r requirements.txt`。\n"
        f"详情: {exc}"
    )


try:
    import cv2
    import docx
    import fitz
    import imagehash
    import numpy as np
    import pytesseract
    from PIL import Image
except ImportError as exc:
    raise _dependency_error(exc) from exc


logger = logging.getLogger(__name__)


class DocumentParser:
    """文档解析器：负责提取文本、代码块、图片和元数据。"""

    CV_PREPROCESS = True

    @staticmethod
    def read_file(filepath: str) -> Dict[str, Any]:
        result = {
            "content": "",
            "clean_text": "",
            "code_blocks": [],
            "images": [],
            "metadata": {},
            "filepath": filepath,
            "filename": os.path.basename(filepath),
            "error": None,
        }

        try:
            ext = os.path.splitext(filepath)[1].lower()
            if ext == ".pdf":
                DocumentParser._parse_pdf(filepath, result)
            elif ext == ".docx":
                DocumentParser._parse_docx(filepath, result)
            elif ext in [".md", ".txt"]:
                DocumentParser._parse_text(filepath, result)
            else:
                result["error"] = "不支持的文件格式"
        except Exception as exc:
            result["error"] = str(exc)

        if result["content"]:
            result["code_blocks"] = DocumentParser._extract_code_blocks(result["content"])
            if result.get("image_ocr_texts"):
                for text in result["image_ocr_texts"]:
                    result["code_blocks"].extend(DocumentParser._extract_code_blocks(text))
            result["clean_text"] = DocumentParser._clean_text(result["content"])

        return result

    @staticmethod
    def _extract_code_blocks(text: str) -> List[str]:
        pattern = r"```(?:\w+)?\s*([\s\S]*?)```"
        blocks = re.findall(pattern, text, re.DOTALL)
        if not blocks:
            lines = text.splitlines()
            tmp = []
            res = []
            keyword_pattern = (
                r"\b(def|class|for|while|if|elif|return|function|var|let|const|#include|"
                r"import|public|private|try|catch|python|curl|bash|sh|gcc|g\+\+|make|"
                r"openssl|nc|netcat|wget|pip|npm|node|java|go|rustc|clang)\b"
            )
            for line in lines:
                score = sum(1 for ch in line if ch in "{}[]();=<>+/#")
                if score >= 2 or re.search(keyword_pattern, line):
                    tmp.append(line)
                else:
                    if len(tmp) >= 2:
                        res.append("\n".join(tmp))
                    tmp = []
            if len(tmp) >= 2:
                res.append("\n".join(tmp))
            blocks = res
        if not blocks:
            keyword_pattern = (
                r"\b(def|class|for|while|if|elif|return|function|var|let|const|#include|"
                r"import|public|private|try|catch|python|curl|bash|sh|gcc|g\+\+|make|"
                r"openssl|nc|netcat|wget|pip|npm|node|java|go|rustc|clang)\b"
            )
            n = len(text)
            win = 400
            step = 200
            windows = []
            for i in range(0, n, step):
                seg = text[i : i + win]
                score = sum(1 for ch in seg if ch in "{}[]();=<>+/#")
                hits = len(re.findall(keyword_pattern, seg))
                if score >= 10 or hits >= 3:
                    windows.append(seg)
            blocks = windows
        return [block.strip() for block in blocks if len(block.strip()) > 20]

    @staticmethod
    def _parse_pdf(filepath: str, result: Dict[str, Any]) -> None:
        doc = fitz.open(filepath)
        text_content = []
        result["metadata"] = doc.metadata
        for page in doc:
            text_content.append(page.get_text("text"))
            for img_info in page.get_images(full=True):
                xref = img_info[0]
                try:
                    base_image = doc.extract_image(xref)
                    DocumentParser._process_image_bytes(
                        base_image["image"],
                        result,
                        {"type": "pdf", "page": page.number + 1},
                    )
                except Exception:
                    continue
        content = "\n".join(text_content)
        content = re.sub(r"-\s*\n", "", content)
        content = re.sub(r"\s+", " ", content)
        result["content"] = content.strip()

    @staticmethod
    def _parse_docx(filepath: str, result: Dict[str, Any]) -> None:
        doc = docx.Document(filepath)
        texts = [para.text for para in doc.paragraphs]
        for table in getattr(doc, "tables", []):
            for row in table.rows:
                for cell in row.cells:
                    if cell.text:
                        texts.append(cell.text)
        result["content"] = "\n".join(texts)

        props = doc.core_properties
        result["metadata"] = {
            "author": props.author,
            "last_modified_by": props.last_modified_by,
            "created": str(props.created),
            "modified": str(props.modified),
        }

        with zipfile.ZipFile(filepath) as archive:
            for file_info in archive.infolist():
                if file_info.filename.startswith("word/media/"):
                    try:
                        with archive.open(file_info) as img_file:
                            DocumentParser._process_image_bytes(
                                img_file.read(),
                                result,
                                {"type": "docx", "name": file_info.filename},
                            )
                    except Exception:
                        continue

    @staticmethod
    def _parse_text(filepath: str, result: Dict[str, Any]) -> None:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as handle:
            result["content"] = handle.read()

    @staticmethod
    def _process_image_bytes(img_data: bytes, result: Dict[str, Any], ctx: Dict[str, Any] | None = None) -> None:
        try:
            if DocumentParser.CV_PREPROCESS:
                nparr = np.frombuffer(img_data, np.uint8)
                img_cv = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
                if img_cv is None:
                    return
                gray = cv2.cvtColor(img_cv, cv2.COLOR_BGR2GRAY)
                blur = cv2.GaussianBlur(gray, (5, 5), 0)
                img_pil = Image.fromarray(blur)
            else:
                img_pil = Image.open(io.BytesIO(img_data)).convert("L")

            phash = imagehash.phash(img_pil, hash_size=8)
            dhash = imagehash.dhash(img_pil, hash_size=8)
            ahash = imagehash.average_hash(img_pil, hash_size=8)

            thumb = img_pil.copy()
            thumb.thumbnail((180, 180))
            buf = io.BytesIO()
            thumb.save(buf, format="JPEG", quality=60)
            thumb_b64 = base64.b64encode(buf.getvalue()).decode("ascii")

            ocr_preview = None
            try:
                ocr_text = pytesseract.image_to_string(img_pil)
                if ocr_text and len(ocr_text.strip()) > 10:
                    ocr_preview = re.sub(r"\s+", " ", ocr_text.strip())[:120]
            except Exception:
                pass

            result["images"].append(
                {
                    "hash_obj": phash,
                    "dhash_obj": dhash,
                    "ahash_obj": ahash,
                    "hash_str": str(phash),
                    "thumb_b64": thumb_b64,
                    "origin": ctx or {},
                    "ocr_preview": ocr_preview,
                }
            )
        except Exception:
            pass

    @staticmethod
    def _clean_text(text: str) -> str:
        if not text:
            return ""
        text = re.sub(r"(flag|ctf|cyber|key)\{.*?\}", "", text, flags=re.IGNORECASE)
        text = re.sub(r"[a-fA-F0-9]{32,}", "", text)
        text = re.sub(r"[a-zA-Z0-9+/]{50,}={0,2}", "", text)
        text = re.sub(r"```.*?```", "", text, flags=re.DOTALL)
        text = re.sub(r"[^\w\s\u4e00-\u9fa5]", " ", text)
        text = re.sub(r"\s+", " ", text)
        return text.lower().strip()
