import ast
import difflib
import logging
import os
import re
import warnings
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor
from datetime import datetime
from typing import Dict, List, Tuple


def _dependency_error(exc: Exception) -> RuntimeError:
    return RuntimeError(
        "错误: 缺少必要的库。请先运行 `pip install -r requirements.txt`。\n"
        "如需隔离环境，执行 `python3 -m venv .venv && .venv/bin/pip install -r requirements.txt`。\n"
        f"详情: {exc}"
    )


try:
    from sklearn.feature_extraction.text import TfidfVectorizer
    from sklearn.metrics.pairwise import cosine_similarity
    from tqdm import tqdm
except ImportError as exc:
    raise _dependency_error(exc) from exc


from .parser import DocumentParser
from .report import ReportBuilder, build_ai_summary


logger = logging.getLogger(__name__)


class AuditEngine:
    def __init__(
        self,
        directory: str,
        text_thresh: float,
        img_thresh: int,
        output_dir: str | None = None,
        name_template: str | None = None,
        cv_preprocess: bool = True,
        dedup_thresh: float = 0.85,
        db_path: str | None = None,
        whitelist_path: str | None = None,
        simhash_thresh: int = 4,
        whitelist_mode: str = "mark",
    ) -> None:
        self.directory = directory
        self.text_threshold = text_thresh
        self.img_threshold = img_thresh
        self.output_dir = output_dir
        self.name_template = name_template
        self.documents: List[Dict] = []
        self.dedup_threshold = dedup_thresh
        self.db_path = db_path or os.path.join(os.getcwd(), "PitcherPlant.sqlite")
        self.whitelist_path = whitelist_path
        self.simhash_thresh = simhash_thresh
        self.whitelist_mode = whitelist_mode
        DocumentParser.CV_PREPROCESS = cv_preprocess

    def load_documents(self) -> None:
        files = []
        valid_exts = (".docx", ".pdf", ".md", ".txt")
        for root, _, filenames in os.walk(self.directory):
            for filename in filenames:
                if filename.lower().endswith(valid_exts) and not filename.startswith("~$"):
                    files.append(os.path.join(root, filename))

        logger.info("扫描到 %s 个文件，开始并行解析...", len(files))
        with ProcessPoolExecutor() as executor:
            results = list(tqdm(executor.map(DocumentParser.read_file, files), total=len(files), unit="file"))

        self.documents = [doc for doc in results if not doc["error"] and len(doc["content"]) > 10]
        logger.info("有效文档数: %s", len(self.documents))

    def get_text_snippet(self, text_a: str, text_b: str) -> str:
        matcher = difflib.SequenceMatcher(None, text_a, text_b)
        match = matcher.find_longest_match(0, len(text_a), 0, len(text_b))
        if match.size > 20:
            snippet = text_a[match.a : match.a + match.size]
            return snippet[:160].replace("\n", " ") + "..."
        return "全文语义高度相似，未发现显著连续长句（可能是洗稿）"

    def get_text_evidence(self, text_a: str, text_b: str) -> Tuple[str, str, str]:
        matcher = difflib.SequenceMatcher(None, text_a, text_b)
        match = matcher.find_longest_match(0, len(text_a), 0, len(text_b))
        if match.size > 20:
            core = text_a[match.a : match.a + match.size]
            ctx_a_start = max(0, match.a - 120)
            ctx_a_end = min(len(text_a), match.a + match.size + 120)
            ctx_b_start = max(0, match.b - 120)
            ctx_b_end = min(len(text_b), match.b + match.size + 120)
            ctx_a = text_a[ctx_a_start:ctx_a_end].replace("\n", " ")
            ctx_b = text_b[ctx_b_start:ctx_b_end].replace("\n", " ")
            return core[:160].replace("\n", " ") + "...", ctx_a, ctx_b

        try:
            vec = TfidfVectorizer(ngram_range=(2, 4), sublinear_tf=True)
            matrix = vec.fit_transform([text_a, text_b])
            terms = vec.get_feature_names_out()
            wa = {terms[i] for i in matrix[0].nonzero()[1]}
            wb = {terms[i] for i in matrix[1].nonzero()[1]}
            inter = sorted(list(wa.intersection(wb)), key=lambda term: -len(term))
            hint = " ".join(inter[:10])
            return hint[:160] + "...", "", ""
        except Exception:
            return "全文语义高度相似，未发现显著连续长句（可能是洗稿）", "", ""

    def analyze_text_similarity(self) -> List[Dict]:
        if len(self.documents) < 2:
            return []

        logger.info("正在进行语义分析 (TF-IDF)...")
        corpus = [doc["clean_text"] for doc in self.documents]
        filenames = [doc["filename"] for doc in self.documents]
        raw_contents = [doc["content"] for doc in self.documents]

        word_vec = TfidfVectorizer(min_df=1, ngram_range=(1, 5), sublinear_tf=True)
        char_vec = TfidfVectorizer(analyzer="char", ngram_range=(3, 7))

        try:
            tfidf_word = word_vec.fit_transform(corpus)
            tfidf_char = char_vec.fit_transform(corpus)
            cosine_word = cosine_similarity(tfidf_word)
            cosine_char = cosine_similarity(tfidf_char)
            cosine_sim = 0.6 * cosine_word + 0.4 * cosine_char
        except ValueError:
            return []

        suspicious_pairs = []
        num_docs = len(self.documents)
        for i in range(num_docs):
            for j in range(i + 1, num_docs):
                score = cosine_sim[i][j]
                if score > self.text_threshold:
                    core, ev_a, ev_b = self.get_text_evidence(raw_contents[i], raw_contents[j])
                    lcs = difflib.SequenceMatcher(
                        None,
                        raw_contents[i],
                        raw_contents[j],
                    ).find_longest_match(0, len(raw_contents[i]), 0, len(raw_contents[j])).size
                    suspicious_pairs.append(
                        {
                            "file_a": filenames[i],
                            "file_b": filenames[j],
                            "score": round(score * 100, 2),
                            "evidence": core,
                            "evidence_a": ev_a,
                            "evidence_b": ev_b,
                            "ai_paraphrase": score > self.text_threshold and lcs < 20,
                        }
                    )
        return sorted(suspicious_pairs, key=lambda x: x["score"], reverse=True)

    @staticmethod
    def _simhash(text: str) -> int:
        tokens = re.findall(r"\w+", text)
        weights = defaultdict(int)
        for token in tokens:
            weights[token] += 1
        bits = [0] * 64
        for token, weight in weights.items():
            token_hash = hash(token)
            for i in range(64):
                if ((token_hash >> i) & 1) == 1:
                    bits[i] += weight
                else:
                    bits[i] -= weight
        result = 0
        for i in range(64):
            if bits[i] > 0:
                result |= 1 << i
        return result

    def build_fingerprint_db(self) -> List[Dict]:
        db = []
        for doc in self.documents:
            db.append(
                {
                    "filename": doc["filename"],
                    "ext": os.path.splitext(doc["filename"])[1].lower(),
                    "author": (doc.get("metadata", {}) or {}).get("author"),
                    "size": len(doc.get("clean_text", "")),
                    "simhash": format(self._simhash(doc.get("clean_text", "")), "016x"),
                }
            )
        return db

    def persist_fingerprints(self, records: List[Dict]) -> None:
        import sqlite3

        db_dir = os.path.dirname(self.db_path)
        if db_dir:
            os.makedirs(db_dir, exist_ok=True)

        conn = sqlite3.connect(self.db_path)
        cur = conn.cursor()
        cur.execute(
            "CREATE TABLE IF NOT EXISTS fingerprints ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT, filename TEXT, ext TEXT, author TEXT, "
            "size INTEGER, simhash TEXT, scan_dir TEXT, scanned_at TEXT)"
        )
        cur.execute("CREATE TABLE IF NOT EXISTS whitelist (pattern TEXT UNIQUE, type TEXT)")
        scanned_at = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        scan_dir = os.path.basename(self.directory.rstrip(os.sep))
        for record in records:
            cur.execute(
                "INSERT INTO fingerprints (filename, ext, author, size, simhash, scan_dir, scanned_at) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (
                    record.get("filename"),
                    record.get("ext"),
                    record.get("author"),
                    record.get("size"),
                    record.get("simhash"),
                    scan_dir,
                    scanned_at,
                ),
            )
        conn.commit()
        conn.close()

    def load_whitelist(self) -> List[Dict]:
        items = []
        if not self.whitelist_path:
            return items
        if os.path.exists(self.whitelist_path):
            try:
                with open(self.whitelist_path, "r", encoding="utf-8") as handle:
                    for line in handle:
                        stripped = line.strip()
                        if not stripped or stripped.startswith("#"):
                            continue
                        if ":" in stripped:
                            item_type, pattern = stripped.split(":", 1)
                            items.append({"type": item_type.strip(), "pattern": pattern.strip()})
                        else:
                            items.append({"type": "filename", "pattern": stripped})
            except Exception:
                return []
        return items

    @staticmethod
    def _hamming_hex(a: str, b: str) -> int:
        if not a or not b:
            return 64
        try:
            value = int(a, 16) ^ int(b, 16)
        except ValueError:
            return 64
        dist = 0
        while value:
            dist += 1
            value &= value - 1
        return dist

    def cross_scan_audit(self, current_records: List[Dict]) -> List[Dict]:
        import sqlite3

        conn = sqlite3.connect(self.db_path)
        cur = conn.cursor()
        try:
            cur.execute("SELECT filename, ext, author, size, simhash, scan_dir, scanned_at FROM fingerprints")
            history = cur.fetchall()
        except Exception:
            history = []
        conn.close()

        whitelist = self.load_whitelist()
        results = []
        for rec in current_records:
            for hf in history:
                prev = {
                    "filename": hf[0],
                    "ext": hf[1],
                    "author": hf[2],
                    "size": hf[3],
                    "simhash": hf[4],
                    "scan_dir": hf[5],
                    "scanned_at": hf[6],
                }
                dist = self._hamming_hex(rec.get("simhash"), prev.get("simhash"))
                if dist <= self.simhash_thresh:
                    whitelist_reason = ""
                    for item in whitelist:
                        if item["type"] == "author" and rec.get("author") and rec.get("author") == item["pattern"]:
                            whitelist_reason = "author"
                            break
                        if item["type"] == "filename" and (
                            rec.get("filename") == item["pattern"] or prev.get("filename") == item["pattern"]
                        ):
                            whitelist_reason = "filename"
                            break
                        if item["type"] == "simhash" and (
                            rec.get("simhash") == item["pattern"] or prev.get("simhash") == item["pattern"]
                        ):
                            whitelist_reason = "simhash"
                            break
                    if self.whitelist_mode == "hide" and whitelist_reason:
                        continue
                    results.append(
                        {
                            "current_file": rec.get("filename"),
                            "current_author": rec.get("author"),
                            "prev_file": prev.get("filename"),
                            "prev_scan": prev.get("scan_dir"),
                            "prev_author": prev.get("author"),
                            "dist": dist,
                            "whitelisted": bool(whitelist_reason),
                            "wl_type": whitelist_reason,
                        }
                    )
        return sorted(results, key=lambda x: x["dist"])

    def analyze_dedup(self, threshold: float | None = None) -> List[Dict]:
        thr = threshold if threshold is not None else self.dedup_threshold
        if len(self.documents) < 2:
            return []

        corpus = [doc["clean_text"] for doc in self.documents]
        filenames = [doc["filename"] for doc in self.documents]
        raw_contents = [doc["content"] for doc in self.documents]
        word_vec = TfidfVectorizer(min_df=1, ngram_range=(1, 3))
        char_vec = TfidfVectorizer(analyzer="char", ngram_range=(3, 5))

        try:
            tfidf_word = word_vec.fit_transform(corpus)
            tfidf_char = char_vec.fit_transform(corpus)
            cosine_word = cosine_similarity(tfidf_word)
            cosine_char = cosine_similarity(tfidf_char)
            cosine_sim = 0.5 * cosine_word + 0.5 * cosine_char
        except ValueError:
            return []

        results = []
        n = len(self.documents)
        for i in range(n):
            for j in range(i + 1, n):
                score = cosine_sim[i][j]
                if score >= thr:
                    file_a = filenames[i]
                    file_b = filenames[j]
                    ext_a = os.path.splitext(file_a)[1].lower()
                    ext_b = os.path.splitext(file_b)[1].lower()
                    author_a = (self.documents[i].get("metadata", {}) or {}).get("author")
                    author_b = (self.documents[j].get("metadata", {}) or {}).get("author")
                    core, ev_a, ev_b = self.get_text_evidence(raw_contents[i], raw_contents[j])
                    results.append(
                        {
                            "file_a": file_a,
                            "file_b": file_b,
                            "score": round(score * 100, 2),
                            "cross_format": ext_a != ext_b,
                            "team_hint": author_a if author_a and author_a == author_b else "",
                            "evidence": core,
                            "evidence_a": ev_a,
                            "evidence_b": ev_b,
                        }
                    )
        return sorted(results, key=lambda x: x["score"], reverse=True)

    def analyze_code_plagiarism(self) -> List[Dict]:
        logger.info("正在分析代码块 (Script Fingerprinting)...")
        results = []
        doc_codes = []
        for doc in self.documents:
            fingerprints = []
            astprints = []
            blocks = []
            for block in doc["code_blocks"]:
                simple_code = re.sub(r"\s+", "", block.lower())
                if len(simple_code) > 20:
                    fingerprints.append({simple_code[k : k + 8] for k in range(len(simple_code) - 7)})
                    try:
                        with warnings.catch_warnings():
                            warnings.simplefilter("ignore", SyntaxWarning)
                            warnings.simplefilter("ignore", DeprecationWarning)
                            tree = ast.parse(block)
                        seq = [type(node).__name__ for node in ast.walk(tree)]
                        astprints.append({"|".join(seq[k : k + 5]) for k in range(max(0, len(seq) - 4))})
                    except Exception:
                        astprints.append(set())
                    blocks.append(block)
            doc_codes.append({"filename": doc["filename"], "fps": fingerprints, "ast": astprints, "blocks": blocks})

        n = len(doc_codes)
        for i in range(n):
            for j in range(i + 1, n):
                doc_a = doc_codes[i]
                doc_b = doc_codes[j]
                match_found = False
                max_sim = 0.0
                best = (None, None)
                struct_match = False
                struct_sim = 0.0

                for idx_a, fp_a in enumerate(doc_a["fps"]):
                    for idx_b, fp_b in enumerate(doc_b["fps"]):
                        union = len(fp_a.union(fp_b))
                        if union == 0:
                            continue
                        sim = len(fp_a.intersection(fp_b)) / union
                        if sim > 0.8:
                            match_found = True
                            if sim > max_sim:
                                max_sim = sim
                                best = (idx_a, idx_b)

                for ap_a in doc_a["ast"]:
                    for ap_b in doc_b["ast"]:
                        if not ap_a or not ap_b:
                            continue
                        union = len(ap_a.union(ap_b))
                        if union == 0:
                            continue
                        sim = len(ap_a.intersection(ap_b)) / union
                        if sim > 0.85:
                            struct_match = True
                            if sim > struct_sim:
                                struct_sim = sim

                if match_found or struct_match:
                    ev_a = ""
                    ev_b = ""
                    if best[0] is not None and best[1] is not None:
                        ev_a = doc_a["blocks"][best[0]][:400]
                        ev_b = doc_b["blocks"][best[1]][:400]
                    results.append(
                        {
                            "file_a": doc_a["filename"],
                            "file_b": doc_b["filename"],
                            "score": round(max(max_sim, struct_sim) * 100, 2),
                            "type": "Code Plagiarism" if match_found else "Code Structural Paraphrase",
                            "evidence_a": ev_a,
                            "evidence_b": ev_b,
                        }
                    )

        return sorted(results, key=lambda x: x["score"], reverse=True)

    def analyze_image_reuse(self) -> List[Dict]:
        logger.info("正在进行图片取证分析 (OpenCV + pHash)...")
        all_images = []
        for doc in self.documents:
            for img in doc["images"]:
                all_images.append(
                    {
                        "filename": doc["filename"],
                        "hash_obj": img.get("hash_obj"),
                        "dhash_obj": img.get("dhash_obj"),
                        "ahash_obj": img.get("ahash_obj"),
                        "thumb_b64": img.get("thumb_b64"),
                        "hash_str": img.get("hash_str"),
                        "origin": img.get("origin"),
                        "ocr": img.get("ocr_preview"),
                    }
                )

        suspicious_pairs_count = defaultdict(int)
        pair_examples = defaultdict(list)
        n = len(all_images)

        for i in tqdm(range(n), desc="Image Compare"):
            for j in range(i + 1, n):
                img1 = all_images[i]
                img2 = all_images[j]
                if img1["filename"] == img2["filename"]:
                    continue

                pair_key = tuple(sorted((img1["filename"], img2["filename"])))
                d1 = img1["hash_obj"] - img2["hash_obj"] if img1.get("hash_obj") and img2.get("hash_obj") else 99
                d2 = img1["dhash_obj"] - img2["dhash_obj"] if img1.get("dhash_obj") and img2.get("dhash_obj") else 99
                d3 = img1["ahash_obj"] - img2["ahash_obj"] if img1.get("ahash_obj") and img2.get("ahash_obj") else 99
                diff = int(d1) + int(d2) + int(d3)
                if diff <= self.img_threshold * 3:
                    suspicious_pairs_count[pair_key] += 1
                    if len(pair_examples[pair_key]) < 5:
                        pair_examples[pair_key].append(
                            {
                                "diff": diff,
                                "a_thumb": img1.get("thumb_b64"),
                                "b_thumb": img2.get("thumb_b64"),
                                "a_ctx": img1.get("origin"),
                                "b_ctx": img2.get("origin"),
                                "a_ocr": img1.get("ocr"),
                                "b_ocr": img2.get("ocr"),
                            }
                        )

        results = []
        for (file_a, file_b), count in suspicious_pairs_count.items():
            if count >= 1:
                pair_key = tuple(sorted((file_a, file_b)))
                results.append({"files": [file_a, file_b], "count": count, "examples": pair_examples[pair_key]})
        return sorted(results, key=lambda x: x["count"], reverse=True)

    def analyze_metadata(self) -> List[Dict]:
        logger.info("正在分析文档元数据...")
        author_map = defaultdict(set)

        for doc in self.documents:
            meta = doc.get("metadata", {})
            for author in [meta.get("author"), meta.get("last_modified_by")]:
                if author and len(str(author).strip()) > 1:
                    name = str(author).strip()
                    if name.lower() not in ["administrator", "admin", "user", "microsoft office user"]:
                        author_map[name].add(doc["filename"])

        def infer_team(filename: str) -> str:
            base = os.path.basename(filename)
            parts = re.split(r"[\s\-_\.]+", base)
            return parts[0] if parts else base

        results = []
        for author, files in author_map.items():
            if len(files) > 1:
                results.append(
                    {
                        "author": author,
                        "files": list(files),
                        "count": len(files),
                        "teams": [infer_team(f) for f in files],
                    }
                )
        return sorted(results, key=lambda x: x["count"], reverse=True)

    def generate_report(
        self,
        text_res,
        code_res,
        img_res,
        meta_res,
        ai_summary: str | None = None,
        dedup_res: List[Dict] | None = None,
        fingerprint_db: List[Dict] | None = None,
        cross_res: List[Dict] | None = None,
    ) -> str:
        builder = ReportBuilder(
            directory=self.directory,
            output_dir=self.output_dir,
            name_template=self.name_template,
            documents=self.documents,
            text_threshold=self.text_threshold,
            img_threshold=self.img_threshold,
            dedup_threshold=self.dedup_threshold,
        )
        return builder.generate(text_res, code_res, img_res, meta_res, ai_summary, dedup_res, fingerprint_db, cross_res)


