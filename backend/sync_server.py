"""
Stream App Sync Server
Deploy on your own private server for cross-device sync.

Setup:
  pip install fastapi uvicorn
  uvicorn sync_server:app --host 0.0.0.0 --port 8000
"""

import hashlib
import json
import os
import sqlite3
import time
import uuid
from pathlib import Path

from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel
from typing import List, Optional

app = FastAPI(title="Stream App Sync Server")

DB_PATH = os.environ.get("SYNC_DB_PATH", "sync_data.db")


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = get_db()
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS devices (
            device_id TEXT PRIMARY KEY,
            device_name TEXT,
            auth_token TEXT UNIQUE,
            sync_group TEXT,
            registered_at INTEGER
        );

        CREATE TABLE IF NOT EXISTS watch_history (
            history_id TEXT,
            device_id TEXT,
            media_id TEXT,
            title TEXT,
            media_type TEXT,
            season INTEGER,
            episode INTEGER,
            poster_url TEXT,
            backdrop_url TEXT,
            source_id TEXT,
            last_position INTEGER,
            duration INTEGER,
            is_watched INTEGER,
            updated_at_ms INTEGER,
            PRIMARY KEY (history_id, device_id)
        );

        CREATE TABLE IF NOT EXISTS library_items (
            media_id TEXT,
            device_id TEXT,
            title TEXT,
            media_type TEXT,
            poster_url TEXT,
            backdrop_url TEXT,
            description TEXT,
            rating REAL,
            updated_at_ms INTEGER,
            PRIMARY KEY (media_id, device_id)
        );

        CREATE TABLE IF NOT EXISTS watched_items (
            media_id TEXT,
            device_id TEXT,
            title TEXT,
            media_type TEXT,
            poster_url TEXT,
            backdrop_url TEXT,
            description TEXT,
            rating REAL,
            updated_at_ms INTEGER,
            PRIMARY KEY (media_id, device_id)
        );

        CREATE TABLE IF NOT EXISTS app_settings (
            device_id TEXT PRIMARY KEY,
            settings_json TEXT,
            updated_at_ms INTEGER
        );

        CREATE TABLE IF NOT EXISTS custom_sources (
            source_id TEXT,
            device_id TEXT,
            source_json TEXT,
            updated_at_ms INTEGER,
            PRIMARY KEY (source_id, device_id)
        );

        CREATE TABLE IF NOT EXISTS addon_configs (
            device_id TEXT PRIMARY KEY,
            config_json TEXT,
            updated_at_ms INTEGER
        );

        CREATE TABLE IF NOT EXISTS deleted_items (
            item_id TEXT,
            device_id TEXT,
            deleted_at_ms INTEGER,
            PRIMARY KEY (item_id, device_id)
        );

        CREATE INDEX IF NOT EXISTS idx_wh_updated ON watch_history(updated_at_ms);
        CREATE INDEX IF NOT EXISTS idx_wh_device ON watch_history(device_id);
        CREATE INDEX IF NOT EXISTS idx_lib_updated ON library_items(updated_at_ms);
        CREATE INDEX IF NOT EXISTS idx_wat_updated ON watched_items(updated_at_ms);
        CREATE INDEX IF NOT EXISTS idx_src_updated ON custom_sources(updated_at_ms);
    """)

    # 1. Update devices table
    columns = conn.execute("PRAGMA table_info(devices)").fetchall()
    column_names = {row["name"] for row in columns}
    if "sync_group" not in column_names:
        conn.execute("ALTER TABLE devices ADD COLUMN sync_group TEXT")
        conn.commit()

    # 2. Update watch_history table
    columns = conn.execute("PRAGMA table_info(watch_history)").fetchall()
    column_names = {row["name"] for row in columns}
    if "source_id" not in column_names:
        conn.execute("ALTER TABLE watch_history ADD COLUMN source_id TEXT")
        conn.commit()

    # 3. Update library_items table
    columns = conn.execute("PRAGMA table_info(library_items)").fetchall()
    column_names = {row["name"] for row in columns}
    for col, col_type in [("backdrop_url", "TEXT"), ("description", "TEXT"), ("rating", "REAL")]:
        if col not in column_names:
            conn.execute(f"ALTER TABLE library_items ADD COLUMN {col} {col_type}")
            conn.commit()

    # 4. Update watched_items table
    columns = conn.execute("PRAGMA table_info(watched_items)").fetchall()
    column_names = {row["name"] for row in columns}
    for col, col_type in [("backdrop_url", "TEXT"), ("description", "TEXT"), ("rating", "REAL")]:
        if col not in column_names:
            conn.execute(f"ALTER TABLE watched_items ADD COLUMN {col} {col_type}")
            conn.commit()

    conn.close()


init_db()


def verify_token(auth_header: Optional[str]):
    if not auth_header or not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid auth token")
    token = auth_header[7:]
    conn = get_db()
    row = conn.execute(
        "SELECT device_id, sync_group FROM devices WHERE auth_token = ?",
        (token,),
    ).fetchone()
    conn.close()
    if not row:
        raise HTTPException(status_code=401, detail="Invalid auth token")
    return row["device_id"], row["sync_group"] or ""


class RegisterRequest(BaseModel):
    device_id: str
    device_name: str
    tmdb_token: str


class PushRequest(BaseModel):
    device_id: str
    watch_history: List[dict] = []
    library: List[dict] = []
    watched: List[dict] = []
    settings: Optional[dict] = None
    sources: List[dict] = []
    addon_config: Optional[dict] = None
    deleted_ids: List[str] = []
    since_ms: int = 0


@app.post("/api/sync/register")
def register_device(req: RegisterRequest):
    token_value = (req.tmdb_token or "").strip()
    if not token_value:
        raise HTTPException(status_code=400, detail="tmdb_token is required")

    sync_group = hashlib.sha256(token_value.encode()).hexdigest()[:32]
    auth_token = hashlib.sha256(f"{req.device_id}_{uuid.uuid4()}".encode()).hexdigest()[:32]
    conn = get_db()
    try:
        conn.execute(
            "INSERT OR REPLACE INTO devices (device_id, device_name, auth_token, sync_group, registered_at) VALUES (?, ?, ?, ?, ?)",
            (req.device_id, req.device_name, auth_token, sync_group, int(time.time() * 1000)),
        )
        conn.commit()
    finally:
        conn.close()
    return {"device_id": req.device_id, "auth_token": auth_token}


@app.post("/api/sync/push")
def push_changes(req: PushRequest, authorization: Optional[str] = Header(None)):
    authed_device_id, _ = verify_token(authorization)
    if authed_device_id != req.device_id:
        raise HTTPException(status_code=403, detail="Device id mismatch")
    conn = get_db()
    try:
        for item in req.watch_history:
            conn.execute("""
                INSERT OR REPLACE INTO watch_history
                (history_id, device_id, media_id, title, media_type, season, episode,
                 poster_url, backdrop_url, source_id, last_position, duration, is_watched, updated_at_ms)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                item.get("history_id"), req.device_id, item.get("media_id"),
                item.get("title"), item.get("media_type"),
                item.get("season", 1), item.get("episode", 1),
                item.get("poster_url"), item.get("backdrop_url"),
                item.get("source_id"),
                item.get("last_position", 0), item.get("duration", 0),
                1 if item.get("is_watched") else 0,
                item.get("updated_at_ms", 0),
            ))

        for item in req.library:
            conn.execute("""
                INSERT OR REPLACE INTO library_items
                (media_id, device_id, title, media_type, poster_url, backdrop_url, description, rating, updated_at_ms)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                item.get("media_id"), req.device_id, item.get("title"),
                item.get("media_type"), item.get("poster_url"),
                item.get("backdrop_url"), item.get("description"),
                item.get("rating"),
                item.get("updated_at_ms", 0),
            ))

        for item in req.watched:
            conn.execute("""
                INSERT OR REPLACE INTO watched_items
                (media_id, device_id, title, media_type, poster_url, backdrop_url, description, rating, updated_at_ms)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                item.get("media_id"), req.device_id, item.get("title"),
                item.get("media_type"), item.get("poster_url"),
                item.get("backdrop_url"), item.get("description"),
                item.get("rating"),
                item.get("updated_at_ms", 0),
            ))

        if req.settings:
            conn.execute("""
                INSERT OR REPLACE INTO app_settings
                (device_id, settings_json, updated_at_ms)
                VALUES (?, ?, ?)
            """, (
                req.device_id,
                json.dumps(req.settings.get("settings", {})),
                req.settings.get("updated_at_ms", 0),
            ))

        for item in req.sources:
            conn.execute("""
                INSERT OR REPLACE INTO custom_sources
                (source_id, device_id, source_json, updated_at_ms)
                VALUES (?, ?, ?, ?)
            """, (
                item.get("id"), req.device_id,
                json.dumps(item),
                item.get("updated_at_ms", 0),
            ))

        if req.addon_config:
            conn.execute("""
                INSERT OR REPLACE INTO addon_configs
                (device_id, config_json, updated_at_ms)
                VALUES (?, ?, ?)
            """, (
                req.device_id,
                json.dumps(req.addon_config.get("config", {})),
                req.addon_config.get("updated_at_ms", 0),
            ))

        now_ms = int(time.time() * 1000)
        for item_id in req.deleted_ids:
            conn.execute("""
                INSERT OR REPLACE INTO deleted_items (item_id, device_id, deleted_at_ms)
                VALUES (?, ?, ?)
            """, (item_id, req.device_id, now_ms))

        conn.commit()
    finally:
        conn.close()
    return {"status": "ok"}


