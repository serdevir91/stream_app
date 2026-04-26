"""WebTorrent Demo Addon: Demonstrates torrent streaming with legal content."""
from typing import List
from .base import BaseAddon, AddonManifest, SearchResult, StreamResult

# Pre-curated list of legal, public domain torrents for demo
LEGAL_TORRENTS = [
    {
        "id": "big-buck-bunny",
        "title": "Big Buck Bunny",
        "year": "2008",
        "description": "Blender Foundation animated short film. CC-BY license.",
        "poster": "https://upload.wikimedia.org/wikipedia/commons/c/c5/Big_buck_bunny_poster_big.jpg",
        "magnet": "magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=Big+Buck+Bunny&tr=udp%3A%2F%2Fexplodie.org%3A6969&tr=udp%3A%2F%2Ftracker.coppersurfer.tk%3A6969",
        "direct_url": "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
    },
    {
        "id": "sintel",
        "title": "Sintel",
        "year": "2010",
        "description": "Blender Foundation animated short film. CC-BY license.",
        "poster": "https://upload.wikimedia.org/wikipedia/commons/1/1f/Sintel_poster.jpg",
        "magnet": "magnet:?xt=urn:btih:08ada5a7a6183aae1e09d831df6748d566095a10&dn=Sintel",
        "direct_url": "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4",
    },
    {
        "id": "tears-of-steel",
        "title": "Tears of Steel",
        "year": "2012",
        "description": "Blender Foundation sci-fi short film. CC-BY license.",
        "poster": "https://upload.wikimedia.org/wikipedia/commons/5/5a/Tears_of_Steel_poster.jpg",
        "magnet": "magnet:?xt=urn:btih:209c8226b299b308beaf2b9cd3fb49212dbd13ec&dn=Tears+of+Steel",
        "direct_url": "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4",
    },
    {
        "id": "elephants-dream",
        "title": "Elephants Dream",
        "year": "2006",
        "description": "Blender Foundation's first open movie. CC-BY license.",
        "poster": "https://upload.wikimedia.org/wikipedia/commons/9/90/Elephants_Dream_poster.jpg",
        "magnet": "magnet:?xt=urn:btih:1af129fe3e0dcaf37e59ee1fb66dfae63f7fa28b&dn=Elephants+Dream",
        "direct_url": "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
    },
]


class WebTorrentAddon(BaseAddon):
    def get_manifest(self) -> AddonManifest:
        return AddonManifest(
            id="webtorrent",
            name="WebTorrent Demo",
            description="Legal/açık kaynak torrent streaming demo (Blender filmleri)",
            version="1.0",
            types=["movie"],
            icon="🧲",
            is_builtin=True,
        )

    def search(self, query: str, content_type: str = "movie") -> List[SearchResult]:
        query_lower = query.lower()
        results = []
        for item in LEGAL_TORRENTS:
            if query_lower in item["title"].lower() or query_lower in item.get("description", "").lower():
                results.append(SearchResult(
                    id=item["id"],
                    title=item["title"],
                    type="movie",
                    year=item.get("year"),
                    poster=item.get("poster"),
                    description=item.get("description"),
                ))
        # If no match, return all items
        if not results:
            results = [SearchResult(
                id=item["id"],
                title=item["title"],
                type="movie",
                year=item.get("year"),
                poster=item.get("poster"),
                description=item.get("description"),
            ) for item in LEGAL_TORRENTS]
        return results

    def get_streams(self, content_id: str, content_type: str = "movie",
                    season: int = 1, episode: int = 1) -> List[StreamResult]:
        for item in LEGAL_TORRENTS:
            if item["id"] == content_id:
                streams = []
                # Direct HTTP stream (always works)
                if item.get("direct_url"):
                    streams.append(StreamResult(
                        url=item["direct_url"],
                        title=f"{item['title']} - Direct HTTP",
                        quality="720p",
                        provider="WebTorrent (HTTP)",
                    ))
                # Magnet link (for learning/demo)
                if item.get("magnet"):
                    streams.append(StreamResult(
                        url=item["magnet"],
                        title=f"{item['title']} - Magnet Link",
                        quality="Original",
                        provider="WebTorrent (Magnet)",
                    ))
                return streams
        return []
