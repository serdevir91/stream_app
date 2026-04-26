"""VidSrc Addon for providing HTML embed links."""
from typing import List, Optional
from .base import BaseAddon, AddonManifest, SearchResult, StreamResult


class VidSrcAddon(BaseAddon):
    """Addon for resolving vidsrc-embed.ru links."""

    def get_manifest(self) -> AddonManifest:
        return AddonManifest(
            id="builtin.vidsrc",
            name="VidSrc",
            description="VidSrc embed player provider.",
            version="1.0.0",
            types=["movie", "series"],
            is_builtin=True,
        )

    def search(self, query: str, content_type: str = "movie") -> List[SearchResult]:
        # VidSrc doesn't provide a direct title search that we use for resolution,
        # it relies on TMDB/IMDB IDs. We return an empty list because the TMDB
        # integration in the frontend will supply the TMDB ID directly.
        return []

    def get_streams(
        self,
        content_id: str,
        content_type: str = "movie",
        season: int = 1,
        episode: int = 1,
    ) -> List[StreamResult]:
        """Resolve stream from TMDB/IMDB id."""
        # Check if content_id is a numeric TMDB ID or starts with 'tt' (IMDB ID)
        is_imdb = content_id.startswith("tt")
        
        streams = []
        if content_type == "movie":
            if is_imdb:
                url = f"https://vidsrc-embed.ru/embed/movie?imdb={content_id}&ds_lang=tr"
            else:
                url = f"https://vidsrc-embed.ru/embed/movie?tmdb={content_id}&ds_lang=tr"
            
            streams.append(
                StreamResult(
                    url=url,
                    title="VidSrc Embed",
                    quality="HD",
                    provider="VidSrc",
                    is_direct_link=False,
                )
            )
        else:
            if is_imdb:
                url = f"https://vidsrc-embed.ru/embed/tv?imdb={content_id}&season={season}&episode={episode}&ds_lang=tr&autonext=1"
            else:
                url = f"https://vidsrc-embed.ru/embed/tv?tmdb={content_id}&season={season}&episode={episode}&ds_lang=tr&autonext=1"
            
            streams.append(
                StreamResult(
                    url=url,
                    title="VidSrc Embed",
                    quality="HD",
                    provider="VidSrc",
                    is_direct_link=False,
                )
            )

        return streams
