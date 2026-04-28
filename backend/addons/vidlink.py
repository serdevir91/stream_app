"""VidLink Addon for providing embed links."""
from typing import List
from .base import BaseAddon, AddonManifest, SearchResult, StreamResult


class VidLinkAddon(BaseAddon):
    """Addon for resolving vidlink.pro links."""

    def get_manifest(self) -> AddonManifest:
        return AddonManifest(
            id="builtin.vidlink",
            name="VidLink",
            description="VidLink embed player provider.",
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
                url = f"https://vidlink.pro/movie/{content_id}"
            else:
                url = f"https://vidlink.pro/movie/{content_id}"

            streams.append(
                StreamResult(
                    url=url,
                    title="VidLink Server",
                    quality="HD",
                    provider="VidLink",
                    is_direct_link=False,
                )
            )
        else:
            if is_imdb:
                url = f"https://vidlink.pro/tv/{content_id}/{season}/{episode}"
            else:
                url = f"https://vidlink.pro/tv/{content_id}/{season}/{episode}"

            streams.append(
                StreamResult(
                    url=url,
                    title="VidLink Server",
                    quality="HD",
                    provider="VidLink",
                    is_direct_link=False,
                )
            )

        return streams
