#!/bin/sh
# evidence.sh -- greps that show 11 unpatched Django CVEs do not reach this product.
#
# Why this exists
#   Django 4.2 (required by GeoNode 4.3.1) reached end of life on 2026-04-07 with
#   4.2.30. Fifteen CVEs were fixed only in Django 5.2.14-5.2.17 / 6.0.x. Four of them
#   reach code GeoNode runs and are transposed as the *.patch files next to this script.
#   The other eleven hit code that nothing in this image uses, or that does not exist
#   in Django 4.2. Instead of a generic sentence, this script re-measures that claim
#   on every build, one line per CVE, and fails the build the day it stops being true
#   (a new dependency, a plugin, or a newer Django series).
#
#   CVE            fixed in  entry point                            why it does not reach us
#   CVE-2026-8404  5.2.15    UpdateCacheMiddleware (Cache-Control    the cache middlewares and
#                            case)                                  cache_page() are not used
#   CVE-2026-35193 5.2.15    UpdateCacheMiddleware (Vary:            (same)
#                            Authorization)
#   CVE-2026-48587 5.2.15    has_vary_header() whitespace, only      (same)
#                            consulted by the cache middlewares
#   CVE-2026-48588 5.2.16    UpdateCacheMiddleware / cache_page()    (same)
#                            with Set-Cookie
#   CVE-2026-6907  5.2.14    UpdateCacheMiddleware with Vary: *      (same)
#   CVE-2026-6873  5.2.15    HttpRequest.get_signed_cookie() salt    no code calls
#                            collision                              get/set_signed_cookie()
#   CVE-2026-53877 5.2.16    GDALRaster built from a bytes object    no code builds a GDALRaster
#                            (heap over-read)                       (CVE-2026-15307, the
#                                                                    admin-filter path into it,
#                                                                    is patched separately)
#   CVE-2026-35192 5.2.14    SESSION_SAVE_EVERY_REQUEST=True with     the setting is never set
#                            public cached pages (session fixation)  (default False) and there
#                                                                    is no page cache
#   CVE-2026-5766  5.2.14    ASGI handler: upload size limit bypass  GeoNode is served by uWSGI
#                            with missing/understated Content-Length through WSGI
#                                                                    (inteligeo5.wsgi:application
#                                                                    in inteligeo-geonode's
#                                                                    uwsgi.ini); no ASGI server
#                                                                    is installed
#   CVE-2026-53878 5.2.16    DomainNameValidator accepts newlines     the class does not exist in
#                                                                    Django 4.2 (added in 5.1)
#   CVE-2026-15920 5.2.17    admin display_for_field() renders        Django 4.2 renders URLField
#                            URLField as a link (XSS)                as plain text (links since
#                                                                    5.2)
#
#   The full disposition table, with dates and the four transposed CVEs, is in the
#   repository README: see README, "Known vulnerabilities and disposition".
#
# What it does
#   For each CVE it greps the given folder for the symbol that would put the vulnerable
#   code on an execution path, prints one line (CVE, what it looked for, hit count,
#   PASS/FAIL) and, on FAIL, the matching lines. Exit status is 0 only when every line
#   passes. It is deliberately dumb: no Python import, no settings loading, so it works
#   inside the Dockerfile right after the patches are applied, and on a plain checkout.
#
#   Rows 1-9 (the two-sided greps): *.py files only, pruning exactly these top-level
#   folders of the given directory, and only those (a folder named "django" deeper in
#   the tree, e.g. celery/contrib/django, is still searched):
#     ./django    defines the symbols we look for
#     ./tornado   has its own, unrelated, get_signed_cookie/set_signed_cookie
#     ./jedi      ships django-stubs (today as .pyi, so not matched anyway; kept in case
#                 the include pattern is ever widened)
#   For the ASGI row two more folders are pruned, measured on 2026-09-21 against the
#   container-common image (site-packages of Django 4.2.22 + GeoNode 4.3.1):
#     ./tutorial       DRF's tutorial project, shipped by mistake inside the
#                      djangorestframework 3.15.2 wheel (see its RECORD)
#     ./sample_taggit  django-taggit 6.1.0's sample project, likewise
#   Both contain the stock `startproject` asgi.py (get_asgi_application()), nothing
#   imports them and their own settings point at WSGI_APPLICATION. The ASGI row also
#   fails if an ASGI server package is installed at the top level (uvicorn, daphne,
#   hypercorn, channels, granian) or if a server configuration file (*.ini, *.conf,
#   *.cfg, *.yaml, *.yml, *.toml) outside ./django mentions asgi or one of those servers.
#
#   Rows 10-11 look INSIDE one file of django/ and pass with zero hits: they exist to
#   trip the day Django is upgraded to a series that has the vulnerable code, so the
#   README row has to be revisited. When the file is absent (running on a checkout that
#   has no django/), the row prints SKIP and does not affect the exit status.
#
# How to run it by hand
#   On the built image (site-packages is the folder the Dockerfile uses):
#     podman run --rm -v "$PWD/patches:/patches:ro" \
#       -w /usr/src/venv/lib/python3.12/site-packages <image> sh /patches/django/evidence.sh .
#   geonode_ldap is an editable install (pip install -e), so it lives outside
#   site-packages and needs its own run:
#     podman run --rm -v "$PWD/patches:/patches:ro" <image> \
#       sh /patches/django/evidence.sh /usr/src/geonode-contribs/ldap
#   On the Inteligeo code, which is not in the base image (dates go in the README table):
#     sh patches/django/evidence.sh ../inteligeo-geonode/src
#     sh patches/django/evidence.sh ../inteligeo-geonode/plugins
#   To prove it still bites, plant `cache_page(` in a .py file under the folder: the
#   five cache rows must FAIL and the exit status must be non-zero.
#
# POSIX sh (the image's /bin/sh is dash); needs find, xargs, grep -E.

