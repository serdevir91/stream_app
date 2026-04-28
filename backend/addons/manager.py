"""Addon Manager: loads, stores, and manages all addons."""

from __future__ import annotations

import hashlib
import json
import os
import re
from typing import Dict, List, Optional
from urllib.parse import quote, urlparse

import httpx

from .base import AddonManifest, BaseAddon, SearchResult, StreamResult
from .websource import WebSourceAddon

ADDONS_CONFIG_PATH = os.path.join(os.path.dirname(__file__), "..", "addons_config.json")

# TMDB API token for IMDB ID lookups.
TMDB_ACCESS_TOKEN = os.getenv("TMDB_ACCESS_TOKEN", "")

_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36",
    "Accept": "application/json, */*",
}

# Cache TMDB->IMDB lookups
_imdb_cache: Dict[str, str] = {}


def set_tmdb_access_token(token: str) -> None:
    """Set TMDB access token at runtime and clear lookup cache."""
    global TMDB_ACCESS_TOKEN
    TMDB_ACCESS_TOKEN = (token or "").strip()
    _imdb_cache.clear()


def tmdb_to_imdb(tmdb_id: str, content_type: str = "movie") -> Optional[str]:
    """Convert TMDB ID to IMDB ID using TMDB API."""
    cache_key = f"{content_type}:{tmdb_id}"
    if cache_key in _imdb_cache:
        return _imdb_cache[cache_key]

    if not TMDB_ACCESS_TOKEN:
        return None

    try:
        media_type = "tv" if content_type in ("series", "tv") else "movie"
        with httpx.Client(timeout=10.0) as client:
            response = client.get(
                f"https://api.themoviedb.org/3/{media_type}/{tmdb_id}/external_ids",
                headers={"Authorization": f"Bearer {TMDB_ACCESS_TOKEN}"},
            )
            data = response.json()
            imdb_id = data.get("imdb_id")
            if imdb_id:
                _imdb_cache[cache_key] = imdb_id
                return imdb_id
    except Exception as exc:
        print(f"[TMDB] Lookup error for {tmdb_id}: {exc}")
    return None


def _normalize_input_url(raw_url: str) -> str:
    """Normalize user-provided addon/source URLs."""
    value = (raw_url or "").strip()
    if value.startswith("stremio://"):
        value = "https://" + value[len("stremio://") :]

    parsed = urlparse(value)
    if not parsed.scheme:
        value = "https://" + value

    parsed = urlparse(value)
    clean_path = parsed.path.rstrip("/")
    clean = parsed._replace(path=clean_path, fragment="")
    return clean.geturl()


def _build_manifest_candidates(normalized_url: str) -> tuple[str, List[str]]:
    """Build manifest candidate URLs and base URL for stream/search calls."""
    parsed = urlparse(normalized_url)
    path = parsed.path or ""

    if path.endswith("/manifest.json"):
        base_path = path[: -len("/manifest.json")]
        manifest_url = parsed.geturl()
        base_url = parsed._replace(path=base_path, query="", fragment="").geturl().rstrip("/")
        return base_url, [manifest_url]

    if path.endswith(".json"):
        base_path = path.rsplit("/", 1)[0]
        manifest_url = parsed.geturl()
        base_url = parsed._replace(path=base_path, query="", fragment="").geturl().rstrip("/")
        return base_url, [manifest_url]

    base_url = parsed._replace(query="", fragment="").geturl().rstrip("/")
    return base_url, [
        f"{base_url}/manifest.json",
        f"{base_url}/addon/manifest.json",
        f"{base_url}/stremio/v1/manifest.json",
    ]


def _detect_stremio_manifest(manifest_data: dict) -> bool:
    """Detect if manifest likely belongs to a Stremio addon."""
    resources = manifest_data.get("resources")
    if isinstance(resources, list) and resources:
        return True
    return any(key in manifest_data for key in ("idPrefixes", "catalogs", "behaviorHints"))


def _build_web_source_manifest(url: str) -> AddonManifest:
    """Build a deterministic pseudo-manifest for a direct web source URL."""
    parsed = urlparse(url)
    host = parsed.netloc or "web-source"
    digest = hashlib.sha1(url.encode("utf-8")).hexdigest()[:10]

    return AddonManifest(
        id=f"websource.{digest}",
        name=f"Web Source ({host})",
        description="Direkt site/link kaynağından çıkarılan dizi/film streamleri",
        version="1.0",
        types=["movie", "series"],
        icon="🌐",
        is_builtin=False,
    )


