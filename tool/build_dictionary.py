#!/usr/bin/env python3
"""Regenerates assets/data/dictionary.json.

Builds the app's offline Japanese dictionary from JMdict:

1. Fetch JMdict_e.gz from EDRDG and parse every entry: all its spellings, its
   readings, English glosses, a display part of speech and its conjugation
   class (ichidan, godan, suru, kuru, i-adjective, copula, suru-noun).
2. Keep every entry JMdict marks as common, plus entries whose spellings
   appear in Japanese subtitles, ordered most common first. The order matters:
   when two entries share a spelling or reading, the app resolves it to the
   first one.
3. Emit them in a compact array format (format 2) that the app decodes on a
   background isolate. The conjugation class lets the app turn inflected
   forms (食べなかった, 行きます) back into their dictionary form.

The output keeps the JMdict/EDICT CC BY-SA 4.0 attribution inside `meta`; the
same credit is shown in the app's Settings screen.

Usage:
    python3 tool/build_dictionary.py [--frequency-limit 20000] [--cache-dir .cache]

Downloads are cached, so re-running is cheap. If a download fails the script
exits non-zero and the existing asset is left untouched.
"""

from __future__ import annotations

import argparse
import gzip
import json
import sys
import urllib.request
import xml.etree.ElementTree as ElementTree
from pathlib import Path

FREQUENCY_URL = (
    "https://raw.githubusercontent.com/hermitdave/FrequencyWords/"
    "master/content/2018/ja/ja_full.txt"
)
JMDICT_URLS = (
    "https://www.edrdg.org/pub/Nihongo/JMdict_e.gz",
    "http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz",
)

META = {
    "license": "CC BY-SA 4.0",
    "source": "JMdict/EDICT",
    "attribution": (
        "This dictionary data is derived from JMdict (CC BY-SA 4.0). "
        "See https://www.jdic.org/codedoc JMdict for licensing details."
    ),
    "description": "Curated Japanese dictionary subset for ingrain MVP",
}

MAX_GLOSSES = 3

# The bundled JMdict XML expands its entity references to readable labels such
# as "noun (common) (futsuumeishi)", so parts of speech are matched by their
# leading word.
POS_LABELS = {
    "noun": "noun",
    "suru verb": "verb",
    "ichidan verb": "verb",
    "godan verb": "verb",
    "nidan verb": "verb",
    "verb": "verb",
    "kuru verb": "verb",
    "i-adjective": "i-adjective",
    "adjective": "i-adjective",
    "adjectival": "i-adjective",
    "na-adjective": "na-adjective",
    "adjectival nouns": "na-adjective",
    "adverb": "adverb",
    "adverbial": "adverb",
    "particle": "particle",
    "conjunction": "conjunction",
    "interjection": "interjection",
    "numeric": "numeral",
    "counter": "numeral",
    "pronoun": "pronoun",
    "prefix": "prefix",
    "suffix": "suffix",
    "expression": "expression",
}

# Senses are ranked so a word like 人 shows "person" instead of the rare "-ian"
# suffix reading that happens to come first in the source file.
POS_RANK = {
    "noun": 0,
    "verb": 1,
    "i-adjective": 2,
    "na-adjective": 3,
    "adverb": 4,
    "pronoun": 5,
    "particle": 6,
    "conjunction": 7,
    "interjection": 8,
    "numeral": 9,
    "expression": 10,
    "prefix": 11,
    "suffix": 12,
}

# JMdict's own definition of a common word, then its second band.
COMMON_PRIORITIES = {"ichi1", "news1", "spec1", "spec2", "gai1"}
SECOND_PRIORITIES = {"ichi2", "news2", "gai2"}
DEFAULT_NEWS_RANK = 99
DEFAULT_FREQUENCY_RANK = 10**9
FORMAT_VERSION = 2

# Conjugation classes, as bit flags shared with the app's Deinflector.
CONJ_ICHIDAN = 1
CONJ_GODAN = 2
CONJ_KURU = 4
CONJ_SURU = 8
CONJ_I_ADJECTIVE = 16
CONJ_COPULA = 32
CONJ_SURU_NOUN = 512

