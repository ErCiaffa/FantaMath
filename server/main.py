import io
import json
import os
import re
import time
import uuid
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from openpyxl import Workbook

BASE_DIR = Path(__file__).resolve().parent.parent
CONFIG_DIR = Path(os.environ.get("FANTAMANAGER_CONFIG_DIR", str(BASE_DIR / "config")))
FRONTEND_DIR = Path(os.environ.get("FANTAMANAGER_FRONTEND_DIR", str(BASE_DIR / "frontend")))
UPLOADS_DIR = CONFIG_DIR / "uploads"
LEAGUES_DIR = CONFIG_DIR / "leagues"
ACTIVE_JSON = CONFIG_DIR / "active.json"

CONFIG_DIR.mkdir(parents=True, exist_ok=True)
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
LEAGUES_DIR.mkdir(parents=True, exist_ok=True)

EMPTY_STATE = {
    "meta": None,
    "epsilon": None,
    "players": [],
    "teams": {"table": [], "transactions": [], "released": []},
}

app = FastAPI(title="FantaManager")


def _slugify(name: str) -> str:
    lowered = name.strip().lower()
    collapsed = re.sub(r"[^a-z0-9]+", "-", lowered)
    slug = collapsed.strip("-")
    if not slug:
        raise HTTPException(status_code=400, detail=f'Il nome lega "{name}" non produce uno slug valido.')
    return slug


def _active_slug() -> str:
    if not ACTIVE_JSON.exists():
        ACTIVE_JSON.write_text(json.dumps({"activeLeague": "default"}), encoding="utf-8")
        return "default"
    return json.loads(ACTIVE_JSON.read_text(encoding="utf-8"))["activeLeague"]


def _set_active_slug(slug: str):
    ACTIVE_JSON.write_text(json.dumps({"activeLeague": slug}), encoding="utf-8")


def _league_dir(slug: str) -> Path:
    d = LEAGUES_DIR / slug
    d.mkdir(parents=True, exist_ok=True)
    return d


def _active_paths():
    d = _league_dir(_active_slug())
    return d / "lega.json", d / "queue.json"


def _read_queue(queue_json: Path):
    if not queue_json.exists():
        return []
    text = queue_json.read_text(encoding="utf-8").strip()
    if not text:
        return []
    data = json.loads(text)
    return data if isinstance(data, list) else [data]


def _write_queue(queue_json: Path, entries):
    queue_json.write_text(json.dumps(entries, ensure_ascii=False), encoding="utf-8")


@app.get("/api/leagues")
def list_leagues():
    slugs = sorted(p.name for p in LEAGUES_DIR.iterdir() if p.is_dir()) if LEAGUES_DIR.exists() else []
    return {"leagues": slugs, "active": _active_slug()}


@app.post("/api/leagues")
def create_league(body: dict):
    if "name" not in body:
        raise HTTPException(status_code=400, detail="Richiesta priva di 'name'.")
    slug = _slugify(body["name"])
    league_dir = _league_dir(slug)
    if (league_dir / "lega.mat").exists():
        raise HTTPException(status_code=409, detail=f'Una lega chiamata "{slug}" esiste gia\'.')
    _set_active_slug(slug)
    return {"slug": slug}


@app.post("/api/leagues/active")
def switch_active_league(body: dict):
    if "slug" not in body:
        raise HTTPException(status_code=400, detail="Richiesta priva di 'slug'.")
    slug = body["slug"]
    if not (LEAGUES_DIR / slug).is_dir():
        raise HTTPException(status_code=404, detail=f'Lega "{slug}" non trovata.')
    _set_active_slug(slug)
    return {"active": slug}


@app.get("/api/state")
def get_state():
    state_json, _ = _active_paths()
    if not state_json.exists():
        return JSONResponse(EMPTY_STATE)
    return JSONResponse(json.loads(state_json.read_text(encoding="utf-8")))


@app.post("/api/actions")
def create_action(body: dict):
    if "type" not in body or "payload" not in body:
        raise HTTPException(status_code=400, detail="Richiesta azione priva di 'type' o 'payload'.")
    _, queue_json = _active_paths()
    entries = _read_queue(queue_json)
    entry = {
        "id": uuid.uuid4().hex,
        "type": body["type"],
        "payload": body["payload"],
        "status": "pending",
        "createdAt": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "appliedAt": "",
        "error": "",
    }
    entries.append(entry)
    _write_queue(queue_json, entries)
    return {"id": entry["id"]}


@app.get("/api/actions/{action_id}")
def get_action(action_id: str):
    _, queue_json = _active_paths()
    for entry in _read_queue(queue_json):
        if entry["id"] == action_id:
            return entry
    raise HTTPException(status_code=404, detail="Azione non trovata.")


@app.get("/api/export-listone")
def export_listone():
    state_json, _ = _active_paths()
    if not state_json.exists():
        raise HTTPException(status_code=404, detail="Nessuna lega attiva con dati caricati.")
    state = json.loads(state_json.read_text(encoding="utf-8"))

    scores_by_id = {s["id"]: s for s in state.get("scores", [])}

    wb = Workbook()
    ws = wb.active
    ws.title = "Lista calciatori"
    headers = [
        "#", "Nome", "Fuori lista", "Ruolo", "Ruolo Mantra", "FantaSquadra", "Costo",
        "FVM", "QUOT", "Credito stimato (lordo)", "Netto svincolo",
    ]
    ws.append(headers)

    for p in state.get("players", []):
        owned = bool(p.get("owned"))
        s = scores_by_id.get(p.get("id"), {})
        ws.append([
            p.get("id"),
            p.get("nome"),
            "*" if p.get("fuoriLista") else "",
            p.get("roleClassic"),
            p.get("roleMantra"),
            p.get("team") if owned else "",
            p.get("costo") if owned else None,
            p.get("fvm"),
            p.get("quot"),
            s.get("creditoStimato") if owned else None,
            s.get("incassoNettoDecisionale") if owned else None,
        ])

    buffer = io.BytesIO()
    wb.save(buffer)
    buffer.seek(0)
    filename = f"listone_{_active_slug()}.xlsx"
    return StreamingResponse(
        buffer,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@app.post("/api/upload-csv")
async def upload_csv(file: UploadFile = File(...)):
    dest = UPLOADS_DIR / f"{int(time.time())}_{file.filename}"
    contents = await file.read()
    dest.write_bytes(contents)
    return {"path": str(dest)}


app.mount("/", StaticFiles(directory=str(FRONTEND_DIR), html=True), name="frontend")