@app.get("/api/sync/pull")
def pull_changes(device_id: str, since_ms: int = 0, authorization: Optional[str] = Header(None)):
    authed_device_id, sync_group = verify_token(authorization)
    if authed_device_id != device_id:
        raise HTTPException(status_code=403, detail="Device id mismatch")

    conn = get_db()
    try:
        # Get watch history from OTHER devices, newer than since_ms.
        rows = conn.execute("""
            SELECT * FROM watch_history
            WHERE device_id != ? AND updated_at_ms > ?
              AND device_id IN (SELECT device_id FROM devices WHERE sync_group = ?)
            ORDER BY updated_at_ms DESC
        """, (device_id, since_ms, sync_group)).fetchall()

        watch_history = []
        for row in rows:
            watch_history.append({
                "history_id": row["history_id"],
                "media_id": row["media_id"],
                "title": row["title"],
                "media_type": row["media_type"],
                "season": row["season"],
                "episode": row["episode"],
                "poster_url": row["poster_url"],
                "backdrop_url": row["backdrop_url"],
                "source_id": row["source_id"],
                "last_position": row["last_position"],
                "duration": row["duration"],
                "is_watched": bool(row["is_watched"]),
                "updated_at_ms": row["updated_at_ms"],
            })

        # Get library items from OTHER devices.
        lib_rows = conn.execute("""
            SELECT * FROM library_items
            WHERE device_id != ? AND updated_at_ms > ?
              AND device_id IN (SELECT device_id FROM devices WHERE sync_group = ?)
        """, (device_id, since_ms, sync_group)).fetchall()

        library = []
        for row in lib_rows:
            library.append({
                "media_id": row["media_id"],
                "title": row["title"],
                "media_type": row["media_type"],
                "poster_url": row["poster_url"],
                "backdrop_url": row["backdrop_url"],
                "description": row["description"],
                "rating": row["rating"],
                "updated_at_ms": row["updated_at_ms"],
            })

        # Get watched items from OTHER devices.
        wat_rows = conn.execute("""
            SELECT * FROM watched_items
            WHERE device_id != ? AND updated_at_ms > ?
              AND device_id IN (SELECT device_id FROM devices WHERE sync_group = ?)
        """, (device_id, since_ms, sync_group)).fetchall()

        watched = []
        for row in wat_rows:
            watched.append({
                "media_id": row["media_id"],
                "title": row["title"],
                "media_type": row["media_type"],
                "poster_url": row["poster_url"],
                "backdrop_url": row["backdrop_url"],
                "description": row["description"],
                "rating": row["rating"],
                "updated_at_ms": row["updated_at_ms"],
            })

        # Get the latest settings from the sync group.
        settings_row = conn.execute("""
            SELECT settings_json, updated_at_ms FROM app_settings
            WHERE device_id IN (SELECT device_id FROM devices WHERE sync_group = ?)
            ORDER BY updated_at_ms DESC LIMIT 1
        """, (sync_group,)).fetchone()

        settings = None
        if settings_row and settings_row["updated_at_ms"] > since_ms:
            settings = {
                "settings": json.loads(settings_row["settings_json"]),
                "updated_at_ms": settings_row["updated_at_ms"],
            }

        # Get custom sources from OTHER devices.
        src_rows = conn.execute("""
            SELECT * FROM custom_sources
            WHERE device_id != ? AND updated_at_ms > ?
              AND device_id IN (SELECT device_id FROM devices WHERE sync_group = ?)
        """, (device_id, since_ms, sync_group)).fetchall()

        sources = []
        for row in src_rows:
            sources.append({
                **json.loads(row["source_json"]),
                "updated_at_ms": row["updated_at_ms"],
            })

        # Get the latest addon configs from the sync group.
        addon_row = conn.execute("""
            SELECT config_json, updated_at_ms FROM addon_configs
            WHERE device_id IN (SELECT device_id FROM devices WHERE sync_group = ?)
            ORDER BY updated_at_ms DESC LIMIT 1
        """, (sync_group,)).fetchone()

        addon_config = None
        if addon_row and addon_row["updated_at_ms"] > since_ms:
            addon_config = {
                "config": json.loads(addon_row["config_json"]),
                "updated_at_ms": addon_row["updated_at_ms"],
            }

        # Get deleted items from OTHER devices.
        del_rows = conn.execute("""
            SELECT item_id FROM deleted_items
            WHERE device_id != ? AND deleted_at_ms > ?
              AND device_id IN (SELECT device_id FROM devices WHERE sync_group = ?)
        """, (device_id, since_ms, sync_group)).fetchall()

        deleted_ids = [row["item_id"] for row in del_rows]

        # Clean old tombstones (30 days).
        cutoff = int(time.time() * 1000) - (30 * 24 * 60 * 60 * 1000)
        conn.execute("DELETE FROM deleted_items WHERE deleted_at_ms < ?", (cutoff,))
        conn.commit()

    finally:
        conn.close()

    return {
        "watch_history": watch_history,
        "library": library,
        "watched": watched,
        "settings": settings,
        "sources": sources,
        "addon_config": addon_config,
        "deleted_ids": deleted_ids,
    }


@app.get("/api/sync/status")
def sync_status():
    conn = get_db()
    try:
        device_count = conn.execute("SELECT COUNT(*) as c FROM devices").fetchone()["c"]
        history_count = conn.execute("SELECT COUNT(*) as c FROM watch_history").fetchone()["c"]
    finally:
        conn.close()
    return {
        "status": "ok",
        "devices": device_count,
        "history_entries": history_count,
    }
