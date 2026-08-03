#!/usr/bin/env bash
# Find DeepCine's movie-web backend + provider config.
set -u
DEX=/tmp/all_dex.bin
echo "=== A. meWeb / movie-web context ==="
strings "$DEX" | grep -iE 'meWeb|movie-web|movieweb|movie_web' | sort -u | head -30

echo
echo "=== B. movie-web provider / proxy fragments ==="
for s in 'whvx' 'warezcdn' 'suubmon' 'vidlink' 'vidbinge' 'meweb' 'provider' 'backend' 'scrape' 'mw-backend' 'mw-api'; do
  n=$(strings "$DEX" | grep -c -i "$s" 2>/dev/null || echo 0)
  echo "$s: $n"
done

echo
echo "=== C. candidate API hosts (non-ad SDK) ==="
strings "$DEX" | grep -oE 'https?://[a-zA-Z0-9.-]+' | sed 's#https\?://##' | sort -u | grep -viE 'google|gstatic|play\.google|github|w3\.org|whatwg|example|schemas|developer|support\.|xmlpull|mozilla|apache|json\.org|android|goo\.gl|doubleclick|googlesyndication|applovin|unity3d|unityads|inmobi|vungle|mossturbo|pangle|tiktok|mnbvcxzas|hookspf|inner-active|safedk|oss-|aliyuncs|mythad|mopub|facebook|linkedin|mixpanel|firebase|crashlytics|segment|amplitude|appsflyer|branch|adjust|kochava|singular' | sort -u | head -50

echo
echo "=== D. JSON keys around 'sources' (movie-web payload) ==="
strings "$DEX" | grep -oE '"[a-zA-Z_]+":' | sort | uniq -c | sort -rn | grep -iE 'source|stream|url|video|subtitle|quality|hls|manifest|referer|user.?agent|header|cookie|embed|provider' | head -25

echo
echo "=== E. Remote config / dynamic URL hints ==="
strings "$DEX" | grep -iE 'baseUrl|base_url|apiUrl|serverUrl|SERVER_URL|CONFIG_URL|configUrl|host|endpoint' | sort -u | head -25

echo
echo "=== F. ijk/libpp/other player deps ==="
strings "$DEX" | grep -iE 'libpp|pp_hls|pgl|alliance|weapon' | sort -u | head -15
