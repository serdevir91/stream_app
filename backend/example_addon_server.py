"""
Örnek Custom Addon Sunucusu
============================
Bu dosyayı çalıştırarak kendi addon sunucunuzu başlatabilirsiniz.
Ardından Flutter uygulamasından http://127.0.0.1:9001 adresini ekleyin.

Kullanım:
  python example_addon_server.py

Bu addon, YouTube'daki Creative Commons lisanslı videoları listeler.
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

# ─── Manifest ───
@app.get("/manifest.json")
def manifest():
    return {
        "id": "my-custom-addon",
        "name": "Benim Addonum",
        "description": "Kendi oluşturduğum örnek addon - Creative Commons videolar",
        "version": "1.0",
        "types": ["movie"],
        "icon": "🎬",
    }


# ─── Sample Data ───
VIDEOS = [
    {
        "id": "sample-1",
        "title": "Big Buck Bunny (4K)",
        "type": "movie",
        "year": "2008",
        "description": "Blender Foundation tarafından üretilen animasyon kısa film.",
        "poster": "https://upload.wikimedia.org/wikipedia/commons/c/c5/Big_buck_bunny_poster_big.jpg",
        "stream_url": "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
    },
    {
        "id": "sample-2",
        "title": "Sintel",
        "type": "movie",
        "year": "2010",
        "description": "Ejderha avcısı bir kızın hikayesi. Blender Foundation.",
        "poster": "https://upload.wikimedia.org/wikipedia/commons/1/1f/Sintel_poster.jpg",
        "stream_url": "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4",
    },
    {
        "id": "sample-3",
        "title": "Tears of Steel",
        "type": "movie",
        "year": "2012",
        "description": "Bilim kurgu kısa film. Blender Foundation.",
        "poster": "https://upload.wikimedia.org/wikipedia/commons/5/5a/Tears_of_Steel_poster.jpg",
        "stream_url": "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4",
    },
    {
        "id": "sample-4",
        "title": "For Bigger Blazes",
        "type": "movie",
        "year": "2013",
        "description": "Google tarafından sağlanan test videosu.",
        "stream_url": "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
    },
    {
        "id": "sample-5",
        "title": "Subaru Outback",
        "type": "movie",
        "year": "2013",
        "description": "Google test videosu - araba reklamı.",
        "stream_url": "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/SubaruOutbackOnStreetAndDirt.mp4",
    },
]


# ─── Search ───
@app.get("/search")
def search(query: str = "", type: str = "movie"):
    query_lower = query.lower()
    results = [v for v in VIDEOS if query_lower in v["title"].lower() or query_lower in v.get("description", "").lower()]
    if not results:
        results = VIDEOS  # Return all if no match
    return {"results": [{k: v for k, v in item.items() if k != "stream_url"} for item in results]}


# ─── Stream ───
@app.get("/stream")
def stream(id: str = "", type: str = "movie", season: int = 1, episode: int = 1):
    for v in VIDEOS:
        if v["id"] == id:
            return {"streams": [{"url": v["stream_url"], "title": v["title"], "quality": "720p", "provider": "Custom Addon"}]}
    return {"streams": []}


if __name__ == "__main__":
    print("=" * 50)
    print("  Örnek Addon Sunucusu")
    print("  URL: http://127.0.0.1:9001")
    print("  Bu URL'yi uygulamadan 'Addon Ekle' ile ekleyin")
    print("=" * 50)
    uvicorn.run(app, host="0.0.0.0", port=9001)
