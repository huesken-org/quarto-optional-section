#!/usr/bin/env bash
#
# Golden-file tests for the extension.
#
# A case is a directory under tests/cases/ holding `input.qmd`, which names the
# output format and the extension itself:
#
#     format: revealjs
#     filters: [optional-section]
#
# The document is rendered with quarto in a scratch directory, and one capture —
# exit code, rendered content, injected stylesheets, warnings — is compared
# against `expected.txt`.
#
# The content is the part of the rendered document the reader sees: `<main>` for
# html, the slides div for RevealJS, the whole file for everything else. Quarto's
# head and script boilerplate stays out of it. The stylesheet list shows which
# badge CSS the extension asked quarto for, or that `optional-badges` switched it
# off. Warnings are quarto's own `(W)`/`(E)` lines, which is where
# `remove-optional` reports a bad value.
#
#   tests/run.sh                  all cases
#   tests/run.sh heading reveal   only cases whose name contains a pattern
#   tests/run.sh --update         rewrite expected.txt from the actual capture
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

command -v quarto >/dev/null || {
	printf 'quarto not on PATH\n' >&2
	exit 2
}

update=0 patterns=()
for arg in "$@"; do
	case "$arg" in
	--update) update=1 ;;
	-*)
		sed -n '3,23p' "$0" | sed 's/^# \{0,1\}//'
		exit 2
		;;
	*) patterns+=("$arg") ;;
	esac
done

# the region a reader sees, without quarto's head and script boilerplate
content() {
	local file=$1
	case "$file" in
	*.html)
		if grep -q '<div class="slides">' "$file"; then
			awk '/<div class="slides">/,/^    <\/div>$/' "$file"
		else
			awk '/<main/,/<\/main>/' "$file"
		fi |
			# quarto puts a MathJax style block into every speaker note; drop the
			# block but keep whatever follows its closing tag on the same line
			sed -E '/<style type="text\/css">/,/<\/style>/{ /<\/style>/!d; s#^.*</style>##; }'
		;;
	*) cat "$file" ;;
	esac
}

pass=0 fail=0 failed=()

for dir in "$HERE"/cases/*/; do
	dir=${dir%/}
	name=${dir##*/}

	if [[ ${#patterns[@]} -gt 0 ]]; then
		hit=0
		for p in "${patterns[@]}"; do [[ "$name" == *"$p"* ]] && hit=1; done
		[[ $hit == 1 ]] || continue
	fi
	work=$(mktemp -d)
	cp -r "$HERE/../_extensions" "$dir/input.qmd" "$work/"

	(cd "$work" && quarto render input.qmd) >"$work/out" 2>"$work/err"
	rc=$?
	rendered=$(ls "$work"/input.* 2>/dev/null | grep -v '\.qmd$' | head -1)

	{
		printf -- '--- exit %d\n' "$rc"
		printf -- '--- content %s\n' "${rendered##*/}"
		[[ -n $rendered ]] && content "$rendered"
		printf -- '--- css\n'
		[[ -n $rendered ]] && grep -oh -- 'optional-section-[a-z]*\.css' "$rendered" | sort -u
		printf -- '--- warnings\n'
		# a failed render explains itself in full; a good one only reports (W)/(E)
		if [[ $rc == 0 ]]; then
			grep -E '^\((W|E)\)' "$work/err"
		else
			cat "$work/err"
		fi
	} | sed -E \
		-e 's/\x1b\[[0-9;]*m//g' \
		-e "s#$work#TMP#g" \
		-e "s#$HERE#TESTS#g" >"$work/actual"

	[[ $update == 1 ]] && cp "$work/actual" "$dir/expected.txt"

	if diff -u "$dir/expected.txt" "$work/actual" >"$work/diff" 2>&1; then
		printf 'PASS %s\n' "$name"
		pass=$((pass + 1))
	else
		printf 'FAIL %s\n' "$name"
		sed 's/^/     /' "$work/diff"
		fail=$((fail + 1))
		failed+=("$name")
	fi
	rm -rf "$work"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail == 0 ]] || {
	printf 'failed: %s\n' "${failed[*]}"
	exit 1
}
