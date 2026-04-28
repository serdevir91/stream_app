"""SuperEmbed Addon for providing multi-server embed links."""
from typing import List
from .base import BaseAddon, AddonManifest, SearchResult, StreamResult


class SuperEmbedAddon(BaseAddon):
    """Addon for resolving multiembed.mov / superembed links."""

    def get_manifest(self) -> AddonManifest:
        return AddonManifest(
            id="builtin.superembed",
            name="SuperEmbed",
            description="SuperEmbed multi-server embed provider.",
            version="1.0.0",
            types=["movie", "series"],
            is_builtin=True,
        )

    def search(self, query: str, content_type: str = "movie") -> List[SearchResult]:
        return []

    def get_streams(
        self,
        content_id: str,
        content_type: str = "movie",
        season: int = 1,
        episode: int = 1,
    ) -> List[StreamResult]:
        is_imdb = content_id.startswith("tt")

        streams = []
        if content_type == "movie":
            if is_imdb:
                url = f"https://multiembed.mov/?video_id={content_id}&imdb=1"
            else:
                url = f"https://multiembed.mov/?video_id={content_id}&tmdb=1"

            streams.append(
                StreamResult(
                    url=url,
                    title="SuperEmbed Server",
                    quality="HD",
                    provider="SuperEmbed",
                    is_direct_link=False,
                )
            )
        else:
            if is_imdb:
                url = f"https://multiembed.mov/?video_id={content_id}&imdb=1&s={season}&e={episode}"
            else:
                url = f"https://multiembed.mov/?video_id={content_id}&tmdb=1&s={season}&e={episode}"

            streams.append(
                StreamResult(
                    url=url,
                    title="SuperEmbed Server",
                    quality="HD",
                    provider="SuperEmbed",
                    is_direct_link=False,
                )
            )

        return streams
