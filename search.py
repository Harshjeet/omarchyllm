#!/usr/bin/env python3
"""
OmarchyLLM Web Search Engine
Fetches live web search results using DuckDuckGo HTML search or SearXNG instances.
Pure Python standard library (no pip dependencies required).
"""

import sys
import os
import re
import html
import json
import argparse
import urllib.request
import urllib.parse

USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

def search_duckduckgo(query, max_results=5):
    """Performs a search via DuckDuckGo HTML endpoint and extracts results."""
    encoded_query = urllib.parse.quote_plus(query)
    url = f"https://html.duckduckgo.com/html/?q={encoded_query}"
    
    headers = {
        "User-Agent": USER_AGENT,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
    }
    
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=12) as response:
            page_content = response.read().decode("utf-8", errors="ignore")
    except Exception as e:
        return {"error": f"Search request failed: {str(e)}", "results": []}

    results = []
    # Match each result item block in DuckDuckGo HTML
    items = re.findall(
        r'<div[^>]+class=\"[^\"]*result\s+results_links[^\"]*\"[^>]*>(.*?)</div>\s*</div>\s*</div>',
        page_content,
        re.DOTALL
    )

    for item in items:
        if len(results) >= max_results:
            break
        
        # Extract title and link
        a_m = re.search(r'<a[^>]+class=\"[^\"]*result__a[^\"]*\"[^>]+href=\"([^\"]+)\"[^>]*>(.*?)</a>', item, re.DOTALL)
        # Extract snippet
        s_m = re.search(r'<a[^>]+class=\"[^\"]*result__snippet[^\"]*\"[^>]*>(.*?)</a>', item, re.DOTALL)
        
        if a_m:
            raw_href = a_m.group(1)
            # DuckDuckGo wraps destination links in /l/?uddg=<actual_url>
            parsed_url = urllib.parse.parse_qs(urllib.parse.urlparse(raw_href).query).get("uddg", [raw_href])[0]
            title = html.unescape(re.sub(r"<[^>]+>", "", a_m.group(2)).strip())
            snippet = html.unescape(re.sub(r"<[^>]+>", "", s_m.group(1)).strip()) if s_m else ""
            
            if title and parsed_url:
                results.append({
                    "title": title,
                    "url": parsed_url,
                    "snippet": snippet
                })

    return {"query": query, "results": results}

def search_searxng(query, base_url, max_results=5):
    """Searches a SearXNG JSON API endpoint if configured."""
    base = base_url.rstrip("/")
    api_url = f"{base}/search?q={urllib.parse.quote_plus(query)}&format=json"
    headers = {"User-Agent": USER_AGENT}
    req = urllib.request.Request(api_url, headers=headers)
    
    try:
        with urllib.request.urlopen(req, timeout=12) as response:
            data = json.loads(response.read().decode("utf-8", errors="ignore"))
            raw_results = data.get("results", [])[:max_results]
            results = []
            for r in raw_results:
                results.append({
                    "title": r.get("title", ""),
                    "url": r.get("url", ""),
                    "snippet": r.get("content", "")
                })
            return {"query": query, "results": results}
    except Exception as e:
        return {"error": f"SearXNG search failed: {str(e)}", "results": []}

def format_text_output(search_data):
    """Formats search results into clean markdown for LLM consumption."""
    query = search_data.get("query", "")
    results = search_data.get("results", [])
    err = search_data.get("error")

    if err:
        return f"❌ Web search failed: {err}"

    if not results:
        return f"🔍 Web search for '{query}' returned no results."

    lines = [f"🔍 Web search results for: \"{query}\"\n"]
    for i, r in enumerate(results, 1):
        lines.append(f"{i}. **{r['title']}**")
        lines.append(f"   URL: {r['url']}")
        if r.get("snippet"):
            lines.append(f"   {r['snippet']}")
        lines.append("")
    
    return "\n".join(lines).strip()

def main():
    parser = argparse.ArgumentParser(description="OmarchyLLM Web Search")
    parser.add_argument("--query", "-q", required=True, help="Search query")
    parser.add_argument("--max", "-m", type=int, default=5, help="Max results")
    parser.add_argument("--searxng", default=None, help="Optional SearXNG base URL")
    parser.add_argument("--json", action="store_true", help="Output raw JSON")
    args = parser.parse_args()

    if args.searxng:
        data = search_searxng(args.query, args.searxng, args.max)
    else:
        data = search_duckduckgo(args.query, args.max)

    if args.json:
        print(json.dumps(data, indent=2))
    else:
        print(format_text_output(data))

if __name__ == "__main__":
    main()
