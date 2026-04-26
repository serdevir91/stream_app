"""Web source addon that extracts playable links from direct URLs or web pages."""

from __future__ import annotations

from dataclasses import dataclass
from html import unescape
import os
import re
from typing import Dict, List, Optional
from urllib.parse import urljoin, urlparse

import httpx

from .base import AddonManifest, BaseAddon, SearchResult, StreamResult

_MEDIA_EXTENSIONS = (
    ".m3u8",
    ".mp4",
    ".webm",
    ".mkv",
    ".avi",
    ".mov",
    ".m4v",
    ".mpd",
)

_URL_RE = re.compile(r"https?://[^\s\"'<>]+", re.IGNORECASE)
_HREF_RE = re.compile(r"(?:href|src)=['\"]([^'\"]+)['\"]", re.IGNORECASE)
_TITLE_RE = re.compile(r"<title[^>]*>(.*?)</title>", re.IGNORECASE | re.DOTALL)
_META_DESCRIPTION_RE = re.compile(
    r"<meta[^>]+(?:name=['\"]description['\"]|property=['\"]og:description['\"])[^>]+content=['\"](.*?)['\"]",
    re.IGNORECASE,
)
_META_IMAGE_RE = re.compile(
    r"<meta[^>]+property=['\"]og:image['\"][^>]+content=['\"](.*?)['\"]",
    re.IGNORECASE,
)


@dataclass
class _CandidateItem:
    """Internal candidate object for search and stream extraction."""

    id: str
    title: str
    content_type: str
    description: Optional[str]
    poster: Optional[str]
    streams: List[str]


class WebSourceAddon(BaseAddon):
    """Addon that treats a web URL as a stream source."""

    def __init__(self, source_url: str, manifest: AddonManifest):
        self._source_url = source_url.strip()
        self._manifest = manifest
        self._parsed_items: Dict[str, _CandidateItem] = {}
        self._is_parsed = False

    def get_manifest(self) -> AddonManifest:
        """Return addon manifest."""
        return self._manifest

    def search(self, query: str, content_type: str = "movie") -> List[SearchResult]:
        """Search in extracted candidates from the web source URL."""
        self._ensure_parsed(default_type=content_type)
        q = query.strip().lower()

        results: List[SearchResult] = []
        for candidate in self._parsed_items.values():
            if content_type == "series" and candidate.content_type == "movie":
                continue
            if content_type == "movie" and candidate.content_type == "series":
                continue

            haystack = f"{candidate.title} {candidate.description or ''}".lower()
            if q and q not in haystack:
                continue

            results.append(
                SearchResult(
                    id=candidate.id,
                    title=candidate.title,
                    type=candidate.content_type,
                    year=None,
                    poster=candidate.poster,
                    description=candidate.description,
                )
            )

        return results[:50]

    def get_streams(
        self,
        content_id: str,
        content_type: str = "movie",
        season: int = 1,
        episode: int = 1,
    ) -> List[StreamResult]:
        """Return extracted streams for a candidate item."""
        self._ensure_parsed(default_type=content_type)

        candidate = self._parsed_items.get(content_id)
        if not candidate and len(self._parsed_items) == 1:
            candidate = next(iter(self._parsed_items.values()))

        if not candidate:
            return []

        streams: List[StreamResult] = []
        for stream_url in candidate.streams:
            streams.append(
                StreamResult(
                    url=stream_url,
                    title=candidate.title,
                    quality=_guess_quality(stream_url),
                    provider=self._manifest.name,
                )
            )

        return streams

    def _ensure_parsed(self, default_type: str) -> None:
        """Parse source URL once and cache candidate items."""
        if self._is_parsed:
            return

        self._is_parsed = True

        if _is_direct_media_url(self._source_url):
            cid = _candidate_id(self._source_url)
            self._parsed_items[cid] = _CandidateItem(
                id=cid,
                title=_title_from_url(self._source_url),
                content_type=default_type if default_type in ("movie", "series") else "movie",
                description="Doğrudan medya bağlantısı",
                poster=None,
                streams=[self._source_url],
            )
            return

        try:
            with httpx.Client(
                timeout=15.0,
                follow_redirects=True,
                headers={
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36",
                    "Accept": "text/html,application/json,*/*",
                },
            ) as client:
                response = client.get(self._source_url)
                if response.status_code >= 400:
                    return
                body = response.text
        except Exception:
            return

        title_match = _TITLE_RE.search(body)
        page_title = _cleanup_text(title_match.group(1)) if title_match else _title_from_url(self._source_url)

        desc_match = _META_DESCRIPTION_RE.search(body)
        page_description = _cleanup_text(desc_match.group(1)) if desc_match else None

        poster_match = _META_IMAGE_RE.search(body)
        page_poster = _normalize_url(poster_match.group(1), self._source_url) if poster_match else None

        urls = set()
        for found in _URL_RE.findall(body):
            normalized = _normalize_url(found, self._source_url)
            if _is_direct_media_url(normalized):
                urls.add(normalized)

        for found in _HREF_RE.findall(body):
            normalized = _normalize_url(found, self._source_url)
            if _is_direct_media_url(normalized):
                urls.add(normalized)

        if not urls:
            return

        for media_url in sorted(urls):
            item_title = _title_from_url(media_url)
            inferred_type = _infer_type(item_title, page_title, default_type)
            cid = _candidate_id(media_url)
            self._parsed_items[cid] = _CandidateItem(
                id=cid,
                title=item_title,
                content_type=inferred_type,
                description=page_description,
                poster=page_poster,
                streams=[media_url],
            )

        if self._parsed_items:
            merged_id = _candidate_id(self._source_url)
            merged_streams = [item.streams[0] for item in self._parsed_items.values()]
            self._parsed_items[merged_id] = _CandidateItem(
                id=merged_id,
                title=page_title,
                content_type=default_type if default_type in ("movie", "series") else "movie",
                description=page_description,
                poster=page_poster,
                streams=merged_streams,
            )


