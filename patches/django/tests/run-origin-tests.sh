#!/bin/sh
# Run the Django origin regression tests of the four transposed CVE patches
# (01-04 in the parent folder) inside the built geonode-base image, against a
# PostGIS server. See README.md in this folder for the rationale and the
# acceptance criterion.
#
# usage: sh run-origin-tests.sh <workdir> <image> [patched|baseline|both]
#
#   <workdir>  scratch folder (created); receives the 4.2.30 sdist, a pristine
#              and a patched copy of its tests/ tree, and results/*.txt
#   <image>    e.g. localhost/mirandadam/geonode-base:5.5.4
#   mode       patched  (default) image as built, tests with the CVE test
#                       patches -> every new test must pass
#              baseline pristine Django 4.2.30 reinstalled inside a throwaway
#                       container (pip install --force-reinstall --no-deps):
#                       one run with the pristine tests (the list of failures
#                       that pre-exist the patches) and three with the patched
#                       tests, in which every new test must fail -- see
#                       "baseline runs" below for why three
#              both     baseline then patched
#
# environment: POSTGRES_PASSWORD (required; the `env_postgis` value in
#              inteligeo-deploy/instancia_r/pod.yaml -- POSTGRES_PASSWORD also
#              appears earlier in that file, in env_geonode, with another value),
#              POSTGRES_HOST (127.0.0.1), POSTGRES_PORT (5432), POSTGRES_USER
#              (postgres), MODULES ("mail i18n gis_tests").
set -eu

WORKDIR=${1:?usage: run-origin-tests.sh <workdir> <image> [patched|baseline|both]}
IMAGE=${2:?usage: run-origin-tests.sh <workdir> <image> [patched|baseline|both]}
MODE=${3:-patched}
: "${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD (env_postgis block of pod.yaml)}"
MODULES=${MODULES:-"mail i18n gis_tests"}
HERE=$(cd "$(dirname "$0")" && pwd)
DJANGO_VERSION=4.2.30
SDIST="django-$DJANGO_VERSION"

mkdir -p "$WORKDIR/results"
WORKDIR=$(cd "$WORKDIR" && pwd)

# 1. The sdist (it carries tests/runtests.py); downloaded with the image's pip
#    so the host needs neither pip nor Python.
if [ ! -f "$WORKDIR/$SDIST.tar.gz" ]; then
    echo "== downloading $SDIST.tar.gz"
    podman run --rm --network host -v "$WORKDIR:/w" "$IMAGE" \
        pip download -q --no-deps --no-binary :all: "Django==$DJANGO_VERSION" -d /w
fi

# 2. Three copies of the tests tree: pristine; with the CVE test patches
#    applied in CVE order (15830 edits files that 15307 already changed); and
#    with the CVE-2026-15307 test patch alone, used only by the baseline (see
#    "baseline runs" below).
for kind in pristine patched patched-15307; do
    rm -rf "$WORKDIR/tests-$kind"
    mkdir -p "$WORKDIR/tests-$kind"
    tar -xzf "$WORKDIR/$SDIST.tar.gz" -C "$WORKDIR/tests-$kind" --strip-components=1 "$SDIST/tests"
    cp "$HERE/test_postgis.py" "$WORKDIR/tests-$kind/tests/"
    # Same requirements as the origin, minus the two that need system
    # libraries the image does not have (pylibmc, pywatchman); neither is
    # used by mail, i18n or gis_tests.
    grep -v -e '^pylibmc' -e '^pywatchman' "$WORKDIR/tests-$kind/tests/requirements/py3.txt" \
        > "$WORKDIR/tests-$kind/tests/requirements/py3-image.txt"
done
echo "== applying the test patches"
for cve in 2026-15307 2026-15830 2026-15337 2026-7666; do
    (cd "$WORKDIR/tests-patched" && patch -p1 --fuzz=0 --no-backup-if-mismatch < "$HERE/CVE-$cve-tests.patch")