def run_audit(
    directory,
    text_thresh,
    img_thresh,
    output_dir,
    name_template,
    cv_preprocess,
    ollama_enable=False,
    ollama_model="llama3",
    ollama_host="http://localhost:11434",
    dedup_thresh=0.85,
    db_path: str | None = None,
    whitelist_path: str | None = None,
    simhash_thresh: int = 4,
    whitelist_mode: str = "mark",
    progress_cb=None,
):
    if directory:
        directory = os.path.abspath(os.path.expanduser(directory))
    if output_dir:
        output_dir = os.path.abspath(os.path.expanduser(output_dir))
    if db_path:
        db_path = os.path.abspath(os.path.expanduser(db_path))
    if whitelist_path:
        whitelist_path = os.path.abspath(os.path.expanduser(whitelist_path))

    from .cli import banner

    banner()
    print(f"[*] 启动审计任务: {directory}")
    print(f"[*] 引擎配置: 文本阈值={text_thresh}, 图片阈值={img_thresh}, 启用 OpenCV 预处理={cv_preprocess}")

    if progress_cb:
        try:
            progress_cb(5, "初始化")
        except Exception:
            pass

    auditor = AuditEngine(
        directory,
        text_thresh,
        img_thresh,
        output_dir,
        name_template,
        cv_preprocess,
        dedup_thresh,
        db_path,
        whitelist_path,
        simhash_thresh,
        whitelist_mode,
    )
    auditor.load_documents()
    if progress_cb:
        try:
            progress_cb(15, "解析文档完成")
        except Exception:
            pass

    text_results = auditor.analyze_text_similarity()
    if progress_cb:
        try:
            progress_cb(35, "文本分析完成")
        except Exception:
            pass

    code_results = auditor.analyze_code_plagiarism()
    if progress_cb:
        try:
            progress_cb(55, "代码分析完成")
        except Exception:
            pass

    img_results = auditor.analyze_image_reuse()
    if progress_cb:
        try:
            progress_cb(75, "图片分析完成")
        except Exception:
            pass

    meta_results = auditor.analyze_metadata()
    if progress_cb:
        try:
            progress_cb(85, "元数据分析完成")
        except Exception:
            pass

    dedup_results = auditor.analyze_dedup()
    fingerprint_db = auditor.build_fingerprint_db()
    auditor.persist_fingerprints(fingerprint_db)
    cross_results = auditor.cross_scan_audit(fingerprint_db)
    ai_summary = ""
    if ollama_enable:
        ai_summary = build_ai_summary(text_results, code_results, img_results, ollama_model, ollama_host)
    path = auditor.generate_report(
        text_results,
        code_results,
        img_results,
        meta_results,
        ai_summary if ai_summary else None,
        dedup_results,
        fingerprint_db,
        cross_results,
    )
    if progress_cb:
        try:
            progress_cb(100, "报告生成完成")
        except Exception:
            pass
    return path