USUALLY_KANA = "word usually written using kana alone"

# Grammar words are kept whatever their frequency tags say: a subtitle line
# is full of them, and ます or particles are rarely tagged as common.
GRAMMAR_POS_PREFIXES = ("particle", "auxiliary", "copula")

HALFWIDTH_KATAKANA_START = 0xFF61
HALFWIDTH_KATAKANA_END = 0xFF9F
HALFWIDTH_KANA_OFFSET = HALFWIDTH_KATAKANA_START - 0x30A1
KATAKANA_START = 0x30A1
KATAKANA_END = 0x30F6
HIRAGANA_OFFSET = KATAKANA_START - 0x3041
CJK_START = 0x3040
CJK_END = 0x9FFF
HALFWIDTH_START = 0xFF01
HALFWIDTH_END = 0xFF60

# An entry whose canonical sense is a prefix or a suffix describes a derived
# form, never the word itself, so it loses to a real headword meaning.
AFFIX_LABELS = {"prefix", "suffix"}


def to_hiragana(text: str) -> str:
    """Normalises katakana (half or full width) to hiragana."""
    out = []
    for ch in text:
        code = ord(ch)
        if HALFWIDTH_KATAKANA_START <= code <= HALFWIDTH_KATAKANA_END:
            out.append(chr(code - HALFWIDTH_KANA_OFFSET))
        elif KATAKANA_START <= code <= KATAKANA_END:
            out.append(chr(code - HIRAGANA_OFFSET))
        else:
            out.append(ch)
    return "".join(out)


def to_fullwidth_kana(text: str) -> str:
    """Widens halfwidth katakana so subtitle text can match the headword."""
    return "".join(
        chr(ord(ch) + HALFWIDTH_KANA_OFFSET)
        if HALFWIDTH_KATAKANA_START <= ord(ch) <= HALFWIDTH_KATAKANA_END
        else ch
        for ch in text
    )


def is_japanese(text: str) -> bool:
    return any(
        CJK_START <= ord(ch) <= CJK_END
        or HALFWIDTH_START <= ord(ch) <= HALFWIDTH_END
        for ch in text
    )


def download(urls: tuple[str, ...], cache_dir: Path) -> Path:
    cache_dir.mkdir(parents=True, exist_ok=True)
    cached = cache_dir / urls[0].rsplit("/", 1)[-1]
    if cached.exists() and cached.stat().st_size > 0:
        return cached

    errors = []
    for candidate in urls:
        try:
            request = urllib.request.Request(
                candidate, headers={"User-Agent": "ingrain-dictionary-builder"}
            )
            with urllib.request.urlopen(request, timeout=180) as response:
                payload = response.read()
            cached.write_bytes(payload)
            return cached
        except Exception as error:  # noqa: BLE001 - report and try the mirror
            errors.append(f"{candidate}: {error}")
    raise RuntimeError("download failed -> " + " | ".join(errors))


def read_frequency(cache_dir: Path) -> list[str]:
    """Surfaces that appear in Japanese subtitles, most frequent first."""
    raw = download((FREQUENCY_URL,), cache_dir).read_text(
        encoding="utf-8", errors="replace"
    )
    counts: dict[str, int] = {}
    for line in raw.splitlines():
        parts = line.split()
        if len(parts) != 2 or not parts[1].isdigit():
            continue
        if not is_japanese(parts[0]):
            continue
        counts[parts[0]] = int(parts[1])
    return [
        surface
        for surface, _ in sorted(
            counts.items(), key=lambda kv: (-kv[1], kv[0])
        )
    ]


def _text(element: ElementTree.Element | None) -> str:
    return (element.text or "").strip() if element is not None else ""


def _pos_label(element: ElementTree.Element) -> str:
    """Maps a JMdict <pos> element to one of the labels above.

    Labels are matched by prefix, longest first, so "Godan verb with 'ru'
    ending" maps to "godan verb" rather than nothing.
    """
    head = _text(element).split("(")[0].strip().lower()
    if not head:
        return ""
    for key in _POS_KEYS_LONGEST_FIRST:
        if head.startswith(key):
            return POS_LABELS[key]
    return ""


