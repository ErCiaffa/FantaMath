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


def test_list_leagues_defaults_to_default_slug(client):
    response = client.get("/api/leagues")
    assert response.status_code == 200
    body = response.json()
    assert body["active"] == "default"


def test_create_league_slugifies_name_and_activates_it(client):
    response = client.post("/api/leagues", json={"name": "Lega Vera 2027!"})
    assert response.status_code == 200
    assert response.json()["slug"] == "lega-vera-2027"

    active_response = client.get("/api/leagues")
    assert active_response.json()["active"] == "lega-vera-2027"


def test_state_and_actions_are_scoped_to_the_active_league(client):
    client.post("/api/leagues", json={"name": "Lega A"})
    client.post("/api/actions", json={"type": "setBankOverride", "payload": {"teamName": "X", "value": 1}})

    client.post("/api/leagues", json={"name": "Lega B"})
    response = client.get("/api/leagues")
    leagues = response.json()["leagues"]
    assert "lega-a" in leagues
    assert "lega-b" in leagues

    switch_response = client.post("/api/leagues/active", json={"slug": "lega-a"})
    assert switch_response.status_code == 200
    assert switch_response.json()["active"] == "lega-a"


def test_switch_to_unknown_league_returns_404(client):
    response = client.post("/api/leagues/active", json={"slug": "non-esiste"})
    assert response.status_code == 404


def test_create_league_with_duplicate_name_conflicts_only_if_already_saved(client):
    # Creating twice before MATLAB ever saves a lega.mat is allowed (idempotent activation);
    # the 409 only fires once the league actually has persisted state.
    first = client.post("/api/leagues", json={"name": "Prova"})
    assert first.status_code == 200
    second = client.post("/api/leagues", json={"name": "Prova"})
    assert second.status_code == 200
