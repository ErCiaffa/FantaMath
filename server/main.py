import json
import os
import time
import uuid
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

BASE_DIR = Path(__file__).resolve().parent.parent
CONFIG_DIR = Path(os.environ.get("FANTAMANAGER_CONFIG_DIR", str(BASE_DIR / "config")))
FRONTEND_DIR = Path(os.environ.get("FANTAMANAGER_FRONTEND_DIR", str(BASE_DIR / "frontend")))
UPLOADS_DIR = CONFIG_DIR / "uploads"
STATE_JSON = CONFIG_DIR / "lega.json"
QUEUE_JSON = CONFIG_DIR / "queue.json"

CONFIG_DIR.mkdir(parents=True, exist_ok=True)
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)

EMPTY_STATE = {
    "meta": None,
    "epsilon": None,
    "players": [],
    "teams": {"table": [], "transactions": [], "released": []},
}

app = FastAPI(title="FantaManager")


def _read_queue():
    if not QUEUE_JSON.exists():
        return []
    text = QUEUE_JSON.read_text(encoding="utf-8").strip()
    if not text:
        return []
    data = json.loads(text)
    return data if isinstance(data, list) else [data]


def _write_queue(entries):
    QUEUE_JSON.write_text(json.dumps(entries, ensure_ascii=False), encoding="utf-8")


@app.get("/api/state")
def get_state():
    if not STATE_JSON.exists():
        return JSONResponse(EMPTY_STATE)
    return JSONResponse(json.loads(STATE_JSON.read_text(encoding="utf-8")))


@app.post("/api/actions")
def create_action(body: dict):
    if "type" not in body or "payload" not in body:
        raise HTTPException(status_code=400, detail="Richiesta azione priva di 'type' o 'payload'.")
    entries = _read_queue()
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
    _write_queue(entries)
    return {"id": entry["id"]}


@app.get("/api/actions/{action_id}")
def get_action(action_id: str):
    for entry in _read_queue():
        if entry["id"] == action_id:
            return entry
    raise HTTPException(status_code=404, detail="Azione non trovata.")


@app.post("/api/upload-csv")
async def upload_csv(file: UploadFile = File(...)):
    dest = UPLOADS_DIR / f"{int(time.time())}_{file.filename}"
    contents = await file.read()
    dest.write_bytes(contents)
    return {"path": str(dest)}


app.mount("/", StaticFiles(directory=str(FRONTEND_DIR), html=True), name="frontend")