_POS_KEYS_LONGEST_FIRST = sorted(POS_LABELS, key=len, reverse=True)


def _is_marked(sense: ElementTree.Element) -> bool:
    """Archaic, slang, rare and similar senses. "Usually kana" is a spelling
    note, not a marker, so it never demotes a sense."""
    return any(_text(misc) != USUALLY_KANA for misc in sense.findall("misc"))


def _priorities_for(entry: ElementTree.Element) -> set[str]:
    return {
        _text(node).strip()
        for node in entry.iter()
        if node.tag in ("ke_pri", "re_pri")
    }


def _commonness(priorities: set[str]) -> int:
    """How many independent lists call the entry common; more is commoner.

    ichi1 (the Ichimango everyday word list) counts double: it is what keeps
    居る "to be" ahead of 要る "to need" for いる.
    """
    return len(priorities & COMMON_PRIORITIES) + ("ichi1" in priorities)


def _priority_band(priorities: set[str]) -> int:
    if priorities & COMMON_PRIORITIES:
        return 0
    if priorities & SECOND_PRIORITIES:
        return 1
    return 2


def _news_rank(priorities: set[str]) -> int:
    """JMdict's news-frequency rank (nf01 is the most common)."""
    ranks = [
        int(priority[2:])
        for priority in priorities
        if priority.startswith("nf") and priority[2:].isdigit()
    ]
    return min(ranks) if ranks else DEFAULT_NEWS_RANK


def _sequence(entry: ElementTree.Element) -> int:
    try:
        return int(_text(entry.find("ent_seq")))
    except ValueError:
        return 0


def _readings_for(entry: ElementTree.Element) -> list[str]:
    """Readings in source order, in the script JMdict writes them in.

    Katakana stays katakana: コーヒー must match コーヒー in a subtitle. The app
    folds katakana to hiragana itself when it indexes readings.
    """
    readings = []
    for r_ele in entry.findall("r_ele"):
        reading = to_fullwidth_kana(_text(r_ele.find("reb")))
        if reading and reading not in readings:
            readings.append(reading)
    return readings


def _kanji_forms_for(entry: ElementTree.Element) -> list[str]:
    forms = []
    for k_ele in entry.findall("k_ele"):
        form = to_fullwidth_kana(_text(k_ele.find("keb")))
        if form and is_japanese(form) and form not in forms:
            forms.append(form)
    return forms


def _conjugation_for(entry: ElementTree.Element) -> int:
    """Every conjugation class any sense of the entry has."""
    mask = 0
    for pos in entry.iter("pos"):
        label = _text(pos).lower()
        if label.startswith("ichidan verb") and "zuru" not in label:
            mask |= CONJ_ICHIDAN
        elif label.startswith("godan verb"):
            mask |= CONJ_GODAN
        elif label.startswith("kuru verb"):
            mask |= CONJ_KURU
        elif label.startswith(("suru verb - included", "suru verb - special")):
            mask |= CONJ_SURU
        elif label.startswith("adjective (keiyoushi)") or label == (
            "auxiliary adjective"
        ):
            mask |= CONJ_I_ADJECTIVE
        elif label == "copula":
            mask |= CONJ_COPULA
        elif label.startswith("noun or participle which takes the aux. verb suru"):
            mask |= CONJ_SURU_NOUN
    return mask


def _is_grammar_word(entry: ElementTree.Element) -> bool:
    return any(
        _text(pos).lower().startswith(GRAMMAR_POS_PREFIXES)
        for pos in entry.iter("pos")
    )


def _is_kana(text: str) -> bool:
    return all(
        0x3040 <= ord(ch) <= 0x30FF or HALFWIDTH_START <= ord(ch) <= HALFWIDTH_END
        for ch in text
    )


