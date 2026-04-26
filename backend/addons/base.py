"""Base class for all addons."""
from abc import ABC, abstractmethod
from typing import List, Optional
from dataclasses import dataclass, asdict


@dataclass
class SearchResult:
    id: str
    title: str
    type: str  # "movie" or "series"
    year: Optional[str] = None
    poster: Optional[str] = None
    description: Optional[str] = None

    def to_dict(self):
        return asdict(self)


@dataclass
class StreamResult:
    url: str
    title: str
    quality: Optional[str] = None
    provider: Optional[str] = None
    is_direct_link: bool = True

    def to_dict(self):
        return asdict(self)


@dataclass
class AddonManifest:
    id: str
    name: str
    description: str
    version: str
    types: List[str]  # ["movie", "series"]
    icon: Optional[str] = None
    is_builtin: bool = False

    def to_dict(self):
        return asdict(self)


class BaseAddon(ABC):
    """Abstract base class for all addons (built-in and custom)."""

    @abstractmethod
    def get_manifest(self) -> AddonManifest:
        """Return addon metadata."""
        pass

    @abstractmethod
    def search(self, query: str, content_type: str = "movie") -> List[SearchResult]:
        """Search for content. Returns list of search results."""
        pass

    @abstractmethod
    def get_streams(self, content_id: str, content_type: str = "movie",
                    season: int = 1, episode: int = 1) -> List[StreamResult]:
        """Get stream URLs for a given content ID."""
        pass
