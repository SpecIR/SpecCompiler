# Validator Self-Test @SPEC-OOXML-SELF

> version: 1.0

> status: Draft

## Purpose

This test verifies that the OOXML validator correctly detects malformed XML,
missing parts, and broken relationships. It generates a valid DOCX, then
programmatically corrupts copies and asserts the validator catches each issue.

## Content

Simple content to produce a minimal DOCX output.
