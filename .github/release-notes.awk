# Build release notes for the latest version section in CHANGELOG.md.
# - Skips leading HTML comment blocks (Unreleased template, etc.).
# - Extracts first "## [x.y.z]" section.
# - Joins wrapped bullet continuation lines into one line.

/^<!--/,/^-->/ { next }

/^## \[[0-9]+\.[0-9]+\.[0-9]+\]/ {
  if (found) { exit }
  found = 1
  next
}

found {
  gsub(/\r$/, "", $0)

  if (/^## \[/) { exit }

  if (/^$/) {
    flush()
    print
    next
  }

  if (/^\* / || /^- /) {
    flush()
    buf = $0
    next
  }

  if (/^###/ || /^\[/) {
    flush()
    print
    next
  }

  sub(/^[ \t]+/, "")
  sub(/[ \t]+$/, "")
  if (buf != "") {
    buf = buf " " $0
  } else {
    buf = $0
  }
  next
}

function flush() {
  if (buf != "") {
    print buf
    buf = ""
  }
}

END {
  flush()
}