class RemoteAddon(BaseAddon):
    """An addon that uses custom API format (/search, /stream)."""

    def __init__(self, base_url: str, manifest: AddonManifest):
        self._base_url = base_url.rstrip("/")
        self._manifest = manifest

    def get_manifest(self) -> AddonManifest:
        return self._manifest

    def search(self, query: str, content_type: str = "movie") -> List[SearchResult]:
        try:
            with httpx.Client(timeout=10.0, headers=_HEADERS) as client:
                response = client.get(
                    f"{self._base_url}/search",
                    params={"query": query, "type": content_type},
                )
                data = response.json()
                return [SearchResult(**item) for item in data.get("results", [])]
        except Exception as exc:
            print(f"[RemoteAddon:{self._manifest.id}] Search error: {exc}")
            return []

    def get_streams(
        self,
        content_id: str,
        content_type: str = "movie",
        season: int = 1,
        episode: int = 1,
    ) -> List[StreamResult]:
        try:
            with httpx.Client(timeout=10.0, headers=_HEADERS) as client:
                response = client.get(
                    f"{self._base_url}/stream",
                    params={
                        "id": content_id,
                        "type": content_type,
                        "season": season,
                        "episode": episode,
                    },
                )
                data = response.json()
                return [StreamResult(**stream) for stream in data.get("streams", [])]
        except Exception as exc:
            print(f"[RemoteAddon:{self._manifest.id}] Stream error: {exc}")
            return []


