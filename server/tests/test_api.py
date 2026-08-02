import os
import shutil
import tempfile

import pytest


@pytest.fixture()
def client(monkeypatch):
    work_dir = tempfile.mkdtemp()
    monkeypatch.setenv("FANTAMANAGER_CONFIG_DIR", os.path.join(work_dir, "config"))
    monkeypatch.setenv("FANTAMANAGER_FRONTEND_DIR", os.path.join(work_dir, "frontend"))
    os.makedirs(os.path.join(work_dir, "frontend"), exist_ok=True)
    with open(os.path.join(work_dir, "frontend", "index.html"), "w") as f:
        f.write("<html><body>ok</body></html>")

    import importlib
    import server.main as main_module
    importlib.reload(main_module)
    from fastapi.testclient import TestClient

    with TestClient(main_module.app) as test_client:
        yield test_client

    shutil.rmtree(work_dir, ignore_errors=True)


def test_get_state_returns_default_shape_when_no_snapshot_yet(client):
    response = client.get("/api/state")
    assert response.status_code == 200
    body = response.json()
    assert body["players"] == []
    assert body["teams"]["table"] == []


def test_create_action_appends_pending_entry_to_queue(client):
    response = client.post("/api/actions", json={"type": "setBankOverride", "payload": {"teamName": "A", "value": 10}})
    assert response.status_code == 200
    action_id = response.json()["id"]
    assert action_id

    status_response = client.get(f"/api/actions/{action_id}")
    assert status_response.status_code == 200
    entry = status_response.json()
    assert entry["status"] == "pending"
    assert entry["type"] == "setBankOverride"


def test_get_unknown_action_returns_404(client):
    response = client.get("/api/actions/does-not-exist")
    assert response.status_code == 404


def test_upload_csv_saves_file_and_returns_path(client):
    response = client.post(
        "/api/upload-csv",
        files={"file": ("listone.csv", b"#;Nome\n1;Test\n", "text/csv")},
    )
    assert response.status_code == 200
    saved_path = response.json()["path"]
    assert os.path.isfile(saved_path)
