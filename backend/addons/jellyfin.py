"""Jellyfin Addon: Streams from your self-hosted Jellyfin server."""
import os
from typing import List
from .base import BaseAddon, AddonManifest, SearchResult, StreamResult
import httpx

JELLYFIN_URL = os.getenv("JELLYFIN_URL", "http://127.0.0.1:8096").strip()
JELLYFIN_TOKEN = os.getenv("JELLYFIN_TOKEN", "").strip()
JELLYFIN_USER_ID = os.getenv("JELLYFIN_USER_ID", "").strip()

HEADERS = {
    "X-Emby-Authorization": f'MediaBrowser Token="{JELLYFIN_TOKEN}"',
    "Accept": "application/json",
}


def _has_valid_config() -> bool:
    return bool(JELLYFIN_URL and JELLYFIN_TOKEN and JELLYFIN_USER_ID)


class JellyfinAddon(BaseAddon):
    def get_manifest(self) -> AddonManifest:
        return AddonManifest(
            id="jellyfin",
            name="Jellyfin",
            description="Kendi sunucunuzdaki medya kütüphanesi",
            version="1.0",
            types=["movie", "series"],
            icon="🟣",
            is_builtin=True,
        )

    def search(self, query: str, content_type: str = "movie") -> List[SearchResult]:
        if not _has_valid_config():
            return []
        try:
            jf_type = "Movie" if content_type == "movie" else "Series"
            with httpx.Client(timeout=10.0) as client:
                r = client.get(
                    f"{JELLYFIN_URL}/Users/{JELLYFIN_USER_ID}/Items",
                    headers=HEADERS,
                    params={
                        "SearchTerm": query,
                        "IncludeItemTypes": jf_type,
                        "Recursive": "true",
                        "Limit": 20,
                        "Fields": "Overview",
                    },
                )
                data = r.json()
                results = []
                for item in data.get("Items", []):
                    poster = None
                    if item.get("ImageTags", {}).get("Primary"):
                        poster = f"{JELLYFIN_URL}/Items/{item['Id']}/Images/Primary?api_key={JELLYFIN_TOKEN}"
                    results.append(SearchResult(
                        id=item["Id"],
                        title=item["Name"],
                        type=content_type,
                        year=str(item.get("ProductionYear", "")),
                        poster=poster,
                        description=item.get("Overview"),
                    ))
                return results
        except Exception as e:
            print(f"[Jellyfin] Search error: {e}")
            return []

    def get_streams(self, content_id: str, content_type: str = "movie",
                    season: int = 1, episode: int = 1) -> List[StreamResult]:
        if not _has_valid_config():
            return []
        try:
            if content_type == "series":
                with httpx.Client(timeout=10.0) as client:
                    r = client.get(
                        f"{JELLYFIN_URL}/Shows/{content_id}/Episodes",
                        headers=HEADERS,
                        params={"UserId": JELLYFIN_USER_ID, "Season": season},
                    )
                    episodes = r.json().get("Items", [])
                    for ep in episodes:
                        if ep.get("IndexNumber") == episode:
                            return [StreamResult(
                                url=f"{JELLYFIN_URL}/Items/{ep['Id']}/Download?api_key={JELLYFIN_TOKEN}",
                                title=f"Jellyfin - S{season:02d}E{episode:02d}",
                                quality="Original",
                                provider="Jellyfin",
                            )]
                return []
            else:
                return [StreamResult(
                    url=f"{JELLYFIN_URL}/Items/{content_id}/Download?api_key={JELLYFIN_TOKEN}",
                    title="Jellyfin - Original",
                    quality="Original",
                    provider="Jellyfin",
                )]
        except Exception as e:
            print(f"[Jellyfin] Stream error: {e}")
            return []
