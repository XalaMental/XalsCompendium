#!/usr/bin/env python3
"""
Xal's Compendium - quest catalog extraction pipeline (build-plan item 13).

Two-stage process, since Blizzard's client data (DB2) only exposes quest IDs
- not names - for the general quest pool (quest text moved server-side since
Legion, confirmed earlier via research: client DB2 only carries names for a
narrow ~6,246 "Task"-quest subset, not the general catalog):

  1. Pull the full current list of quest IDs that exist in the live client
     from wago.tools' QuestV2 CSV export - a public, auto-updated DB2 dump,
     refreshed whenever Blizzard ships a new build. Verified live: the
     QuestV2 table's real columns are ID, UniqueBitFlag, UiQuestDetailsThemeID
     - no name field, confirming names aren't extractable this way.
  2. Diff that ID list against the last run's snapshot (committed in this
     repo at .github/data/quest_ids.json). Only NEW ids need lookups.
  3. For each new ID, call Blizzard's own official Game Data API
     (single-quest-by-ID - confirmed earlier this session as the only
     option; there is no bulk quest-listing endpoint) to fetch the real name.
  4. Write results into catalog_data.json - skeleton only (id, name).
     Daily/Weekly classification is NOT extractable this way at all - it's a
     live-only value (C_QuestLog.GetInfo().frequency) the addon itself
     detects at runtime once a quest is actually in a player's log. See
     Data.lua's D:RunDiagnostics for the addon side of that.

Requires two GitHub Actions secrets: BLIZZARD_CLIENT_ID, BLIZZARD_CLIENT_SECRET
- a free OAuth client, registered at develop.battle.net. Without them, nothing
runs this pass (no lookups happened, so nothing should be marked as resolved).

Capped and resumable: a full first-run backfill covers every quest ID that has
EVER existed (tens of thousands), which would take hours - way past GitHub
Actions' 6-hour job limit. Each run only processes MAX_LOOKUPS_PER_RUN ids and
saves progress every SAVE_EVERY lookups, so an interrupted/cancelled run only
loses a small batch, not everything, and whatever's left over just gets
picked up automatically by the next scheduled run (or a manual re-trigger).
"""
import base64
import csv
import io
import json
import os
import socket
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

QUESTV2_CSV_URL = "https://wago.tools/db2/QuestV2/csv"
OAUTH_TOKEN_URL = "https://oauth.battle.net/token"
QUEST_API_URL = "https://us.api.blizzard.com/data/wow/quest/{id}"
NAMESPACE = "static-us"
LOCALE = "en_US"

ID_SNAPSHOT_PATH = ".github/data/quest_ids.json"
CATALOG_OUTPUT_PATH = ".github/data/catalog_data.json"

REQUEST_DELAY = 0.05  # ~20 req/sec - well under Blizzard's API rate limit
MAX_LOOKUPS_PER_RUN = 2000  # keeps a single run safely under GitHub's 6-hour job limit
SAVE_EVERY = 200  # flush progress periodically so an interrupted run doesn't lose it all

MAX_RETRIES = 4
RETRY_BACKOFF = 3  # seconds, doubles each retry (3, 6, 12, 24)

# Real failure mode hit in production (2026-08-09): a transient SSL/connection
# error mid-run to oauth.battle.net crashed the WHOLE script uncaught, wasting
# a 15-minute run that had already fetched 66,412 quest IDs from wago.tools
# for nothing. Every network call is now retried against these transient
# error types before giving up - HTTPError (a real server response, e.g. 404)
# is deliberately NOT retried here, that's handled separately per-caller.
TRANSIENT_ERRORS = (urllib.error.URLError, ssl.SSLError, socket.timeout, ConnectionError)


def with_retries(description, fn):
    """Calls fn() with no args, retrying on transient network errors with
    exponential backoff. Raises the last error if every attempt fails.

    HTTPError is deliberately let through immediately, NOT retried here -
    it means a real response came back (e.g. a 404), which is a valid
    outcome each caller handles itself, not a connection-level problem.
    It has to be checked first since HTTPError is actually a SUBCLASS of
    URLError in Python - without this check it would get caught below too
    and every legitimate 404 would burn through 4 pointless retries."""
    delay = RETRY_BACKOFF
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            return fn()
        except urllib.error.HTTPError:
            raise
        except TRANSIENT_ERRORS as err:
            if attempt == MAX_RETRIES:
                print(f"  {description} failed after {MAX_RETRIES} attempts: {err}")
                raise
            print(f"  {description} failed (attempt {attempt}/{MAX_RETRIES}: {err}) - retrying in {delay}s...")
            time.sleep(delay)
            delay *= 2


def fetch_current_quest_ids():
    """Every quest ID that currently exists in the live client, from
    wago.tools' auto-updated QuestV2 DB2 dump."""
    def _do():
        req = urllib.request.Request(
            QUESTV2_CSV_URL, headers={"User-Agent": "XalsCompendium-Extractor/1.0"}
        )
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.read().decode("utf-8")

    text = with_retries("Fetching quest ID list from wago.tools", _do)
    reader = csv.DictReader(io.StringIO(text))
    ids = set()
    for row in reader:
        try:
            ids.add(int(row["ID"]))
        except (KeyError, ValueError, TypeError):
            continue
    return ids