def _usually_kana(entry: ElementTree.Element) -> bool:
    first = entry.find("sense")
    return first is not None and any(
        _text(misc) == USUALLY_KANA for misc in first.findall("misc")
    )


def _senses_for(entry: ElementTree.Element) -> tuple[int, str, list[str]]:
    """Returns (rank, pos label, glosses) for the entry's canonical sense.

    JMdict already lists senses in order of importance, so the first sense is
    taken as the meaning. Senses carrying a `misc` marker (archaic, slang,
    abbreviation, ...) are skipped so 何 resolves to "what" instead of a marked
    colloquial reading. Only an entry whose canonical sense is a prefix or a
    suffix is downgraded, which keeps 人 on "person" rather than its rare
    "-ian" suffix reading while leaving verb and adjective entries alone.
    """
    # A sense without <pos> inherits the previous sense's.
    senses: list[tuple[list[str], list[str], bool]] = []
    inherited: list[str] = []
    for sense in entry.findall("sense"):
        own = [_pos_label(pos) for pos in sense.findall("pos")]
        if sense.findall("pos"):
            inherited = [label for label in own if label]
        glosses = [
            _text(gloss) for gloss in sense.findall("gloss") if _text(gloss)
        ]
        if glosses:
            senses.append((glosses, inherited, _is_marked(sense)))

    if not senses:
        return (len(POS_RANK), "", [])
    chosen = next((s for s in senses if not s[2]), senses[0])
    meanings, labels, _ = chosen
    label = labels[0] if labels else ""
    rank = 1 if label in AFFIX_LABELS else 0
    return (rank, label, meanings[:MAX_GLOSSES])


def parse_jmdict(cache_dir: Path) -> list[dict]:
    """Every JMdict entry that has an English meaning."""
    path = download(JMDICT_URLS, cache_dir)
    records: list[dict] = []

    with gzip.open(path, "rb") as stream:
        context = ElementTree.iterparse(stream, events=("start", "end"))
        _, root = next(context)
        for event, element in context:
            if event != "end" or element.tag != "entry":
                continue

            affix_rank, label, meanings = _senses_for(element)
            readings = _readings_for(element)
            kanji = _kanji_forms_for(element)
            if meanings and readings:
                priorities = _priorities_for(element)
                kana_first = _usually_kana(element) or not kanji
                if kana_first:
                    # Written in kana in practice, so every kana spelling is
                    # something a subtitle may contain; kanji spellings still
                    # resolve to it.
                    surface = readings[0]
                    forms = readings[1:] + kanji
                    other_readings = []
                else:
                    surface = kanji[0]
                    forms = kanji[1:]
                    other_readings = readings[1:]
                records.append(
                    {
                        "surface": surface,
                        "reading": readings[0],
                        "forms": forms,
                        "readings": other_readings,
                        "kanaFirst": kana_first,
                        "grammar": _is_grammar_word(element),
                        "pos": label,
                        "meanings": meanings,
                        "conjugation": _conjugation_for(element),
                        "band": _priority_band(priorities),
                        "affixRank": affix_rank,
                        "commonness": _commonness(priorities),
                        "newsRank": _news_rank(priorities),
                        "sequence": _sequence(element),
                        "senseCount": len(element.findall("sense")),
                    }
                )
            element.clear()
            root.clear()

    return records


