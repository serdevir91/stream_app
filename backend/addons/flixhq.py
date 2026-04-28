"""FlixHQ Addon for searching and streaming from FlixHQ/MoviesAPI."""
import asyncio
from typing import List, Optional
import httpx

from .base import BaseAddon, AddonManifest, SearchResult, StreamResult


# Known FlixHQ/MoviesAPI mirror domains. Update if one goes down.
FLIXHQ_DOMAINS = [
    "https://moviesapi.club",
    "https://flixhq.to",
]


class FlixHQAddon(BaseAddon):
    """Addon for searching and streaming from FlixHQ-compatible APIs."""

    def __init__(self) -> None:
        self._base_url: Optional[str] = None

    def get_manifest(self) -> AddonManifest:
        return AddonManifest(
            id="builtin.flixhq",
            name="FlixHQ",
            description="FlixHQ/MoviesAPI free streaming source.",
            version="1.0.0",
            types=["movie", "series"],
            is_builtin=True,
        )

    async def _find_working_domain(self) -> str:
        if self._base_url:
            return self._base_url
        async with httpx.AsyncClient(timeout=10, follow_redirects=True) as client:
            for domain in FLIXHQ_DOMAINS:
                try:
                    resp = await client.get(f"{domain}/search?query=test")
                    if resp.status_code == 200:
                        self._base_url = domain
                        return domain
                except Exception:
                    continue
        self._base_url = FLIXHQ_DOMAINS[0]
        return self._base_url

    def search(self, query: str, content_type: str = "movie") -> List[SearchResult]:
        try:
            return asyncio.get_event_loop().run_until_complete(
                self._search_async(query, content_type)
            )
        except RuntimeError:
            loop = asyncio.new_event_loop()
            try:
                return loop.run_until_complete(self._search_async(query, content_type))
            finally:
                loop.close()

    async def _search_async(self, query: str, content_type: str) -> List[SearchResult]:
        base = await self._find_working_domain()
        async with httpx.AsyncClient(timeout=15, follow_redirects=True) as client:
            try:
                resp = await client.get(f"{base}/search", params={"query": query})
                if resp.status_code != 200:
                    return []
                data = resp.json()
            except Exception as exc:
                print(f"[FlixHQ] Search error: {exc}")
                return []

        results = []
        items = data if isinstance(data, list) else data.get("results", [])
        for item in items[:15]:
            item_type = item.get("type", "").lower()
            if "tv" in item_type or "show" in item_type or "series" in item_type:
                mapped_type = "series"
            else:
                mapped_type = "movie"

            results.append(
                SearchResult(
                    id=item.get("id", ""),
                    title=item.get("title", item.get("name", "Unknown")),
                    type=mapped_type,
                    year=str(item.get("releaseDate", item.get("year", ""))) or None,
                    poster=item.get("image", item.get("poster")),
                    description=item.get("description"),
                )
            )
        return results

    def get_streams(
        self,
        content_id: str,
        content_type: str = "movie",
        season: int = 1,
        episode: int = 1,
    ) -> List[StreamResult]:
        try:
            return asyncio.get_event_loop().run_until_complete(
                self._get_streams_async(content_id, content_type, season, episode)
            )
        except RuntimeError:
            loop = asyncio.new_event_loop()
            try:
                return loop.run_until_complete(
                    self._get_streams_async(content_id, content_type, season, episode)
                )
            finally:
                loop.close()

    async def _get_streams_async(
        self,
        content_id: str,
        content_type: str,
        season: int,
        episode: int,
    ) -> List[StreamResult]:
        base = await self._find_working_domain()
        async with httpx.AsyncClient(timeout=15, follow_redirects=True) as client:
            try:
                if content_type == "series":
                    info_resp = await client.get(
                        f"{base}/tv/info", params={"id": content_id}
                    )
                else:
                    info_resp = await client.get(
                        f"{base}/movie/info", params={"id": content_id}
                    )

                if info_resp.status_code != 200:
                    return []

                info = info_resp.json()
            except Exception as exc:
                print(f"[FlixHQ] Info error: {exc}")
                return []

        episode_id = None
        if content_type == "series":
            seasons = info.get("seasons", [])
            for s in seasons:
                if s.get("season") == season or s.get("number") == season:
                    episodes = s.get("episodes", [])
                    for ep in episodes:
                        if ep.get("episode") == episode or ep.get("number") == episode:
                            episode_id = ep.get("id")
                            break
                    break

            if not episode_id:
                return []
        else:
            episode_id = info.get("id", content_id)

        async with httpx.AsyncClient(timeout=15, follow_redirects=True) as client:
            try:
                if content_type == "series":
                    stream_resp = await client.get(
                        f"{base}/tv/stream", params={"id": episode_id}
                    )
                else:
                    stream_resp = await client.get(
                        f"{base}/movie/stream", params={"id": episode_id}
                    )

                if stream_resp.status_code != 200:
                    return []

                stream_data = stream_resp.json()
            except Exception as exc:
                print(f"[FlixHQ] Stream error: {exc}")
                return []

        streams = []
        sources = stream_data.get("sources", [])
        for source in sources:
            url = source.get("url", source.get("file", ""))
            if not url:
                continue
            quality = source.get("quality", "HD")
            streams.append(
                StreamResult(
                    url=url,
                    title=f"FlixHQ ({quality})",
                    quality=quality,
                    provider="FlixHQ",
                    is_direct_link=True,
                )
            )

        return streams