def load_json(path, default):
    if not os.path.exists(path):
        return default
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def save_json(path, data):
    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, sort_keys=True)
        fh.write("\n")


def get_access_token():
    client_id = os.environ.get("BLIZZARD_CLIENT_ID")
    client_secret = os.environ.get("BLIZZARD_CLIENT_SECRET")
    if not client_id or not client_secret:
        print("BLIZZARD_CLIENT_ID / BLIZZARD_CLIENT_SECRET not set - name lookups will be skipped.")
        return None

    def _do():
        data = urllib.parse.urlencode({"grant_type": "client_credentials"}).encode()
        req = urllib.request.Request(OAUTH_TOKEN_URL, data=data)
        auth = f"{client_id}:{client_secret}".encode()
        req.add_header("Authorization", b"Basic " + base64.b64encode(auth))
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))

    try:
        payload = with_retries("Getting Blizzard OAuth token", _do)
    except TRANSIENT_ERRORS:
        # A persistent connection problem shouldn't kill a run that already
        # did useful work (the ID snapshot fetch) - degrade to "no lookups
        # this pass" instead of crashing the whole script.
        print("  Could not reach Blizzard's OAuth endpoint - name lookups will be skipped this run.")
        return None
    return payload.get("access_token")


def fetch_quest_data(quest_id, token):
    """Returns the quest's full raw API response (a dict), or None if the
    API has no record for it (a valid outcome, not an error - some client-
    side IDs have no public API record, e.g. removed/internal-only quests).

    Deliberately kept as the FULL payload, not just the name - this addon
    still needs to sort quests into Daily/Weekly tiers and content
    categories, and no reliable documented example of this endpoint's full
    field set could be found (checked Blizzard's own docs, Postman
    collections, and community client libraries - none had a real captured
    response body). Capturing everything now means the next real run gives
    genuine field data to build automatic categorization from, instead of
    guessing field names in advance."""
    def _do():
        # Bearer header, NOT an access_token query param - confirmed via a
        # real working client library (FuzzyStatic/blizzard's Go source)
        # that Blizzard's API expects the token this way. The query-param
        # form was the actual bug behind every single lookup 404ing
        # regardless of which quest ID was asked about (tested both oldest
        # and newest quests - same 0/2000 result either way, which is what
        # exposed this wasn't about which quests, it was the auth method).
        url = f"{QUEST_API_URL.format(id=quest_id)}?namespace={NAMESPACE}&locale={LOCALE}"
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode("utf-8"))

    try:
        return with_retries(f"Looking up quest {quest_id}", _do)
    except urllib.error.HTTPError as err:
        if err.code == 404:
            return None
        raise


def main():
    print("Fetching current quest ID list from wago.tools...")
    current_ids = fetch_current_quest_ids()
    print(f"  {len(current_ids)} quest IDs found in the live client.")

    # known_ids means "already resolved" (looked up or confirmed no record) -
    # NOT "currently exists in the client". A quest only gets added here once
    # it's actually been processed, so a capped/interrupted run correctly
    # leaves the leftover ids "new" again for the next run to pick up.
    known_ids = set(load_json(ID_SNAPSHOT_PATH, []))
    # Newest (highest ID) first, not oldest - confirmed via Blizzard's own
    # developer forums that the Quest API excludes obsolete/disabled quests
    # from old expansion content, which are concentrated in low ID ranges.
    # Processing ascending meant the very first run burned its entire 2000-
    # lookup cap on old Vanilla-era quests that were never going to resolve
    # (real result: 0 names found out of 2000). Newest content is both more
    # likely to have a real API record AND more relevant to this addon.
    new_ids = sorted(current_ids - known_ids, reverse=True)
    print(f"  {len(new_ids)} unresolved quest IDs (new, or left over from a previous capped run).")

    if not new_ids:
        print("Nothing new - catalog is already up to date.")
        return 0

    token = get_access_token()
    if not token:
        # Nothing was actually looked up this run - don't touch the
        # snapshot, or these ids would be wrongly marked resolved forever.
        return 0

    batch = new_ids[:MAX_LOOKUPS_PER_RUN]
    remaining = len(new_ids) - len(batch)
    print(f"  Looking up {len(batch)} this run" + (f" ({remaining} left for future runs)." if remaining else "."))

    catalog = load_json(CATALOG_OUTPUT_PATH, {})
    resolved_ids = set(known_ids)
    looked_up, skipped = 0, 0

    for i, quest_id in enumerate(batch, start=1):
        data = fetch_quest_data(quest_id, token)
        if data:
            catalog[str(quest_id)] = data
            looked_up += 1
        else:
            skipped += 1
        resolved_ids.add(quest_id)  # either way, this id is now resolved - don't ask again

        if i % SAVE_EVERY == 0:
            save_json(CATALOG_OUTPUT_PATH, catalog)
            save_json(ID_SNAPSHOT_PATH, sorted(resolved_ids))
            print(f"  ...saved progress at {i}/{len(batch)}")

        time.sleep(REQUEST_DELAY)

    print(f"  Looked up {looked_up} names, {skipped} had no retrievable API record.")

    save_json(CATALOG_OUTPUT_PATH, catalog)
    save_json(ID_SNAPSHOT_PATH, sorted(resolved_ids))
    return 0


if __name__ == "__main__":
    sys.exit(main())