def select(records: list[dict], frequent: list[str], frequency_limit: int) -> list[dict]:
    """Common entries plus entries met in subtitles, most common first.

    JMdict's common band covers everyday and news vocabulary; the subtitle
    list adds the colloquial words that band misses. Ordering by band and
    then by subtitle frequency means a shared spelling resolves to the
    everyday sense.
    """
    rank_of = {
        surface: rank for rank, surface in enumerate(frequent[:frequency_limit])
    }

    chosen = []
    for record in records:
        # The main spelling's frequency ranks first: あなた the pronoun must
        # beat 彼方, which merely lists あなた as a rare alternative.
        primary = rank_of.get(record["surface"], DEFAULT_FREQUENCY_RANK)
        alternative = min(
            (rank_of[form] for form in record["forms"] if form in rank_of),
            default=DEFAULT_FREQUENCY_RANK,
        )
        if (
            record["band"] == 0
            or record["grammar"]
            or min(primary, alternative) != DEFAULT_FREQUENCY_RANK
        ):
            record["primaryRank"] = primary
            record["alternativeRank"] = alternative
            chosen.append(record)

    chosen.sort(
        key=lambda r: (
            r["band"],
            r["affixRank"],
            # Coarse on purpose: past "on the everyday list", news tags say
            # little (生る outranks 成る there), so sense count decides.
            -min(r["commonness"], 2),
            r["primaryRank"],
            # A general word has many senses; 成る beats 生る for なる.
            -r["senseCount"],
            r["alternativeRank"],
            r["newsRank"],
            r["sequence"],
        )
    )
    return chosen


def assign_spellings(records: list[dict]) -> None:
    """Leaves each alternative spelling only on the entry it should open.

    A spelling stays an entry's primary surface regardless, but it may be an
    alternative of several entries (本 is a rare spelling of 元). A spelling
    has a strong claim when it is an entry's surface, or the kanji of a word
    usually written in kana (事 for こと): those are how the word is really
    written. Strong claims beat weak ones, then the more common entry wins.
    So 事 opens こと while 本 still opens ほん. The app indexes alternatives
    before primaries, so pruning the losers is all it needs.
    """
    users: dict[str, list[tuple[tuple, int]]] = {}
    for order, record in enumerate(records):
        for spelling, primary in [(record["surface"], True)] + [
            (form, False) for form in record["forms"]
        ]:
            strong = primary or (
                record["kanaFirst"] and not _is_kana(spelling)
            )
            key = (not strong, -record["commonness"], not primary, order)
            users.setdefault(spelling, []).append((key, order))
        # Readings compete for kana spellings too, though they are never kept
        # as forms: はし is 橋's reading before it is a variant of くちばし.
        for reading, primary in [(record["reading"], True)] + [
            (other, False) for other in record["readings"]
        ]:
            key = (not primary, -record["commonness"], True, order)
            users.setdefault(reading, []).append((key, -1))

    owner = {spelling: min(entries)[1] for spelling, entries in users.items()}
    for order, record in enumerate(records):
        record["forms"] = [
            form for form in record["forms"] if owner[form] == order
        ]


def _compact(record: dict) -> list:
    """[surface, reading, meanings, pos, conjugation, forms, readings].

    Trailing empty fields are dropped to keep the asset small.
    """
    row = [
        record["surface"],
        record["reading"],
        record["meanings"],
        record["pos"],
        record["conjugation"],
        record["forms"],
        record["readings"],
    ]
    while row and row[-1] in ([], "", 0):
        row.pop()
    return row


def build(frequency_limit: int, cache_dir: Path) -> dict:
    frequent = read_frequency(cache_dir)
    chosen = select(parse_jmdict(cache_dir), frequent, frequency_limit)
    assign_spellings(chosen)
    output = [_compact(r) for r in chosen]

    meta = dict(META)
    meta["entryCount"] = len(output)
    return {"meta": meta, "format": FORMAT_VERSION, "entries": output}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--frequency-limit",
        type=int,
        default=20000,
        help="How many of the most frequent subtitle words to cover",
    )
    parser.add_argument(
        "--cache-dir",
        default=".cache",
        help="Where downloaded sources are cached (default: .cache)"
    )
    parser.add_argument(
        "--output",
        default="assets/data/dictionary.json",
        help="Destination asset path",
    )
    args = parser.parse_args()

    try:
        payload = build(args.frequency_limit, Path(args.cache_dir))
    except Exception as error:  # noqa: BLE001 - surface a clean CLI failure
        print(f"error: {error}", file=sys.stderr)
        return 1

    destination = Path(args.output)
    if not payload["entries"]:
        print("error: no entries produced", file=sys.stderr)
        return 1

    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        f"wrote {len(payload['entries'])} entries to {destination} "
        f"({destination.stat().st_size} bytes)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())