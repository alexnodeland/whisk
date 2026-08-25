# Maps to: Tests/PatternRendererTests.swift
# Cross-references: RFC 0001 §2.1
Feature: Destination and rename templates

  Scenario: Tokens render from file facts
    Given a template "{name}-copy.{ext}" and "{date.modified:yyyy-MM}"
    Then they render from the file's stem, lowercase extension, and dates

  Scenario: Unknown or malformed tokens invalidate the template
    Given "{bogus}", an unterminated brace, or "{date.created:}"
    Then rendering returns nil and validation rejects the template

  Scenario: Name conflicts resolve by policy
    Given a proposed name colliding case-insensitively with an existing entry
    Then rename uniquifies Finder-style (" 2", " 3", …), skip leaves the file, and replace targets the collider