class StremioRemoteAddon(BaseAddon):
    """Addon wrapper for Stremio API style endpoints."""

    def __init__(self, base_url: str, manifest: AddonManifest, raw_manifest: Optional[dict] = None):
        self._base_url = base_url.rstrip("/")
        self._manifest = manifest
        self._raw_manifest = raw_manifest or {}

    def get_manifest(self) -> AddonManifest:
        return self._manifest

    def search(self, query: str, content_type: str = "movie") -> List[SearchResult]:
        """Search catalog endpoints with query-aware fallback chain."""
        allowed_types = ("series", "tv") if content_type == "series" else ("movie",)
        catalog_targets = self._catalog_targets(allowed_types)
        results: List[SearchResult] = []
        seen_ids: set[str] = set()

        try:
            with httpx.Client(timeout=12.0, headers=_HEADERS, follow_redirects=True) as client:
                for catalog_type, catalog_id in catalog_targets:
                    endpoints = self._catalog_endpoints(catalog_type, catalog_id, query)
                    for endpoint in endpoints:
                        response = client.get(endpoint)
                        if response.status_code != 200:
                            continue

                        data = response.json()
                        metas = data.get("metas", [])
                        for meta in metas[:40]:
                            media_id = str(meta.get("id", "")).strip()
                            if not media_id or media_id in seen_ids:
                                continue
                            seen_ids.add(media_id)

                            raw_type = str(meta.get("type", catalog_type)).lower()
                            mapped_type = "series" if raw_type in ("series", "tv") else "movie"

                            results.append(
                                SearchResult(
                                    id=media_id,
                                    title=meta.get("name") or meta.get("title") or "Unknown",
                                    type=mapped_type,
                                    year=str(meta.get("releaseInfo") or meta.get("year") or ""),
                                    poster=meta.get("poster"),
                                    description=meta.get("description", ""),
                                )
                            )

                        if results:
                            break
                    if results:
                        break
        except Exception as exc:
            print(f"[Stremio:{self._manifest.id}] Search error: {exc}")

        return results

    def get_streams(
        self,
        content_id: str,
        content_type: str = "movie",
        season: int = 1,
        episode: int = 1,
    ) -> List[StreamResult]:
        """Resolve Stremio streams with multiple ID and route fallbacks."""
        candidate_ids = self._candidate_ids(content_id, content_type)
        stream_types = ["series", "tv"] if content_type == "series" else ["movie"]

        streams: List[StreamResult] = []
        seen_urls: set[str] = set()

        try:
            with httpx.Client(timeout=15.0, headers=_HEADERS, follow_redirects=True) as client:
                for stype in stream_types:
                    for candidate_id in candidate_ids:
                        stream_ids = [f"{candidate_id}:{season}:{episode}", candidate_id] if stype in ("series", "tv") else [candidate_id]

                        for stream_id in stream_ids:
                            endpoint = f"{self._base_url}/stream/{stype}/{stream_id}.json"
                            response = client.get(endpoint)
                            if response.status_code != 200:
                                continue

                            data = response.json()
                            for stream in self._parse_stremio_streams(data):
                                if stream.url in seen_urls:
                                    continue
                                seen_urls.add(stream.url)
                                streams.append(stream)

                            if streams:
                                return streams
        except Exception as exc:
            print(f"[Stremio:{self._manifest.id}] Stream error: {exc}")

        return streams

    def _catalog_targets(self, allowed_types: tuple[str, ...]) -> List[tuple[str, str]]:
        """Build ordered catalog target list from manifest metadata."""
        targets: List[tuple[str, str]] = []
        catalogs = self._raw_manifest.get("catalogs", [])

        if isinstance(catalogs, list):
            for catalog in catalogs:
                if not isinstance(catalog, dict):
                    continue
                catalog_type = str(catalog.get("type", "")).lower().strip()
                catalog_id = str(catalog.get("id", "")).strip()
                if not catalog_id or catalog_type not in allowed_types:
                    continue
                targets.append((catalog_type, catalog_id))

        if not targets:
            default_type = allowed_types[0]
            targets.append((default_type, "top"))

        return targets

    def _catalog_endpoints(self, catalog_type: str, catalog_id: str, query: str) -> List[str]:
        """Create candidate Stremio catalog URLs for query and fallback."""
        encoded = quote((query or "").strip())
        endpoints: List[str] = []

        if encoded:
            endpoints.extend(
                [
                    f"{self._base_url}/catalog/{catalog_type}/{catalog_id}/search={encoded}.json",
                    f"{self._base_url}/catalog/{catalog_type}/{catalog_id}.json?search={encoded}",
                    f"{self._base_url}/catalog/{catalog_type}/{catalog_id}.json?query={encoded}",
                ]
            )

        endpoints.append(f"{self._base_url}/catalog/{catalog_type}/{catalog_id}.json")
        return endpoints

    def _candidate_ids(self, content_id: str, content_type: str) -> List[str]:
        """Build candidate IDs in preferred order."""
        raw = (content_id or "").strip()
        results: List[str] = []

        if raw.startswith("tt"):
            results.append(raw)
        elif raw.startswith("tmdb:"):
            tmdb_id = raw.split(":", 1)[1]
            imdb_id = tmdb_to_imdb(tmdb_id, content_type)
            if imdb_id:
                results.append(imdb_id)
        elif raw.isdigit():
            imdb_id = tmdb_to_imdb(raw, content_type)
            if imdb_id:
                results.append(imdb_id)

        imdb_match = re.search(r"tt\d+", raw)
        if imdb_match and imdb_match.group(0) not in results:
            results.append(imdb_match.group(0))

        if raw and raw not in results:
            results.append(raw)

        return results

    def _parse_stremio_streams(self, payload: dict) -> List[StreamResult]:
        """Parse Stremio stream list into normalized StreamResult objects."""
        parsed: List[StreamResult] = []

        for stream in payload.get("streams", []):
            stream_url = stream.get("url") or stream.get("externalUrl")

            if not stream_url and stream.get("ytId"):
                stream_url = f"https://www.youtube.com/watch?v={stream['ytId']}"

            if not stream_url:
                info_hash = stream.get("infoHash")
                if info_hash:
                    display_name = stream.get("title") or stream.get("name") or self._manifest.name
                    stream_url = f"magnet:?xt=urn:btih:{info_hash}&dn={quote(display_name)}"

            if not stream_url:
                continue

            title_parts = []
            if stream.get("name"):
                title_parts.append(str(stream["name"]))
            if stream.get("title"):
                title_parts.append(str(stream["title"]))

            title = " - ".join([part for part in title_parts if part]).strip()
            if not title:
                title = self._manifest.name

            parsed.append(
                StreamResult(
                    url=stream_url,
                    title=title[:140],
                    quality=str(stream.get("name", ""))[:60],
                    provider=self._manifest.name,
                )
            )

        return parsed


