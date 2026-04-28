"""2Embed Addon for providing HTML embed links."""
from typing import List
from .base import BaseAddon, AddonManifest, SearchResult, StreamResult


class TwoEmbedAddon(BaseAddon):
    """Addon for resolving 2embed.cc links."""

    def get_manifest(self) -> AddonManifest:
        return AddonManifest(
            id="builtin.twoembed",
            name="2Embed",
            description="2Embed multi-server embed provider.",
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
                url = f"https://www.2embed.cc/embed/{content_id}"
            else:
                url = f"https://www.2embed.cc/embed/{content_id}"

            streams.append(
                StreamResult(
                    url=url,
                    title="2Embed Server",
                    quality="HD",
                    provider="2Embed",
                    is_direct_link=False,
                )
            )
        else:
            if is_imdb:
                url = f"https://www.2embed.cc/embed/tv?id={content_id}&s={season}&e={episode}"
            else:
                url = f"https://www.2embed.cc/embed/tv?id={content_id}&s={season}&e={episode}"

            streams.append(
                StreamResult(
                    url=url,
                    title="2Embed Server",
                    quality="HD",
                    provider="2Embed",
                    is_direct_link=False,
                )
            )

        return streams