set -u

if [ $# -ne 1 ] || [ ! -d "$1" ]; then
    echo "usage: $0 <folder>   (a site-packages, or a source checkout)" >&2
    exit 2
fi
cd "$1" || exit 2

status=0
tmp=$(mktemp) || exit 2
trap 'rm -f "$tmp"' EXIT INT TERM

# find_py [extra top-level folders to prune...]
# Lists *.py files under ., NUL-separated, pruning ./django ./tornado ./jedi and the
# extra top-level folders given as arguments.
find_py() {
    prune="-path ./django"
    for d in ./tornado ./jedi "$@"; do
        prune="$prune -o -path $d"
    done
    # shellcheck disable=SC2086  # $prune is built from fixed words, splitting is intended
    find . \( $prune \) -prune -o -type f -name '*.py' -print0
}

# find_conf: server configuration files under ., pruning ./django.
find_conf() {
    find . -path ./django -prune -o -type f \
        \( -name '*.ini' -o -name '*.conf' -o -name '*.cfg' \
           -o -name '*.yaml' -o -name '*.yml' -o -name '*.toml' \) -print0
}

# report CVE "what was searched" hits
# Prints the CVE line; on hits > 0 prints the matches collected in $tmp and marks
# the run as failed.
report() {
    if [ "$3" -eq 0 ]; then
        printf '%-15s %-76s hits=%-4s PASS\n' "$1" "$2" "$3"
    else
        printf '%-15s %-76s hits=%-4s FAIL\n' "$1" "$2" "$3"
        sed 's/^/    /' "$tmp"
        status=1
    fi
}

# --- rows 1-5: page cache -----------------------------------------------------------
pat='UpdateCacheMiddleware|FetchFromCacheMiddleware|CacheMiddleware|cache_page'
find_py | xargs -0 -r grep -HnE "$pat" > "$tmp"
n=$(wc -l < "$tmp")
for cve in CVE-2026-8404 CVE-2026-35193 CVE-2026-48587 CVE-2026-48588 CVE-2026-6907; do
    report "$cve" "cache middlewares / cache_page in *.py (not django/ tornado/ jedi/)" "$n"
done

# --- row 6: signed cookies ----------------------------------------------------------
pat='get_signed_cookie|set_signed_cookie'
find_py | xargs -0 -r grep -HnE "$pat" > "$tmp"
report CVE-2026-6873 "get_signed_cookie / set_signed_cookie in *.py (same exclusions)" "$(wc -l < "$tmp")"

# --- row 7: GDALRaster from bytes ---------------------------------------------------
pat='GDALRaster\('
find_py | xargs -0 -r grep -HnE "$pat" > "$tmp"
report CVE-2026-53877 "GDALRaster( in *.py (same exclusions)" "$(wc -l < "$tmp")"

# --- row 8: session saved on every request ------------------------------------------
pat='SESSION_SAVE_EVERY_REQUEST'
find_py | xargs -0 -r grep -HnE "$pat" > "$tmp"
report CVE-2026-35192 "SESSION_SAVE_EVERY_REQUEST in *.py (same exclusions)" "$(wc -l < "$tmp")"

# --- row 9: ASGI --------------------------------------------------------------------
# (a) something wires Django's ASGI handler; (b) an ASGI server is installed;
# (c) a server configuration file points at ASGI.
: > "$tmp"
find_py ./tutorial ./sample_taggit | xargs -0 -r grep -HnE 'get_asgi_application|ASGIHandler' >> "$tmp"
for d in uvicorn daphne hypercorn channels granian; do
    [ -d "./$d" ] && echo "./$d/: ASGI server package installed" >> "$tmp"
done
find_conf | xargs -0 -r grep -HniE 'asgi|uvicorn|daphne|hypercorn|granian' >> "$tmp"
report CVE-2026-5766 "ASGI: handler wired in *.py, server package, or asgi in server config" "$(wc -l < "$tmp")"

# --- rows 10-11: code that does not exist in Django 4.2 ------------------------------
# in_django_file CVE file pattern
in_django_file() {
    if [ ! -f "$2" ]; then
        printf '%-15s %-76s hits=n/a  SKIP (no %s here)\n' "$1" "$3 inside $2" "$2"
        return
    fi
    grep -HnE "$3" "$2" > "$tmp"
    report "$1" "$3 inside $2 (absent in Django 4.2)" "$(wc -l < "$tmp")"
}
in_django_file CVE-2026-53878 django/core/validators.py 'DomainNameValidator'
in_django_file CVE-2026-15920 django/contrib/admin/utils.py 'URLField'

if [ "$status" -eq 0 ]; then
    echo "evidence.sh: all rows PASS in $(pwd)"
else
    echo "evidence.sh: at least one row FAILED in $(pwd) -- see README, Known vulnerabilities and disposition" >&2
fi
exit "$status"