class AddonManager:
    """Manages all addons (built-in and custom)."""

    def __init__(self):
        self._addons: Dict[str, BaseAddon] = {}
        self._enabled: Dict[str, bool] = {}
        self._custom_urls: Dict[str, str] = {}
        self._custom_manifests: Dict[str, dict] = {}
        self._removed_builtins: set[str] = set()
        self._load_config()

    def register_builtin(self, addon: BaseAddon):
        """Register a built-in addon."""
        manifest = addon.get_manifest()
        manifest.is_builtin = True
        self._addons[manifest.id] = addon
        if manifest.id not in self._enabled:
            self._enabled[manifest.id] = True

    def install_from_url(self, url: str) -> tuple[Optional[AddonManifest], str]:
        """Install a custom addon or a direct web source URL."""
        normalized_url = _normalize_input_url(url)
        if not normalized_url.startswith("http"):
            return None, "URL 'http://' veya 'https://' ile başlamalıdır."

        base_url, manifest_urls = _build_manifest_candidates(normalized_url)

        data: Optional[dict] = None
        last_error = ""
        for manifest_url in manifest_urls:
            try:
                with httpx.Client(timeout=15.0, follow_redirects=True, headers=_HEADERS) as client:
                    response = client.get(manifest_url)
                    if response.status_code == 200:
                        data = response.json()
                        break
                    last_error = f"HTTP {response.status_code} - {manifest_url}"
            except httpx.ConnectError:
                last_error = f"Bağlantı hatası: Sunucuya ulaşılamıyor ({normalized_url})"
            except httpx.TimeoutException:
                last_error = f"Zaman aşımı: Sunucu yanıt vermedi ({normalized_url})"
            except Exception as exc:
                last_error = f"{manifest_url} → {str(exc)}"

        # If manifest is missing, treat URL as a direct web source.
        if data is None:
            manifest = _build_web_source_manifest(normalized_url)
            addon = WebSourceAddon(normalized_url, manifest)
            self._addons[manifest.id] = addon
            self._enabled[manifest.id] = True
            self._custom_urls[manifest.id] = normalized_url
            self._custom_manifests.pop(manifest.id, None)
            self._save_config()
            return manifest, ""

        if "id" not in data or "name" not in data:
            return None, f"Geçersiz manifest: 'id' ve 'name' alanları zorunludur. Bulunan: {list(data.keys())}"

        try:
            manifest_types = data.get("types")
            if not manifest_types:
                manifest_types = []
                for catalog in data.get("catalogs", []):
                    if not isinstance(catalog, dict):
                        continue
                    catalog_type = str(catalog.get("type", "")).lower()
                    if catalog_type == "tv":
                        catalog_type = "series"
                    if catalog_type in ("movie", "series") and catalog_type not in manifest_types:
                        manifest_types.append(catalog_type)
                if not manifest_types:
                    manifest_types = ["movie", "series"]

            manifest = AddonManifest(
                id=data["id"],
                name=data["name"],
                description=data.get("description", ""),
                version=data.get("version", "1.0"),
                types=manifest_types,
                icon=data.get("icon") or data.get("logo") or "🔌",
                is_builtin=False,
            )

            existing = self._addons.get(manifest.id)
            if existing and existing.get_manifest().is_builtin:
                return None, f"'{manifest.id}' yerleşik addon olduğu için üzerine yazılamaz."

            is_stremio = _detect_stremio_manifest(data)
            if is_stremio:
                addon = StremioRemoteAddon(base_url, manifest, raw_manifest=data)
            else:
                addon = RemoteAddon(base_url, manifest)

            self._addons[manifest.id] = addon
            self._enabled[manifest.id] = True
            self._custom_urls[manifest.id] = normalized_url
            self._custom_manifests.pop(manifest.id, None)
            self._save_config()
            return manifest, ""
        except Exception as exc:
            return None, f"Manifest parse hatası: {str(exc)}"

    def install_from_manifest_data(
        self, manifest_data: dict, source_label: str = "local-manifest.json"
    ) -> tuple[Optional[AddonManifest], str]:
        """Install addon from local manifest JSON content."""
        if not isinstance(manifest_data, dict):
            return None, "Manifest JSON formati gecersiz."

        base_url = (
            str(
                manifest_data.get("transportUrl")
                or manifest_data.get("transport_url")
                or manifest_data.get("baseUrl")
                or ""
            )
            .strip()
            .rstrip("/")
        )
        if not base_url:
            return None, "Manifest dosyasinda 'transportUrl' veya 'baseUrl' alani zorunlu."
        if not base_url.startswith("http"):
            return None, "transportUrl/baseUrl http veya https ile baslamalidir."
        if "id" not in manifest_data or "name" not in manifest_data:
            return (
                None,
                "Manifest dosyasinda 'id' ve 'name' alanlari zorunludur.",
            )

        try:
            manifest_types = manifest_data.get("types")
            if not manifest_types:
                manifest_types = []
                for catalog in manifest_data.get("catalogs", []):
                    if not isinstance(catalog, dict):
                        continue
                    catalog_type = str(catalog.get("type", "")).lower()
                    if catalog_type == "tv":
                        catalog_type = "series"
                    if catalog_type in ("movie", "series") and catalog_type not in manifest_types:
                        manifest_types.append(catalog_type)
                if not manifest_types:
                    manifest_types = ["movie", "series"]

            manifest = AddonManifest(
                id=manifest_data["id"],
                name=manifest_data["name"],
                description=manifest_data.get("description", ""),
                version=manifest_data.get("version", "1.0"),
                types=manifest_types,
                icon=manifest_data.get("icon") or manifest_data.get("logo") or "??",
                is_builtin=False,
            )

            existing = self._addons.get(manifest.id)
            if existing and existing.get_manifest().is_builtin:
                return None, f"'{manifest.id}' yerlesik addon oldugu icin uzerine yazilamaz."

            is_stremio = _detect_stremio_manifest(manifest_data)
            if is_stremio:
                addon = StremioRemoteAddon(base_url, manifest, raw_manifest=manifest_data)
            else:
                addon = RemoteAddon(base_url, manifest)

            self._addons[manifest.id] = addon
            self._enabled[manifest.id] = True
            self._custom_urls.pop(manifest.id, None)
            manifest_payload = dict(manifest_data)
            if not manifest_payload.get("transportUrl") and not manifest_payload.get("transport_url"):
                manifest_payload["transportUrl"] = base_url
            self._custom_manifests[manifest.id] = {
                "manifest": manifest_payload,
                "source_label": source_label,
            }
            self._save_config()
            return manifest, ""
        except Exception as exc:
            return None, f"Manifest parse hatasi: {str(exc)}"

    def remove(self, addon_id: str) -> bool:
        """Remove an addon (built-in or custom)."""
        if addon_id in self._addons:
            manifest = self._addons[addon_id].get_manifest()
            if manifest.is_builtin:
                self._removed_builtins.add(addon_id)
            del self._addons[addon_id]
            self._enabled.pop(addon_id, None)
            self._custom_urls.pop(addon_id, None)
            self._custom_manifests.pop(addon_id, None)
            self._save_config()
            return True
        return False

    def set_enabled(self, addon_id: str, enabled: bool):
        """Enable or disable an addon."""
        if addon_id in self._addons:
            self._enabled[addon_id] = enabled
            self._save_config()

    def is_builtin_removed(self, addon_id: str) -> bool:
        """Check if a built-in addon has been removed by the user."""
        return addon_id in self._removed_builtins

    def get_addon(self, addon_id: str) -> Optional[BaseAddon]:
        """Get one enabled addon by identifier."""
        if addon_id in self._addons and self._enabled.get(addon_id, False):
            return self._addons[addon_id]
        return None

    def list_addons(self) -> List[dict]:
        """List all addons with status."""
        result = []
        for addon_id, addon in self._addons.items():
            manifest = addon.get_manifest()
            result.append(
                {
                    **manifest.to_dict(),
                    "enabled": self._enabled.get(addon_id, True),
                }
            )
        return result

    def get_enabled_addons(self) -> List[BaseAddon]:
        """Return enabled addons."""
        return [addon for addon_id, addon in self._addons.items() if self._enabled.get(addon_id, False)]

    def _save_config(self):
        """Persist addon states and custom URLs."""
        config = {
            "enabled": self._enabled,
            "custom_urls": self._custom_urls,
            "custom_manifests": self._custom_manifests,
            "removed_builtins": list(self._removed_builtins),
        }
        try:
            with open(ADDONS_CONFIG_PATH, "w", encoding="utf-8") as file:
                json.dump(config, file, indent=2)
        except Exception as exc:
            print(f"[AddonManager] Save error: {exc}")

    def _load_config(self):
        """Load persisted addon states and reinstall custom addon URLs."""
        try:
            if not os.path.exists(ADDONS_CONFIG_PATH):
                return

            with open(ADDONS_CONFIG_PATH, "r", encoding="utf-8") as file:
                config = json.load(file)

            saved_enabled = config.get("enabled", {})
            saved_urls = config.get("custom_urls", {})
            saved_manifests = config.get("custom_manifests", {})
            self._removed_builtins = set(config.get("removed_builtins", []))

            self._enabled = dict(saved_enabled)
            self._custom_urls = {}
            self._custom_manifests = {}

            for url in list(saved_urls.values()):
                manifest, _ = self.install_from_url(url)
                if manifest and manifest.id in saved_enabled:
                    self._enabled[manifest.id] = bool(saved_enabled[manifest.id])

            for item in list(saved_manifests.values()):
                if not isinstance(item, dict):
                    continue
                payload = item.get("manifest")
                source_label = str(item.get("source_label") or "local-manifest.json")
                if not isinstance(payload, dict):
                    continue
                manifest, _ = self.install_from_manifest_data(payload, source_label=source_label)
                if manifest and manifest.id in saved_enabled:
                    self._enabled[manifest.id] = bool(saved_enabled[manifest.id])
        except Exception as exc:
            print(f"[AddonManager] Load config error: {exc}")
