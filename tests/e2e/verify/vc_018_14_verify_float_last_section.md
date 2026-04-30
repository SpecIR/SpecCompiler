# Verify Float Parent in Last Section @SVC-VERIFY-FLOAT-LAST

This test verifies that floats in the last section of a file get
their parent object correctly assigned (no false orphan).

Covers edge cases:
- Float as the very last element in the document (EOF)
- Float followed by only whitespace/newlines
- Multiple sections where last has floats

> version: 1.0

## Section: First Section @SEC-FIRST

Some content in the first section with no floats.

## Section: Middle Section @SEC-MIDDLE

A section with content and a float.

```fig:middle-figure{caption="Figure in middle section"}
middle.png
```

More text after the figure in the middle section.

## Section: Last Section With Trailing Text @SEC-LAST-A

A float followed by text.

```fig:last-with-text{caption="Float with trailing text"}
trailing.png
```

This paragraph comes after the float.

## Section: Last Section Float at EOF @SEC-LAST-B

This section ends with a float as the very last element in the file.
There is no paragraph after it — the code block IS the last block.

```fig:last-at-eof{caption="Float at very end of file"}
eof.png
```
