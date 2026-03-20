# Edge Cases

## Setext Headings

Setext Heading 1
================

Setext Heading 2
----------------

## Nested Structures

> Blockquote with a list:
>
> - Item 1
> - Item 2
>
> And a paragraph.

- Item with **bold** and *italic*
- Item with `code` and [link](url)
- Item with nested list:
  1. Sub-item one
  2. Sub-item two

## Code in Various Contexts

Inline `code` in a paragraph.

> `code` inside a blockquote.

- `code` in a list item

## Empty Blocks

---

---

## Multiple Blank Lines



The parser should handle multiple blank lines.

## Emphasis Edge Cases

***Bold and italic***

**Bold with *italic* inside**

*Italic with **bold** inside*

## HTML Inline

A paragraph with <strong>html</strong> inside.
