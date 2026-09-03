# optional-section

> [!NOTE]
> Built with AI

A Quarto filter for material that is *optional*: slides, sections, blocks and
single list items you would drop first when a talk runs long. Mark them once,
then decide per render whether they are shown, shown with a badge, or removed
entirely.

> [!WARNING]
> Built for my own presentations. Fit for that, not promised to
> fit anything else.

## Install

```bash
quarto add huesken-consulting/quarto-optional-section
```

Requires Quarto 1.4 or newer.

Then use it in a document:

```yaml
---
format: revealjs
filters: [optional-section]
---
```

## Marking

Two classes give two trimming levels: `.optional` goes first, `.optional-extra`
goes even earlier. Both can be attached in three places.

**Headings** — takes the heading and everything up to the next heading of the
same or a higher level, deeper headings included:

```markdown
## Error handling {.optional}

### Wrapping errors

Both this slide and the one above belong to the marked section.

## Next topic
```

**Divs** — takes the whole block:

```markdown
::: {.optional-extra}
An aside that only fits on a good day.
:::
```

**Inline spans** — takes just that stretch of text:

```markdown
The API is stable [and has been since 1.0]{.optional}.
```

A span that stands alone in a list item marks the **whole item**, indented
sub-items included. Pandoc list items cannot carry attributes of their own, so
this is the way to mark one:

```markdown
- Always covered
- [Only if there is time]{.optional}
    - this sub-item goes too
- Covered, [with an aside]{.optional} kept inline
```

## Removing

`remove-optional` decides what is dropped:

| Value | Effect |
| --- | --- |
| `none` | *(default)* nothing is removed |
| `extra` | `.optional-extra` is removed |
| `all` | `.optional` and `.optional-extra` are removed |

Set it in the front matter, or on the command line for a single render:

```bash
quarto render slides.qmd -M remove-optional:extra
```

An unknown value is reported as a warning and removes nothing.

## Badges

- **Divs and spans** get a badge naming the level, and divs a dashed border.
- **Headings** get a badge on the website. On RevealJS they instead get a line
  in the **speaker notes** (`⚑ optional`) and the class is taken off the
  heading: on the slides the trimming level is the presenter's business, not
  something the audience needs to see.

To keep the markers but draw nothing:

```yaml
optional-badges: false
```

The classes stay in the html either way, so your own CSS can target them.

Formats that are not html-based get neither badges nor speaker notes; the
removal works there all the same.

## Tests

`tests/run.sh` renders every case under `tests/cases/` with quarto and diffs the
result against a golden file. Each case is a directory with an `input.qmd` that
names its own format, and an `expected.txt` holding the capture: exit code, the
rendered content (`<main>` for html, the slides div for RevealJS, the whole file
otherwise), the stylesheets the filter asked for, and any warnings.

```bash
tests/run.sh                  # all cases
tests/run.sh heading reveal   # only cases whose name contains a pattern
tests/run.sh --update         # rewrite expected.txt from the actual capture
```

Quarto has to be on `PATH`.
