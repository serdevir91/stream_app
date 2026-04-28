"""StreamApp Backend - VidSrc streaming server."""

from __future__ import annotations

from typing import Any, Dict, List, Optional

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from addons.base import BaseAddon
from addons.archiveorg import ArchiveOrgAddon
from addons.embedsu import EmbedSUAddon
from addons.flixhq import FlixHQAddon
from addons.jellyfin import JellyfinAddon
from addons.manager import AddonManager, set_tmdb_access_token
from addons.superembed import SuperEmbedAddon
from addons.twoembed import TwoEmbedAddon
from addons.vidlink import VidLinkAddon
from addons.vidsrc import VidSrcAddon
from addons.webtorrent import WebTorrentAddon

app = FastAPI(title="StreamApp Backend", version="3.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

manager = AddonManager()


def _register_default_addons() -> None:
    """Register default built-in addons on backend startup."""
    # Embed-based addons (most reliable, TMDB/IMDB ID based)
    for factory in (VidSrcAddon, TwoEmbedAddon, SuperEmbedAddon, VidLinkAddon, EmbedSUAddon):
        addon = factory()
        if not manager.is_builtin_removed(addon.get_manifest().id):
            manager.register_builtin(addon)

    # API/scraping-based addons (may need working dependencies)
    for factory in (FlixHQAddon, ArchiveOrgAddon, WebTorrentAddon, JellyfinAddon):
        try:
            addon = factory()
            if not manager.is_builtin_removed(addon.get_manifest().id):
                manager.register_builtin(addon)
        except Exception as exc:
            print(f"[Addon] Builtin registration failed for {factory.__name__}: {exc}")


_register_default_addons()


class InstallAddonRequest(BaseModel):
    """Request payload for addon installation."""

    url: str


class InstallManifestAddonRequest(BaseModel):
    """Request payload for local manifest addon installation."""

    manifest: Dict[str, Any]
    source_label: str = "local-manifest.json"


class SetEnabledRequest(BaseModel):
    """Request payload for addon state updates."""

    addon_id: str
    enabled: bool


class TmdbSettingsRequest(BaseModel):
    """Request payload for TMDB token updates."""

    tmdb_access_token: str = ""


def _normalize_content_type(raw_type: str) -> str:
    """Normalize external content type values to movie/series."""
    value = (raw_type or "").strip().lower()
    if value in ("series", "tv", "show"):
        return "series"
    return "movie"


def _addon_supports_type(addon: BaseAddon, content_type: str) -> bool:
    """Check whether an addon supports the requested content type."""
    manifest = addon.get_manifest()
    allowed = {(item or "").strip().lower() for item in manifest.types}

    if content_type == "series":
        return bool(allowed.intersection({"series", "tv"}))
    return "movie" in allowed


def _dedupe_stream_dicts(streams: List[dict]) -> List[dict]:
    """Deduplicate streams by URL preserving order."""
    seen: set[str] = set()
    unique: List[dict] = []
    for stream in streams:
        url = stream.get("url")
        if not url or url in seen:
            continue
        seen.add(url)
        unique.append(stream)
    return unique


def _try_addon_streams(
    addon: BaseAddon,
    query: str,
    content_type: str,
    season: int,
    episode: int,
    tmdb_id: Optional[str] = None,
) -> List[dict]:
    """Resolve streams from a single addon using fallback strategy."""
    streams = []

    def _append_streams(items):
        for item in items:
            streams.append(
                {
                    **item.to_dict(),
                    "addon_id": addon.get_manifest().id,
                    "provider": item.provider or addon.get_manifest().name,
                }
            )

    # 1) Try TMDB ID for Stremio-like addons first.
    if tmdb_id:
        direct_tmdb = addon.get_streams(tmdb_id, content_type, season, episode)
        _append_streams(direct_tmdb)

    # 2) Try direct content_id call with user query/title.
    if not streams:
        direct_query = addon.get_streams(query, content_type, season, episode)
        _append_streams(direct_query)

    # 3) Search then resolve with found IDs.
    if not streams:
        try:
            results = addon.search(query, content_type)
            for result in results[:5]:
                found = addon.get_streams(result.id, content_type, season, episode)
                if found:
                    _append_streams(found)
                    break
        except Exception as exc:
            print(f"[Stream] Search+stream error ({addon.get_manifest().id}): {exc}")

    return _dedupe_stream_dicts(streams)


def _resolve_streams(
    query: str,
    content_type: str,
    season: int,
    episode: int,
    addon_id: Optional[str],
    tmdb_id: Optional[str],
) -> List[dict]:
    """Resolve streams from selected addon(s)."""
    all_streams: List[dict] = []

    if addon_id:
        addon = manager.get_addon(addon_id)
        if not addon:
            raise HTTPException(status_code=404, detail=f"Addon '{addon_id}' bulunamadı veya pasif.")
        if not _addon_supports_type(addon, content_type):
            raise HTTPException(status_code=400, detail=f"Addon '{addon_id}' bu içerik tipini desteklemiyor.")
        all_streams = _try_addon_streams(addon, query, content_type, season, episode, tmdb_id)
        return _dedupe_stream_dicts(all_streams)

    for addon in manager.get_enabled_addons():
        if not _addon_supports_type(addon, content_type):
            continue
        addon_streams = _try_addon_streams(addon, query, content_type, season, episode, tmdb_id)
        if addon_streams:
            all_streams.extend(addon_streams)

    return _dedupe_stream_dicts(all_streams)


def _resolve_streams_fast(
    query: str,
    content_type: str,
    season: int,
    episode: int,
    addon_id: Optional[str],
    tmdb_id: Optional[str],
) -> List[dict]:
    """Resolve quickly by returning the first addon that yields streams."""
    if addon_id:
        return _resolve_streams(query, content_type, season, episode, addon_id, tmdb_id)

    enabled = [
        addon
        for addon in manager.get_enabled_addons()
        if _addon_supports_type(addon, content_type)
    ]

    # Embed-based addons are generally the fastest fallback.
    embed_ids = {"builtin.vidsrc", "builtin.twoembed", "builtin.superembed", "builtin.vidlink", "builtin.embedsu"}
    enabled.sort(key=lambda addon: 0 if addon.get_manifest().id in embed_ids else 1)

    for addon in enabled:
        addon_streams = _try_addon_streams(addon, query, content_type, season, episode, tmdb_id)
        if addon_streams:
            return _dedupe_stream_dicts(addon_streams)

    return []


@app.get("/api/addons")
def list_addons():
    """List all installed addons."""
    return {"addons": manager.list_addons()}


@app.post("/api/addons/install")
def install_addon(req: InstallAddonRequest):
    """Install custom addon from manifest URL or direct website link source."""
    manifest, error = manager.install_from_url(req.url)
    if manifest:
        return {"success": True, "addon": manifest.to_dict()}
    raise HTTPException(status_code=400, detail=error or "Addon veya kaynak eklenemedi.")


@app.post("/api/addons/install/manifest")
def install_manifest_addon(req: InstallManifestAddonRequest):
    """Install custom addon from local manifest JSON data."""
    manifest, error = manager.install_from_manifest_data(
        req.manifest, source_label=req.source_label
    )
    if manifest:
        return {"success": True, "addon": manifest.to_dict()}
    raise HTTPException(status_code=400, detail=error or "Manifest addon eklenemedi.")


@app.post("/api/addons/remove/{addon_id}")
def remove_addon(addon_id: str):
    """Remove custom addon/source."""
    if manager.remove(addon_id):
        return {"success": True, "message": f"'{addon_id}' kaldırıldı."}
    raise HTTPException(status_code=400, detail="Addon bulunamadı.")


@app.post("/api/addons/toggle")
def toggle_addon(req: SetEnabledRequest):
    """Enable or disable addon."""
    manager.set_enabled(req.addon_id, req.enabled)
    return {"success": True, "addon_id": req.addon_id, "enabled": req.enabled}


@app.post("/api/settings/tmdb")
def update_tmdb_settings(req: TmdbSettingsRequest):
    """Update TMDB token used by backend add-on resolvers."""
    set_tmdb_access_token(req.tmdb_access_token)
    return {"success": True}


@app.get("/api/search")
def search(query: str, addon_id: Optional[str] = None, type: str = "movie"):
    """Search across enabled addons or a specific addon."""
    content_type = _normalize_content_type(type)
    all_results = []

    if addon_id:
        addon = manager.get_addon(addon_id)
        if not addon:
            raise HTTPException(status_code=404, detail=f"Addon '{addon_id}' bulunamadı veya pasif.")
        if not _addon_supports_type(addon, content_type):
            raise HTTPException(status_code=400, detail=f"Addon '{addon_id}' bu içerik tipini desteklemiyor.")

        results = addon.search(query, content_type)
        all_results = [{"addon_id": addon_id, **result.to_dict()} for result in results]
    else:
        for addon in manager.get_enabled_addons():
            if not _addon_supports_type(addon, content_type):
                continue
            addon_id_current = addon.get_manifest().id
            try:
                results = addon.search(query, content_type)
                all_results.extend([{"addon_id": addon_id_current, **result.to_dict()} for result in results])
            except Exception as exc:
                print(f"[Search] Error from {addon_id_current}: {exc}")

    return {"results": all_results}


@app.get("/api/resolve")
def resolve_streams(
    query: str,
    type: str = "series",
    season: int = 1,
    episode: int = 1,
    addon_id: Optional[str] = None,
    tmdb_id: Optional[str] = None,
):
    """Resolve all available stream candidates for movie/series detail pages."""
    content_type = _normalize_content_type(type)
    streams = _resolve_streams(query, content_type, season, episode, addon_id, tmdb_id)
    return {
        "success": True,
        "query": query,
        "type": content_type,
        "season": season,
        "episode": episode,
        "count": len(streams),
        "streams": streams,
    }


@app.get("/api/stream")
def get_stream(
    query: str,
    type: str = "series",
    season: int = 1,
    episode: int = 1,
    addon_id: Optional[str] = None,
    tmdb_id: Optional[str] = None,
    fast: bool = True,
):
    """Return best stream and alternatives for compatibility with existing clients."""
    content_type = _normalize_content_type(type)
    if fast:
        all_streams = _resolve_streams_fast(query, content_type, season, episode, addon_id, tmdb_id)
        if not all_streams:
            all_streams = _resolve_streams(query, content_type, season, episode, addon_id, tmdb_id)
    else:
        all_streams = _resolve_streams(query, content_type, season, episode, addon_id, tmdb_id)

    if all_streams:
        return {
            "success": True,
            "stream_url": all_streams[0]["url"],
            "provider": all_streams[0].get("provider", "Unknown"),
            "is_direct_link": all_streams[0].get("is_direct_link", True),
            "streams": all_streams,
            "alternatives": all_streams[1:] if len(all_streams) > 1 else [],
        }

    # Fallback demo streams.
    import random

    fallback_videos = [
        "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
        "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4",
        "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
        "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4",
    ]

    return {
        "success": True,
        "stream_url": random.choice(fallback_videos),
        "provider": "Fallback",
        "is_direct_link": True,
        "streams": [],
        "message": f"'{query}' için içerik bulunamadı. Örnek video oynatılıyor.",
    }


@app.get("/api/health")
def health_check():
    """Backend health and addon counts."""
    addon_count = len(manager.list_addons())
    enabled_count = len(manager.get_enabled_addons())
    return {
        "status": "ok",
        "addons_total": addon_count,
        "addons_enabled": enabled_count,
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
