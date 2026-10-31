#!/usr/bin/env python3
"""
Enhance MP3 metadata for a DJ music library.

Pipeline:
    1. Read existing ID3 metadata as fallback/baseline.
    2. Fingerprint audio via fpcalc + AcoustID API (cached, including no-match).
    3. Resolve genre via artist rules, filename keywords, and Last.fm API.
    4. Compute BPM, Camelot Key, and key confidence via Essentia unconditionally.
    5. Write tag updates to MP3 files (ID3v2.3).
    6. Write JSON catalog atomically, retaining both active tags and
       Essentia analysis telemetry (analyzed_bpm / analyzed_key / strength).

Caching model
-------------
* Fingerprint cache key   : file signature (abs path + size + mtime_ns)
* Fingerprint sentinel    : presence of "acoustid_match" in the cached dict.
                            A track that was fingerprinted but yielded no
                            AcoustID match is NOT re-fingerprinted.
* Genre cache key         : genre::<artist>::<title>::<filename>
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

try:
    import requests
except ImportError:
    requests = None  # type: ignore[assignment]

try:
    import essentia
    essentia.log.infoActive = False
    import essentia.standard as es
except ImportError:
    essentia = None  # type: ignore[assignment]
    es = None  # type: ignore[assignment]

try:
    from mutagen.id3 import ID3, ID3NoHeaderError, TBPM, TCON, TKEY, TIT2, TPE1
except ImportError:
    ID3 = None  # type: ignore[assignment,misc]
    ID3NoHeaderError = Exception  # type: ignore[misc,assignment]
    TBPM = TCON = TKEY = TIT2 = TPE1 = None  # type: ignore[assignment,misc]


# ---------------------------------------------------------------------------
# Configuration & Constants
# ---------------------------------------------------------------------------

DEFAULT_MUSIC_DIR = Path("/home/ekco/Music/music")
DEFAULT_CATALOG_NAME = "dj_catalog.json"
DEFAULT_CACHE_NAME = ".metadata_cache.json"

# Keys come from the environment (~/.config/kaia/env, sourced by .bashrc).
# They used to be inline; this script is published in the public arch-config repo.
ACOUSTID_API_KEY = ""
LASTFM_API_KEY = ""

ACOUSTID_API_URL = "https://api.acoustid.org/v2/lookup"
LASTFM_API_URL = "https://ws.audioscrobbler.com/2.0/"

HTTP_TIMEOUT = (4, 10)
FPCALC_TIMEOUT = 20

CAMELOT_MAP = {
    ("C", "major"): "8B",  ("A", "minor"): "8A",
    ("G", "major"): "9B",  ("E", "minor"): "9A",
    ("D", "major"): "10B", ("B", "minor"): "10A",
    ("A", "major"): "11B", ("F#", "minor"): "11A", ("Gb", "minor"): "11A",
    ("E", "major"): "12B", ("C#", "minor"): "12A", ("Db", "minor"): "12A",
    ("B", "major"): "1B",  ("G#", "minor"): "1A",  ("Ab", "minor"): "1A",
    ("F#", "major"): "2B", ("Gb", "major"): "2B",  ("D#", "minor"): "2A", ("Eb", "minor"): "2A",
    ("Db", "major"): "3B", ("C#", "major"): "3B",  ("Bb", "minor"): "3A", ("A#", "minor"): "3A",
    ("Ab", "major"): "4B", ("G#", "major"): "4B",  ("F", "minor"): "4A",
    ("Eb", "major"): "5B", ("D#", "major"): "5B",  ("C", "minor"): "5A",
    ("Bb", "major"): "6B", ("A#", "major"): "6B",  ("G", "minor"): "6A",
    ("F", "major"): "7B",  ("D", "minor"): "7A",
}

ARTIST_GENRES = {
    "taylor swift": "Pop",
    "the church": "Post-Punk / New Wave",
    "dj icey": "Breakbeat",
    "jondi & spesh": "Progressive House / Trance",
    "cleveland lounge": "Drum & Bass",
    "yeah yeah yeahs": "Indie Rock",
    "boy harsher": "Darkwave / EBM",
    "purple disco machine": "Nu-Disco / House",
    "goldie": "Drum & Bass / Jungle",
    "rüfüs du sol": "Melodic House",
    "rufus du sol": "Melodic House",
    "tool": "Progressive Metal",
    "depeche mode": "Synthpop / Darkwave",
    "duran duran": "Synthpop / New Wave",
    "justice": "Electro House / French Touch",
    "the chemical brothers": "Big Beat / Electronic",
    "chemical brothers": "Big Beat / Electronic",
    "inzo": "Electronic / Dubstep",
    "bicep": "Electronic / Breaks",
    "dvrst": "Phonk",
    "crystal castles": "Electropop / Synthpunk",
    "monrroe": "Liquid DnB",
    "ghost in the shell ost": "Soundtrack / Drum & Bass",
    "infected mushroom": "Psytrance",
    "mitch murder": "Synthwave",
    "lazerhawk": "Synthwave",
    "french 79": "Synthwave / Electropop",
    "elderbrook": "Deep House / Electronic",
    "die antwoord": "Electro Hip-Hop",
    "aesop rock": "Hip-Hop",
    "swedish house mafia": "Progressive House",
    "ferry corsten": "Trance",
    "paul van dyk": "Trance",
    "energy 52": "Trance",
    "system f": "Trance",
    "gouryella": "Trance",
    "the orb": "Ambient Techno",
    "bonobo": "Downtempo / Electronic",
    "röyksopp": "Electropop / Downtempo",
    "royksopp": "Electropop / Downtempo",
    "dirty vegas": "House / Electropop",
    "stardust": "French House",
    "empire of the sun": "Synthpop / Electro",
    "kosheen": "Drum & Bass / Trip-Hop",
    "trevor something": "Synthwave",
}

GENRE_KEYWORDS = [
    (r"\b(dnb|drum\s*(?:and|&)\s*bass)\b", "Drum & Bass"),
    (r"\bjungle\b", "Jungle"),
    (r"\bphonk\b", "Phonk"),
    (r"\bdeep\s+house\b", "Deep House"),
    (r"\btech\s+house\b", "Tech House"),
    (r"\bprogressive\s+house\b", "Progressive House"),
    (r"\btechno\b", "Techno"),
    (r"\bhouse\b", "House"),
    (r"\btrance\b", "Trance"),
    (r"\b(synthwave|retrowave|dreamwave)\b", "Synthwave"),
    (r"\b(breakbeat|breaks)\b", "Breakbeat"),
    (r"\bdubstep\b", "Dubstep"),
    (r"\b(nu[- ]disco|disco)\b", "Disco"),
    (r"\bhip\s*-?\s*hop\b|\brap\b", "Hip-Hop"),
    (r"\b(synthpop|pop)\b", "Pop"),
    (r"\b(rock|post-punk|indie)\b", "Rock"),
    (r"\b(ebm|industrial|darkwave)\b", "Industrial / Darkwave"),
    (r"\b(chillstep|downtempo|ambient)\b", "Chillout / Ambient"),
]

TAG_NORMALIZE = {
    "synth-pop": "Synthpop", "synthpop": "Synthpop", "post-punk": "Post-Punk",
    "new wave": "New Wave", "indie rock": "Indie Rock", "indie": "Indie",
    "drum and bass": "Drum & Bass", "dnb": "Drum & Bass", "jungle": "Jungle",
    "phonk": "Phonk", "breakbeat": "Breakbeat", "breaks": "Breakbeat",
    "nu disco": "Nu-Disco", "nu-disco": "Nu-Disco", "disco": "Disco",
    "tech house": "Tech House", "deep house": "Deep House", "house": "House",
    "trance": "Trance", "techno": "Techno", "progressive house": "Progressive House",
    "dubstep": "Dubstep", "synthwave": "Synthwave", "pop": "Pop",
    "electronic": "Electronic", "ambient": "Ambient", "industrial": "Industrial",
    "ebm": "EBM", "darkwave": "Darkwave", "trip-hop": "Trip-Hop", "downtempo": "Downtempo",
}

IGNORE_TAGS = {
    "seen live", "favourites", "favorites", "awesome", "cool", "american",
    "check out", "female vocalists", "spotify",
}

BPM_RANGES = {
    "Drum & Bass": (150, 180),
    "Jungle": (150, 175),
    "Breakbeat": (115, 145),
    "House": (110, 132),
    "Deep House": (110, 125),
    "Tech House": (120, 132),
    "Progressive House": (120, 132),
    "Trance": (128, 142),
    "Techno": (125, 145),
    "Synthwave": (80, 120),
    "Phonk": (80, 150),
    "Dubstep": (130, 150),
}


@dataclass
class TrackResult:
    """One row in dj_catalog.json.

    ``bpm`` / ``key``          — active tags (what is written to ID3v2.3).
    ``analyzed_bpm`` / ``analyzed_key`` / ``analyzed_key_strength``
                               — raw Essentia telemetry, recorded regardless
                                 of whether the active value came from ID3
                                 or from the analyzer.
    """
    filename: str
    filepath: str
    bpm: int | None
    key: str | None
    analyzed_bpm: int | None
    analyzed_key: str | None
    analyzed_key_strength: float | None
    genre: str
    artist: str
    title: str
    acoustid_match: bool
    errors: list[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Utility Helpers
# ---------------------------------------------------------------------------

def normalize_text(value: str | None) -> str:
    value = (value or "").strip().lower()
    return re.sub(r"\s+", " ", value)


def first_tag(tags: ID3, frame_id: str) -> str | None:
    frame = tags.get(frame_id)
    if frame is None:
        return None
    text = getattr(frame, "text", None)
    if not text:
        return None
    return str(text[0]).strip() or None


def read_existing_metadata(file_path: Path) -> dict[str, str | None]:
    if ID3 is None:
        raise RuntimeError("mutagen is not installed")
    try:
        tags = ID3(file_path)
    except ID3NoHeaderError:
        return {"artist": None, "title": None, "genre": None, "bpm": None, "key": None}
    except Exception as exc:
        logging.warning("Could not read ID3 tags from %s: %s", file_path.name, exc)
        return {"artist": None, "title": None, "genre": None, "bpm": None, "key": None}

    return {
        "artist": first_tag(tags, "TPE1"),
        "title": first_tag(tags, "TIT2"),
        "genre": first_tag(tags, "TCON"),
        "bpm": first_tag(tags, "TBPM"),
        "key": first_tag(tags, "TKEY"),
    }


def parse_bpm(value: str | None) -> int | None:
    if not value:
        return None
    match = re.search(r"(\d+(?:\.\d+)?)", value)
    if not match:
        return None
    try:
        bpm = round(float(match.group(1)))
    except ValueError:
        return None
    return bpm if 40 <= bpm <= 240 else None


def load_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        logging.warning("Could not read %s: %s", path, exc)
        return default


def atomic_json_dump(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_name, path)
    except Exception:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise


def parse_filename(filename: str) -> tuple[str | None, str | None]:
    base = Path(filename).stem
    base = base.replace("＂", "").replace("’", "'").replace("`", "'")
    base = re.sub(r"[\u2010\u2011\u2012\u2013\u2014\u2015\u2212]", " - ", base)
    base = re.sub(r"[\u29f8\u29f9]", "/", base)

    clutter = [
        r"\((?:official|audio|lyric|lyrics|visualizer|4k|hd|video|remaster).*?\)",
        r"\[(?:official|audio|lyric|lyrics|visualizer|4k|hd|video|remaster).*?\]",
        r"[\[(]\d+\s*kbps[\])]",
    ]
    for pattern in clutter:
        base = re.sub(pattern, "", base, flags=re.IGNORECASE)

    base = re.sub(r"\s+", " ", base).strip(" -")
    if " - " in base:
        artist, title = base.split(" - ", 1)
        return artist.strip() or None, title.strip() or None

    return None, base or None


def genre_from_artist(artist: str | None) -> str | None:
    clean = normalize_text(artist)
    if not clean:
        return None
    if clean in ARTIST_GENRES:
        return ARTIST_GENRES[clean]

    for key in sorted(ARTIST_GENRES, key=len, reverse=True):
        if key in clean:
            return ARTIST_GENRES[key]
    return None


def genre_from_filename(filename: str) -> str | None:
    clean = filename.lower()
    for pattern, genre in GENRE_KEYWORDS:
        if re.search(pattern, clean, flags=re.IGNORECASE):
            return genre
    return None


def normalize_lastfm_tag(tag: str) -> str | None:
    tag_raw = normalize_text(tag)
    if not tag_raw or tag_raw in IGNORE_TAGS:
        return None

    exact = TAG_NORMALIZE.get(tag_raw)
    if exact:
        return exact

    for key in sorted(TAG_NORMALIZE, key=len, reverse=True):
        if key in tag_raw:
            return TAG_NORMALIZE[key]
    return None


def file_path_signature(path: Path) -> str:
    stat = path.stat()
    return f"{path.resolve()}:{stat.st_size}:{stat.st_mtime_ns}"


def sanitize_http_error(exc: "requests.RequestException") -> str:
    if exc.response is not None:
        return f"{exc.response.status_code} Client Error: {exc.response.reason}"
    return "Network connection failed"


# ---------------------------------------------------------------------------
# External Metadata Services
# ---------------------------------------------------------------------------

def get_acoustid_fingerprint(file_path: Path) -> tuple[int | None, str | None, str | None]:
    if not shutil.which("fpcalc"):
        return None, None, "fpcalc not found in PATH"
    try:
        result = subprocess.run(
            ["fpcalc", "-json", str(file_path)],
            capture_output=True,
            text=True,
            timeout=FPCALC_TIMEOUT,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return None, None, "fpcalc timed out"
    except OSError as exc:
        return None, None, f"fpcalc failed: {exc}"

    if result.returncode != 0:
        return None, None, f"fpcalc exited with code {result.returncode}"

    try:
        data = json.loads(result.stdout)
        duration = int(round(float(data["duration"]))) if data.get("duration") else None
        fingerprint = data.get("fingerprint")
        if duration and fingerprint:
            return duration, fingerprint, None
    except (ValueError, TypeError, KeyError, json.JSONDecodeError) as exc:
        return None, None, f"invalid fpcalc JSON output: {exc}"

    return None, None, "fpcalc returned no fingerprint"


def lookup_acoustid(
    session: "requests.Session",
    api_key: str,
    duration: int | None,
    fingerprint: str | None,
) -> tuple[str | None, str | None, str | None]:
    if requests is None:
        return None, None, "python-requests missing"
    if not api_key:
        return None, None, "ACOUSTID_API_KEY unconfigured"
    if not duration or not fingerprint:
        return None, None, "no fingerprint"

    # NOTE: pass "recordings compress" with a space, so requests encodes it as
    # the delimiter AcoustID expects. Passing a literal '+' would be re-encoded
    # to %2B and rejected with HTTP 400.
    params = {
        "client": api_key,
        "meta": "recordings compress",
        "duration": duration,
        "fingerprint": fingerprint,
    }

    try:
        response = session.get(ACOUSTID_API_URL, params=params, timeout=HTTP_TIMEOUT)
        response.raise_for_status()
        data = response.json()
    except requests.RequestException as exc:
        return None, None, f"AcoustID request failed: {sanitize_http_error(exc)}"
    except ValueError as exc:
        return None, None, f"AcoustID invalid JSON: {exc}"

    if data.get("status") != "ok":
        return None, None, f"AcoustID status: {data.get('status', 'unknown')}"

    results = sorted(
        data.get("results", []),
        key=lambda item: float(item.get("score", 0) or 0),
        reverse=True,
    )

    for result in results:
        recordings = result.get("recordings", []) or []
        for recording in recordings:
            artists = recording.get("artists", []) or []
            artist = artists[0].get("name") if artists else None
            title = recording.get("title")
            if artist and title:
                return artist.strip(), title.strip(), None

    return None, None, "no matching recording found"


def lastfm_tags(
    session: "requests.Session",
    api_key: str,
    method: str,
    artist: str,
    title: str | None = None,
) -> tuple[list[str], str | None]:
    if requests is None:
        return [], "python-requests missing"
    if not api_key:
        return [], "LASTFM_API_KEY unconfigured"

    params = {
        "method": method,
        "artist": artist,
        "api_key": api_key,
        "format": "json",
    }
    if title:
        params["track"] = title

    try:
        response = session.get(LASTFM_API_URL, params=params, timeout=HTTP_TIMEOUT)
        response.raise_for_status()
        data = response.json()
    except requests.RequestException as exc:
        return [], f"Last.fm request failed: {sanitize_http_error(exc)}"
    except ValueError as exc:
        return [], f"Last.fm invalid JSON: {exc}"

    if "error" in data:
        return [], f"Last.fm error {data.get('error')}: {data.get('message', 'unknown')}"

    tags = data.get("toptags", {}).get("tag", []) or []
    return [str(item.get("name", "")) for item in tags], None


def lookup_lastfm_genre(
    session: "requests.Session",
    api_key: str,
    artist: str | None,
    title: str | None,
    filename: str,
) -> tuple[str, str | None]:
    local = genre_from_artist(artist)
    if local:
        return local, None

    local = genre_from_filename(filename)
    if local:
        return local, None

    if not artist or normalize_text(artist) == "unknown":
        return "Electronic", None

    clean_title = re.sub(r"\(.*?\)|\[.*?\]", "", title or "").strip()

    if clean_title:
        tags, err = lastfm_tags(session, api_key, "track.getTopTags", artist, clean_title)
        for tag in tags:
            normalized = normalize_lastfm_tag(tag)
            if normalized:
                return normalized, err

    tags, err = lastfm_tags(session, api_key, "artist.getTopTags", artist)
    for tag in tags:
        normalized = normalize_lastfm_tag(tag)
        if normalized:
            return normalized, err

    return "Electronic", err


# ---------------------------------------------------------------------------
# Audio Analysis
# ---------------------------------------------------------------------------

def get_target_bpm_range(genre: str, filename: str) -> tuple[int, int] | None:
    text = f"{genre} {filename}".lower()

    if any(k in text for k in ["dnb", "drum & bass", "drum and bass", "jungle", "liquid dnb"]):
        return (150, 180)
    if "phonk" in text:
        return (80, 150)
    if any(k in text for k in ["tech house", "deep house", "progressive house", "melodic house", "house", "french touch"]):
        return (110, 132)
    if "trance" in text or "psytrance" in text:
        return (128, 142)
    if "techno" in text:
        return (125, 145)
    if "breakbeat" in text or "breaks" in text or "big beat" in text:
        return (115, 145)
    if "dubstep" in text:
        return (130, 150)
    if "synthwave" in text or "retrowave" in text:
        return (80, 120)

    for g_key, r in BPM_RANGES.items():
        if g_key.lower() in text:
            return r

    return None


def choose_bpm_candidate(bpm: float, genre: str, filename: str = "") -> int:
    candidates = {round(bpm), round(bpm / 2), round(bpm * 2)}
    candidates = {value for value in candidates if 40 <= value <= 240}

    target_range = get_target_bpm_range(genre, filename)
    if not target_range:
        return min(candidates, key=lambda value: abs(value - bpm))

    low, high = target_range
    center = (low + high) / 2

    def distance(value: int) -> tuple[float, float]:
        if low <= value <= high:
            return (0.0, abs(value - center))
        return (min(abs(value - low), abs(value - high)), abs(value - center))

    return min(candidates, key=distance)


def analyze_audio_essentia(
    file_path: Path,
    genre: str,
    filename: str,
) -> tuple[int | None, str | None, float | None, str | None]:
    if es is None:
        return None, None, None, "Essentia is not installed"
    try:
        audio = es.MonoLoader(filename=str(file_path))()

        rhythm_extractor = es.RhythmExtractor2013(method="multifeature")
        bpm_val, _, confidence, _, _ = rhythm_extractor(audio)
        bpm = choose_bpm_candidate(float(bpm_val), genre, filename)

        key_extractor = es.KeyExtractor(profileType="edma")
        key, scale, strength = key_extractor(audio)
        camelot = CAMELOT_MAP.get((key, scale), f"{key} {scale}")

        return bpm, camelot, float(strength), None
    except Exception as exc:
        return None, None, None, f"Essentia analysis failed: {exc}"


# ---------------------------------------------------------------------------
# ID3 Tag Operations
# ---------------------------------------------------------------------------

def embed_id3_tags(
    file_path: Path,
    bpm: int | None,
    key: str | None,
    genre: str | None,
    artist: str | None,
    title: str | None,
    *,
    preserve_existing: bool = True,
) -> tuple[bool, str | None]:
    if ID3 is None:
        return False, "mutagen missing"
    try:
        try:
            tags = ID3(file_path)
        except ID3NoHeaderError:
            tags = ID3()

        changed = False

        def set_text(frame_id: str, frame: Any, value: str | None) -> None:
            nonlocal changed
            if not value:
                return
            existing = first_tag(tags, frame_id)
            if preserve_existing and existing:
                return
            if existing != value:
                tags[frame_id] = frame(encoding=3, text=value)
                changed = True

        set_text("TBPM", TBPM, str(bpm) if bpm else None)
        set_text("TKEY", TKEY, key)
        set_text("TCON", TCON, genre if genre and genre != "Unknown" else None)
        set_text("TPE1", TPE1, artist if artist and artist != "Unknown" else None)
        set_text("TIT2", TIT2, title if title and title != "Unknown" else None)

        if changed:
            tags.save(file_path, v2_version=3)
        return changed, None
    except Exception as exc:
        return False, f"ID3 write failed: {exc}"


# ---------------------------------------------------------------------------
# Track Execution Pipeline
# ---------------------------------------------------------------------------

def process_track(
    file_path: Path,
    session: "requests.Session",
    acoustid_key: str,
    lastfm_key: str,
    *,
    dry_run: bool,
    preserve_existing: bool,
    cache: dict[str, Any],
) -> TrackResult:
    errors: list[str] = []
    filename = file_path.name
    existing = read_existing_metadata(file_path)

    parsed_artist, parsed_title = parse_filename(filename)

    if preserve_existing and existing["artist"]:
        artist = existing["artist"]
    else:
        artist = parsed_artist or "Unknown"

    if preserve_existing and existing["title"]:
        title = existing["title"]
    else:
        title = parsed_title or "Unknown"

    cache_key = file_path_signature(file_path)
    cached = cache.get(cache_key, {})

    acoustid_match = False

    # -----------------------------------------------------------------
    # Fix D: sentinel is presence of "acoustid_match", NOT truthiness.
    # A cached no-match entry suppresses redundant fpcalc on later runs.
    # -----------------------------------------------------------------
    if "acoustid_match" in cached:
        if cached.get("artist") and (not existing["artist"] or not preserve_existing):
            artist = cached["artist"]
        if cached.get("title") and (not existing["title"] or not preserve_existing):
            title = cached["title"]
        acoustid_match = bool(cached.get("acoustid_match"))
    else:
        duration, fingerprint, fp_error = get_acoustid_fingerprint(file_path)
        if fp_error:
            errors.append(fp_error)
        fp_artist, fp_title, acoustid_error = lookup_acoustid(
            session, acoustid_key, duration, fingerprint
        )
        if acoustid_error and acoustid_error != "no matching recording found":
            errors.append(acoustid_error)
        if fp_artist and (not existing["artist"] or not preserve_existing):
            artist = fp_artist
        if fp_title and (not existing["title"] or not preserve_existing):
            title = fp_title
        acoustid_match = bool(fp_artist and fp_title)

        cache[cache_key] = {
            "artist": fp_artist,
            "title": fp_title,
            "acoustid_match": acoustid_match,
        }

    if preserve_existing and existing["genre"]:
        genre = existing["genre"]
    else:
        genre_cache_key = (
            f"genre::{normalize_text(artist)}::{normalize_text(title)}::{normalize_text(filename)}"
        )
        cached_genre = cache.get(genre_cache_key)
        if isinstance(cached_genre, str) and cached_genre:
            genre = cached_genre
        else:
            resolved_genre, genre_error = lookup_lastfm_genre(
                session, lastfm_key, artist, title, filename,
            )
            genre = resolved_genre
            cache[genre_cache_key] = genre
            if genre_error and genre == "Electronic":
                errors.append(genre_error)

    # -----------------------------------------------------------------
    # Essentia runs unconditionally: analysis is verification telemetry,
    # decoupled from the --overwrite policy.
    # -----------------------------------------------------------------
    analyzed_bpm, analyzed_key, analyzed_key_strength, analysis_error = analyze_audio_essentia(
        file_path, genre, filename
    )
    if analysis_error:
        errors.append(analysis_error)

    # Active tag assignment: existing ID3 wins under preserve_existing
    # only when it parses / is non-empty; otherwise fall back to analysis.
    existing_bpm = parse_bpm(existing["bpm"]) if preserve_existing else None
    bpm = existing_bpm if existing_bpm is not None else analyzed_bpm

    if preserve_existing and existing["key"]:
        key = existing["key"]
    else:
        key = analyzed_key

    if not dry_run:
        changed, write_error = embed_id3_tags(
            file_path, bpm, key, genre, artist, title,
            preserve_existing=preserve_existing,
        )
        if write_error:
            errors.append(write_error)

        # Re-key fingerprint cache entry if the write mutated the file.
        if cache_key in cache:
            cache[file_path_signature(file_path)] = cache.pop(cache_key)

    return TrackResult(
        filename=filename,
        filepath=str(file_path),
        bpm=bpm,
        key=key,
        analyzed_bpm=analyzed_bpm,
        analyzed_key=analyzed_key,
        analyzed_key_strength=analyzed_key_strength,
        genre=genre,
        artist=artist,
        title=title,
        acoustid_match=acoustid_match,
        errors=errors,
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Enhance MP3 metadata for a DJ library.")
    parser.add_argument("music_dir", nargs="?", type=Path, default=DEFAULT_MUSIC_DIR)
    parser.add_argument("--catalog", type=Path, default=None)
    parser.add_argument("--cache", type=Path, default=None)
    parser.add_argument("--recursive", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--no-cache", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    return parser


def _print_result(index: int, total: int, r: TrackResult) -> None:
    status = "OK" if not r.errors else "WARN"
    print(f"[{index}/{total}] {status} {r.filename}")
    print(f"    ├─ Artist: {r.artist}")
    print(f"    ├─ Title:  {r.title}")
    print(f"    ├─ Genre:  {r.genre}")
    print(f"    ├─ Key:    {r.key or 'Failed'}")
    print(f"    ├─ BPM:    {r.bpm or 'Failed'}")

    # Telemetry: only surface when it diverges from the active tag, so
    # the common case stays concise.
    key_differs = r.analyzed_key and r.analyzed_key != r.key
    bpm_differs = r.analyzed_bpm and r.analyzed_bpm != r.bpm

    if key_differs or bpm_differs:
        strength = (
            f" (strength {r.analyzed_key_strength:.3f})"
            if r.analyzed_key_strength is not None else ""
        )
        analyzed_key_str = r.analyzed_key or "Failed"
        analyzed_bpm_str = r.analyzed_bpm if r.analyzed_bpm is not None else "Failed"
        print(f"    ├─ Analyzed key: {analyzed_key_str}{strength}")
        print(f"    ├─ Analyzed BPM: {analyzed_bpm_str}")
    elif r.analyzed_key_strength is not None and not key_differs:
        print(f"    ├─ Key strength: {r.analyzed_key_strength:.3f}")

    print(f"    └─ AcoustID: {'matched' if r.acoustid_match else 'no match'}")
    for error in r.errors:
        print(f"       ! {error}")
    print()


def main() -> int:
    args = build_parser().parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s: %(message)s",
    )

    if requests is None:
        logging.error("python-requests is not installed")
        return 1
    if ID3 is None:
        logging.error("python-mutagen is not installed")
        return 1

    music_dir: Path = args.music_dir.expanduser().resolve()
    catalog_path = (args.catalog or music_dir / DEFAULT_CATALOG_NAME).expanduser()
    cache_path = (args.cache or music_dir / DEFAULT_CACHE_NAME).expanduser()

    if not music_dir.is_dir():
        logging.error("Directory does not exist: %s", music_dir)
        return 1

    pattern = "**/*.mp3" if args.recursive else "*.mp3"
    mp3_files = sorted(music_dir.glob(pattern))
    if not mp3_files:
        logging.warning("No MP3 files found in %s", music_dir)
        return 0

    acoustid_key = os.getenv("ACOUSTID_API_KEY", ACOUSTID_API_KEY).strip()
    lastfm_key = os.getenv("LASTFM_API_KEY", LASTFM_API_KEY).strip()

    cache = {} if args.no_cache else load_json(cache_path, {})
    session = requests.Session()
    session.headers.update({"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"})

    print(f"[*] Processing {len(mp3_files)} MP3 files with Essentia + AcoustID/Last.fm...\n")

    results: list[TrackResult] = []
    for index, file_path in enumerate(mp3_files, start=1):
        result = process_track(
            file_path,
            session,
            acoustid_key,
            lastfm_key,
            dry_run=args.dry_run,
            preserve_existing=not args.overwrite,
            cache=cache,
        )
        results.append(result)
        _print_result(index, len(mp3_files), result)

    if not args.dry_run:
        atomic_json_dump(catalog_path, [asdict(r) for r in results])
        if not args.no_cache:
            atomic_json_dump(cache_path, cache)

    success_count = sum(not r.errors for r in results)
    warning_count = len(results) - success_count
    print("[✓] Analysis complete.")
    print(f"    Tracks: {len(results)} | Clean: {success_count} | Warnings: {warning_count}")
    if not args.dry_run:
        print(f"    Catalog: {catalog_path}")
        if not args.no_cache:
            print(f"    Cache:   {cache_path}")

    return 0 if warning_count == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