def _cleanup_text(value: str) -> str:
    """Normalize text extracted from HTML."""
    text = unescape(value or "")
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def _normalize_url(url: str, base_url: str) -> str:
    """Normalize and absolutize potentially relative URL values."""
    clean = url.strip()
    if clean.startswith("//"):
        parsed = urlparse(base_url)
        return f"{parsed.scheme}:{clean}"
    if clean.startswith("/"):
        return urljoin(base_url, clean)
    return clean


def _is_direct_media_url(url: str) -> bool:
    """Check if URL likely points to direct media content."""
    value = (url or "").strip().lower()
    if value.startswith("magnet:?"):
        return True

    path = value.split("?", 1)[0].split("#", 1)[0]
    return any(path.endswith(ext) for ext in _MEDIA_EXTENSIONS)


def _title_from_url(url: str) -> str:
    """Create a readable title from a URL path."""
    parsed = urlparse(url)
    filename = os.path.basename(parsed.path) or parsed.netloc
    filename = re.sub(r"\.[A-Za-z0-9]{2,5}$", "", filename)
    title = filename.replace("-", " ").replace("_", " ").strip()
    return title or "Web Kaynağı"


def _candidate_id(value: str) -> str:
    """Build deterministic candidate identifier from URL."""
    import hashlib

    digest = hashlib.sha1(value.encode("utf-8")).hexdigest()[:14]
    return f"web-{digest}"


def _infer_type(title: str, context_title: str, default_type: str) -> str:
    """Infer whether candidate is movie or series."""
    text = f"{title} {context_title}".lower()
    if any(token in text for token in ["s01", "s1", "season", "episode", "bölüm", "sezon"]):
        return "series"
    if default_type in ("movie", "series"):
        return default_type
    return "movie"


def _guess_quality(url: str) -> str:
    """Guess quality from URL tokens."""
    lower = (url or "").lower()
    for token in ["2160", "1440", "1080", "720", "480", "360"]:
        if token in lower:
            return f"{token}p"
    if lower.startswith("magnet:?"):
        return "Torrent"
    if ".m3u8" in lower:
        return "HLS"
    if ".mpd" in lower:
        return "DASH"
    return "Auto"