done
(cd "$WORKDIR/tests-patched-15307" && patch -p1 --fuzz=0 --no-backup-if-mismatch < "$HERE/CVE-2026-15307-tests.patch")

# 3. One throwaway container per run. --network host reaches the PostGIS
#    published on 127.0.0.1:5432; the settings read POSTGRES_* from the
#    environment, so the password is never written anywhere.
#
#    Baseline runs. On unpatched Django the patched tests cannot all run in
#    one go: runtests.py installs every gis_tests app whenever any gis_tests
#    label is given, and the CVE-2026-15830 test patch adds a model field
#    with the new `max_geom_collections` keyword to gis_tests/geoapp/models.py,
#    so the process aborts while importing the apps, before a single test
#    runs -- which would leave mail, i18n and the CVE-2026-15307 tests
#    unobserved. Hence three baseline runs with the patched tests:
#      baseline-patched-tests-mail-i18n  mail and i18n (no gis app installed):
#                                        the changed mail tests fail one by
#                                        one; i18n.tests fails to import
#                                        (its new test imports the function
#                                        patch 03 creates);
#      baseline-patched-tests-gis-15307  gis_tests with the 15307 test patch
#                                        alone: its new tests fail one by one;
#      baseline-patched-tests-gis-all    gis_tests with all test patches: the
#                                        abort above, recorded as evidence
#                                        that the 15830 tests need patch 02
#                                        (a module-level failure; the 15830
#                                        tests are observed passing only in
#                                        the patched run).
run_in_image() { # run_in_image <label> <tests dir> <reinstall pristine django: yes|no> [modules]
    label=$1; tests=$2; reinstall=$3; modules=${4:-$MODULES}
    out="$WORKDIR/results/$label.txt"
    echo "== $label -> $out"
    podman run --rm --network host \
        -e POSTGRES_PASSWORD -e POSTGRES_HOST -e POSTGRES_PORT -e POSTGRES_USER \
        -v "$tests/tests:/tests" "$IMAGE" sh -c "
            set -e
            if [ '$reinstall' = yes ]; then
                pip install -q --force-reinstall --no-deps Django==$DJANGO_VERSION
            fi
            pip install -q -r /tests/requirements/py3-image.txt
            python -c 'import django; print(\"Django\", django.get_version())'
            cd /tests && python runtests.py --settings=test_postgis --noinput -v 2 $modules
        " > "$out" 2>&1 || echo "   (exit status $? -- see the file; failures are expected in the baseline)"
    # -a: the output carries a few control bytes (a test prints raw socket
    # data) and grep would otherwise answer "binary file matches".
    grep -a -E '^Ran |^OK|^FAILED' "$out" || tail -5 "$out"
}

baseline_runs() {
    run_in_image baseline-pristine-tests          "$WORKDIR/tests-pristine"       yes
    run_in_image baseline-patched-tests-mail-i18n "$WORKDIR/tests-patched"        yes "mail i18n"
    run_in_image baseline-patched-tests-gis-15307 "$WORKDIR/tests-patched-15307"  yes "gis_tests"
    run_in_image baseline-patched-tests-gis-all   "$WORKDIR/tests-patched"        yes "gis_tests"
}

case "$MODE" in
    baseline)
        baseline_runs ;;
    patched)
        run_in_image patched "$WORKDIR/tests-patched" no ;;
    both)
        baseline_runs
        run_in_image patched "$WORKDIR/tests-patched" no ;;
    *) echo "unknown mode: $MODE" >&2; exit 2 ;;
esac

# 4. Summary: failing tests per run, to compare by eye or with diff(1).
for f in "$WORKDIR"/results/*.txt; do
    echo "== $(basename "$f"): $(grep -a -E '^Ran ' "$f" || echo 'no summary line (aborted before running: see the traceback in the file)')"
    grep -a -E '^(FAIL|ERROR): \S+ \(' "$f" | sort > "${f%.txt}.failures" || true
    echo "   failing tests: $(wc -l < "${f%.txt}.failures") (list in $(basename "${f%.txt}.failures"))"
done
