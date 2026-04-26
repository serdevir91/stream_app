"""Archive.org Addon: Streams public domain movies and videos."""
from typing import List
from .base import BaseAddon, AddonManifest, SearchResult, StreamResult
import httpx


class ArchiveOrgAddon(BaseAddon):
    def get_manifest(self) -> AddonManifest:
        return AddonManifest(
            id="archiveorg",
            name="Archive.org",
            description="Kamu malı filmler ve videolar (Public Domain)",
            version="1.0",
            types=["movie"],
            icon="📚",
            is_builtin=True,
        )

    def search(self, query: str, content_type: str = "movie") -> List[SearchResult]:
        try:
            with httpx.Client(timeout=10.0) as client:
                r = client.get("https://archive.org/advancedsearch.php", params={
                    "q": f"{query} mediatype:movies",
                    "fl[]": "identifier,title,description,year",
                    "rows": 20,
                    "output": "json",
                })
                data = r.json()
                results = []
                for doc in data.get("response", {}).get("docs", []):
                    identifier = doc.get("identifier", "")
                    results.append(SearchResult(
                        id=identifier,
                        title=doc.get("title", "Unknown"),
                        type="movie",
                        year=str(doc.get("year", "")),
                        poster=f"https://archive.org/services/img/{identifier}",
                        description=doc.get("description", "")[:200] if doc.get("description") else None,
                    ))
                return results
        except Exception as e:
            print(f"[Archive.org] Search error: {e}")
            return []

    def get_streams(self, content_id: str, content_type: str = "movie",
                    season: int = 1, episode: int = 1) -> List[StreamResult]:
        try:
            with httpx.Client(timeout=10.0, follow_redirects=True) as client:
                r = client.get(f"https://archive.org/metadata/{content_id}")
                data = r.json()

                streams = []
                files = data.get("files", [])

                # Find video files (mp4, avi, mkv, ogv)
                video_extensions = {".mp4", ".avi", ".mkv", ".ogv", ".webm"}
                for f in files:
                    name = f.get("name", "")
                    ext = name[name.rfind("."):].lower() if "." in name else ""
                    if ext in video_extensions:
                        size_mb = round(int(f.get("size", 0)) / (1024 * 1024), 1)
                        quality = f.get("height", "")
                        if quality:
                            quality = f"{quality}p"
                        else:
                            quality = f"{size_mb}MB"

                        streams.append(StreamResult(
                            url=f"https://archive.org/download/{content_id}/{name}",
                            title=f"Archive.org - {name}",
                            quality=quality,
                            provider="Archive.org",
                        ))

                # Also add torrent link for WebTorrent demo
                torrent_url = f"https://archive.org/download/{content_id}/{content_id}_archive.torrent"
                streams.append(StreamResult(
                    url=torrent_url,
                    title=f"Archive.org Torrent - {content_id}",
                    quality="Torrent",
                    provider="Archive.org (Torrent)",
                ))

                return streams
        except Exception as e:
            print(f"[Archive.org] Stream error: {e}")
            return []
